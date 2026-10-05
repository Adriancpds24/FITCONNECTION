import crypto from 'crypto';
import pool from '../db';
import { sendEmail } from './email';

const RESET_TOKEN_TTL_MINUTES = Number(
  process.env.PASSWORD_RESET_TOKEN_TTL_MINUTES || 60,
);
const PASSWORD_RESET_URL =
  process.env.PASSWORD_RESET_URL || 'http://localhost:3000/reset-password';
const PASSWORD_RESET_APP_URL = process.env.PASSWORD_RESET_APP_URL?.trim() || '';
const IS_PRODUCTION = process.env.NODE_ENV === 'production';

export type PasswordResetUser = {
  id: number;
  email: string;
  username: string;
};

function buildPasswordResetToken(): { rawToken: string; tokenHash: string } {
  const rawToken = crypto.randomBytes(32).toString('hex');
  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');

  return { rawToken, tokenHash };
}

export function buildResetLink(token: string): string {
  const separator = PASSWORD_RESET_URL.includes('?') ? '&' : '?';
  return `${PASSWORD_RESET_URL}${separator}token=${encodeURIComponent(token)}`;
}

export function buildAppResetLink(token: string): string | null {
  if (!PASSWORD_RESET_APP_URL) {
    return null;
  }
  const separator = PASSWORD_RESET_APP_URL.includes('?') ? '&' : '?';
  return `${PASSWORD_RESET_APP_URL}${separator}token=${encodeURIComponent(token)}`;
}

function buildPasswordResetEmail(username: string, token: string) {
  const resetLink = buildResetLink(token);
  const appResetLink = buildAppResetLink(token);
  const subject = 'Recuperacion de contrasena de FitConnect';
  const text = [
    `Hola ${username},`,
    '',
    'Hemos recibido una solicitud para restablecer tu contrasena.',
    appResetLink
      ? `Abre este enlace en la app: ${appResetLink}`
      : `Abre este enlace para continuar: ${resetLink}`,
    appResetLink ? `Si no se abre la app, usa este enlace web: ${resetLink}` : '',
    `Este enlace caduca en ${RESET_TOKEN_TTL_MINUTES} minutos.`,
    '',
    'Si no has solicitado este cambio, ignora este correo.',
  ]
    .filter(Boolean)
    .join('\n');
  const html = `
    <p>Hola ${username},</p>
    <p>Hemos recibido una solicitud para restablecer tu contrasena.</p>
    ${
      appResetLink
        ? `<p><a href="${appResetLink}">Abrir en la app</a></p>
    <p>Si no se abre la app, usa la version web: <a href="${resetLink}">Recuperar contrasena en web</a></p>`
        : `<p><a href="${resetLink}">Recuperar contrasena</a></p>`
    }
    <p>Este enlace caduca en ${RESET_TOKEN_TTL_MINUTES} minutos.</p>
    <p>Si no has solicitado este cambio, ignora este correo.</p>
  `;

  return { subject, text, html, resetLink };
}

function canFallbackToConsoleDelivery(error: unknown): boolean {
  if (!(error instanceof Error)) {
    return false;
  }

  return (
    error.message.includes('SMTP no configurado') ||
    error.message.includes('SMTP_FROM no configurado') ||
    error.message.includes('Falta la dependencia nodemailer')
  );
}

export async function cleanupExpiredPasswordResetTokens(): Promise<void> {
  await pool.query('DELETE FROM "PasswordResetToken" WHERE "expiresAt" < NOW()');
}

export async function issuePasswordResetForUser(
  user: PasswordResetUser,
): Promise<{ delivery: 'email' | 'console'; resetLink?: string }> {
  await cleanupExpiredPasswordResetTokens();

  const { rawToken, tokenHash } = buildPasswordResetToken();

  await pool.query('DELETE FROM "PasswordResetToken" WHERE "userId" = $1', [
    user.id,
  ]);

  await pool.query(
    `
      INSERT INTO "PasswordResetToken" ("userId", "tokenHash", "expiresAt")
      VALUES ($1, $2, NOW() + ($3 * INTERVAL '1 minute'))
    `,
    [user.id, tokenHash, RESET_TOKEN_TTL_MINUTES],
  );

  const emailContent = buildPasswordResetEmail(user.username, rawToken);

  try {
    await sendEmail({
      to: user.email,
      subject: emailContent.subject,
      text: emailContent.text,
      html: emailContent.html,
    });

    return { delivery: 'email' };
  } catch (error) {
    if (!IS_PRODUCTION && canFallbackToConsoleDelivery(error)) {
      console.warn(
        'SMTP no configurado. Usando entrega por consola para password reset.',
      );
      console.info(
        `Password reset link para ${user.email}: ${emailContent.resetLink}`,
      );

      return {
        delivery: 'console',
        resetLink: emailContent.resetLink,
      };
    }

    throw error;
  }
}
