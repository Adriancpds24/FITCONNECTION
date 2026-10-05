import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { OAuth2Client } from 'google-auth-library';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import pool from '../db';

const googleOAuthClient = new OAuth2Client();

const APPLE_JWKS = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

export type OAuthProvider = 'google' | 'apple';

export type LoginUserRow = {
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

function parseAudienceList(raw: string | undefined, fallback: string): string[] {
  const s = (raw && raw.trim()) || fallback;
  return s
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean);
}

export async function verifyGoogleIdToken(idToken: string): Promise<{
  subject: string;
  email: string;
  name: string | null;
  picture: string | null;
}> {
  const fromEnv =
    process.env.GOOGLE_OAUTH_CLIENT_IDS || process.env.GOOGLE_WEB_CLIENT_ID || '';
  const audiences = parseAudienceList(fromEnv, '');
  if (!audiences.length) {
    throw new Error(
      'Configura GOOGLE_OAUTH_CLIENT_IDS (o GOOGLE_WEB_CLIENT_ID) en el servidor',
    );
  }

  const ticket = await googleOAuthClient.verifyIdToken({
    idToken,
    audience: audiences.length === 1 ? audiences[0] : audiences,
  });
  const p = ticket.getPayload();
  if (!p?.sub || !p.email) {
    throw new Error('Token de Google invalido');
  }
  if (p.email_verified === false) {
    throw new Error('El correo de Google no esta verificado');
  }

  return {
    subject: p.sub,
    email: p.email.toLowerCase().trim(),
    name: p.name ? String(p.name) : null,
    picture: p.picture ? String(p.picture) : null,
  };
}

export async function verifyAppleIdentityToken(identityToken: string): Promise<{
  subject: string;
  email?: string;
}> {
  const audiences = parseAudienceList(
    process.env.APPLE_SIGN_IN_AUDIENCES,
    'com.fitconnect.rms',
  );

  const { payload } = await jwtVerify(identityToken, APPLE_JWKS, {
    issuer: 'https://appleid.apple.com',
    audience: audiences,
  });

  const sub = String(payload.sub ?? '');
  if (!sub) {
    throw new Error('Token de Apple invalido');
  }
  const emailClaim =
    typeof payload.email === 'string' ? payload.email.toLowerCase().trim() : undefined;

  return { subject: sub, email: emailClaim };
}

function emailLocalPart(email: string): string {
  const local = email.split('@')[0] || 'user';
  let s = local.replace(/[^a-zA-Z0-9_]/g, '_').toLowerCase();
  if (!s) s = 'user';
  return s.slice(0, 24);
}

export async function allocateUniqueUsername(email: string): Promise<string> {
  const base = emailLocalPart(email);
  let candidate = base;
  for (let n = 0; n < 80; n++) {
    const check = await pool.query('SELECT 1 FROM "User" WHERE username = $1 LIMIT 1', [
      candidate,
    ]);
    if (check.rows.length === 0) return candidate;
    const suffix = `_${crypto.randomBytes(3).toString('hex')}`;
    const maxBase = Math.max(1, 30 - suffix.length);
    candidate = `${base.slice(0, maxBase)}${suffix}`;
  }
  throw new Error('No se pudo generar un nombre de usuario unico');
}

export async function findOrCreateOAuthUser(params: {
  provider: OAuthProvider;
  subject: string;
  email: string;
  displayName: string | null;
  imageUrl: string | null;
}): Promise<{ user: LoginUserRow; created: boolean }> {
  const { provider, subject, email, displayName, imageUrl } = params;
  const em = email.toLowerCase().trim();

  const byOAuth = await pool.query<LoginUserRow>(
    `
      SELECT
        id, email, username, password, name,
        COALESCE(role, 'user') as role,
        COALESCE("isActive", true) as "isActive",
        xp, level, fitcoins, streak
      FROM "User"
      WHERE "oauthProvider" = $1 AND "oauthSubject" = $2
      LIMIT 1
    `,
    [provider, subject],
  );

  if (byOAuth.rows.length) {
    const user = byOAuth.rows[0];
    if (user.isActive === false) {
      throw new Error('deactivated');
    }
    return { user, created: false };
  }

  const byEmail = await pool.query<LoginUserRow>(
    `
      SELECT
        id, email, username, password, name,
        COALESCE(role, 'user') as role,
        COALESCE("isActive", true) as "isActive",
        xp, level, fitcoins, streak
      FROM "User"
      WHERE lower(email) = lower($1)
      LIMIT 1
    `,
    [em],
  );

  if (byEmail.rows.length) {
    const user = byEmail.rows[0];
    if (user.isActive === false) {
      throw new Error('deactivated');
    }
    const nameVal = displayName?.trim() || user.name;
    await pool.query(
      `
        UPDATE "User"
        SET
          "oauthProvider" = $1,
          "oauthSubject" = $2,
          "updatedAt" = NOW(),
          name = COALESCE($3, name),
          "imagePath" = COALESCE($4, "imagePath")
        WHERE id = $5
      `,
      [provider, subject, nameVal, imageUrl, user.id],
    );

    const refresh = await pool.query<LoginUserRow>(
      `
        SELECT
          id, email, username, password, name,
          COALESCE(role, 'user') as role,
          COALESCE("isActive", true) as "isActive",
          xp, level, fitcoins, streak
        FROM "User"
        WHERE id = $1
      `,
      [user.id],
    );
    return { user: refresh.rows[0], created: false };
  }

  const username = await allocateUniqueUsername(em);
  const hashedPassword = await bcrypt.hash(crypto.randomBytes(48).toString('hex'), 12);
  const display = displayName?.trim() || username;

  const ins = await pool.query<LoginUserRow>(
    `
      INSERT INTO "User" (
        email,
        username,
        password,
        name,
        role,
        "isActive",
        "oauthProvider",
        "oauthSubject",
        "imagePath",
        "updatedAt"
      )
      VALUES ($1, $2, $3, $4, 'user', true, $5, $6, $7, NOW())
      RETURNING
        id, email, username, password, name,
        COALESCE(role, 'user') as role,
        COALESCE("isActive", true) as "isActive",
        xp, level, fitcoins, streak
    `,
    [em, username, hashedPassword, display, provider, subject, imageUrl],
  );

  return { user: ins.rows[0], created: true };
}
