import { NextFunction, Request, Response } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import pool from '../db';
import { syncUsersToSeedFile } from '../services/userSeedSync';

const JWT_SECRET = process.env.JWT_SECRET || 'fitconnect_super_secret_key';

type AuthenticatedUserRow = {
  id: number;
  username: string;
  email: string;
  role: string | null;
  isActive: boolean | null;
};

declare global {
  namespace Express {
    interface Request {
      user?: {
        userId: number;
        username: string;
        email: string;
        role: string;
        isActive: boolean;
      };
    }
  }
}

export interface AuthRequest extends Request {}

async function loadAuthenticatedUserById(
  userId: number,
): Promise<Express.Request['user'] | null> {
  const userQuery = await pool.query<AuthenticatedUserRow>(
    `
      SELECT
        id,
        username,
        email,
        COALESCE(role, 'user') AS role,
        COALESCE("isActive", true) AS "isActive"
      FROM "User"
      WHERE id = $1
      LIMIT 1
    `,
    [userId],
  );

  if (userQuery.rows.length === 0) {
    return null;
  }

  const user = userQuery.rows[0];
  return {
    userId: user.id,
    username: user.username,
    email: user.email,
    role: user.role || 'user',
    isActive: user.isActive ?? true,
  };
}

async function loadOrCreateMockUser(
  username: string,
): Promise<Express.Request['user'] | null> {
  const normalizedUsername = username.trim() || 'guest';
  const isAdminUser = normalizedUsername === 'admin';
  const email = isAdminUser
    ? 'fitconnect.app.admin@gmail.com'
    : `${normalizedUsername}@fitconnect.local`;
  const role = isAdminUser ? 'admin' : 'user';

  let userQuery = await pool.query<{ id: number }>(
    'SELECT id FROM "User" WHERE username = $1 OR email = $2 LIMIT 1',
    [normalizedUsername, email],
  );

  if (userQuery.rows.length === 0) {
    console.log(`[AUTH] Auto-creating mock user: ${normalizedUsername}`);

    const hashedBootstrap = await bcrypt.hash('123456', 10);

    await pool.query(
      `
        INSERT INTO "User" (
          username,
          email,
          password,
          name,
          role,
          "isActive",
          "updatedAt"
        )
        VALUES ($1, $2, $3, $4, $5, true, NOW())
      `,
      [normalizedUsername, email, hashedBootstrap, normalizedUsername, role],
    );

    await syncUsersToSeedFile().catch((syncError) => {
      console.warn('[AUTH] No se pudo sincronizar seed_data.sql:', syncError);
    });

    userQuery = await pool.query<{ id: number }>(
      'SELECT id FROM "User" WHERE username = $1 OR email = $2 LIMIT 1',
      [normalizedUsername, email],
    );
  }

  if (userQuery.rows.length === 0) {
    return null;
  }

  return loadAuthenticatedUserById(userQuery.rows[0].id);
}

export const authenticateToken = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction,
) => {
  const authHeader = req.headers.authorization;
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res
      .status(401)
      .json({ error: 'Acceso denegado. Token no proporcionado.' });
  }

  if (
    token.startsWith('token_local_') ||
    token === 'token_admin_123' ||
    token === 'token_local_admin'
  ) {
    const username = token
      .replace('token_local_', '')
      .replace('token_admin_123', 'admin');

    console.log(`[AUTH] Processing mock token for user: "${username}"`);

    try {
      const authenticatedUser = await loadOrCreateMockUser(username);

      if (!authenticatedUser) {
        return res.status(401).json({ error: 'Usuario mock no encontrado' });
      }

      if (!authenticatedUser.isActive) {
        return res.status(403).json({ error: 'Tu cuenta esta desactivada.' });
      }

      req.user = authenticatedUser;
      return next();
    } catch (error) {
      console.error('[AUTH] Database error with mock token:', error);
      return res
        .status(500)
        .json({ error: 'Error de base de datos en autenticacion mock' });
    }
  }

  try {
    const verified = jwt.verify(token, JWT_SECRET) as { userId: number };
    const authenticatedUser = await loadAuthenticatedUserById(verified.userId);

    if (!authenticatedUser) {
      return res.status(401).json({ error: 'Usuario no encontrado.' });
    }

    if (!authenticatedUser.isActive) {
      return res.status(403).json({ error: 'Tu cuenta esta desactivada.' });
    }

    req.user = authenticatedUser;
    return next();
  } catch (error) {
    console.warn(
      `[AUTH] JWT verification failed for token: ${token.substring(0, 10)}...`,
    );
    return res.status(403).json({ error: 'Token invalido o expirado.' });
  }
};

export const requireAdmin = (
  req: AuthRequest,
  res: Response,
  next: NextFunction,
) => {
  if (!req.user) {
    return res
      .status(401)
      .json({ error: 'Acceso denegado. Usuario no autenticado.' });
  }

  if (req.user.role !== 'admin') {
    return res.status(403).json({
      error: 'Solo los administradores pueden realizar esta accion.',
    });
  }

  return next();
};
