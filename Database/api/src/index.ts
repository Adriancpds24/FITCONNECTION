import "dotenv/config";
import express from "express";
import cors from "cors";
import path from "path";
import fs from "fs";
import { createServer } from "http";
import { Server } from "socket.io";
import crypto from "crypto";
import jwt from "jsonwebtoken";
import pool from "./db";
import authRoutes from "./routes/auth";
import adminRoutes from "./routes/admin";
import trainingRoutes from "./routes/training";
import nutritionRoutes from "./routes/nutrition";
import progressRoutes from "./routes/progress";
import sportsCentersRoutes from "./routes/sportsCenters";
import socialRoutes, { runStoryCleanupSafely, setSocketInstance } from "./routes/social";
import wearableRoutes from "./routes/wearable";
import reservationsRoutes from "./routes/reservations";
import accountRoutes from "./routes/account";
import { ensureDatabaseSupport } from "./bootstrap/initDb";
import { syncUsersToSeedFile } from "./services/userSeedSync";
import { ensureAllUploadDirs, getUploadsRoot } from "./config/uploads";
import { buildAppResetLink } from "./services/passwordReset";

const app = express();
const listenPort = Number(process.env.PORT || 3000);
const JWT_SECRET = process.env.JWT_SECRET || "fitconnect_super_secret_key";
const httpServer = createServer(app);
const io = new Server(httpServer, {
    cors: {
        origin: "*",
        methods: ["GET", "POST", "DELETE", "PUT"]
    }
});

setSocketInstance(io);

type SocketUser = {
    userId: number;
    username: string;
};

const onlineUsers = new Map<number, { username: string; socketIds: Set<string> }>();
const socketUsers = new Map<string, SocketUser>();

function userRoom(userId: number): string {
    return `user_${userId}`;
}

function usernameRoom(username: string): string {
    return `username_${username.trim().toLowerCase()}`;
}

function chatRoom(leftUsername: string, rightUsername: string): string {
    return `chat_${[leftUsername, rightUsername]
        .map((value) => value.trim().toLowerCase())
        .sort()
        .join("__")}`;
}

function onlineSnapshot() {
    return Array.from(onlineUsers.entries()).map(([userId, value]) => ({
        userId,
        username: value.username,
        isOnline: value.socketIds.size > 0,
    }));
}

async function findSocketUserById(userId: number): Promise<SocketUser | null> {
    const result = await pool.query<{ id: number; username: string }>(
        'SELECT id, username FROM "User" WHERE id = $1 AND COALESCE("isActive", true) = true LIMIT 1',
        [userId],
    );

    const user = result.rows[0];
    return user ? { userId: user.id, username: user.username } : null;
}

async function findSocketUserByUsername(username: string): Promise<SocketUser | null> {
    const result = await pool.query<{ id: number; username: string }>(
        'SELECT id, username FROM "User" WHERE LOWER(username) = LOWER($1) AND COALESCE("isActive", true) = true LIMIT 1',
        [username],
    );

    const user = result.rows[0];
    return user ? { userId: user.id, username: user.username } : null;
}

async function authenticateSocket(socket: any): Promise<SocketUser | null> {
    const rawToken =
        socket.handshake.auth?.token ||
        socket.handshake.query?.token ||
        socket.handshake.headers?.authorization?.toString().replace(/^Bearer\s+/i, "");
    const token = typeof rawToken === "string" ? rawToken.trim() : "";
    const usernameHint =
        typeof socket.handshake.auth?.username === "string"
            ? socket.handshake.auth.username.trim()
            : "";

    if (!token) {
        return null;
    }

    if (token.startsWith("token_local_") && usernameHint) {
        return findSocketUserByUsername(usernameHint);
    }

    const verified = jwt.verify(token, JWT_SECRET) as { userId?: number };
    if (!verified.userId) {
        return null;
    }

    return findSocketUserById(verified.userId);
}

app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));

app.use(
  "/uploads",
  express.static(getUploadsRoot(), {
    maxAge: process.env.NODE_ENV === "production" ? "7d" : 0,
    fallthrough: true,
  }),
);

app.use((req: express.Request, res: express.Response, next: express.NextFunction) => {
    const requestId = (crypto as any).randomUUID ? (crypto as any).randomUUID() : crypto.randomBytes(16).toString("hex");
    (req as any).requestId = requestId;
    res.setHeader("X-Request-Id", requestId);

    const start = Date.now();
    res.on("finish", () => {
        const ms = Date.now() - start;
        const pathOnly = req.originalUrl?.split("?")[0] ?? req.url;
        const status = res.statusCode;
        // Keep logs minimal and avoid leaking tokens/PII.
        console.log(`[${requestId}] ${req.method} ${pathOnly} -> ${status} (${ms}ms)`);
    });
    next();
});

app.get("/reset-password", (req, res) => {
    const token = typeof req.query.token === "string" ? req.query.token.trim() : "";
    const appLink = token ? buildAppResetLink(token) : null;

    if (!token) {
        res.status(400).send("Enlace no valido. Solicita un nuevo correo de recuperacion.");
        return;
    }

    const safeToken = encodeURIComponent(token);
    const safeAppLink = appLink ? appLink.replace(/"/g, "&quot;") : "";

    res.type("html").send(`<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Recuperar contrasena · FitConnect</title>
  <style>
    body { font-family: system-ui, sans-serif; background: #0b0b0b; color: #f5f5f5; margin: 0; padding: 32px 20px; }
    .card { max-width: 420px; margin: 0 auto; background: #151515; border-radius: 16px; padding: 24px; }
    a.btn { display: inline-block; margin-top: 16px; padding: 12px 18px; background: #fff; color: #111; border-radius: 999px; text-decoration: none; font-weight: 600; }
    p { color: #b0b0b0; line-height: 1.5; }
  </style>
  ${appLink ? `<meta http-equiv="refresh" content="0;url=${safeAppLink}" />` : ""}
  <script>
    (function () {
      var appUrl = ${appLink ? JSON.stringify(appLink) : "null"};
      if (!appUrl) return;
      window.location.replace(appUrl);
      setTimeout(function () {
        window.location.href = appUrl;
      }, 400);
    })();
  </script>
</head>
<body>
  <div class="card">
    <h1>Recuperar contrasena</h1>
    <p>Abre FitConnect para elegir tu nueva contrasena.</p>
    ${appLink ? `<a class="btn" href="${safeAppLink}">Abrir en la app</a>` : "<p>Abre la app FitConnect manualmente.</p>"}
  </div>
</body>
</html>`);
});

app.use('/api/auth', authRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/training', trainingRoutes);
app.use('/api/nutrition', nutritionRoutes);
app.use('/api/progress', progressRoutes);
app.use('/api/sports-centers', sportsCentersRoutes);
app.use('/api/social', socialRoutes);
app.use('/api/wearable', wearableRoutes);
app.use('/api/reservations', reservationsRoutes);
app.use('/api/account', accountRoutes);

app.get("/api/health", (req, res) => {
    res.json({ status: "ok", message: "FitConnect API is running" });
});

app.get("/api/health/uploads", async (_req, res) => {
    res.json({
        uploadsRoot: getUploadsRoot(),
        persistentVolumeConfigured: process.env.UPLOADS_DIR === "/app/uploads",
        hint:
            "En Railway debes montar un volumen en /app/uploads o las imagenes se pierden al redesplegar.",
    });
});

// ---------- Flutter Web static files ----------
// In production, serve the Flutter web build from /app/public (or PUBLIC_DIR).
// All non-API routes fall through to index.html (SPA).
const publicDir = process.env.PUBLIC_DIR || path.join(__dirname, "..", "public");
const publicIndexPath = path.join(publicDir, "index.html");

if (fs.existsSync(publicIndexPath)) {
    app.use(express.static(publicDir, { maxAge: "7d", index: false }));

    // SPA fallback: any GET that didn't match an API route or a static file → index.html
    app.get("*", (req, res, next) => {
        // Don't intercept /api/* or /uploads/* or /reset-password
        if (req.path.startsWith("/api/") || req.path.startsWith("/uploads/") || req.path === "/reset-password") {
            return next();
        }
        res.sendFile(publicIndexPath);
    });

    console.log(`Serving Flutter web from ${publicDir}`);
} else {
    console.log(`No Flutter web build found at ${publicDir} — API-only mode.`);
}

io.on("connection", async (socket: any) => {
    let user: SocketUser | null = null;

    try {
        user = await authenticateSocket(socket);
    } catch (error) {
        console.warn("Socket auth failed:", error);
    }

    if (!user) {
        socket.emit("presence:error", { error: "No autenticado" });
        socket.disconnect(true);
        return;
    }

    socketUsers.set(socket.id, user);
    socket.join(userRoom(user.userId));
    socket.join(usernameRoom(user.username));

    const presence = onlineUsers.get(user.userId) ?? {
        username: user.username,
        socketIds: new Set<string>(),
    };
    const wasOnline = presence.socketIds.size > 0;
    presence.socketIds.add(socket.id);
    onlineUsers.set(user.userId, presence);

    console.log("Client connected to Socket.io:", socket.id, user.username);
    socket.emit("presence:snapshot", onlineSnapshot());
    if (!wasOnline) {
        io.emit("presence:changed", {
            userId: user.userId,
            username: user.username,
            isOnline: true,
        });
    }

    socket.on("join_post", (postId: any) => {
        socket.join(`post_${postId}`);
        console.log(`Socket ${socket.id} joined room post_${postId}`);
    });

    socket.on("chat:join", (payload: any) => {
        const targetUsername = String(payload?.targetUsername ?? "").trim();
        if (!targetUsername) return;
        socket.join(chatRoom(user.username, targetUsername));
    });

    socket.on("chat:leave", (payload: any) => {
        const targetUsername = String(payload?.targetUsername ?? "").trim();
        if (!targetUsername) return;
        socket.leave(chatRoom(user.username, targetUsername));
    });

    socket.on("chat:typing", (payload: any) => {
        const targetUsername = String(payload?.targetUsername ?? "").trim();
        if (!targetUsername) return;

        const isTyping = payload?.isTyping === true;
        const eventPayload = {
            senderUsername: user.username,
            targetUsername,
            isTyping,
        };

        io.to(usernameRoom(targetUsername)).emit("chat:typing", eventPayload);
        io.to(chatRoom(user.username, targetUsername)).emit("chat:typing", eventPayload);
    });

    socket.on("disconnect", () => {
        const disconnectedUser = socketUsers.get(socket.id);
        socketUsers.delete(socket.id);

        if (!disconnectedUser) {
            console.log("Client disconnected");
            return;
        }

        const currentPresence = onlineUsers.get(disconnectedUser.userId);
        currentPresence?.socketIds.delete(socket.id);

        if (!currentPresence || currentPresence.socketIds.size === 0) {
            onlineUsers.delete(disconnectedUser.userId);
            io.emit("presence:changed", {
                userId: disconnectedUser.userId,
                username: disconnectedUser.username,
                isOnline: false,
            });
        }

        console.log("Client disconnected:", disconnectedUser.username);
    });
});

async function startServer() {
    // Escuchar en 0.0.0.0 (Docker/Railway) y abrir el puerto antes del bootstrap de BD,
    // para que el proxy deje de devolver 502 mientras initDb corre o si tarda.
    await new Promise<void>((resolve, reject) => {
        httpServer.once("error", reject);
        httpServer.listen(listenPort, "0.0.0.0", () => {
            console.log(
                `Server listening on 0.0.0.0:${listenPort} (Socket.io); running database bootstrap...`
            );
            resolve();
        });
    });

    try {
        await ensureAllUploadDirs();
        console.log(`Uploads storage: ${getUploadsRoot()}`);
        await ensureDatabaseSupport();
        await syncUsersToSeedFile().catch((syncError) => {
            console.warn("No se pudo sincronizar seed_data.sql al arrancar la API:", syncError);
        });
        await runStoryCleanupSafely();
        setInterval(() => {
            void runStoryCleanupSafely();
        }, 5 * 60 * 1000);
        console.log("Database bootstrap finished.");
    } catch (error) {
        console.error("Error during database bootstrap:", error);
        process.exit(1);
    }
}

void startServer();
