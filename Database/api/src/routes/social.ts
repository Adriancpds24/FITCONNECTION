import { randomUUID } from "crypto";
import fs from "fs/promises";
import path from "path";
import { Router } from "express";
import { Server } from "socket.io";
import pool from "../db";
import { authenticateToken, AuthRequest } from "../middleware/auth";

const router = Router();
import {
  ensureAllUploadDirs,
  postsUploadDir,
  storiesUploadDir,
} from "../config/uploads";

const STORIES_UPLOAD_DIR = storiesUploadDir();
const POSTS_UPLOAD_DIR = postsUploadDir();
const MAX_STORY_IMAGE_BYTES = 10 * 1024 * 1024;

let io: Server | null = null;
export function setSocketInstance(socketInstance: Server) {
  io = socketInstance;
}

function socketUserRoom(userId: number): string {
  return `user_${userId}`;
}

function emitChatMessage(senderId: number, receiverId: number, message: unknown): void {
  io?.to(socketUserRoom(senderId)).emit("chat:message", message);
  io?.to(socketUserRoom(receiverId)).emit("chat:message", message);
}

type StoryImagePayload = {
  mimeType: string;
  binary: Buffer;
  extension: string;
};

type StoryRow = {
  id: number;
  userId: number;
  imagePath: string | null;
  userImage?: string | null;
  createdAt: string;
  expiresAt: string;
  deletedAt: string | null;
  deleteReason: string | null;
  imageDeletedAt: string | null;
  username?: string;
  name?: string;
};

function toInt(value: unknown): number {
  return Number.parseInt(String(value ?? 0), 10) || 0;
}

async function isEitherBlocked(viewerId: number, targetId: number): Promise<boolean> {
  if (viewerId === targetId) return false;
  try {
    const r = await pool.query(
      `
        SELECT 1 FROM "UserBlock"
        WHERE ("blockerId" = $1 AND "blockedId" = $2)
           OR ("blockerId" = $2 AND "blockedId" = $1)
        LIMIT 1
      `,
      [viewerId, targetId],
    );
    return r.rows.length > 0;
  } catch {
    return false;
  }
}

function parseStoryImageDataUri(imageData: string): StoryImagePayload | null {
  const match = imageData.match(
    /^data:((?:image|video)\/(?:png|jpeg|jpg|webp|mp4|mov|quicktime));base64,([A-Za-z0-9+/=]+)$/,
  );

  if (!match) {
    return null;
  }

  const mimeType = match[1];
  const base64Payload = match[2];
  const binary = Buffer.from(base64Payload, "base64");

  if (binary.length === 0 || binary.length > MAX_STORY_IMAGE_BYTES) {
    return null;
  }

  const extensionMap: Record<string, string> = {
    "image/png": "png",
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/webp": "webp",
    "video/mp4": "mp4",
    "video/mov": "mov",
    "video/quicktime": "mov",
  };

  const extension = extensionMap[mimeType];
  if (!extension) {
    return null;
  }

  return { mimeType, binary, extension };
}

async function ensureStoriesUploadDir(): Promise<void> {
  await ensureAllUploadDirs();
}

async function ensurePostsUploadDir(): Promise<void> {
  await ensureAllUploadDirs();
}

export async function cleanupExpiredStories(): Promise<void> {
  const expiredStoriesResult = await pool.query(
    `
      SELECT id
      FROM "Story"
      WHERE "deletedAt" IS NULL AND "expiresAt" <= NOW()
    `,
  );

  const expiredStories = expiredStoriesResult.rows as Array<{
    id: number;
  }>;

  for (const story of expiredStories) {
    await pool.query(
      `
        UPDATE "Story"
        SET
          "deletedAt" = NOW(),
          "deleteReason" = 'expired'
        WHERE id = $1 AND "deletedAt" IS NULL
      `,
      [story.id],
    );
  }
}

let isStoryCleanupRunning = false;

export async function runStoryCleanupSafely(): Promise<void> {
  if (isStoryCleanupRunning) return;

  isStoryCleanupRunning = true;
  try {
    await cleanupExpiredStories();
  } catch (error) {
    console.error("Error cleaning expired stories:", error);
  } finally {
    isStoryCleanupRunning = false;
  }
}

function mapStoryResponse(row: StoryRow, currentUserId: number) {
  return {
    id: row.id,
    userId: row.userId,
    username: row.username ?? row.name ?? "usuario",
    userImage: row.userImage ?? null,
    image: row.imagePath,
    createdAt: row.createdAt,
    expiresAt: row.expiresAt,
    isOwn: row.userId === currentUserId,
    isExpired: false,
  };
}

// Crear una publicacion
router.post("/posts", authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const { content, image, imageData } = req.body;
    const normalizedContent =
      typeof content === "string" ? content.trim() : "";

    if (!normalizedContent && !image && !imageData) {
      return res.status(400).json({
        error: "Debes incluir texto o una imagen en la publicacion",
      });
    }

    let finalImagePath =
      typeof image === "string" && image.trim().length > 0
        ? image.trim()
        : null;

    if (imageData) {
      const parsedImage = parseStoryImageDataUri(imageData);
      if (!parsedImage) {
        return res.status(400).json({
          error: "Formato de imagen invalido. Usa PNG, JPG o WEBP con tamano maximo 10MB",
        });
      }

      await ensurePostsUploadDir();
      const fileName = `${randomUUID()}.${parsedImage.extension}`;
      const absolutePath = path.join(POSTS_UPLOAD_DIR, fileName);
      await fs.writeFile(absolutePath, parsedImage.binary);
      
      finalImagePath = `/uploads/posts/${fileName}`;
    }

    const query = `
      INSERT INTO "Post" ("userId", content, image, "createdAt")
      VALUES ($1, $2, $3, NOW())
      RETURNING *
    `;
    const result = await pool.query(query, [
      userId,
      normalizedContent,
      finalImagePath,
    ]);

    res.status(201).json({
      message: "Publicacion creada",
      post: result.rows[0],
    });
  } catch (error) {
    console.error("Error creating post:", error);
    res.status(500).json({ error: "Error del servidor al crear post" });
  }
});

// Eliminar una publicacion propia
router.delete("/posts/:id", authenticateToken, async (req: AuthRequest, res) => {
  const userId = req.user!.userId;
  const isAdmin = req.user!.role === "admin";
  const postId = Number.parseInt(req.params.id, 10);

  if (!Number.isInteger(postId) || postId <= 0) {
    return res.status(400).json({ error: "ID de publicacion invalido" });
  }

  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const postResult = await client.query(
      `
        SELECT id, "userId"
        FROM "Post"
        WHERE id = $1
        LIMIT 1
      `,
      [postId],
    );

    if (postResult.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({ error: "Publicacion no encontrada" });
    }

    const post = postResult.rows[0] as { id: number; userId: number };
    if (post.userId !== userId && !isAdmin) {
      await client.query("ROLLBACK");
      return res
        .status(403)
        .json({ error: "No tienes permiso para eliminar esta publicacion" });
    }

    await client.query(
      'DELETE FROM "CommentLike" WHERE "commentId" IN (SELECT id FROM "Comment" WHERE "postId" = $1)',
      [postId],
    );
    await client.query(`DELETE FROM "Like" WHERE "postId" = $1`, [postId]);
    await client.query(`DELETE FROM "Bookmark" WHERE "postId" = $1`, [postId]);
    await client.query(
      'DELETE FROM "Report" WHERE type = $1 AND "targetId" IN (SELECT id FROM "Comment" WHERE "postId" = $2)',
      ["comment", postId],
    );
    await client.query(`DELETE FROM "Report" WHERE type = $1 AND "targetId" = $2`, [
      "post",
      postId,
    ]);
    await client.query(`DELETE FROM "Comment" WHERE "postId" = $1`, [postId]);
    await client.query(`DELETE FROM "Post" WHERE id = $1`, [postId]);

    await client.query("COMMIT");
    return res.json({
      message:
        isAdmin && post.userId !== userId
          ? "Publicacion eliminada correctamente por administracion"
          : "Publicacion eliminada correctamente",
    });
  } catch (error) {
    await client.query("ROLLBACK");
    console.error("Error deleting post:", error);
    return res.status(500).json({ error: "Error del servidor al borrar post" });
  } finally {
    client.release();
  }
});

// Feed central de publicaciones
router.get(["/posts", "/feed"], authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const query = `
      SELECT 
        p.*, 
        u.name as "authorName", 
        u.username as "authorUsername", 
        u."imagePath",
        (SELECT COUNT(*) FROM "Like" l WHERE l."postId" = p.id)::int as "likesCount",
        EXISTS(SELECT 1 FROM "Like" l WHERE l."postId" = p.id AND l."userId" = $1) as "isLiked",
        EXISTS(SELECT 1 FROM "Bookmark" b WHERE b."postId" = p.id AND b."userId" = $1) as "isBookmarked"
      FROM "Post" p
      JOIN "User" u ON p."userId" = u.id
      ORDER BY p."createdAt" DESC
    `;
    const result = await pool.query(query, [userId]);
    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching activity feed:", error);
    res.status(500).json({ error: "Error del servidor al obtener el feed" });
  }
});

// Crear historia (expira en 24h)
router.post("/stories", authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const { imageData } = req.body as { imageData?: string };

    if (!imageData) {
      return res.status(400).json({ error: "La imagen de la historia es obligatoria" });
    }

    // Special case for sharing post to story
    if (imageData.startsWith("SHARED_POST:")) {
      await runStoryCleanupSafely();
      const insertStoryResult = await pool.query(
        `
          INSERT INTO "Story" ("userId", "imagePath", "expiresAt")
          VALUES ($1, $2, NOW() + INTERVAL '24 hours')
          RETURNING id, "userId", "imagePath", "createdAt", "expiresAt"
        `,
        [userId, imageData],
      );
      const storyRow = insertStoryResult.rows[0] as StoryRow;
      return res.status(201).json({
        message: "Post compartido en historia correctamente",
        story: {
          id: storyRow.id,
          userId: storyRow.userId,
          image: storyRow.imagePath,
          createdAt: storyRow.createdAt,
          expiresAt: storyRow.expiresAt,
        },
      });
    }

    const parsedImage = parseStoryImageDataUri(imageData);
    if (!parsedImage) {
      return res.status(400).json({
        error: "Formato de imagen invalido. Usa PNG, JPG o WEBP con tamano maximo 10MB",
      });
    }

    await ensureStoriesUploadDir();
    await runStoryCleanupSafely();

    const storyFilename = `${randomUUID()}.${parsedImage.extension}`;
    const storyAbsolutePath = path.join(STORIES_UPLOAD_DIR, storyFilename);
    await fs.writeFile(storyAbsolutePath, parsedImage.binary);

    const storyPublicPath = `/uploads/stories/${storyFilename}`;
    const insertStoryResult = await pool.query(
      `
        INSERT INTO "Story" ("userId", "imagePath", "expiresAt")
        VALUES ($1, $2, NOW() + INTERVAL '24 hours')
        RETURNING id, "userId", "imagePath", "createdAt", "expiresAt"
      `,
      [userId, storyPublicPath],
    );

    const storyRow = insertStoryResult.rows[0] as StoryRow;
    return res.status(201).json({
      message: "Historia creada correctamente",
      story: {
        id: storyRow.id,
        userId: storyRow.userId,
        image: storyRow.imagePath,
        createdAt: storyRow.createdAt,
        expiresAt: storyRow.expiresAt,
      },
    });
  } catch (error) {
    console.error("Error creating story:", error);
    return res.status(500).json({ error: "Error del servidor al crear historia" });
  }
});

// Historias activas
router.get("/stories", authenticateToken, async (req: AuthRequest, res) => {
  try {
    const currentUserId = req.user!.userId;
    await runStoryCleanupSafely();

    const result = await pool.query(
      `
        SELECT
          s.id,
          s."userId",
          s."imagePath",
          s."createdAt",
          s."expiresAt",
          u."imagePath" as "userImage",
          u.username,
          u.name
        FROM "Story" s
        JOIN "User" u ON u.id = s."userId"
        WHERE s."deletedAt" IS NULL AND s."expiresAt" > NOW()
        ORDER BY s."createdAt" DESC
      `,
    );

    const stories = (result.rows as StoryRow[]).map((row) =>
      mapStoryResponse(row, currentUserId),
    );
    return res.json(stories);
  } catch (error) {
    console.error("Error fetching stories:", error);
    return res.status(500).json({ error: "Error del servidor al obtener historias" });
  }
});

// Eliminar historia antes de que expire
router.delete("/stories/:storyId", authenticateToken, async (req: AuthRequest, res) => {
  try {
    const currentUserId = req.user!.userId;
    const isAdmin = req.user!.role === "admin";
    const storyId = Number(req.params.storyId);

    if (!Number.isInteger(storyId) || storyId <= 0) {
      return res.status(400).json({ error: "ID de historia invalido" });
    }

    const storyResult = await pool.query(
      `
        SELECT id, "userId", "imagePath", "deletedAt"
        FROM "Story"
        WHERE id = $1
        LIMIT 1
      `,
      [storyId],
    );

    if (storyResult.rows.length === 0) {
      return res.status(404).json({ error: "Historia no encontrada" });
    }

    const story = storyResult.rows[0] as StoryRow;
    if (story.userId !== currentUserId && !isAdmin) {
      return res.status(403).json({ error: "No tienes permiso para borrar esta historia" });
    }

    if (story.deletedAt) {
      return res.json({ message: "La historia ya estaba archivada" });
    }

    const deleteReason =
      story.userId !== currentUserId && isAdmin ? "admin" : "manual";

    await pool.query(
      `
        UPDATE "Story"
        SET
          "deletedAt" = NOW(),
          "deleteReason" = $2
        WHERE id = $1
      `,
      [storyId, deleteReason],
    );

    return res.json({ message: "Historia archivada correctamente" });
  } catch (error) {
    console.error("Error deleting story:", error);
    return res.status(500).json({ error: "Error del servidor al borrar historia" });
  }
});

// Archivo de historias del usuario (expiradas o borradas)
router.get("/stories/archive", authenticateToken, async (req: AuthRequest, res) => {
  try {
    const currentUserId = req.user!.userId;
    await runStoryCleanupSafely();

    const result = await pool.query(
      `
        SELECT
          id,
          "userId",
          "imagePath",
          "createdAt",
          "expiresAt",
          "deletedAt",
          "deleteReason",
          "imageDeletedAt"
        FROM "Story"
        WHERE "userId" = $1 AND "deletedAt" IS NOT NULL
        ORDER BY "deletedAt" DESC
      `,
      [currentUserId],
    );

    const archive = (result.rows as StoryRow[]).map((row) => ({
      id: row.id,
      userId: row.userId,
      image: row.imagePath,
      createdAt: row.createdAt,
      expiresAt: row.expiresAt,
      archivedAt: row.deletedAt,
      imageDeletedAt: row.imageDeletedAt,
      deleteReason: row.deleteReason,
      isOwn: true,
      isExpired: row.deleteReason === "expired",
    }));

    return res.json(archive);
  } catch (error) {
    console.error("Error fetching story archive:", error);
    return res.status(500).json({ error: "Error del servidor al obtener archivo" });
  }
});
// Listar/buscar usuarios
router.get('/users', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const { query } = req.query;
        let sql = `SELECT id, name, username, email, bio, sport, "imagePath", "isPrivate", xp, level, fitcoins, streak FROM "User"`;
        const params: any[] = [];
        
        if (query) {
            sql += ` WHERE name ILIKE $1 OR username ILIKE $1`;
            params.push(`%${query}%`);
        }
        
        const result = await pool.query(sql, params);
        res.json(result.rows);
    } catch (e) {
        res.status(500).json({ error: 'Error fetching users' });
    }
});

// Obtener perfil por Username (más robusto para el frontend)
router.get('/profile/user/:username', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const username = req.params.username;
        
        const profileQuery = await pool.query(`
            SELECT 
                u.id, u.name, u.username, u.bio, u."imagePath", u.sport, u.xp, u.level, u.fitcoins, u.streak,
                COALESCE(u."isPrivate", false) as "isPrivate",
                COALESCE(w.steps, 0) as steps,
                COALESCE(w."burnedCalories", 0) as "burnedCalories",
                COALESCE(w."heartRate", 0) as "heartRate"
            FROM "User" u
            LEFT JOIN (
                SELECT "userId", steps, "burnedCalories", "heartRate"
                FROM "UserWearableData"
                WHERE "date" = CURRENT_DATE
            ) w ON u.id = w."userId"
            WHERE LOWER(u.username) = LOWER($1)
              AND COALESCE(u."isActive", true) = true
        `, [username]);
        if (profileQuery.rows.length === 0) return res.status(404).json({error: 'Usuario no encontrado'});
        const profile = profileQuery.rows[0];
        const profileId = profile.id;

        if (await isEitherBlocked(myId, profileId)) {
            return res.json({
                id: profile.id,
                name: profile.name,
                username: profile.username,
                bio: profile.bio,
                imagePath: profile.imagePath,
                sport: profile.sport,
                isPrivate: profile.isPrivate,
                isFollowing: false,
                isRequested: false,
                followersCount: 0,
                followingCount: 0,
                postsCount: 0,
                restricted: true,
                restrictionReason: 'blocked',
            });
        }
        
        const followQuery = await pool.query(`SELECT status FROM "Follow" WHERE "followerId" = $1 AND "followingId" = $2`, [myId, profileId]);
        const followStatus = followQuery.rows.length > 0 ? followQuery.rows[0].status : null;
        profile.isFollowing = followStatus === 'accepted';
        profile.isRequested = followStatus === 'pending';

        // Estadísticas
        const followersCount = await pool.query(`SELECT count(*)::int FROM "Follow" WHERE "followingId" = $1 AND status = 'accepted'`, [profileId]);
        const followingCount = await pool.query(`SELECT count(*)::int FROM "Follow" WHERE "followerId" = $1 AND status = 'accepted'`, [profileId]);
        const postsCount = await pool.query(`SELECT count(*)::int FROM "Post" WHERE "userId" = $1`, [profileId]);
        
        profile.followersCount = toInt(followersCount.rows[0].count);
        profile.followingCount = toInt(followingCount.rows[0].count);
        profile.postsCount = toInt(postsCount.rows[0].count);
        
        res.json(profile);
    } catch (e) {
        console.error('Error in profile by username:', e);
        res.status(500).json({ error: 'Error al cargar perfil por username' });
    }
});

// Obtener perfil por ID y si lo sigo
router.get('/profile/:id', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const profileId = parseInt(req.params.id);
        if (isNaN(profileId)) return res.status(400).json({error: 'ID inválido'});
        
        const profileQuery = await pool.query(`
            SELECT 
                u.id, u.name, u.username, u.bio, u."imagePath", u.sport, u.xp, u.level, u.fitcoins, u.streak,
                COALESCE(u."isPrivate", false) as "isPrivate",
                COALESCE(w.steps, 0) as steps,
                COALESCE(w."burnedCalories", 0) as "burnedCalories",
                COALESCE(w."heartRate", 0) as "heartRate"
            FROM "User" u
            LEFT JOIN (
                SELECT "userId", steps, "burnedCalories", "heartRate"
                FROM "UserWearableData"
                WHERE "date" = CURRENT_DATE
            ) w ON u.id = w."userId"
            WHERE u.id = $1
        `, [profileId]);
        if (profileQuery.rows.length === 0) return res.status(404).json({error: 'No encontrado'});
        const profile = profileQuery.rows[0];

        if (await isEitherBlocked(myId, profileId)) {
            return res.json({
                id: profile.id,
                name: profile.name,
                username: profile.username,
                bio: profile.bio,
                imagePath: profile.imagePath,
                sport: profile.sport,
                isPrivate: profile.isPrivate,
                isFollowing: false,
                isRequested: false,
                followersCount: 0,
                followingCount: 0,
                postsCount: 0,
                restricted: true,
                restrictionReason: 'blocked',
            });
        }
        
        const followQuery = await pool.query(`SELECT status FROM "Follow" WHERE "followerId" = $1 AND "followingId" = $2`, [myId, profileId]);
        const followStatus = followQuery.rows.length > 0 ? followQuery.rows[0].status : null;
        profile.isFollowing = followStatus === 'accepted';
        profile.isRequested = followStatus === 'pending';

        // Agregar estadisticas reales
        const followersCount = await pool.query(`SELECT count(*)::int FROM "Follow" WHERE "followingId" = $1 AND status = 'accepted'`, [profileId]);
        const followingCount = await pool.query(`SELECT count(*)::int FROM "Follow" WHERE "followerId" = $1 AND status = 'accepted'`, [profileId]);
        
        profile.followersCount = toInt(followersCount.rows[0].count);
        profile.followingCount = toInt(followingCount.rows[0].count);
        profile.postsCount = toInt((await pool.query(`SELECT count(*)::int FROM "Post" WHERE "userId" = $1`, [profileId])).rows[0].count);
        
        res.json(profile);
    } catch (e) {
        console.error('Error in profile by id:', e);
        res.status(500).json({ error: 'Error al cargar perfil' });
    }
});

// Actualizar perfil de usuario
router.put('/profile', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const { name, bio, sport, imagePath, username, isPrivate } = req.body;
        
        // Si se intenta cambiar el username, validar que no exista ya
        if (username) {
            const checkUser = await pool.query('SELECT id FROM "User" WHERE username = $1 AND id != $2', [username, userId]);
            if (checkUser.rows.length > 0) {
                return res.status(400).json({ error: 'El nombre de usuario ya está en uso' });
            }
        }

        const updateQuery = `
            UPDATE "User"
            SET 
                name = COALESCE($1, name),
                bio = COALESCE($2, bio),
                "sport" = COALESCE($3, "sport"),
                "imagePath" = COALESCE($4, "imagePath"),
                username = COALESCE($5, username),
                "isPrivate" = COALESCE($6, "isPrivate"),
                "updatedAt" = NOW()
            WHERE id = $7
            RETURNING id, name, username, bio, "imagePath", sport, "isPrivate", xp, level, fitcoins, streak
        `;
        
        const result = await pool.query(updateQuery, [name, bio, sport, imagePath, username, isPrivate, userId]);
        if (result.rows.length === 0) return res.status(404).json({error: 'Usuario no encontrado'});
        
        res.json({
            message: 'Perfil actualizado con éxito',
            user: result.rows[0]
        });
    } catch (e) {
        console.error('Error updating profile:', e);
        res.status(500).json({ error: 'Error al actualizar perfil' });
    }
});

// Seguir usuario por Username
router.post('/follow/user/:username', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const targetUsername = req.params.username;
        
        const targetUserResult = await pool.query('SELECT id, "isPrivate" FROM "User" WHERE LOWER(username) = LOWER($1)', [targetUsername]);
        if (targetUserResult.rows.length === 0) return res.status(404).json({error: 'No encontrado'});
        const targetId = targetUserResult.rows[0].id;
        const isPrivate = targetUserResult.rows[0].isPrivate;
        
        if (myId === targetId) return res.status(400).json({error: 'No puedes seguirte a ti mismo'});
        if (await isEitherBlocked(myId, targetId)) {
            return res.status(403).json({ error: 'No puedes interactuar con este usuario' });
        }
        
        const status = isPrivate ? 'pending' : 'accepted';
        const followResult = await pool.query('INSERT INTO "Follow" ("followerId", "followingId", "status") VALUES ($1, $2, $3) ON CONFLICT ( "followerId", "followingId" ) DO UPDATE SET status = EXCLUDED.status WHERE "Follow".status = \'rejected\' RETURNING status', [myId, targetId, status]);
        
        if (followResult.rowCount && followResult.rowCount > 0) {
            const msg = status === 'pending' ? 'quiere seguirte' : 'ha empezado a seguirte';
            const type = status === 'pending' ? 'follow_request' : 'follow';
            await createNotification(targetId, type, msg, myId);
        }
        res.json({ message: status === 'pending' ? 'Solicitud enviada' : 'Siguiendo', status });
    } catch (e) {
        console.error('Error in follow by username:', e);
        res.status(500).json({ error: 'Error al seguir' });
    }
});

router.post('/unfollow/user/:username', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const targetUsername = req.params.username;

        const targetUser = await pool.query('SELECT id FROM "User" WHERE LOWER(username) = LOWER($1)', [targetUsername]);
        if (targetUser.rows.length === 0) return res.status(404).json({error: 'No encontrado'});

        await pool.query(
            'DELETE FROM "Follow" WHERE "followerId" = $1 AND "followingId" = $2',
            [myId, targetUser.rows[0].id],
        );

        res.json({ message: 'Dejaste de seguir' });
    } catch (e) {
        console.error('Error in unfollow by username:', e);
        res.status(500).json({ error: 'Error al dejar de seguir' });
    }
});

router.post('/block/user/:username', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const targetUsername = req.params.username;
        const targetUser = await pool.query('SELECT id FROM "User" WHERE LOWER(username) = LOWER($1)', [targetUsername]);
        if (targetUser.rows.length === 0) return res.status(404).json({ error: 'No encontrado' });
        const targetId = targetUser.rows[0].id;
        if (myId === targetId) return res.status(400).json({ error: 'No puedes bloquearte a ti mismo' });
        await pool.query(
            `
                INSERT INTO "UserBlock" ("blockerId", "blockedId")
                VALUES ($1, $2)
                ON CONFLICT ("blockerId", "blockedId") DO NOTHING
            `,
            [myId, targetId],
        );
        await pool.query(
            'DELETE FROM "Follow" WHERE ("followerId" = $1 AND "followingId" = $2) OR ("followerId" = $2 AND "followingId" = $1)',
            [myId, targetId],
        );
        return res.json({ message: 'Usuario bloqueado' });
    } catch (e) {
        console.error('block user:', e);
        return res.status(500).json({ error: 'Error al bloquear' });
    }
});

router.delete('/block/user/:username', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const targetUsername = req.params.username;
        const targetUser = await pool.query('SELECT id FROM "User" WHERE LOWER(username) = LOWER($1)', [targetUsername]);
        if (targetUser.rows.length === 0) return res.status(404).json({ error: 'No encontrado' });
        const targetId = targetUser.rows[0].id;
        await pool.query(
            'DELETE FROM "UserBlock" WHERE "blockerId" = $1 AND "blockedId" = $2',
            [myId, targetId],
        );
        return res.json({ message: 'Usuario desbloqueado' });
    } catch (e) {
        console.error('unblock user:', e);
        return res.status(500).json({ error: 'Error al desbloquear' });
    }
});

// Obtener solicitudes de seguimiento pendientes
router.get('/follow/requests', authenticateToken, async (req: AuthRequest, res) => {
    try {
        res.set('Cache-Control', 'no-store');
        const userId = req.user!.userId;
        const query = `
            SELECT u.id, u.name, u.username, u."imagePath" as "userImage"
            FROM "Follow" f
            JOIN "User" u ON f."followerId" = u.id
            WHERE f."followingId" = $1 AND f.status = 'pending'
        `;
        const result = await pool.query(query, [userId]);
        res.json(result.rows);
    } catch (e) {
        res.status(500).json({ error: 'Error al obtener solicitudes' });
    }
});

// Aceptar solicitud de seguimiento
router.post('/follow/request/:requesterId/accept', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const requesterId = parseInt(req.params.requesterId);
        if (!Number.isInteger(requesterId)) {
            return res.status(400).json({ error: 'ID de solicitud invalido' });
        }
        
        const result = await pool.query(
            'UPDATE "Follow" SET status = \'accepted\' WHERE "followerId" = $1 AND "followingId" = $2 AND status = \'pending\' RETURNING *',
            [requesterId, myId]
        );
        
        if (result.rows.length === 0) {
            const existing = await pool.query(
                'SELECT status FROM "Follow" WHERE "followerId" = $1 AND "followingId" = $2',
                [requesterId, myId]
            );
            if (existing.rows[0]?.status === 'accepted') {
                await pool.query(
                    'UPDATE "Notification" SET "read" = true WHERE "userId" = $1 AND "senderId" = $2 AND type = \'follow_request\'',
                    [myId, requesterId]
                );
                return res.json({ message: 'Solicitud ya aceptada' });
            }
            return res.status(404).json({ error: 'Solicitud no encontrada' });
        }
        
        await pool.query(
            'UPDATE "Notification" SET "read" = true WHERE "userId" = $1 AND "senderId" = $2 AND type = \'follow_request\'',
            [myId, requesterId]
        );
        await createNotification(requesterId, 'follow_accept', 'ha aceptado tu solicitud de seguimiento', myId);
        res.json({ message: 'Solicitud aceptada' });
    } catch (e) {
        res.status(500).json({ error: 'Error al aceptar solicitud' });
    }
});

// Rechazar solicitud de seguimiento
router.post('/follow/request/:requesterId/reject', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const requesterId = parseInt(req.params.requesterId);
        if (!Number.isInteger(requesterId)) {
            return res.status(400).json({ error: 'ID de solicitud invalido' });
        }
        
        const result = await pool.query(
            'DELETE FROM "Follow" WHERE "followerId" = $1 AND "followingId" = $2 AND status = \'pending\' RETURNING *',
            [requesterId, myId]
        );
        
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Solicitud no encontrada' });
        }
        
        await pool.query(
            'UPDATE "Notification" SET "read" = true WHERE "userId" = $1 AND "senderId" = $2 AND type = \'follow_request\'',
            [myId, requesterId]
        );
        res.json({ message: 'Solicitud rechazada' });
    } catch (e) {
        res.status(500).json({ error: 'Error al rechazar solicitud' });
    }
});
// Rutas anidadas por Username para facilitar el frontend
router.get('/profile/user/:username/following', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const username = req.params.username;
        const user = await pool.query('SELECT id FROM "User" WHERE LOWER(username) = LOWER($1)', [username]);
        if (user.rows.length === 0) return res.status(404).json({error: 'No encontrado'});
        const userId = user.rows[0].id;
        
        const query = `
            SELECT u.id, u.name, u.username, u."imagePath" as "userImage"
            FROM "Follow" f
            JOIN "User" u ON f."followingId" = u.id
            WHERE f."followerId" = $1 AND f.status = 'accepted'
        `;
        const result = await pool.query(query, [userId]);
        res.json(result.rows);
    } catch (e) {
        res.status(500).json({ error: 'Error al obtener siguiendo' });
    }
});

router.get('/profile/user/:username/followers', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const username = req.params.username;
        const user = await pool.query('SELECT id FROM "User" WHERE LOWER(username) = LOWER($1)', [username]);
        if (user.rows.length === 0) return res.status(404).json({error: 'No encontrado'});
        const userId = user.rows[0].id;
        
        const query = `
            SELECT u.id, u.name, u.username, u."imagePath" as "userImage"
            FROM "Follow" f
            JOIN "User" u ON f."followerId" = u.id
            WHERE f."followingId" = $1 AND f.status = 'accepted'
        `;
        const result = await pool.query(query, [userId]);
        res.json(result.rows);
    } catch (e) {
        res.status(500).json({ error: 'Error al obtener seguidores' });
    }
});

router.get('/profile/user/:username/posts', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const username = req.params.username;
        const user = await pool.query('SELECT id FROM "User" WHERE LOWER(username) = LOWER($1)', [username]);
        if (user.rows.length === 0) return res.status(404).json({error: 'No encontrado'});
        const userId = user.rows[0].id;
        if (await isEitherBlocked(myId, userId)) {
            return res.json([]);
        }
        
        const query = `
            SELECT p.*, u.name as "authorName", u.username as "authorUsername"
            FROM "Post" p
            JOIN "User" u ON p."userId" = u.id
            WHERE p."userId" = $1
            ORDER BY p."createdAt" DESC
        `;
        const result = await pool.query(query, [userId]);
        res.json(result.rows);
    } catch (e) {
        res.status(500).json({ error: 'Error al obtener posts del usuario' });
    }
});

// Mensajes por username
router.get('/messages/user/:username', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const targetUsername = req.params.username;
        const targetUser = await pool.query('SELECT id FROM "User" WHERE LOWER(username) = LOWER($1)', [targetUsername]);
        if (targetUser.rows.length === 0) return res.status(404).json({error: 'No encontrado'});
        const targetId = targetUser.rows[0].id;
        if (await isEitherBlocked(myId, targetId)) {
            return res.json([]);
        }

        await pool.query(
            `
                UPDATE "Message"
                SET "read" = true
                WHERE "senderId" = $1 AND "receiverId" = $2 AND "read" = false
            `,
            [targetId, myId],
        );
        
        const q = `
            SELECT
                m.*,
                sender.username as "senderUsername",
                receiver.username as "receiverUsername"
            FROM "Message" m
            JOIN "User" sender ON sender.id = m."senderId"
            JOIN "User" receiver ON receiver.id = m."receiverId"
            LEFT JOIN "ConversationClear" cc
              ON cc."userId" = $1
             AND cc."otherUserId" = $2
            WHERE (
                ("senderId" = $1 AND "receiverId" = $2)
                OR ("senderId" = $2 AND "receiverId" = $1)
            )
            AND (cc."clearedAt" IS NULL OR m."createdAt" > cc."clearedAt")
            ORDER BY "createdAt" ASC
        `;
        const result = await pool.query(q, [myId, targetId]);
        res.json(result.rows);
    } catch (e) {
        res.status(500).json({ error: 'Error al obtener mensajes' });
    }
});

router.delete('/messages/user/:username', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const targetUsername = req.params.username;
        const targetUser = await pool.query<{ id: number }>(
            'SELECT id FROM "User" WHERE LOWER(username) = LOWER($1)',
            [targetUsername],
        );

        if (targetUser.rows.length === 0) {
            return res.status(404).json({ error: 'No encontrado' });
        }

        const targetId = targetUser.rows[0].id;
        if (targetId === myId) {
            return res.status(400).json({ error: 'No puedes eliminar tu propia conversación' });
        }

        await pool.query(
            `
                INSERT INTO "ConversationClear" ("userId", "otherUserId", "clearedAt")
                VALUES ($1, $2, NOW())
                ON CONFLICT ("userId", "otherUserId")
                DO UPDATE SET "clearedAt" = NOW()
            `,
            [myId, targetId],
        );

        return res.json({ message: 'Conversación eliminada correctamente' });
    } catch (e) {
        console.error('Error deleting conversation:', e);
        return res.status(500).json({ error: 'Error al eliminar la conversación' });
    }
});

router.get('/messages/conversations', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const q = `
            WITH user_clears AS (
                SELECT "otherUserId", "clearedAt"
                FROM "ConversationClear"
                WHERE "userId" = $1
            ),
            ranked_messages AS (
                SELECT
                    m.id,
                    m.content,
                    m."createdAt",
                    CASE
                        WHEN m."senderId" = $1 THEN m."receiverId"
                        ELSE m."senderId"
                    END as "otherUserId",
                    ROW_NUMBER() OVER (
                        PARTITION BY CASE
                            WHEN m."senderId" = $1 THEN m."receiverId"
                            ELSE m."senderId"
                        END
                        ORDER BY m."createdAt" DESC
                    ) as rn
                FROM "Message" m
                LEFT JOIN user_clears uc ON uc."otherUserId" = CASE
                    WHEN m."senderId" = $1 THEN m."receiverId"
                    ELSE m."senderId"
                END
                WHERE (m."senderId" = $1 OR m."receiverId" = $1)
                  AND (uc."clearedAt" IS NULL OR m."createdAt" > uc."clearedAt")
            ),
            unread_counts AS (
                SELECT
                    m."senderId" as "otherUserId",
                    COUNT(*)::int as "unreadCount"
                FROM "Message" m
                LEFT JOIN user_clears uc ON uc."otherUserId" = m."senderId"
                WHERE m."receiverId" = $1
                  AND m."read" = false
                  AND (uc."clearedAt" IS NULL OR m."createdAt" > uc."clearedAt")
                GROUP BY m."senderId"
            )
            SELECT
                rm.id,
                rm.content,
                rm."createdAt",
                u.id as "userId",
                u.username,
                u.name,
                u.bio,
                u.sport,
                u."imagePath",
                COALESCE(uc."unreadCount", 0) as "unreadCount"
            FROM ranked_messages rm
            JOIN "User" u ON u.id = rm."otherUserId"
            LEFT JOIN unread_counts uc ON uc."otherUserId" = rm."otherUserId"
            WHERE rm.rn = 1
            ORDER BY rm."createdAt" DESC
        `;
        const result = await pool.query(q, [myId]);
        res.json(result.rows);
    } catch (e) {
        console.error('Error fetching conversations:', e);
        res.status(500).json({ error: 'Error al obtener conversaciones' });
    }
});

router.post('/messages/user/:username', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const targetUsername = req.params.username;
        const { content } = req.body;
        
        const targetUser = await pool.query<{ id: number; username: string }>(
            'SELECT id, username FROM "User" WHERE LOWER(username) = LOWER($1)',
            [targetUsername],
        );
        if (targetUser.rows.length === 0) return res.status(404).json({error: 'No encontrado'});
        const targetId = targetUser.rows[0].id;
        const receiverUsername = targetUser.rows[0].username;
        if (await isEitherBlocked(myId, targetId)) {
            return res.status(403).json({ error: 'No puedes enviar mensajes a este usuario' });
        }
        
        const q = 'INSERT INTO "Message" ("senderId", "receiverId", content) VALUES ($1, $2, $3) RETURNING *';
        const result = await pool.query(q, [myId, targetId, content]);
        const message = {
            ...result.rows[0],
            senderUsername: req.user!.username,
            receiverUsername,
        };
        emitChatMessage(myId, targetId, message);
        res.status(201).json(message);
    } catch (e) {
        res.status(500).json({ error: 'Error al enviar mensaje' });
    }
});

// Obtener mensajes con alguien
router.get('/messages/:id', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const otherId = parseInt(req.params.id);
        const q = `
            SELECT * FROM "Message"
            WHERE ("senderId" = $1 AND "receiverId" = $2)
               OR ("senderId" = $2 AND "receiverId" = $1)
            ORDER BY "createdAt" ASC
        `;
        const result = await pool.query(q, [myId, otherId]);
        res.json(result.rows);
    } catch (e) {
        res.status(500).json({ error: 'Error cargando mensajes' });
    }
});

// Enviar mensaje
router.post('/messages/:id', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const otherId = parseInt(req.params.id);
        const { content } = req.body;
        if (!content) return res.status(400).json({ error: 'Mensaje vacío' });
        
        const q = `
            INSERT INTO "Message" ("senderId", "receiverId", content, "createdAt")
            VALUES ($1, $2, $3, NOW())
            RETURNING *
        `;
        const result = await pool.query(q, [myId, otherId, content]);
        const users = await pool.query<{ id: number; username: string }>(
            'SELECT id, username FROM "User" WHERE id = ANY($1::int[])',
            [[myId, otherId]],
        );
        const usernameById = new Map(users.rows.map((user) => [user.id, user.username]));
        const message = {
            ...result.rows[0],
            senderUsername: usernameById.get(myId) ?? req.user!.username,
            receiverUsername: usernameById.get(otherId) ?? '',
        };
        emitChatMessage(myId, otherId, message);
        res.status(201).json(message);
    } catch (e) {
        res.status(500).json({ error: 'Error enviando' });
    }
});

// Obtener todos los posts (feed global) con estado de like/bookmark
router.get('/posts', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const myId = req.user!.userId;
        const q = `
            SELECT p.*, u.name as "authorName", u.username as "authorUsername",
            u."imagePath" as "userImage",
            (SELECT COUNT(*)::int FROM "Like" l WHERE l."postId" = p.id) as "likesCount",
            EXISTS(SELECT 1 FROM "Like" l WHERE l."postId" = p.id AND l."userId" = $1) as "isLiked",
            EXISTS(SELECT 1 FROM "Bookmark" b WHERE b."postId" = p.id AND b."userId" = $1) as "isBookmarked"
            FROM "Post" p
            JOIN "User" u ON p."userId" = u.id
            WHERE COALESCE(u."isActive", true) = true
              AND (p."userId" = $1 OR EXISTS (
                SELECT 1 FROM "Follow" f WHERE f."followerId" = $1 AND f."followingId" = p."userId"
              ))
            ORDER BY p."createdAt" DESC
        `;
        const result = await pool.query(q, [myId]);
        res.json(result.rows);
    } catch (e) {
        console.error('Error fetching feed:', e);
        res.status(500).json({ error: 'Error al obtener feed' });
    }
});

// Obtener posts de un usuario
router.get('/user/:id/posts', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = parseInt(req.params.id);
        const query = `
            SELECT p.*, u.name as "authorName" 
            FROM "Post" p
            JOIN "User" u ON p."userId" = u.id
            WHERE p."userId" = $1
              AND COALESCE(u."isActive", true) = true
            ORDER BY p."createdAt" DESC
        `;
        const result = await pool.query(query, [userId]);
        res.json(result.rows);
    } catch (e) {
        res.status(500).json({ error: 'Error fetching user posts' });
    }
});

// Listado de personas que sigue un usuario
router.get('/user/:id/following', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = parseInt(req.params.id);
        const query = `
            SELECT u.id, u.name, u.username 
            FROM "Follow" f
            JOIN "User" u ON f."followingId" = u.id
            WHERE f."followerId" = $1
              AND COALESCE(u."isActive", true) = true
        `;
        const result = await pool.query(query, [userId]);
        res.json(result.rows);
    } catch (e) {
        res.status(500).json({ error: 'Error fetching following' });
    }
});

// Listado de seguidores
router.get('/user/:id/followers', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = parseInt(req.params.id);
        const query = `
            SELECT u.id, u.name, u.username 
            FROM "Follow" f
            JOIN "User" u ON f."followerId" = u.id
            WHERE f."followingId" = $1
              AND COALESCE(u."isActive", true) = true
        `;
        const result = await pool.query(query, [userId]);
        res.json(result.rows);
    } catch (e) {
        res.status(500).json({ error: 'Error fetching followers' });
    }
});

// Dar like a una publicación
router.post('/posts/:id/like', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const postId = parseInt(req.params.id);
        if (isNaN(postId)) return res.status(400).json({ error: 'ID de publicación inválido' });
        
        const q = 'INSERT INTO "Like" ("userId", "postId") VALUES ($1, $2) ON CONFLICT ("userId", "postId") DO NOTHING';
        const likeResult = await pool.query(q, [userId, postId]);
        if (likeResult.rowCount && likeResult.rowCount > 0) {
            const postOwner = await pool.query('SELECT "userId" FROM "Post" WHERE id = $1', [postId]);
            if (postOwner.rows.length > 0 && postOwner.rows[0].userId !== userId) {
                await createNotification(postOwner.rows[0].userId, 'like', 'le ha dado me gusta a tu publicación', userId, postId);
            }
        }
        res.json({ message: 'Like registrado' });
    } catch (e) {
        console.error('Error in like:', e);
        res.status(500).json({ error: 'Error al dar like', details: e instanceof Error ? e.message : String(e) });
    }
});

// Quitar like
router.delete('/posts/:id/like', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const postId = parseInt(req.params.id);
        
        await pool.query('DELETE FROM "Like" WHERE "userId" = $1 AND "postId" = $2', [userId, postId]);
        res.json({ message: 'Like eliminado' });
    } catch (e) {
        res.status(500).json({ error: 'Error al quitar like' });
    }
});

// Comentar una publicación
router.post('/posts/:id/comment', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const postId = parseInt(req.params.id);
        if (isNaN(postId)) return res.status(400).json({ error: 'ID de publicación inválido' });
        
        const { content } = req.body;
        console.log(`Commenting post ${postId} for user ${userId}: ${content}`);
        
        if (!content) return res.status(400).json({ error: 'Comentario vacío' });
        
        const q = `
            INSERT INTO "Comment" ("userId", "postId", "content", "createdAt")
            VALUES ($1, $2, $3, NOW())
            RETURNING *
        `;
        const result = await pool.query(q, [userId, postId, content]);
        
        const commentData = await pool.query(`
            SELECT c.*, u.name as "authorName", u.username as "authorUsername", u."imagePath" as "userImage",
            0 as "likesCount", false as "isLiked"
            FROM "Comment" c
            JOIN "User" u ON c."userId" = u.id
            WHERE c.id = $1
        `, [result.rows[0].id]);

        const fullComment = commentData.rows[0];

        // Emitir evento por socket para tiempo real
        if (io) {
            io.to(`post_${postId}`).emit("new_comment", { postId, comment: fullComment });
            console.log(`Comment emitted to post_${postId}`);
        }

        res.status(201).json(fullComment);
    } catch (e) {
        console.error('Error in comment:', e);
        res.status(500).json({ error: 'Error al comentar', details: e instanceof Error ? e.message : String(e) });
    }
});

// Obtener una publicación por ID (p. ej. al abrir desde chat compartido)
router.get('/posts/:id', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const postId = parseInt(req.params.id, 10);
        if (isNaN(postId)) {
            return res.status(400).json({ error: 'ID de publicación inválido' });
        }

        const query = `
            SELECT
                p.*,
                u.name as "authorName",
                u.username as "authorUsername",
                u."imagePath" as "userImage",
                (SELECT COUNT(*)::int FROM "Like" l WHERE l."postId" = p.id) as "likesCount",
                (SELECT COUNT(*)::int FROM "Comment" c WHERE c."postId" = p.id) as "commentsCount",
                EXISTS(SELECT 1 FROM "Like" l WHERE l."postId" = p.id AND l."userId" = $1) as "isLiked",
                EXISTS(SELECT 1 FROM "Bookmark" b WHERE b."postId" = p.id AND b."userId" = $1) as "isBookmarked"
            FROM "Post" p
            JOIN "User" u ON p."userId" = u.id
            WHERE p.id = $2
              AND COALESCE(u."isActive", true) = true
            LIMIT 1
        `;
        const result = await pool.query(query, [userId, postId]);
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Publicación no encontrada' });
        }
        res.json(result.rows[0]);
    } catch (e) {
        console.error('Error fetching post by id:', e);
        res.status(500).json({ error: 'Error al obtener la publicación' });
    }
});

// Obtener comentarios de una publicación
router.get('/posts/:id/comments', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const postId = parseInt(req.params.id);
        const q = `
            SELECT c.*, u.name as "authorName", u.username as "authorUsername", u."imagePath" as "userImage",
            (SELECT COUNT(*)::int FROM "CommentLike" cl WHERE cl."commentId" = c.id) as "likesCount",
            EXISTS(SELECT 1 FROM "CommentLike" cl WHERE cl."commentId" = c.id AND cl."userId" = $1) as "isLiked"
            FROM "Comment" c
            JOIN "User" u ON c."userId" = u.id
            WHERE c."postId" = $2
            ORDER BY c."createdAt" ASC
        `;
        const result = await pool.query(q, [userId, postId]);
        res.json(result.rows);
    } catch (e) {
        res.status(500).json({ error: 'Error fetching comments' });
    }
});

// Dar like a un COMENTARIO
router.post('/comments/:id/like', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const commentId = parseInt(req.params.id);
        await pool.query('INSERT INTO "CommentLike" ("userId", "commentId") VALUES ($1, $2) ON CONFLICT DO NOTHING', [userId, commentId]);
        res.json({ message: 'Like al comentario registrado' });
    } catch (e) {
        res.status(500).json({ error: 'Error al dar like al comentario' });
    }
});

router.delete('/comments/:id/like', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const commentId = parseInt(req.params.id);
        await pool.query('DELETE FROM "CommentLike" WHERE "userId" = $1 AND "commentId" = $2', [userId, commentId]);
        res.json({ message: 'Like al comentario eliminado' });
    } catch (e) {
        res.status(500).json({ error: 'Error al quitar like al comentario' });
    }
});

// Guardar una publicación (Bookmark)
router.post('/posts/:id/bookmark', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const postId = parseInt(req.params.id);
        if (isNaN(postId)) return res.status(400).json({ error: 'ID de publicación inválido' });
        
        console.log(`Bookmarking post ${postId} for user ${userId}`);
        
        await pool.query('INSERT INTO "Bookmark" ("userId", "postId") VALUES ($1, $2) ON CONFLICT ("userId", "postId") DO NOTHING', [userId, postId]);
        res.json({ message: 'Publicación guardada' });
    } catch (e) {
        console.error('Error in bookmark:', e);
        res.status(500).json({ error: 'Error al guardar publicación', details: e instanceof Error ? e.message : String(e) });
    }
});

// Eliminar de guardados
router.delete('/posts/:id/bookmark', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const postId = parseInt(req.params.id);
        
        await pool.query('DELETE FROM "Bookmark" WHERE "userId" = $1 AND "postId" = $2', [userId, postId]);
        res.json({ message: 'Publicación eliminada de guardados' });
    } catch (e) {
        res.status(500).json({ error: 'Error al eliminar de guardados' });
    }
});

// Obtener publicaciones guardadas
router.get('/posts/saved', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const q = `
            SELECT p.*, u.name as "authorName"
            FROM "Bookmark" b
            JOIN "Post" p ON b."postId" = p.id
            JOIN "User" u ON p."userId" = u.id
            WHERE b."userId" = $1
            ORDER BY b.id DESC
        `;
        const result = await pool.query(q, [userId]);
        res.json(result.rows);
    } catch (e) {
        res.status(500).json({ error: 'Error al obtener guardados' });
    }
});

// Reportar una publicación o usuario
router.post('/report', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        let { targetId, type, reason } = req.body; // type: 'post' o 'user'
        
        // Ensure targetId is an integer if it's a numeric string
        const numericTargetId = typeof targetId === 'string' ? parseInt(targetId) : targetId;
        
        console.log(`Reporting ${type} ${numericTargetId} by user ${userId}: ${reason}`);
        
        await pool.query('INSERT INTO "Report" ("userId", "targetId", "type", "reason", "createdAt") VALUES ($1, $2, $3, $4, NOW())', 
            [userId, numericTargetId, type, reason]);
            
        res.json({ message: 'Reporte enviado con éxito' });
    } catch (e) {
        console.error('Error in report:', e);
        res.status(500).json({ error: 'Error al reportar' });
    }
});

// Crear una historia
router.post('/stories', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const { image } = req.body;
        if (!image) return res.status(400).json({ error: 'La imagen es obligatoria' });

        const query = `
            INSERT INTO "Story" ("userId", "imagePath", "createdAt", "expiresAt")
            VALUES ($1, $2, NOW(), NOW() + INTERVAL '24 hours')
            RETURNING id, "userId", "imagePath" as image, "createdAt"
        `;
        const result = await pool.query(query, [userId, image]);
        res.status(201).json(result.rows[0]);
    } catch (error) {
        console.error('Error creating story:', error);
        res.status(500).json({ error: 'Error al crear historia' });
    }
});

// Obtener historias activas (últimas 24 horas)
router.get('/stories', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const query = `
            SELECT s.id, s."userId", s."imagePath" as image, s."createdAt", u.username, u.name, u."imagePath" as "userImage"
            FROM "Story" s
            JOIN "User" u ON s."userId" = u.id
            WHERE s."createdAt" > NOW() - INTERVAL '24 hours'
            AND COALESCE(u."isActive", true) = true
            AND (s."userId" = $1 OR s."userId" IN (SELECT "followingId" FROM "Follow" WHERE "followerId" = $1))
            ORDER BY s."createdAt" DESC
        `;
        const result = await pool.query(query, [userId]);
        res.json(result.rows);
    } catch (error) {
        console.error('Error fetching stories:', error);
        res.status(500).json({ 
            error: 'Error al obtener historias',
            details: error instanceof Error ? error.message : String(error)
        });
    }
});

// Obtener historial de historias propias (archivo)
router.get('/stories/history', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const query = `
            SELECT * FROM "Story"
            WHERE "userId" = $1
            ORDER BY "createdAt" DESC
        `;
        const result = await pool.query(query, [userId]);
        res.json(result.rows);
    } catch (error) {
        res.status(500).json({ error: 'Error al obtener historial' });
    }
});

// Crear un destacado (Highlight)
router.post('/highlights', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        let { title, image, storyImages } = req.body;
        console.log('Creating highlight:', { userId, title, image, storyImagesCount: storyImages?.length });
        
        if (!title) {
            return res.status(400).json({ error: 'Título obligatorio' });
        }

        // Fallback for missing image
        if (!image || typeof image !== 'string' || image.length < 5) {
            image = 'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=600&q=80';
        }

        const query = `
            INSERT INTO "Highlight" ("userId", title, image, "storyImages", "createdAt")
            VALUES ($1, $2, $3, $4, NOW())
            RETURNING *
        `;
        const result = await pool.query(query, [userId, title, image, JSON.stringify(storyImages || [])]);
        res.status(201).json(result.rows[0]);
    } catch (error) {
        console.error('Error creating highlight:', error);
        res.status(500).json({ error: 'Error al crear destacado' });
    }
});

// Eliminar un destacado
router.delete('/highlights/:id', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const highlightId = parseInt(req.params.id);
        
        const check = await pool.query('SELECT "userId" FROM "Highlight" WHERE id = $1', [highlightId]);
        if (check.rows.length === 0) return res.status(404).json({ error: 'No encontrado' });
        
        if (check.rows[0].userId !== userId) {
            return res.status(403).json({ error: 'No tienes permiso' });
        }

        await pool.query('DELETE FROM "Highlight" WHERE id = $1', [highlightId]);
        res.json({ message: 'Destacado eliminado' });
    } catch (error) {
        console.error('Error deleting highlight:', error);
        res.status(500).json({ error: 'Error al eliminar destacado' });
    }
});

// Obtener destacados de un usuario
router.get('/user/:id/highlights', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = parseInt(req.params.id);
        const query = `SELECT * FROM "Highlight" WHERE "userId" = $1 ORDER BY "createdAt" DESC`;
        const result = await pool.query(query, [userId]);
        res.json(result.rows);
    } catch (error) {
        res.status(500).json({ error: 'Error al obtener destacados' });
    }
});

router.get('/profile/user/:username/highlights', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const username = req.params.username;
        const user = await pool.query('SELECT id FROM "User" WHERE username = $1', [username]);
        if (user.rows.length === 0) return res.status(404).json({error: 'No encontrado'});

        const result = await pool.query(
            'SELECT * FROM "Highlight" WHERE "userId" = $1 ORDER BY "createdAt" DESC',
            [user.rows[0].id],
        );
        res.json(result.rows);
    } catch (error) {
        res.status(500).json({ error: 'Error al obtener destacados' });
    }
});

// Notifications
router.get('/notifications', authenticateToken, async (req: AuthRequest, res) => {
    try {
        res.set('Cache-Control', 'no-store');
        const userId = req.user!.userId;
        const result = await pool.query(
            `SELECT n.*, u.username as "senderUsername", u."imagePath" as "senderImage", p.image as "postImage"
             FROM "Notification" n
             LEFT JOIN "User" u ON n."senderId" = u.id
             LEFT JOIN "Post" p ON n."postId" = p.id
             WHERE n."userId" = $1
             AND NOT (
                n.type = 'follow_request'
                AND NOT EXISTS (
                    SELECT 1
                    FROM "Follow" f
                    WHERE f."followerId" = n."senderId"
                      AND f."followingId" = n."userId"
                      AND f.status = 'pending'
                )
             )
             ORDER BY n."createdAt" DESC
             LIMIT 50`,
            [userId]
        );
        res.json(result.rows);
    } catch (error) {
        console.error('Error fetching notifications:', error);
        res.status(500).json({ error: 'Error del servidor' });
    }
});

router.post('/notifications/:id/read', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const id = req.params.id;
        await pool.query('UPDATE "Notification" SET "read" = true WHERE id = $1 AND "userId" = $2', [id, userId]);
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: 'Error del servidor' });
    }
});

router.delete('/comments/:id', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const isAdmin = req.user!.role === 'admin';
        const commentId = parseInt(req.params.id);
        if (isNaN(commentId)) {
            return res.status(400).json({ error: 'ID de comentario inválido' });
        }

        const result = await pool.query(
            `
                SELECT c.id, c."userId" as "commentUserId", c."postId", p."userId" as "postUserId"
                FROM "Comment" c
                JOIN "Post" p ON p.id = c."postId"
                WHERE c.id = $1
                LIMIT 1
            `,
            [commentId],
        );
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Comentario no encontrado' });
        }

        const row = result.rows[0];
        const commentUserId = Number(row.commentUserId);
        const postUserId = Number(row.postUserId);
        const canDelete = isAdmin || commentUserId === userId || postUserId === userId;
        if (!canDelete) {
            return res.status(403).json({ error: 'No tienes permisos para eliminar este comentario' });
        }

        await pool.query('DELETE FROM "CommentLike" WHERE "commentId" = $1', [commentId]);
        await pool.query('DELETE FROM "Comment" WHERE id = $1', [commentId]);
        return res.json({ success: true });
    } catch (e) {
        console.error('Error deleting comment:', e);
        return res.status(500).json({ error: 'Error al eliminar comentario' });
    }
});

router.delete('/notifications/:id', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const id = req.params.id;
        await pool.query('DELETE FROM "Notification" WHERE id = $1 AND "userId" = $2', [id, userId]);
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: 'Error del servidor' });
    }
});

async function createNotification(userId: number, type: string, content: string, senderId?: number, postId?: number) {
    try {
        await pool.query(
            'INSERT INTO "Notification" ("userId", type, content, "senderId", "postId") VALUES ($1, $2, $3, $4, $5)',
            [userId, type, content, senderId, postId]
        );
    } catch (error) {
        console.error('Error creating notification:', error);
    }
}

async function ensureDuelsStorageTable(): Promise<void> {
    await pool.query(`
        CREATE TABLE IF NOT EXISTS "UserDuelState" (
            "userId" INTEGER PRIMARY KEY REFERENCES "User"(id) ON DELETE CASCADE,
            "stateJson" JSONB NOT NULL DEFAULT '{}'::jsonb,
            "updatedAt" TIMESTAMP NOT NULL DEFAULT NOW()
        )
    `);
}

const defaultDuelState = () => ({
    invitations: [],
    activeDuels: [],
    stats: { wins: 0, points: 0, activeCount: 0, rankPosition: 0 },
});

async function loadUserDuelState(userId: number): Promise<Record<string, any>> {
    const result = await pool.query(
        'SELECT "stateJson" FROM "UserDuelState" WHERE "userId" = $1 LIMIT 1',
        [userId],
    );
    if (result.rows.length === 0) {
        return defaultDuelState();
    }
    const state = (result.rows[0].stateJson ?? {}) as Record<string, any>;
    state.invitations = Array.isArray(state.invitations) ? state.invitations : [];
    state.activeDuels = Array.isArray(state.activeDuels) ? state.activeDuels : [];
    state.stats = state.stats ?? defaultDuelState().stats;
    return state;
}

async function saveUserDuelState(
    userId: number,
    state: Record<string, any>,
): Promise<void> {
    await pool.query(
        `
            INSERT INTO "UserDuelState" ("userId", "stateJson", "updatedAt")
            VALUES ($1, $2::jsonb, NOW())
            ON CONFLICT ("userId")
            DO UPDATE SET "stateJson" = EXCLUDED."stateJson", "updatedAt" = NOW()
        `,
        [userId, JSON.stringify(state)],
    );
}

function removeDuelFromState(state: Record<string, any>, duelId: number): void {
    state.invitations = (state.invitations as any[]).filter(
        (inv) => Number(inv?.id) !== duelId,
    );
    state.activeDuels = (state.activeDuels as any[]).filter(
        (duel) => Number(duel?.id) !== duelId,
    );
}

async function removeDuelForUsername(
    username: string,
    duelId: number,
    skipUserId?: number,
): Promise<void> {
    const normalized = username.trim();
    if (!normalized) return;

    const userResult = await pool.query(
        'SELECT id FROM "User" WHERE LOWER(username) = LOWER($1) LIMIT 1',
        [normalized],
    );
    if (userResult.rows.length === 0) return;

    const targetUserId = Number(userResult.rows[0].id);
    if (!Number.isInteger(targetUserId) || targetUserId <= 0) return;
    if (skipUserId != null && targetUserId === skipUserId) return;

    const targetState = await loadUserDuelState(targetUserId);
    removeDuelFromState(targetState, duelId);
    await saveUserDuelState(targetUserId, targetState);
}

router.get('/duels/state', authenticateToken, async (req: AuthRequest, res) => {
    try {
        await ensureDuelsStorageTable();
        const userId = req.user!.userId;
        const result = await pool.query(
            'SELECT "stateJson" FROM "UserDuelState" WHERE "userId" = $1 LIMIT 1',
            [userId],
        );
        if (result.rows.length === 0) {
            return res.json({
                invitations: [],
                activeDuels: [],
                stats: { wins: 0, points: 0, activeCount: 0, rankPosition: 0 },
            });
        }
        const state = (result.rows[0].stateJson ?? {}) as Record<string, any>;
        const activeDuels = Array.isArray(state.activeDuels) ? state.activeDuels : [];
        const dedup = new Map<number, any>();
        for (const duel of activeDuels) {
            const id = Number(duel?.id);
            if (!Number.isInteger(id) || id <= 0) continue;
            if ((duel?.status ?? 'active') !== 'active') continue;
            if (!dedup.has(id)) {
                if (duel.isMulti === true && Array.isArray(duel.scores) && duel.scores.length > 0) {
                    duel.scores[0] = Math.max(0, Math.min(100, Number(duel.scores[0] || 0)));
                    duel.myScore = duel.scores[0];
                } else {
                    duel.myScore = Math.max(0, Math.min(100, Number(duel.myScore || 0)));
                }
                dedup.set(id, duel);
            }
        }
        state.activeDuels = Array.from(dedup.values());
        state.stats = state.stats ?? {};
        state.stats.points = Math.max(0, Math.min(100, Number(state.stats.points || 0)));
        state.stats.pointsApplied = Math.max(0, Math.min(100, Number(state.stats.pointsApplied || 0)));
        return res.json(state);
    } catch (error) {
        console.error('Error fetching duel state:', error);
        return res.status(500).json({ error: 'Error del servidor' });
    }
});

router.put('/duels/state', authenticateToken, async (req: AuthRequest, res) => {
    try {
        await ensureDuelsStorageTable();
        const userId = req.user!.userId;
        const state = req.body ?? {};
        await pool.query(
            `
                INSERT INTO "UserDuelState" ("userId", "stateJson", "updatedAt")
                VALUES ($1, $2::jsonb, NOW())
                ON CONFLICT ("userId")
                DO UPDATE SET "stateJson" = EXCLUDED."stateJson", "updatedAt" = NOW()
            `,
            [userId, JSON.stringify(state)],
        );
        return res.json({ success: true });
    } catch (error) {
        console.error('Error saving duel state:', error);
        return res.status(500).json({ error: 'Error del servidor' });
    }
});

router.post('/duels', authenticateToken, async (req: AuthRequest, res) => {
    try {
        await ensureDuelsStorageTable();
        const userId = req.user!.userId;
        const opponents = Array.isArray(req.body?.opponents) ? req.body.opponents : [];
        const isMulti = req.body?.isMulti === true;
        const id = Date.now();

// Create mirrored invitations for opponents so they can see the duel.
        const meResult = await pool.query(
            'SELECT username, name, "imagePath" FROM "User" WHERE id = $1 LIMIT 1',
            [userId],
        );
        const me = meResult.rows[0] ?? { username: 'tu', name: 'Usuario', imagePath: null };
        for (const rawOpponent of opponents) {
            const opponent = rawOpponent as any;
            const opponentUsername = (opponent?.username ?? '').toString().trim();
            if (!opponentUsername) continue;
            const targetResult = await pool.query(
                'SELECT id FROM "User" WHERE LOWER(username) = LOWER($1) LIMIT 1',
                [opponentUsername],
            );
            if (targetResult.rows.length === 0) continue;
            const targetUserId = Number(targetResult.rows[0].id);
            if (!Number.isInteger(targetUserId) || targetUserId <= 0 || targetUserId === userId) continue;

            const targetStateResult = await pool.query(
                'SELECT "stateJson" FROM "UserDuelState" WHERE "userId" = $1 LIMIT 1',
                [targetUserId],
            );
            const targetState =
                targetStateResult.rows.length > 0
                    ? (targetStateResult.rows[0].stateJson as Record<string, any>)
                    : { invitations: [], activeDuels: [], stats: { wins: 0, points: 0, activeCount: 0 } };

            const invitations = Array.isArray(targetState.invitations)
                ? [...targetState.invitations]
                : [];
            const alreadyExists = invitations.some((inv: any) => Number(inv?.id) === id);
            if (!alreadyExists) {
                invitations.unshift({
                    id,
                    name: me.name ?? me.username ?? 'Usuario',
                    challenge: isMulti ? 'Te ha invitado a un duelo grupal' : 'Te ha retado a un duelo',
                    expires: '24h',
                    avatar: me.imagePath ?? null,
                    fromUsername: me.username ?? null,
                });
            }
            targetState.invitations = invitations;

            await saveUserDuelState(targetUserId, targetState);
        }

        const creatorState = await loadUserDuelState(userId);
        const creatorActive = [...(creatorState.activeDuels as any[])];
        const opponentUsernames: string[] = [];

        for (const rawOpponent of opponents) {
            const opponent = rawOpponent as any;
            const opponentUsername = (opponent?.username ?? '').toString().trim();
            if (opponentUsername) opponentUsernames.push(opponentUsername);
        }

        if (isMulti && opponents.length > 0) {
            const participants = [
                me.name ?? me.username ?? 'Tú',
                ...opponents.map(
                    (raw: any) =>
                        (raw?.displayName ?? raw?.name ?? raw?.username ?? 'Amigo')
                            .toString(),
                ),
            ];
            const participantImages = [
                me.imagePath ?? null,
                ...opponents.map((raw: any) => raw?.userImage ?? null),
            ];
            creatorActive.unshift({
                id,
                title: (req.body?.title ?? 'Duelo grupal').toString(),
                isMulti: true,
                participants,
                participantImages,
                opponentUsernames,
                scores: participants.map(() => 0),
                winningIndex: 0,
                progress: 0.1,
                status: 'active',
            });
        } else if (opponents.length > 0) {
            const opponent = opponents[0] as any;
            const opponentUsername = (opponent?.username ?? '').toString().trim();
            creatorActive.unshift({
                id,
                name: (opponent?.displayName ?? opponent?.name ?? opponentUsername ?? 'Amigo')
                    .toString(),
                opponentUsername: opponentUsername || null,
                opponentImage: opponent?.userImage ?? null,
                myScore: 0,
                opponentScore: 0,
                winning: true,
                isMulti: false,
                status: 'active',
            });
        }

        const dedupCreator = new Map<number, any>();
        for (const duel of creatorActive) {
            const duelKey = Number(duel?.id);
            if (Number.isInteger(duelKey) && duelKey > 0) {
                dedupCreator.set(duelKey, duel);
            }
        }
        creatorState.activeDuels = Array.from(dedupCreator.values());
        await saveUserDuelState(userId, creatorState);

        return res.status(201).json({ success: true, id });
    } catch (error) {
        console.error('Error creating duel:', error);
        return res.status(500).json({ error: 'Error del servidor' });
    }
});

router.delete('/duels/state', authenticateToken, async (req: AuthRequest, res) => {
    try {
        await ensureDuelsStorageTable();
        const userId = req.user!.userId;
        const resetState = {
            invitations: [],
            activeDuels: [],
            stats: { wins: 0, points: 0, activeCount: 0, rankPosition: 0 },
        };
        await pool.query(
            `
                INSERT INTO "UserDuelState" ("userId", "stateJson", "updatedAt")
                VALUES ($1, $2::jsonb, NOW())
                ON CONFLICT ("userId")
                DO UPDATE SET "stateJson" = EXCLUDED."stateJson", "updatedAt" = NOW()
            `,
            [userId, JSON.stringify(resetState)],
        );
        return res.json({ success: true });
    } catch (error) {
        console.error('Error resetting duel state:', error);
        return res.status(500).json({ error: 'Error del servidor' });
    }
});

router.delete('/duels/:id', authenticateToken, async (req: AuthRequest, res) => {
    try {
        await ensureDuelsStorageTable();
        const userId = req.user!.userId;
        const duelId = Number(req.params.id);
        if (!Number.isInteger(duelId) || duelId <= 0) {
            return res.status(400).json({ error: 'ID de duelo invalido' });
        }

        const state = await loadUserDuelState(userId);
        const activeBefore = Array.isArray(state.activeDuels) ? [...state.activeDuels] : [];
        const duelToRemove = activeBefore.find((d: any) => Number(d?.id) === duelId);

        const opponentsToNotify = new Set<string>();
        if (duelToRemove?.opponentUsername) {
            opponentsToNotify.add(String(duelToRemove.opponentUsername).trim());
        }
        if (Array.isArray(duelToRemove?.opponentUsernames)) {
            for (const name of duelToRemove.opponentUsernames) {
                const normalized = String(name ?? '').trim();
                if (normalized) opponentsToNotify.add(normalized);
            }
        }
        for (const inv of state.invitations as any[]) {
            if (Number(inv?.id) === duelId && inv?.fromUsername) {
                opponentsToNotify.add(String(inv.fromUsername).trim());
            }
        }

        removeDuelFromState(state, duelId);
        await saveUserDuelState(userId, state);

        for (const opponentUsername of opponentsToNotify) {
            await removeDuelForUsername(opponentUsername, duelId, userId);
        }

        return res.json({ success: true });
    } catch (error) {
        console.error('Error deleting duel:', error);
        return res.status(500).json({ error: 'Error del servidor' });
    }
});

router.post('/duels/:id/accept', authenticateToken, async (req: AuthRequest, res) => {
    try {
        await ensureDuelsStorageTable();
        const userId = req.user!.userId;
        const duelId = Number(req.params.id);
        if (!Number.isInteger(duelId) || duelId <= 0) {
            return res.status(400).json({ error: 'ID de duelo invalido' });
        }

        const currentResult = await pool.query(
            'SELECT "stateJson" FROM "UserDuelState" WHERE "userId" = $1 LIMIT 1',
            [userId],
        );
        if (currentResult.rows.length === 0) {
            return res.status(404).json({ error: 'No hay estado de duelo' });
        }
        const state = currentResult.rows[0].stateJson as Record<string, any>;
        const invitations = Array.isArray(state.invitations) ? [...state.invitations] : [];
        const invitation = invitations.find((inv: any) => Number(inv?.id) === duelId);
        if (!invitation) {
            return res.status(404).json({ error: 'Invitacion no encontrada' });
        }
        state.invitations = invitations.filter((inv: any) => Number(inv?.id) !== duelId);

        const activeDuels = Array.isArray(state.activeDuels) ? [...state.activeDuels] : [];
        const meResult = await pool.query(
            'SELECT username, name, "imagePath" FROM "User" WHERE id = $1 LIMIT 1',
            [userId],
        );
        const me = meResult.rows[0] ?? { username: 'usuario', name: 'Usuario', imagePath: null };
        const alreadyActive = activeDuels.some((d: any) => Number(d?.id) === duelId);
        if (!alreadyActive) {
            activeDuels.unshift({
                id: duelId,
                name: invitation.name ?? invitation.fromUsername ?? 'Amigo',
                opponentUsername: invitation.fromUsername ?? null,
                opponentImage: invitation.avatar ?? null,
                myScore: 0,
                opponentScore: 0,
                winning: true,
                isMulti: false,
                status: 'active',
            });
        } else {
            for (const duel of activeDuels) {
                if (Number(duel?.id) === duelId) {
                    duel.status = 'active';
                }
            }
        }
        state.activeDuels = activeDuels;

        await pool.query(
            `
                INSERT INTO "UserDuelState" ("userId", "stateJson", "updatedAt")
                VALUES ($1, $2::jsonb, NOW())
                ON CONFLICT ("userId")
                DO UPDATE SET "stateJson" = EXCLUDED."stateJson", "updatedAt" = NOW()
            `,
            [userId, JSON.stringify(state)],
        );

        const fromUsername = (invitation.fromUsername ?? '').toString().trim();
        if (fromUsername) {
            const inviterResult = await pool.query(
                'SELECT id FROM "User" WHERE LOWER(username) = LOWER($1) LIMIT 1',
                [fromUsername],
            );
            if (inviterResult.rows.length > 0) {
                const inviterId = Number(inviterResult.rows[0].id);
                const inviterStateResult = await pool.query(
                    'SELECT "stateJson" FROM "UserDuelState" WHERE "userId" = $1 LIMIT 1',
                    [inviterId],
                );
                if (inviterStateResult.rows.length > 0) {
                    const inviterState = inviterStateResult.rows[0].stateJson as Record<string, any>;
                    const inviterDuels = Array.isArray(inviterState.activeDuels)
                        ? [...inviterState.activeDuels]
                        : [];
                    let foundInviterDuel = false;
                    for (const duel of inviterDuels) {
                        if (Number(duel?.id) === duelId) {
                            duel.status = 'active';
                            foundInviterDuel = true;
                        }
                    }
                    if (!foundInviterDuel) {
                        inviterDuels.unshift({
                            id: duelId,
                            name: me.name ?? me.username ?? 'Amigo',
                            opponentUsername: me.username ?? null,
                            opponentImage: me.imagePath ?? null,
                            myScore: 0,
                            opponentScore: 0,
                            winning: true,
                            isMulti: false,
                            status: 'active',
                        });
                    }
                    inviterState.activeDuels = inviterDuels;
                    await pool.query(
                        `
                            INSERT INTO "UserDuelState" ("userId", "stateJson", "updatedAt")
                            VALUES ($1, $2::jsonb, NOW())
                            ON CONFLICT ("userId")
                            DO UPDATE SET "stateJson" = EXCLUDED."stateJson", "updatedAt" = NOW()
                        `,
                        [inviterId, JSON.stringify(inviterState)],
                    );
                }
            }
        }

        return res.json({ success: true });
    } catch (error) {
        console.error('Error accepting duel invitation:', error);
        return res.status(500).json({ error: 'Error del servidor' });
    }
});

router.post('/duels/sync-points', authenticateToken, async (req: AuthRequest, res) => {
    try {
        await ensureDuelsStorageTable();
        const userId = req.user!.userId;
        const points = Math.max(0, Math.min(100, Number(req.body?.points) || 0));
        if (points <= 0) {
            return res.json({ success: true, pointsAdded: 0 });
        }
        const today = new Date().toISOString().slice(0, 10);

        const current = await pool.query(
            'SELECT "stateJson" FROM "UserDuelState" WHERE "userId" = $1 LIMIT 1',
            [userId],
        );
        const state =
            current.rows.length > 0
                ? (current.rows[0].stateJson as Record<string, any>)
                : { invitations: [], activeDuels: [], stats: { wins: 0, points: 0, activeCount: 0 } };

        const active = Array.isArray(state.activeDuels) ? state.activeDuels : [];
        state.stats = state.stats ?? {};
        if (state.stats.lastPointsDay !== today) {
            state.stats.lastPointsDay = today;
            state.stats.pointsApplied = 0;
            state.stats.points = 0;
        }
        const pointsApplied = Number(state.stats.pointsApplied || 0);
        if (pointsApplied >= 100) {
            return res.json({ success: true, pointsAdded: 0 });
        }
        const pointsToApply = Math.max(0, Math.min(100 - pointsApplied, points));
        if (pointsToApply <= 0) {
            return res.json({ success: true, pointsAdded: 0 });
        }

        for (const duel of active) {
            if (duel.status !== 'active') continue;
            if (duel.isMulti === true && Array.isArray(duel.scores) && duel.scores.length > 0) {
                duel.scores[0] = Number(duel.scores[0] || 0) + pointsToApply;
                duel.myScore = duel.scores[0];
            } else {
                duel.myScore = Number(duel.myScore || 0) + pointsToApply;
            }
        }

        state.stats.pointsApplied = pointsApplied + pointsToApply;
        state.stats.points = state.stats.pointsApplied;
        state.activeDuels = active;

        await pool.query(
            `
                INSERT INTO "UserDuelState" ("userId", "stateJson", "updatedAt")
                VALUES ($1, $2::jsonb, NOW())
                ON CONFLICT ("userId")
                DO UPDATE SET "stateJson" = EXCLUDED."stateJson", "updatedAt" = NOW()
            `,
            [userId, JSON.stringify(state)],
        );

        return res.json({ success: true, pointsAdded: pointsToApply });
    } catch (error) {
        console.error('Error syncing duel points:', error);
        return res.status(500).json({ error: 'Error del servidor' });
    }
});

export default router;


