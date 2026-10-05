import 'dotenv/config';
import { Router, type Request } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import pool from '../db';
import { authenticateToken, AuthRequest } from '../middleware/auth';
import {
  cleanupExpiredPasswordResetTokens,
  issuePasswordResetForUser,
  PasswordResetUser,
} from '../services/passwordReset';
import { syncUsersToSeedFile } from '../services/userSeedSync';
import {
  bufferToBase32,
  generateTotpSecretBytes,
  verifyTotpCode,
} from '../services/totp';
import {
  findOrCreateOAuthUser,
  verifyAppleIdentityToken,
  verifyGoogleIdToken,
} from '../services/oauthUserService';

const router = Router();
const JWT_SECRET = process.env.JWT_SECRET || 'fitconnect_super_secret_key';

type StoredResetTokenRow = {
  id: number;
  userId: number;
};

type LoginUserRow = {
  id: number;
  email: string;
  username: string;
  password: string;
  name: string | null;
  role: string | null;
  isActive: boolean | null;
  xp: number;
  level: number;
  fitcoins: number;
  streak: number;
};

function getPasswordStrengthError(password: string): string | null {
  if (password.length < 8) {
    return 'La contrasena debe tener al menos 8 caracteres.';
  }

  if (!/[a-z]/.test(password)) {
    return 'La contrasena debe incluir al menos una letra minuscula.';
  }

  if (!/[A-Z]/.test(password)) {
    return 'La contrasena debe incluir al menos una letra mayuscula.';
  }

  if (!/[0-9]/.test(password)) {
    return 'La contrasena debe incluir al menos un numero.';
  }

  if (!/[^A-Za-z0-9]/.test(password)) {
    return 'La contrasena debe incluir al menos un simbolo.';
  }

  return null;
}

function maskClientIp(req: Request): string | null {
  const forwarded = req.headers['x-forwarded-for'];
  const raw =
    (typeof forwarded === 'string' ? forwarded.split(',')[0]?.trim() : null) ||
    req.ip ||
    req.socket.remoteAddress ||
    '';
  if (!raw) return null;
  if (raw.includes(':') && !raw.includes('.')) return 'ipv6:hidden';
  const parts = raw.split('.');
  if (parts.length === 4) return `${parts[0]}.${parts[1]}.x.x`;
  return 'unknown';
}

async function recordLoginActivity(userId: number, req: Request): Promise<number | null> {
  const ua =
    typeof req.headers['user-agent'] === 'string' ? req.headers['user-agent'] : null;
  const ip = maskClientIp(req);
  try {
    await pool.query(
      `INSERT INTO "UserLoginEvent" ("userId", "userAgent", "ipMasked") VALUES ($1, $2, $3)`,
      [userId, ua, ip],
    );
    const sess = await pool.query<{ id: number }>(
      `
        INSERT INTO "UserSession" ("userId", "deviceLabel", "userAgent", "ipMasked")
        VALUES ($1, $2, $3, $4)
        RETURNING id
      `,
      [userId, 'FitConnect client', ua, ip],
    );
    return sess.rows[0]?.id ?? null;
  } catch (e) {
    console.warn('recordLoginActivity:', e);
    return null;
  }
}

// Registro de usuario
router.post('/register', async (req, res) => {
  try {
    const { email, username, password, name, gender } = req.body;
    const normalizedGender =
      typeof gender === 'string' ? gender.trim().toLowerCase() : '';

    if (!email || !username || !password || !normalizedGender) {
      return res.status(400).json({
        error: 'Email, username, contrasena y sexo son obligatorios',
      });
    }

    if (!['hombre', 'mujer', 'otro'].includes(normalizedGender)) {
      return res.status(400).json({
        error: 'Sexo no valido',
      });
    }

    const passwordStrengthError = getPasswordStrengthError(password);
    if (passwordStrengthError) {
      return res.status(400).json({ error: passwordStrengthError });
    }

    const emailExistsQuery = await pool.query(
      'SELECT id FROM "User" WHERE email = $1',
      [email],
    );
    if (emailExistsQuery.rows.length > 0) {
      return res.status(409).json({
        error: 'Ese correo electronico ya esta registrado',
        code: 'EMAIL_EXISTS',
      });
    }

    const usernameExistsQuery = await pool.query(
      'SELECT id FROM "User" WHERE username = $1',
      [username],
    );
    if (usernameExistsQuery.rows.length > 0) {
      return res.status(409).json({
        error: 'Ese nombre de usuario ya existe',
        code: 'USERNAME_EXISTS',
      });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    const insertUserQuery = `
      INSERT INTO "User" (
        email,
        username,
        password,
        name,
        gender,
        role,
        "isActive",
        "updatedAt"
      )
      VALUES ($1, $2, $3, $4, $5, 'user', true, NOW())
      RETURNING id, email, username, name, gender, role
    `;
    const newUserResult = await pool.query(insertUserQuery, [
      email,
      username,
      hashedPassword,
      name || username,
      normalizedGender,
    ]);
    const user = newUserResult.rows[0];

    await syncUsersToSeedFile().catch((syncError) => {
      console.warn(
        'No se pudo sincronizar el usuario en seed_data.sql:',
        syncError,
      );
    });

    const token = jwt.sign({ userId: user.id }, JWT_SECRET, {
      expiresIn: '24h',
    });

    const sessionId = await recordLoginActivity(user.id, req);

    return res.status(201).json({
      message: 'Usuario registrado con exito',
      token,
      sessionId,
      role: user.role || 'user',
      user,
    });
  } catch (error) {
    console.error('Error en registro:', error);
    return res.status(500).json({ error: 'Error interno del servidor' });
  }
});

// Inicio de sesion
router.post('/login', async (req, res) => {
  try {
    const { email, username, password } = req.body;
    const identifier = email || username;

    if (!identifier || !password) {
      return res.status(400).json({
        error: 'Email/username y contrasena son obligatorios',
      });
    }

    const userQuery = await pool.query<LoginUserRow>(
      `
        SELECT
          u.id, u.email, u.username, u.password, u.name,
          COALESCE(u.role, 'user') as role,
          COALESCE(u."isActive", true) as "isActive",
          u.xp, u.level, u.fitcoins, u.streak
        FROM "User" u
        WHERE u.email = $1 OR u.username = $1
      `,
      [identifier],
    );

    if (userQuery.rows.length === 0) {
      return res.status(401).json({ error: 'Credenciales invalidas' });
    }

    const user = userQuery.rows[0];
    if (user.isActive === false) {
      return res.status(403).json({ error: 'Tu cuenta esta desactivada' });
    }

    const isPasswordValid = await bcrypt.compare(password, user.password);
    if (!isPasswordValid) {
      return res.status(401).json({ error: 'Credenciales invalidas' });
    }

    const token = jwt.sign({ userId: user.id }, JWT_SECRET, {
      expiresIn: '24h',
    });

    const sessionId = await recordLoginActivity(user.id, req);

    return res.json({
      token,
      sessionId,
      role: user.role || 'user',
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
        name: user.name,
        role: user.role || 'user',
        xp: user.xp,
        level: user.level,
        fitcoins: user.fitcoins,
        streak: user.streak,
      },
    });
  } catch (error) {
    console.error('Error en login:', error);
    return res.status(500).json({ error: 'Error interno del servidor' });
  }
});

// Solicitar recuperacion por correo
router.post('/forgot-password', async (req, res) => {
  const { email } = req.body as { email?: string };
  const genericMessage =
    'Si el correo existe, te hemos enviado instrucciones para recuperar la contrasena.';

  if (!email) {
    return res.status(400).json({ error: 'El email es obligatorio' });
  }

  try {
    await cleanupExpiredPasswordResetTokens();

    const userQuery = await pool.query<PasswordResetUser>(
      `
        SELECT id, email, username
        FROM "User"
        WHERE email = $1
        LIMIT 1
      `,
      [email],
    );

    if (userQuery.rows.length === 0) {
      return res.status(404).json({
        error:
          'No hay ninguna cuenta registrada con ese correo. Comprueba el email o crea una cuenta nueva.',
        code: 'EMAIL_NOT_FOUND',
      });
    }

    const deliveryResult = await issuePasswordResetForUser(userQuery.rows[0]);

    if (deliveryResult.delivery === 'console') {
      return res.json({
        message: genericMessage,
        delivery: 'console',
      });
    }

    return res.json({ message: genericMessage });
  } catch (error) {
    console.error('Error en forgot-password:', error);
    const technicalDetail =
      error instanceof Error && error.message
        ? error.message
        : 'Error desconocido de entrega';
    return res.status(503).json({
      error:
        'No se pudo enviar el correo de recuperacion en este momento. Intentalo de nuevo en unos minutos.',
      code: 'EMAIL_DELIVERY_FAILED',
      detail: technicalDetail,
    });
  }
});

// Confirmar nueva contrasena con token de recuperacion
router.post('/reset-password', async (req, res) => {
  const { token, password } = req.body as {
    token?: string;
    password?: string;
  };

  if (!token || !password) {
    return res.status(400).json({
      error: 'Token y nueva contrasena son obligatorios',
    });
  }

  const passwordStrengthError = getPasswordStrengthError(password);
  if (passwordStrengthError) {
    return res.status(400).json({ error: passwordStrengthError });
  }

  let transactionStarted = false;

  try {
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');

    await pool.query('BEGIN');
    transactionStarted = true;

    await cleanupExpiredPasswordResetTokens();

    const resetTokenQuery = await pool.query<StoredResetTokenRow>(
      `
        SELECT id, "userId"
        FROM "PasswordResetToken"
        WHERE "tokenHash" = $1 AND "expiresAt" > NOW()
        LIMIT 1
      `,
      [tokenHash],
    );

    if (resetTokenQuery.rows.length === 0) {
      await pool.query('ROLLBACK');
      transactionStarted = false;
      return res.status(400).json({ error: 'Token invalido o expirado' });
    }

    const resetToken = resetTokenQuery.rows[0];
    const hashedPassword = await bcrypt.hash(password, 10);

    await pool.query(
      'UPDATE "User" SET password = $1, "updatedAt" = NOW() WHERE id = $2',
      [hashedPassword, resetToken.userId],
    );

    await pool.query('DELETE FROM "PasswordResetToken" WHERE "userId" = $1', [
      resetToken.userId,
    ]);

    await pool.query('COMMIT');
    transactionStarted = false;

    return res.json({ message: 'Contrasena actualizada con exito' });
  } catch (error) {
    if (transactionStarted) {
      await pool.query('ROLLBACK');
    }

    console.error('Error en reset-password:', error);
    return res.status(500).json({
      error: 'No se pudo actualizar la contrasena',
    });
  }
});

router.post('/change-password', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const currentPassword = String(req.body?.currentPassword ?? '');
    const newPassword = String(req.body?.newPassword ?? '');
    if (!currentPassword || !newPassword) {
      return res.status(400).json({ error: 'Contrasena actual y nueva son obligatorias' });
    }
    const strength = getPasswordStrengthError(newPassword);
    if (strength) return res.status(400).json({ error: strength });

    const q = await pool.query<{ password: string }>(
      `SELECT password FROM "User" WHERE id = $1 LIMIT 1`,
      [req.user!.userId],
    );
    const hash = q.rows[0]?.password;
    if (!hash || !(await bcrypt.compare(currentPassword, hash))) {
      return res.status(401).json({ error: 'Contrasena actual incorrecta' });
    }

    const newHash = await bcrypt.hash(newPassword, 10);
    await pool.query(`UPDATE "User" SET password = $1, "updatedAt" = NOW() WHERE id = $2`, [
      newHash,
      req.user!.userId,
    ]);
    await pool.query(
      `UPDATE "UserSession" SET "revokedAt" = NOW() WHERE "userId" = $1 AND "revokedAt" IS NULL`,
      [req.user!.userId],
    );
    return res.json({ message: 'Contrasena actualizada' });
  } catch (e) {
    console.error('change-password:', e);
    return res.status(500).json({ error: 'No se pudo actualizar la contrasena' });
  }
});

router.get('/me', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const result = await pool.query(
      `
        SELECT
          id,
          email,
          username,
          name,
          COALESCE(role, 'user') AS role,
          bio,
          sport,
          "imagePath",
          xp,
          level,
          fitcoins,
          streak
        FROM "User"
        WHERE id = $1
        LIMIT 1
      `,
      [req.user!.userId],
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Usuario no encontrado' });
    }
    return res.json(result.rows[0]);
  } catch (e) {
    console.error('auth/me:', e);
    return res.status(500).json({ error: 'Error al obtener el usuario actual' });
  }
});

router.get('/security-settings', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const r = await pool.query(
      `
        SELECT
          COALESCE("twoFactorEnabled", false) AS "twoFactorEnabled",
          COALESCE("loginAlertsEnabled", true) AS "loginAlertsEnabled"
        FROM "User"
        WHERE id = $1
        LIMIT 1
      `,
      [req.user!.userId],
    );
    if (r.rows.length === 0) return res.status(404).json({ error: 'Usuario no encontrado' });
    return res.json(r.rows[0]);
  } catch (e) {
    console.error('security-settings get:', e);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

router.patch('/security-settings', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const v = req.body?.loginAlertsEnabled;
    if (typeof v !== 'boolean') {
      return res.status(400).json({ error: 'loginAlertsEnabled (boolean) requerido' });
    }
    await pool.query(
      `UPDATE "User" SET "loginAlertsEnabled" = $1, "updatedAt" = NOW() WHERE id = $2`,
      [v, req.user!.userId],
    );
    return res.json({ ok: true, loginAlertsEnabled: v });
  } catch (e) {
    console.error('security-settings patch:', e);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

router.post('/2fa/setup', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const u = await pool.query(
      `SELECT COALESCE("twoFactorEnabled", false) AS enabled FROM "User" WHERE id = $1`,
      [userId],
    );
    if (u.rows.length === 0) return res.status(404).json({ error: 'Usuario no encontrado' });
    if (u.rows[0].enabled) return res.status(400).json({ error: '2FA ya esta activo' });

    const secret = generateTotpSecretBytes(20);
    const secretB64 = secret.toString('base64');
    const secretB32 = bufferToBase32(secret);
    await pool.query(
      `UPDATE "User" SET "twoFactorSecret" = $1, "twoFactorEnabled" = false, "updatedAt" = NOW() WHERE id = $2`,
      [secretB64, userId],
    );
    const issuer = 'FitConnect';
    const account = req.user!.username;
    const otpauthUrl = `otpauth://totp/${encodeURIComponent(issuer + ':' + account)}?secret=${secretB32}&issuer=${encodeURIComponent(issuer)}`;
    return res.json({ secretBase32: secretB32, otpauthUrl });
  } catch (e) {
    console.error('2fa setup:', e);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

router.post('/2fa/confirm', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const code = String(req.body?.code ?? '').replace(/\D/g, '');
    if (code.length !== 6) return res.status(400).json({ error: 'Codigo de 6 digitos requerido' });
    const row = await pool.query(
      `SELECT "twoFactorSecret" FROM "User" WHERE id = $1 LIMIT 1`,
      [req.user!.userId],
    );
    const sec = row.rows[0]?.twoFactorSecret as string | undefined;
    if (!sec) return res.status(400).json({ error: 'Configura 2FA primero (setup)' });
    if (!verifyTotpCode(sec, code)) {
      return res.status(400).json({ error: 'Codigo invalido' });
    }
    await pool.query(
      `UPDATE "User" SET "twoFactorEnabled" = true, "updatedAt" = NOW() WHERE id = $1`,
      [req.user!.userId],
    );
    return res.json({ ok: true });
  } catch (e) {
    console.error('2fa confirm:', e);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

router.post('/2fa/disable', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const password = String(req.body?.password ?? '');
    if (!password) return res.status(400).json({ error: 'Contrasena requerida' });
    const q = await pool.query<{ password: string }>(
      `SELECT password FROM "User" WHERE id = $1`,
      [req.user!.userId],
    );
    const hash = q.rows[0]?.password;
    if (!hash || !(await bcrypt.compare(password, hash))) {
      return res.status(401).json({ error: 'Contrasena incorrecta' });
    }
    await pool.query(
      `
        UPDATE "User"
        SET "twoFactorEnabled" = false, "twoFactorSecret" = NULL, "updatedAt" = NOW()
        WHERE id = $1
      `,
      [req.user!.userId],
    );
    return res.json({ ok: true });
  } catch (e) {
    console.error('2fa disable:', e);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

router.get('/sessions', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const r = await pool.query(
      `
        SELECT id, "deviceLabel", "userAgent", "ipMasked", "createdAt", "lastSeenAt"
        FROM "UserSession"
        WHERE "userId" = $1 AND "revokedAt" IS NULL
        ORDER BY "lastSeenAt" DESC
      `,
      [req.user!.userId],
    );
    return res.json(r.rows);
  } catch (e) {
    console.error('sessions list:', e);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

router.delete('/sessions/:id', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const id = Number.parseInt(req.params.id, 10);
    if (!Number.isFinite(id)) return res.status(400).json({ error: 'ID invalido' });
    const r = await pool.query(
      `
        UPDATE "UserSession"
        SET "revokedAt" = NOW()
        WHERE id = $1 AND "userId" = $2 AND "revokedAt" IS NULL
        RETURNING id
      `,
      [id, req.user!.userId],
    );
    if (r.rowCount === 0) return res.status(404).json({ error: 'Sesion no encontrada' });
    return res.json({ ok: true });
  } catch (e) {
    console.error('sessions delete:', e);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

router.get('/login-alerts', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const r = await pool.query(
      `
        SELECT id, "userAgent", "ipMasked", "createdAt"
        FROM "UserLoginEvent"
        WHERE "userId" = $1
        ORDER BY "createdAt" DESC
        LIMIT 50
      `,
      [req.user!.userId],
    );
    return res.json(r.rows);
  } catch (e) {
    console.error('login-alerts:', e);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

function oauthErrorMessage(err: unknown): string {
  const m = err instanceof Error ? err.message : String(err);
  if (m.includes('GOOGLE_OAUTH') || m.includes('GOOGLE_WEB')) {
    return 'Google OAuth no esta configurado en el servidor';
  }
  return m || 'Error en autenticacion OAuth';
}

router.post('/oauth/google', async (req, res) => {
  try {
    const idToken = String((req.body as { idToken?: string })?.idToken ?? '').trim();
    if (!idToken) {
      return res.status(400).json({ error: 'idToken obligatorio' });
    }

    let google;
    try {
      google = await verifyGoogleIdToken(idToken);
    } catch (e) {
      console.warn('Google token verify:', e);
      return res.status(401).json({ error: oauthErrorMessage(e) });
    }

    let row;
    try {
      row = await findOrCreateOAuthUser({
        provider: 'google',
        subject: google.subject,
        email: google.email,
        displayName: google.name,
        imageUrl: google.picture,
      });
    } catch (e: any) {
      if (e?.message === 'deactivated') {
        return res.status(403).json({ error: 'Tu cuenta esta desactivada' });
      }
      throw e;
    }

    if (row.created) {
      await syncUsersToSeedFile().catch((syncError) => {
        console.warn('syncUsersToSeedFile (oauth google):', syncError);
      });
    }

    const user = row.user;
    const jwtToken = jwt.sign({ userId: user.id }, JWT_SECRET, { expiresIn: '24h' });
    const sessionId = await recordLoginActivity(user.id, req);

    return res.status(row.created ? 201 : 200).json({
      token: jwtToken,
      sessionId,
      role: user.role || 'user',
      isNewUser: row.created,
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
        name: user.name,
        role: user.role || 'user',
        xp: user.xp,
        level: user.level,
        fitcoins: user.fitcoins,
        streak: user.streak,
      },
    });
  } catch (error) {
    console.error('oauth/google:', error);
    return res.status(500).json({ error: 'Error interno del servidor' });
  }
});

router.post('/oauth/apple', async (req, res) => {
  try {
    const body = req.body as {
      identityToken?: string;
      emailHint?: string;
      givenName?: string;
      familyName?: string;
    };
    const identityToken = String(body?.identityToken ?? '').trim();
    if (!identityToken) {
      return res.status(400).json({ error: 'identityToken obligatorio' });
    }

    let verified;
    try {
      verified = await verifyAppleIdentityToken(identityToken);
    } catch (e) {
      console.warn('Apple token verify:', e);
      return res.status(401).json({ error: 'Token de Apple invalido' });
    }

    let email =
      (verified.email && verified.email.toLowerCase().trim()) ||
      (body.emailHint && String(body.emailHint).toLowerCase().trim()) ||
      '';

    if (!email) {
      return res.status(400).json({
        error:
          'Apple no envio correo en esta sesion. Vuelve a intentar; la primera vez elige compartir correo o Hide My Email.',
      });
    }

    const displayName =
      [body.givenName, body.familyName].filter(Boolean).join(' ').trim() || null;

    let row;
    try {
      row = await findOrCreateOAuthUser({
        provider: 'apple',
        subject: verified.subject,
        email,
        displayName,
        imageUrl: null,
      });
    } catch (e: any) {
      if (e?.message === 'deactivated') {
        return res.status(403).json({ error: 'Tu cuenta esta desactivada' });
      }
      throw e;
    }

    if (row.created) {
      await syncUsersToSeedFile().catch((syncError) => {
        console.warn('syncUsersToSeedFile (oauth apple):', syncError);
      });
    }

    const user = row.user;
    const jwtToken = jwt.sign({ userId: user.id }, JWT_SECRET, { expiresIn: '24h' });
    const sessionId = await recordLoginActivity(user.id, req);

    return res.status(row.created ? 201 : 200).json({
      token: jwtToken,
      sessionId,
      role: user.role || 'user',
      isNewUser: row.created,
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
        name: user.name,
        role: user.role || 'user',
        xp: user.xp,
        level: user.level,
        fitcoins: user.fitcoins,
        streak: user.streak,
      },
    });
  } catch (error) {
    console.error('oauth/apple:', error);
    return res.status(500).json({ error: 'Error interno del servidor' });
  }
});

export default router;
