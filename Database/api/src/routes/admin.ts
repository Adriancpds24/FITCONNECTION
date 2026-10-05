import { Router } from 'express';
import { PoolClient } from 'pg';
import pool from '../db';
import {
  authenticateToken,
  AuthRequest,
  requireAdmin,
} from '../middleware/auth';
import {
  issuePasswordResetForUser,
  PasswordResetUser,
} from '../services/passwordReset';

const router = Router();

type AdminRole = 'admin' | 'moderator' | 'user';
type ReportStatus = 'open' | 'in_review' | 'resolved' | 'dismissed';

function parsePositiveInt(value: string): number | null {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    return null;
  }

  return parsed;
}

function isValidAdminRole(role: string): role is AdminRole {
  return role === 'admin' || role === 'moderator' || role === 'user';
}

function isValidReportStatus(status: string): status is ReportStatus {
  return (
    status === 'open' ||
    status === 'in_review' ||
    status === 'resolved' ||
    status === 'dismissed'
  );
}

async function logAdminAction(
  adminUserId: number,
  action: string,
  targetType: string,
  targetId: number | null,
  metadata?: Record<string, unknown>,
): Promise<void> {
  await pool.query(
    `
      INSERT INTO "AdminAuditLog" (
        "adminUserId",
        action,
        "targetType",
        "targetId",
        metadata,
        "createdAt"
      )
      VALUES ($1, $2, $3, $4, $5, NOW())
    `,
    [
      adminUserId,
      action,
      targetType,
      targetId,
      metadata ? JSON.stringify(metadata) : null,
    ],
  );
}

async function countActiveAdmins(): Promise<number> {
  const result = await pool.query<{ count: number }>(
    `
      SELECT COUNT(*)::int AS count
      FROM "User"
      WHERE COALESCE(role, 'user') = 'admin'
        AND COALESCE("isActive", true) = true
    `,
  );

  return result.rows[0]?.count ?? 0;
}

async function deleteUserDependencies(
  client: PoolClient,
  userId: number,
): Promise<void> {
  await client.query(
    'DELETE FROM "Follow" WHERE "followerId" = $1 OR "followingId" = $1',
    [userId],
  );
  await client.query(
    'DELETE FROM "Message" WHERE "senderId" = $1 OR "receiverId" = $1',
    [userId],
  );
  await client.query(
    'DELETE FROM "Report" WHERE "userId" = $1',
    [userId],
  );
  await client.query(
    `
      DELETE FROM "Report"
      WHERE type = 'comment'
        AND "targetId" IN (
          SELECT c.id
          FROM "Comment" c
          WHERE c."userId" = $1
             OR c."postId" IN (
               SELECT p.id
               FROM "Post" p
               WHERE p."userId" = $1
             )
        )
    `,
    [userId],
  );
  await client.query(
    `
      DELETE FROM "Report"
      WHERE type = 'post'
        AND "targetId" IN (
          SELECT p.id
          FROM "Post" p
          WHERE p."userId" = $1
        )
    `,
    [userId],
  );
  await client.query(
    `
      DELETE FROM "Like"
      WHERE "userId" = $1
         OR "postId" IN (
           SELECT p.id
           FROM "Post" p
           WHERE p."userId" = $1
         )
    `,
    [userId],
  );
  await client.query(
    `
      DELETE FROM "Bookmark"
      WHERE "userId" = $1
         OR "postId" IN (
           SELECT p.id
           FROM "Post" p
           WHERE p."userId" = $1
         )
    `,
    [userId],
  );
  await client.query(
    `
      DELETE FROM "Comment"
      WHERE "userId" = $1
         OR "postId" IN (
           SELECT p.id
           FROM "Post" p
           WHERE p."userId" = $1
         )
    `,
    [userId],
  );
  await client.query('DELETE FROM "Post" WHERE "userId" = $1', [userId]);
  await client.query('DELETE FROM "Highlight" WHERE "userId" = $1', [userId]);
  await client.query(
    `
      DELETE FROM "MealItem"
      WHERE "mealId" IN (
        SELECT m.id
        FROM "Meal" m
        WHERE m."userId" = $1
      )
    `,
    [userId],
  );
  await client.query('DELETE FROM "Meal" WHERE "userId" = $1', [userId]);
  await client.query(
    `
      DELETE FROM "TrainingSession"
      WHERE "userId" = $1
         OR "workoutId" IN (
           SELECT w.id
           FROM "Workout" w
           WHERE w."userId" = $1
         )
    `,
    [userId],
  );
  await client.query(
    `
      DELETE FROM "WorkoutExercise"
      WHERE "workoutId" IN (
        SELECT w.id
        FROM "Workout" w
        WHERE w."userId" = $1
      )
    `,
    [userId],
  );
  await client.query('DELETE FROM "Workout" WHERE "userId" = $1', [userId]);
}

router.use(authenticateToken, requireAdmin);

router.get('/overview', async (req: AuthRequest, res) => {
  try {
    const [
      usersResult,
      blockedUsersResult,
      postsResult,
      commentsResult,
      storiesResult,
      reportsResult,
      openReportsResult,
      exercisesResult,
      foodsResult,
      sportsResult,
      workoutTemplatesResult,
      nutritionTemplatesResult,
      passwordResetsResult,
      recentAuditLogsResult,
    ] = await Promise.all([
      pool.query<{ count: number }>('SELECT COUNT(*)::int AS count FROM "User"'),
      pool.query<{ count: number }>(
        'SELECT COUNT(*)::int AS count FROM "User" WHERE COALESCE("isActive", true) = false',
      ),
      pool.query<{ count: number }>('SELECT COUNT(*)::int AS count FROM "Post"'),
      pool.query<{ count: number }>('SELECT COUNT(*)::int AS count FROM "Comment"'),
      pool.query<{ count: number }>(
        'SELECT COUNT(*)::int AS count FROM "Story" WHERE "deletedAt" IS NULL',
      ),
      pool.query<{ count: number }>('SELECT COUNT(*)::int AS count FROM "Report"'),
      pool.query<{ count: number }>(
        `
          SELECT COUNT(*)::int AS count
          FROM "Report"
          WHERE COALESCE(status, 'open') IN ('open', 'in_review')
        `,
      ),
      pool.query<{ count: number }>('SELECT COUNT(*)::int AS count FROM "Exercise"'),
      pool.query<{ count: number }>('SELECT COUNT(*)::int AS count FROM "Food"'),
      pool.query<{ count: number }>('SELECT COUNT(*)::int AS count FROM "SportCategory"'),
      pool.query<{ count: number }>(
        'SELECT COUNT(*)::int AS count FROM "WorkoutTemplate" WHERE COALESCE("isActive", true) = true',
      ),
      pool.query<{ count: number }>(
        'SELECT COUNT(*)::int AS count FROM "NutritionTemplate" WHERE COALESCE("isActive", true) = true',
      ),
      pool.query<{ count: number }>(
        `
          SELECT COUNT(*)::int AS count
          FROM "PasswordResetToken"
          WHERE "createdAt" > NOW() - INTERVAL '24 hours'
        `,
      ),
      pool.query(
        `
          SELECT
            l.id,
            l.action,
            l."targetType",
            l."targetId",
            l.metadata,
            l."createdAt",
            u.username AS "adminUsername"
          FROM "AdminAuditLog" l
          JOIN "User" u ON u.id = l."adminUserId"
          ORDER BY l."createdAt" DESC
          LIMIT 8
        `,
      ),
    ]);

    return res.json({
      metrics: {
        users: usersResult.rows[0]?.count ?? 0,
        blockedUsers: blockedUsersResult.rows[0]?.count ?? 0,
        posts: postsResult.rows[0]?.count ?? 0,
        comments: commentsResult.rows[0]?.count ?? 0,
        activeStories: storiesResult.rows[0]?.count ?? 0,
        reports: reportsResult.rows[0]?.count ?? 0,
        openReports: openReportsResult.rows[0]?.count ?? 0,
        exercises: exercisesResult.rows[0]?.count ?? 0,
        foods: foodsResult.rows[0]?.count ?? 0,
        sportCategories: sportsResult.rows[0]?.count ?? 0,
        workoutTemplates: workoutTemplatesResult.rows[0]?.count ?? 0,
        nutritionTemplates: nutritionTemplatesResult.rows[0]?.count ?? 0,
        passwordResetsLast24h: passwordResetsResult.rows[0]?.count ?? 0,
      },
      system: {
        smtpReady: Boolean(
          process.env.SMTP_HOST &&
            process.env.SMTP_PORT &&
            process.env.SMTP_USER &&
            process.env.SMTP_PASS,
        ),
        passwordResetUrl: process.env.PASSWORD_RESET_URL || null,
        nodeEnv: process.env.NODE_ENV || 'development',
      },
      recentAuditLogs: recentAuditLogsResult.rows,
    });
  } catch (error) {
    console.error('Error loading admin overview:', error);
    return res.status(500).json({ error: 'No se pudo cargar el panel admin' });
  }
});

router.get('/users', async (req: AuthRequest, res) => {
  try {
    const search =
      typeof req.query.search === 'string' ? req.query.search.trim() : '';
    const params: Array<string> = [];
    let whereClause = '';

    if (search) {
      params.push(`%${search}%`);
      whereClause = `
        WHERE u.email ILIKE $1
          OR u.username ILIKE $1
          OR COALESCE(u.name, '') ILIKE $1
          OR COALESCE(u.role, 'user') ILIKE $1
      `;
    }

    const usersQuery = `
      SELECT
        u.id,
        u.email,
        u.username,
        u.name,
        COALESCE(u.role, 'user') AS role,
        COALESCE(u."isActive", true) AS "isActive",
        u.bio,
        u.sport,
        u."imagePath",
        u."updatedAt",
        (SELECT COUNT(*)::int FROM "Post" p WHERE p."userId" = u.id) AS "postsCount",
        (SELECT COUNT(*)::int FROM "Follow" f WHERE f."followingId" = u.id) AS "followersCount",
        (SELECT COUNT(*)::int FROM "Report" r WHERE r."userId" = u.id) AS "reportsCreatedCount"
      FROM "User" u
      ${whereClause}
      ORDER BY
        CASE COALESCE(u.role, 'user')
          WHEN 'admin' THEN 0
          WHEN 'moderator' THEN 1
          ELSE 2
        END,
        COALESCE(u."isActive", true) DESC,
        LOWER(u.username) ASC
    `;

    const result = await pool.query(usersQuery, params);
    return res.json(result.rows);
  } catch (error) {
    console.error('Error loading admin users:', error);
    return res
      .status(500)
      .json({ error: 'No se pudo cargar el listado de usuarios' });
  }
});

router.delete('/users', async (req: AuthRequest, res) => {
  const userId = parsePositiveInt(String(req.body?.id ?? ''));
  const username =
    typeof req.body?.username === 'string' ? req.body.username.trim() : '';

  if (!userId && !username) {
    return res.status(400).json({
      error: 'Debes indicar un ID de usuario o un nombre de usuario',
    });
  }

  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const targetUserResult = await client.query(
      `
        SELECT
          id,
          username,
          email,
          COALESCE(role, 'user') AS role,
          COALESCE("isActive", true) AS "isActive"
        FROM "User"
        WHERE id = COALESCE($1::int, id)
          AND ($2::text = '' OR username = $2)
        LIMIT 1
      `,
      [userId || null, username],
    );

    if (targetUserResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Usuario no encontrado' });
    }

    const targetUser = targetUserResult.rows[0] as {
      id: number;
      username: string;
      email: string;
      role: string;
      isActive: boolean;
    };

    if (targetUser.id === req.user!.userId) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: 'No puedes eliminar tu propia cuenta de administrador',
      });
    }

    if (
      targetUser.role === 'admin' &&
      targetUser.isActive &&
      (await countActiveAdmins()) <= 1
    ) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: 'No puedes eliminar el ultimo administrador activo',
      });
    }

    await deleteUserDependencies(client, targetUser.id);

    const deleteResult = await client.query(
      'DELETE FROM "User" WHERE id = $1 RETURNING id',
      [targetUser.id],
    );

    if (deleteResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Usuario no encontrado' });
    }

    await client.query('COMMIT');

    await logAdminAction(req.user!.userId, 'delete_user', 'user', targetUser.id, {
      username: targetUser.username,
      email: targetUser.email,
    });

    return res.json({ message: 'Usuario eliminado correctamente' });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error deleting user as admin:', error);
    return res.status(500).json({ error: 'No se pudo eliminar el usuario' });
  } finally {
    client.release();
  }
});

router.patch('/users/:id/role', async (req: AuthRequest, res) => {
  const userId = parsePositiveInt(req.params.id);
  const role = String(req.body.role || '').trim();

  if (!userId) {
    return res.status(400).json({ error: 'ID de usuario invalido' });
  }

  if (!isValidAdminRole(role)) {
    return res.status(400).json({ error: 'Rol invalido' });
  }

  try {
    const targetUserResult = await pool.query(
      `
        SELECT id, username, COALESCE(role, 'user') AS role
        FROM "User"
        WHERE id = $1
        LIMIT 1
      `,
      [userId],
    );

    if (targetUserResult.rows.length === 0) {
      return res.status(404).json({ error: 'Usuario no encontrado' });
    }

    const targetUser = targetUserResult.rows[0] as {
      id: number;
      username: string;
      role: string;
    };

    if (
      targetUser.id === req.user!.userId &&
      targetUser.role === 'admin' &&
      role !== 'admin' &&
      (await countActiveAdmins()) <= 1
    ) {
      return res.status(400).json({
        error: 'No puedes quitar el rol al ultimo administrador activo',
      });
    }

    const updateResult = await pool.query(
      `
        UPDATE "User"
        SET role = $1, "updatedAt" = NOW()
        WHERE id = $2
        RETURNING id, email, username, name, role, COALESCE("isActive", true) AS "isActive"
      `,
      [role, userId],
    );

    await logAdminAction(
      req.user!.userId,
      'update_user_role',
      'user',
      userId,
      {
        previousRole: targetUser.role,
        nextRole: role,
        username: targetUser.username,
      },
    );

    return res.json({
      message: 'Rol actualizado correctamente',
      user: updateResult.rows[0],
    });
  } catch (error) {
    console.error('Error updating user role:', error);
    return res.status(500).json({ error: 'No se pudo actualizar el rol' });
  }
});

router.patch('/users/:id/status', async (req: AuthRequest, res) => {
  const userId = parsePositiveInt(req.params.id);
  const isActive = Boolean(req.body.isActive);

  if (!userId) {
    return res.status(400).json({ error: 'ID de usuario invalido' });
  }

  try {
    const targetUserResult = await pool.query(
      `
        SELECT id, username, COALESCE(role, 'user') AS role, COALESCE("isActive", true) AS "isActive"
        FROM "User"
        WHERE id = $1
        LIMIT 1
      `,
      [userId],
    );

    if (targetUserResult.rows.length === 0) {
      return res.status(404).json({ error: 'Usuario no encontrado' });
    }

    const targetUser = targetUserResult.rows[0] as {
      id: number;
      username: string;
      role: string;
      isActive: boolean;
    };

    if (targetUser.id === req.user!.userId && !isActive) {
      return res.status(400).json({
        error: 'No puedes desactivar tu propia cuenta de administrador',
      });
    }

    if (
      targetUser.role === 'admin' &&
      targetUser.isActive &&
      !isActive &&
      (await countActiveAdmins()) <= 1
    ) {
      return res.status(400).json({
        error: 'No puedes desactivar el ultimo administrador activo',
      });
    }

    const updateResult = await pool.query(
      `
        UPDATE "User"
        SET "isActive" = $1, "updatedAt" = NOW()
        WHERE id = $2
        RETURNING id, email, username, name, role, COALESCE("isActive", true) AS "isActive"
      `,
      [isActive, userId],
    );

    await logAdminAction(
      req.user!.userId,
      isActive ? 'activate_user' : 'deactivate_user',
      'user',
      userId,
      {
        username: targetUser.username,
      },
    );

    return res.json({
      message: isActive
        ? 'Usuario activado correctamente'
        : 'Usuario bloqueado correctamente',
      user: updateResult.rows[0],
    });
  } catch (error) {
    console.error('Error updating user status:', error);
    return res
      .status(500)
      .json({ error: 'No se pudo actualizar el estado del usuario' });
  }
});

router.post('/users/:id/password-reset', async (req: AuthRequest, res) => {
  const userId = parsePositiveInt(req.params.id);

  if (!userId) {
    return res.status(400).json({ error: 'ID de usuario invalido' });
  }

  try {
    const userResult = await pool.query<PasswordResetUser>(
      `
        SELECT id, email, username
        FROM "User"
        WHERE id = $1
        LIMIT 1
      `,
      [userId],
    );

    if (userResult.rows.length === 0) {
      return res.status(404).json({ error: 'Usuario no encontrado' });
    }

    const deliveryResult = await issuePasswordResetForUser(userResult.rows[0]);

    await logAdminAction(
      req.user!.userId,
      'send_password_reset',
      'user',
      userId,
      {
        email: userResult.rows[0].email,
        delivery: deliveryResult.delivery,
      },
    );

    return res.json({
      message: 'Correo de recuperacion reenviado correctamente',
      delivery: deliveryResult.delivery,
    });
  } catch (error) {
    console.error('Error sending admin password reset:', error);
    return res.status(500).json({
      error: 'No se pudo reenviar el correo de recuperacion',
    });
  }
});

router.get('/reports', async (req: AuthRequest, res) => {
  try {
    const status = typeof req.query.status === 'string' ? req.query.status : '';
    const params: string[] = [];
    let whereClause = '';

    if (status) {
      if (!isValidReportStatus(status)) {
        return res.status(400).json({ error: 'Estado de reporte invalido' });
      }

      params.push(status);
      whereClause = `WHERE COALESCE(r.status, 'open') = $1`;
    }

    const query = `
      SELECT
        r.id,
        r."userId",
        r."targetId",
        r.type,
        r.reason,
        COALESCE(r.status, 'open') AS status,
        r."reviewedAt",
        r."resolutionNotes",
        r."createdAt",
        reporter.username AS "reporterUsername",
        reviewer.username AS "reviewedByUsername",
        CASE
          WHEN r.type = 'post' THEN (
            SELECT LEFT(COALESCE(p.content, ''), 120)
            FROM "Post" p
            WHERE p.id = r."targetId"
          )
          WHEN r.type = 'user' THEN (
            SELECT u.username
            FROM "User" u
            WHERE u.id = r."targetId"
          )
          WHEN r.type = 'comment' THEN (
            SELECT LEFT(COALESCE(c.content, ''), 120)
            FROM "Comment" c
            WHERE c.id = r."targetId"
          )
          WHEN r.type = 'story' THEN (
            SELECT COALESCE(s."imagePath", 'story')
            FROM "Story" s
            WHERE s.id = r."targetId"
          )
          ELSE NULL
        END AS "targetLabel"
      FROM "Report" r
      JOIN "User" reporter ON reporter.id = r."userId"
      LEFT JOIN "User" reviewer ON reviewer.id = r."reviewedBy"
      ${whereClause}
      ORDER BY
        CASE COALESCE(r.status, 'open')
          WHEN 'open' THEN 0
          WHEN 'in_review' THEN 1
          WHEN 'resolved' THEN 2
          ELSE 3
        END,
        r."createdAt" DESC
    `;

    const result = await pool.query(query, params);
    return res.json(result.rows);
  } catch (error) {
    console.error('Error loading reports:', error);
    return res.status(500).json({ error: 'No se pudieron cargar los reportes' });
  }
});

router.patch('/reports/:id', async (req: AuthRequest, res) => {
  const reportId = parsePositiveInt(req.params.id);
  const status = String(req.body.status || '').trim();
  const resolutionNotes =
    typeof req.body.resolutionNotes === 'string'
      ? req.body.resolutionNotes.trim()
      : null;

  if (!reportId) {
    return res.status(400).json({ error: 'ID de reporte invalido' });
  }

  if (!isValidReportStatus(status)) {
    return res.status(400).json({ error: 'Estado de reporte invalido' });
  }

  try {
    const updateResult = await pool.query(
      `
        UPDATE "Report"
        SET
          status = $1,
          "reviewedBy" = $2,
          "reviewedAt" = NOW(),
          "resolutionNotes" = $3
        WHERE id = $4
        RETURNING *
      `,
      [status, req.user!.userId, resolutionNotes, reportId],
    );

    if (updateResult.rows.length === 0) {
      return res.status(404).json({ error: 'Reporte no encontrado' });
    }

    await logAdminAction(req.user!.userId, 'review_report', 'report', reportId, {
      status,
      resolutionNotes,
    });

    return res.json({
      message: 'Reporte actualizado correctamente',
      report: updateResult.rows[0],
    });
  } catch (error) {
    console.error('Error updating report:', error);
    return res.status(500).json({ error: 'No se pudo actualizar el reporte' });
  }
});

router.get('/moderation/posts', async (req: AuthRequest, res) => {
  try {
    const result = await pool.query(
      `
        SELECT
          p.id,
          p.content,
          p.image,
          p."createdAt",
          p."userId",
          u.username AS "authorUsername",
          u.name AS "authorName",
          (SELECT COUNT(*)::int FROM "Comment" c WHERE c."postId" = p.id) AS "commentsCount",
          (SELECT COUNT(*)::int FROM "Like" l WHERE l."postId" = p.id) AS "likesCount",
          (SELECT COUNT(*)::int FROM "Report" r WHERE r.type = 'post' AND r."targetId" = p.id) AS "reportsCount"
        FROM "Post" p
        JOIN "User" u ON u.id = p."userId"
        ORDER BY "reportsCount" DESC, p."createdAt" DESC
        LIMIT 100
      `,
    );

    return res.json(result.rows);
  } catch (error) {
    console.error('Error loading moderation posts:', error);
    return res
      .status(500)
      .json({ error: 'No se pudieron cargar las publicaciones' });
  }
});

router.delete('/moderation/posts/:id', async (req: AuthRequest, res) => {
  const postId = parsePositiveInt(req.params.id);

  if (!postId) {
    return res.status(400).json({ error: 'ID de publicacion invalido' });
  }

  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const postResult = await client.query(
      `
        SELECT id
        FROM "Post"
        WHERE id = $1
        LIMIT 1
      `,
      [postId],
    );

    if (postResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Publicacion no encontrada' });
    }

    await client.query(
      'DELETE FROM "CommentLike" WHERE "commentId" IN (SELECT id FROM "Comment" WHERE "postId" = $1)',
      [postId],
    );
    await client.query(
      'DELETE FROM "Like" WHERE "postId" = $1',
      [postId],
    );
    await client.query(
      'DELETE FROM "Bookmark" WHERE "postId" = $1',
      [postId],
    );
    await client.query(
      'DELETE FROM "Report" WHERE type = $1 AND "targetId" IN (SELECT id FROM "Comment" WHERE "postId" = $2)',
      ['comment', postId],
    );
    await client.query(
      'DELETE FROM "Comment" WHERE "postId" = $1',
      [postId],
    );
    await client.query(
      'DELETE FROM "Report" WHERE type = $1 AND "targetId" = $2',
      ['post', postId],
    );
    await client.query(
      'DELETE FROM "Post" WHERE id = $1',
      [postId],
    );

    await client.query('COMMIT');

    await logAdminAction(req.user!.userId, 'delete_post', 'post', postId);

    return res.json({ message: 'Publicacion eliminada correctamente' });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error deleting post as admin:', error);
    return res.status(500).json({ error: 'No se pudo eliminar la publicacion' });
  } finally {
    client.release();
  }
});

router.get('/moderation/comments', async (req: AuthRequest, res) => {
  try {
    const result = await pool.query(
      `
        SELECT
          c.id,
          c.content,
          c."createdAt",
          c."postId",
          c."userId",
          u.username AS "authorUsername",
          p.content AS "postContent",
          (SELECT COUNT(*)::int FROM "CommentLike" cl WHERE cl."commentId" = c.id) AS "likesCount",
          (SELECT COUNT(*)::int FROM "Report" r WHERE r.type = 'comment' AND r."targetId" = c.id) AS "reportsCount"
        FROM "Comment" c
        JOIN "User" u ON u.id = c."userId"
        JOIN "Post" p ON p.id = c."postId"
        ORDER BY "reportsCount" DESC, c."createdAt" DESC
        LIMIT 100
      `,
    );

    return res.json(result.rows);
  } catch (error) {
    console.error('Error loading moderation comments:', error);
    return res.status(500).json({ error: 'No se pudieron cargar los comentarios' });
  }
});

router.delete('/moderation/comments/:id', async (req: AuthRequest, res) => {
  const commentId = parsePositiveInt(req.params.id);

  if (!commentId) {
    return res.status(400).json({ error: 'ID de comentario invalido' });
  }

  try {
    const existingComment = await pool.query(
      'SELECT id FROM "Comment" WHERE id = $1 LIMIT 1',
      [commentId],
    );

    if (existingComment.rows.length === 0) {
      return res.status(404).json({ error: 'Comentario no encontrado' });
    }

    await pool.query('DELETE FROM "CommentLike" WHERE "commentId" = $1', [
      commentId,
    ]);
    await pool.query(
      'DELETE FROM "Report" WHERE type = $1 AND "targetId" = $2',
      ['comment', commentId],
    );
    await pool.query('DELETE FROM "Comment" WHERE id = $1', [commentId]);

    await logAdminAction(
      req.user!.userId,
      'delete_comment',
      'comment',
      commentId,
    );

    return res.json({ message: 'Comentario eliminado correctamente' });
  } catch (error) {
    console.error('Error deleting comment as admin:', error);
    return res.status(500).json({ error: 'No se pudo eliminar el comentario' });
  }
});

router.get('/moderation/stories', async (req: AuthRequest, res) => {
  try {
    const result = await pool.query(
      `
        SELECT
          s.id,
          s."imagePath",
          s."createdAt",
          s."expiresAt",
          s."deletedAt",
          s."deleteReason",
          s."userId",
          u.username,
          u.name
        FROM "Story" s
        JOIN "User" u ON u.id = s."userId"
        ORDER BY COALESCE(s."deletedAt", s."createdAt") DESC
        LIMIT 100
      `,
    );

    return res.json(result.rows);
  } catch (error) {
    console.error('Error loading moderation stories:', error);
    return res.status(500).json({ error: 'No se pudieron cargar las historias' });
  }
});

router.delete('/moderation/stories/:id', async (req: AuthRequest, res) => {
  const storyId = parsePositiveInt(req.params.id);

  if (!storyId) {
    return res.status(400).json({ error: 'ID de historia invalido' });
  }

  try {
    const updateResult = await pool.query(
      `
        UPDATE "Story"
        SET
          "deletedAt" = COALESCE("deletedAt", NOW()),
          "deleteReason" = 'admin'
        WHERE id = $1
        RETURNING id
      `,
      [storyId],
    );

    if (updateResult.rows.length === 0) {
      return res.status(404).json({ error: 'Historia no encontrada' });
    }

    await logAdminAction(req.user!.userId, 'archive_story', 'story', storyId);

    return res.json({ message: 'Historia archivada correctamente' });
  } catch (error) {
    console.error('Error deleting story as admin:', error);
    return res.status(500).json({ error: 'No se pudo archivar la historia' });
  }
});

router.get('/catalog/exercises', async (req: AuthRequest, res) => {
  try {
    const result = await pool.query('SELECT * FROM "Exercise" ORDER BY name ASC');
    return res.json(result.rows);
  } catch (error) {
    console.error('Error loading exercises catalog:', error);
    return res
      .status(500)
      .json({ error: 'No se pudo cargar el catalogo de ejercicios' });
  }
});

router.post('/catalog/exercises', async (req: AuthRequest, res) => {
  const { name, description, category } = req.body;

  if (!name || typeof name !== 'string') {
    return res
      .status(400)
      .json({ error: 'El nombre del ejercicio es obligatorio' });
  }

  try {
    const result = await pool.query(
      `
        INSERT INTO "Exercise" (name, description, category)
        VALUES ($1, $2, $3)
        RETURNING *
      `,
      [name.trim(), description?.trim() || null, category?.trim() || null],
    );

    await logAdminAction(
      req.user!.userId,
      'create_exercise',
      'exercise',
      result.rows[0].id,
      {
        name: result.rows[0].name,
      },
    );

    return res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating exercise:', error);
    return res.status(500).json({ error: 'No se pudo crear el ejercicio' });
  }
});

router.put('/catalog/exercises/:id', async (req: AuthRequest, res) => {
  const exerciseId = parsePositiveInt(req.params.id);
  const { name, description, category } = req.body;

  if (!exerciseId) {
    return res.status(400).json({ error: 'ID de ejercicio invalido' });
  }

  try {
    const result = await pool.query(
      `
        UPDATE "Exercise"
        SET
          name = COALESCE($1, name),
          description = COALESCE($2, description),
          category = COALESCE($3, category)
        WHERE id = $4
        RETURNING *
      `,
      [
        name?.trim() || null,
        description?.trim() || null,
        category?.trim() || null,
        exerciseId,
      ],
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Ejercicio no encontrado' });
    }

    await logAdminAction(
      req.user!.userId,
      'update_exercise',
      'exercise',
      exerciseId,
    );

    return res.json(result.rows[0]);
  } catch (error) {
    console.error('Error updating exercise:', error);
    return res.status(500).json({ error: 'No se pudo actualizar el ejercicio' });
  }
});

router.delete('/catalog/exercises/:id', async (req: AuthRequest, res) => {
  const exerciseId = parsePositiveInt(req.params.id);
  if (!exerciseId) {
    return res.status(400).json({ error: 'ID de ejercicio invalido' });
  }

  try {
    const result = await pool.query(
      'DELETE FROM "Exercise" WHERE id = $1 RETURNING id',
      [exerciseId],
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Ejercicio no encontrado' });
    }

    await logAdminAction(
      req.user!.userId,
      'delete_exercise',
      'exercise',
      exerciseId,
    );

    return res.json({ success: true });
  } catch (error) {
    console.error('Error deleting exercise:', error);
    return res.status(500).json({ error: 'No se pudo eliminar el ejercicio' });
  }
});

router.get('/catalog/foods', async (req: AuthRequest, res) => {
  try {
    const result = await pool.query('SELECT * FROM "Food" ORDER BY name ASC');
    return res.json(result.rows);
  } catch (error) {
    console.error('Error loading foods catalog:', error);
    return res
      .status(500)
      .json({ error: 'No se pudo cargar el catalogo de alimentos' });
  }
});

router.post('/catalog/foods', async (req: AuthRequest, res) => {
  const { name, calories, protein, carbs, fat, category } = req.body;

  if (
    !name ||
    calories == null ||
    protein == null ||
    carbs == null ||
    fat == null
  ) {
    return res.status(400).json({
      error: 'Todos los campos del alimento son obligatorios',
    });
  }

  try {
    const result = await pool.query(
      `
        INSERT INTO "Food" (name, calories, protein, carbs, fat, category)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING *
      `,
      [
        name.trim(),
        Number(calories),
        Number(protein),
        Number(carbs),
        Number(fat),
        category?.trim() || 'Mantenimiento',
      ],
    );

    await logAdminAction(
      req.user!.userId,
      'create_food',
      'food',
      result.rows[0].id,
      {
        name: result.rows[0].name,
      },
    );

    return res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating food:', error);
    return res.status(500).json({ error: 'No se pudo crear el alimento' });
  }
});

router.put('/catalog/foods/:id', async (req: AuthRequest, res) => {
  const foodId = parsePositiveInt(req.params.id);
  const { name, calories, protein, carbs, fat, category } = req.body;

  if (!foodId) {
    return res.status(400).json({ error: 'ID de alimento invalido' });
  }

  try {
    const result = await pool.query(
      `
        UPDATE "Food"
        SET
          name = COALESCE($1, name),
          calories = COALESCE($2, calories),
          protein = COALESCE($3, protein),
          carbs = COALESCE($4, carbs),
          fat = COALESCE($5, fat),
          category = COALESCE($6, category)
        WHERE id = $7
        RETURNING *
      `,
      [
        name?.trim() || null,
        calories != null ? Number(calories) : null,
        protein != null ? Number(protein) : null,
        carbs != null ? Number(carbs) : null,
        fat != null ? Number(fat) : null,
        category?.trim() || null,
        foodId,
      ],
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Alimento no encontrado' });
    }

    await logAdminAction(req.user!.userId, 'update_food', 'food', foodId);

    return res.json(result.rows[0]);
  } catch (error) {
    console.error('Error updating food:', error);
    return res.status(500).json({ error: 'No se pudo actualizar el alimento' });
  }
});

router.delete('/catalog/foods/:id', async (req: AuthRequest, res) => {
  const foodId = parsePositiveInt(req.params.id);
  if (!foodId) {
    return res.status(400).json({ error: 'ID de alimento invalido' });
  }

  try {
    const result = await pool.query(
      'DELETE FROM "Food" WHERE id = $1 RETURNING id',
      [foodId],
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Alimento no encontrado' });
    }

    await logAdminAction(req.user!.userId, 'delete_food', 'food', foodId);
    return res.json({ success: true });
  } catch (error) {
    console.error('Error deleting food:', error);
    return res.status(500).json({ error: 'No se pudo eliminar el alimento' });
  }
});

router.get('/catalog/sports', async (req: AuthRequest, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM "SportCategory" ORDER BY COALESCE("isActive", true) DESC, name ASC',
    );
    return res.json(result.rows);
  } catch (error) {
    console.error('Error loading sports catalog:', error);
    return res
      .status(500)
      .json({ error: 'No se pudo cargar el catalogo deportivo' });
  }
});

router.post('/catalog/sports', async (req: AuthRequest, res) => {
  const { name, description } = req.body;

  if (!name || typeof name !== 'string') {
    return res
      .status(400)
      .json({ error: 'El nombre del deporte es obligatorio' });
  }

  try {
    const result = await pool.query(
      `
        INSERT INTO "SportCategory" (name, description, "isActive", "createdAt", "updatedAt")
        VALUES ($1, $2, true, NOW(), NOW())
        RETURNING *
      `,
      [name.trim(), description?.trim() || null],
    );

    await logAdminAction(
      req.user!.userId,
      'create_sport_category',
      'sport_category',
      result.rows[0].id,
      {
        name: result.rows[0].name,
      },
    );

    return res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating sport category:', error);
    return res
      .status(500)
      .json({ error: 'No se pudo crear la categoria deportiva' });
  }
});

router.put('/catalog/sports/:id', async (req: AuthRequest, res) => {
  const sportId = parsePositiveInt(req.params.id);
  const { name, description, isActive } = req.body;

  if (!sportId) {
    return res.status(400).json({ error: 'ID de categoria invalido' });
  }

  try {
    const result = await pool.query(
      `
        UPDATE "SportCategory"
        SET
          name = COALESCE($1, name),
          description = COALESCE($2, description),
          "isActive" = COALESCE($3, "isActive"),
          "updatedAt" = NOW()
        WHERE id = $4
        RETURNING *
      `,
      [
        name?.trim() || null,
        description?.trim() || null,
        typeof isActive === 'boolean' ? isActive : null,
        sportId,
      ],
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Categoria no encontrada' });
    }

    await logAdminAction(
      req.user!.userId,
      'update_sport_category',
      'sport_category',
      sportId,
    );

    return res.json(result.rows[0]);
  } catch (error) {
    console.error('Error updating sport category:', error);
    return res
      .status(500)
      .json({ error: 'No se pudo actualizar la categoria deportiva' });
  }
});

router.delete('/catalog/sports/:id', async (req: AuthRequest, res) => {
  const sportId = parsePositiveInt(req.params.id);
  if (!sportId) {
    return res.status(400).json({ error: 'ID de categoria invalido' });
  }

  try {
    const result = await pool.query(
      'DELETE FROM "SportCategory" WHERE id = $1 RETURNING id',
      [sportId],
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Categoria no encontrada' });
    }

    await logAdminAction(
      req.user!.userId,
      'delete_sport_category',
      'sport_category',
      sportId,
    );
    return res.json({ success: true });
  } catch (error) {
    console.error('Error deleting sport category:', error);
    return res
      .status(500)
      .json({ error: 'No se pudo eliminar la categoria deportiva' });
  }
});

router.get('/catalog/workout-templates', async (req: AuthRequest, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM "WorkoutTemplate" ORDER BY COALESCE("isActive", true) DESC, "updatedAt" DESC',
    );
    return res.json(result.rows);
  } catch (error) {
    console.error('Error loading workout templates:', error);
    return res.status(500).json({
      error: 'No se pudieron cargar las plantillas de entrenamiento',
    });
  }
});

router.post('/catalog/workout-templates', async (req: AuthRequest, res) => {
  const { title, description, sport, difficulty, exercises, isActive } =
    req.body;

  if (!title || typeof title !== 'string') {
    return res.status(400).json({
      error: 'El titulo de la plantilla es obligatorio',
    });
  }

  try {
    const result = await pool.query(
      `
        INSERT INTO "WorkoutTemplate" (
          title,
          description,
          sport,
          difficulty,
          "exercisesJson",
          "isActive",
          "createdBy",
          "createdAt",
          "updatedAt"
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())
        RETURNING *
      `,
      [
        title.trim(),
        description?.trim() || null,
        sport?.trim() || null,
        difficulty?.trim() || null,
        JSON.stringify(Array.isArray(exercises) ? exercises : []),
        typeof isActive === 'boolean' ? isActive : true,
        req.user!.userId,
      ],
    );

    await logAdminAction(
      req.user!.userId,
      'create_workout_template',
      'workout_template',
      result.rows[0].id,
      {
        title: result.rows[0].title,
      },
    );

    return res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating workout template:', error);
    return res.status(500).json({
      error: 'No se pudo crear la plantilla de entrenamiento',
    });
  }
});

router.put('/catalog/workout-templates/:id', async (req: AuthRequest, res) => {
  const templateId = parsePositiveInt(req.params.id);
  const { title, description, sport, difficulty, exercises, isActive } =
    req.body;

  if (!templateId) {
    return res.status(400).json({ error: 'ID de plantilla invalido' });
  }

  try {
    const result = await pool.query(
      `
        UPDATE "WorkoutTemplate"
        SET
          title = COALESCE($1, title),
          description = COALESCE($2, description),
          sport = COALESCE($3, sport),
          difficulty = COALESCE($4, difficulty),
          "exercisesJson" = COALESCE($5, "exercisesJson"),
          "isActive" = COALESCE($6, "isActive"),
          "updatedAt" = NOW()
        WHERE id = $7
        RETURNING *
      `,
      [
        title?.trim() || null,
        description?.trim() || null,
        sport?.trim() || null,
        difficulty?.trim() || null,
        Array.isArray(exercises) ? JSON.stringify(exercises) : null,
        typeof isActive === 'boolean' ? isActive : null,
        templateId,
      ],
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Plantilla no encontrada' });
    }

    await logAdminAction(
      req.user!.userId,
      'update_workout_template',
      'workout_template',
      templateId,
    );

    return res.json(result.rows[0]);
  } catch (error) {
    console.error('Error updating workout template:', error);
    return res.status(500).json({
      error: 'No se pudo actualizar la plantilla de entrenamiento',
    });
  }
});

router.delete('/catalog/workout-templates/:id', async (req: AuthRequest, res) => {
  const templateId = parsePositiveInt(req.params.id);
  if (!templateId) {
    return res.status(400).json({ error: 'ID de plantilla invalido' });
  }

  try {
    const result = await pool.query(
      'DELETE FROM "WorkoutTemplate" WHERE id = $1 RETURNING id',
      [templateId],
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Plantilla no encontrada' });
    }

    await logAdminAction(
      req.user!.userId,
      'delete_workout_template',
      'workout_template',
      templateId,
    );
    return res.json({ success: true });
  } catch (error) {
    console.error('Error deleting workout template:', error);
    return res.status(500).json({
      error: 'No se pudo eliminar la plantilla de entrenamiento',
    });
  }
});

router.get('/catalog/nutrition-templates', async (req: AuthRequest, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM "NutritionTemplate" ORDER BY COALESCE("isActive", true) DESC, "updatedAt" DESC',
    );
    return res.json(result.rows);
  } catch (error) {
    console.error('Error loading nutrition templates:', error);
    return res.status(500).json({
      error: 'No se pudieron cargar las plantillas de nutricion',
    });
  }
});

router.post('/catalog/nutrition-templates', async (req: AuthRequest, res) => {
  const { title, goal, calories, protein, carbs, fat, notes, isActive } =
    req.body;

  if (!title || typeof title !== 'string') {
    return res.status(400).json({
      error: 'El titulo de la plantilla es obligatorio',
    });
  }

  try {
    const result = await pool.query(
      `
        INSERT INTO "NutritionTemplate" (
          title,
          goal,
          calories,
          protein,
          carbs,
          fat,
          notes,
          "isActive",
          "createdBy",
          "createdAt",
          "updatedAt"
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW(), NOW())
        RETURNING *
      `,
      [
        title.trim(),
        goal?.trim() || null,
        calories != null ? Number(calories) : null,
        protein != null ? Number(protein) : null,
        carbs != null ? Number(carbs) : null,
        fat != null ? Number(fat) : null,
        notes?.trim() || null,
        typeof isActive === 'boolean' ? isActive : true,
        req.user!.userId,
      ],
    );

    await logAdminAction(
      req.user!.userId,
      'create_nutrition_template',
      'nutrition_template',
      result.rows[0].id,
      {
        title: result.rows[0].title,
      },
    );

    return res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating nutrition template:', error);
    return res.status(500).json({
      error: 'No se pudo crear la plantilla de nutricion',
    });
  }
});

router.put(
  '/catalog/nutrition-templates/:id',
  async (req: AuthRequest, res) => {
    const templateId = parsePositiveInt(req.params.id);
    const { title, goal, calories, protein, carbs, fat, notes, isActive } =
      req.body;

    if (!templateId) {
      return res.status(400).json({ error: 'ID de plantilla invalido' });
    }

    try {
      const result = await pool.query(
        `
          UPDATE "NutritionTemplate"
          SET
            title = COALESCE($1, title),
            goal = COALESCE($2, goal),
            calories = COALESCE($3, calories),
            protein = COALESCE($4, protein),
            carbs = COALESCE($5, carbs),
            fat = COALESCE($6, fat),
            notes = COALESCE($7, notes),
            "isActive" = COALESCE($8, "isActive"),
            "updatedAt" = NOW()
          WHERE id = $9
          RETURNING *
        `,
        [
          title?.trim() || null,
          goal?.trim() || null,
          calories != null ? Number(calories) : null,
          protein != null ? Number(protein) : null,
          carbs != null ? Number(carbs) : null,
          fat != null ? Number(fat) : null,
          notes?.trim() || null,
          typeof isActive === 'boolean' ? isActive : null,
          templateId,
        ],
      );

      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'Plantilla no encontrada' });
      }

      await logAdminAction(
        req.user!.userId,
        'update_nutrition_template',
        'nutrition_template',
        templateId,
      );

      return res.json(result.rows[0]);
    } catch (error) {
      console.error('Error updating nutrition template:', error);
      return res.status(500).json({
        error: 'No se pudo actualizar la plantilla de nutricion',
      });
    }
  },
);

router.delete(
  '/catalog/nutrition-templates/:id',
  async (req: AuthRequest, res) => {
    const templateId = parsePositiveInt(req.params.id);
    if (!templateId) {
      return res.status(400).json({ error: 'ID de plantilla invalido' });
    }

    try {
      const result = await pool.query(
        'DELETE FROM "NutritionTemplate" WHERE id = $1 RETURNING id',
        [templateId],
      );
      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'Plantilla no encontrada' });
      }

      await logAdminAction(
        req.user!.userId,
        'delete_nutrition_template',
        'nutrition_template',
        templateId,
      );
      return res.json({ success: true });
    } catch (error) {
      console.error('Error deleting nutrition template:', error);
      return res.status(500).json({
        error: 'No se pudo eliminar la plantilla de nutricion',
      });
    }
  },
);

router.get('/audit-logs', async (req: AuthRequest, res) => {
  try {
    const result = await pool.query(
      `
        SELECT
          l.id,
          l.action,
          l."targetType",
          l."targetId",
          l.metadata,
          l."createdAt",
          u.username AS "adminUsername"
        FROM "AdminAuditLog" l
        JOIN "User" u ON u.id = l."adminUserId"
        ORDER BY l."createdAt" DESC
        LIMIT 100
      `,
    );

    return res.json(result.rows);
  } catch (error) {
    console.error('Error loading audit logs:', error);
    return res.status(500).json({
      error: 'No se pudieron cargar los logs de auditoria',
    });
  }
});

export default router;
