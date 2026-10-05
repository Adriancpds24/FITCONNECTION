import bcrypt from "bcryptjs";
import pool from "../db";

type DemoUser = {
  email: string;
  username: string;
  password: string;
  name: string;
  bio: string;
  sport: string;
  imagePath: string;
  role: string;
  isActive: boolean;
};

type SportCategorySeed = {
  name: string;
  description: string;
};

type WorkoutTemplateSeed = {
  title: string;
  description: string;
  sport: string;
  difficulty: string;
  exercises: Array<{
    name: string;
    sets: number;
    reps?: number;
    duration?: string;
  }>;
};

type NutritionTemplateSeed = {
  title: string;
  goal: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  notes: string;
};

type SportsCenterCitySeed = {
  city: string;
  province: string;
  community: string;
  latitude: number;
  longitude: number;
};

type SportsCenterCategorySeed = {
  category: string;
  namePrefix: string;
  type: string;
  address: string;
  latOffset: number;
  lngOffset: number;
};

type SportsCenterVariantSeed = {
  id: string;
  nameSuffix: string;
  addressSuffix: string;
  latOffset: number;
  lngOffset: number;
};

/** Solo cuenta admin en arranque; usuarios reales se registran en la app. */
const ADMIN_USER: DemoUser = {
  email: "fitconnect.app.admin@gmail.com",
  username: "admin",
  password: "Admin123456.",
  name: "Administrador",
  bio: "Cuenta de administracion del sistema FitConnect.",
  sport: "Fitness",
  imagePath: "https://ui-avatars.com/api/?name=Admin&background=random",
  role: "admin",
  isActive: true,
};

const DEMO_SPORT_CATEGORIES: SportCategorySeed[] = [
  {
    name: "CrossFit",
    description: "Entrenamientos funcionales de alta intensidad y comunidad competitiva.",
  },
  {
    name: "Gimnasio",
    description: "Rutinas de fuerza, hipertrofia y mantenimiento fisico.",
  },
  {
    name: "Running",
    description: "Planificacion de carrera, resistencia y mejora de tiempos.",
  },
  {
    name: "Yoga",
    description: "Movilidad, respiracion, control corporal y bienestar.",
  },
  {
    name: "Nutricion",
    description: "Apoyo nutricional para rendimiento, salud y composicion corporal.",
  },
];

const DEMO_WORKOUT_TEMPLATES: WorkoutTemplateSeed[] = [
  {
    title: "Fuerza Full Body",
    description: "Rutina base de fuerza para administrar progresion semanal.",
    sport: "Gimnasio",
    difficulty: "Intermedio",
    exercises: [
      { name: "Sentadilla", sets: 4, reps: 6 },
      { name: "Press banca", sets: 4, reps: 6 },
      { name: "Peso muerto rumano", sets: 3, reps: 8 },
    ],
  },
  {
    title: "WOD MetCon 20",
    description: "Plantilla corta de alta intensidad para clases y boxes.",
    sport: "CrossFit",
    difficulty: "Avanzado",
    exercises: [
      { name: "Burpees", sets: 5, reps: 12 },
      { name: "Thrusters", sets: 5, reps: 10 },
      { name: "Remo", sets: 5, duration: "250m" },
    ],
  },
];

const DEMO_NUTRITION_TEMPLATES: NutritionTemplateSeed[] = [
  {
    title: "Definicion Equilibrada",
    goal: "Definicion",
    calories: 2100,
    protein: 170,
    carbs: 190,
    fat: 65,
    notes: "Modelo base para fases de perdida de grasa con alta saciedad.",
  },
  {
    title: "Volumen Limpio",
    goal: "Volumen",
    calories: 2900,
    protein: 180,
    carbs: 360,
    fat: 80,
    notes: "Plantilla base para superavit controlado y progresion muscular.",
  },
];

const SPORTS_CENTER_CITIES: SportsCenterCitySeed[] = [
  // CIUDADES COSTERAS - Ajustadas agresivamente hacia el interior
  { city: "Barcelona", province: "Barcelona", community: "Catalunya", latitude: 41.4000, longitude: 2.1400 },
  { city: "Valencia", province: "Valencia", community: "Comunitat Valenciana", latitude: 39.4850, longitude: -0.3950 },
  { city: "Malaga", province: "Malaga", community: "Andalucia", latitude: 36.7450, longitude: -4.4350 },
  { city: "Alicante", province: "Alicante", community: "Comunitat Valenciana", latitude: 38.3650, longitude: -0.5050 },
  { city: "Cadiz", province: "Cadiz", community: "Andalucia", latitude: 36.5050, longitude: -6.2700 },
  { city: "Almeria", province: "Almeria", community: "Andalucia", latitude: 36.8550, longitude: -2.4550 },
  { city: "Huelva", province: "Huelva", community: "Andalucia", latitude: 37.2850, longitude: -6.9350 },
  { city: "Vigo", province: "Pontevedra", community: "Galicia", latitude: 42.2300, longitude: -8.7050 },
  { city: "Gijon", province: "Asturias", community: "Asturias", latitude: 43.5150, longitude: -5.6750 },
  { city: "A Coruna", province: "A Coruna", community: "Galicia", latitude: 43.3450, longitude: -8.4250 },
  { city: "Santander", province: "Cantabria", community: "Cantabria", latitude: 43.4450, longitude: -3.8250 },
  { city: "San Sebastian", province: "Gipuzkoa", community: "Pais Vasco", latitude: 43.2950, longitude: -1.9950 },
  { city: "Santa Cruz de Tenerife", province: "Santa Cruz de Tenerife", community: "Canarias", latitude: 28.4550, longitude: -16.2850 },
  { city: "Las Palmas", province: "Las Palmas", community: "Canarias", latitude: 28.1050, longitude: -15.4550 },
  { city: "Palma", province: "Illes Balears", community: "Illes Balears", latitude: 39.5850, longitude: 2.6400 },
  { city: "Cartagena", province: "Murcia", community: "Region de Murcia", latitude: 37.6450, longitude: -0.9850 },

  // CIUDADES DE INTERIOR
  { city: "Madrid", province: "Madrid", community: "Comunidad de Madrid", latitude: 40.4168, longitude: -3.7038 },
  { city: "Sevilla", province: "Sevilla", community: "Andalucia", latitude: 37.3891, longitude: -5.9845 },
  { city: "Zaragoza", province: "Zaragoza", community: "Aragon", latitude: 41.6488, longitude: -0.8891 },
  { city: "Murcia", province: "Murcia", community: "Region de Murcia", latitude: 37.9834, longitude: -1.1299 },
  { city: "Bilbao", province: "Bizkaia", community: "Pais Vasco", latitude: 43.263, longitude: -2.935 },
  { city: "Cordoba", province: "Cordoba", community: "Andalucia", latitude: 37.8882, longitude: -4.7794 },
  { city: "Valladolid", province: "Valladolid", community: "Castilla y Leon", latitude: 41.6523, longitude: -4.7245 },
  { city: "Granada", province: "Granada", community: "Andalucia", latitude: 37.1773, longitude: -3.5986 },
  { city: "Vitoria", province: "Araba", community: "Pais Vasco", latitude: 42.8467, longitude: -2.6727 },
  { city: "Oviedo", province: "Asturias", community: "Asturias", latitude: 43.3619, longitude: -5.8494 },
  { city: "Pamplona", province: "Navarra", community: "Navarra", latitude: 42.8125, longitude: -1.6458 },
  { city: "Logrono", province: "La Rioja", community: "La Rioja", latitude: 42.4627, longitude: -2.4449 },
  { city: "Toledo", province: "Toledo", community: "Castilla-La Mancha", latitude: 39.8628, longitude: -4.0273 },
  { city: "Badajoz", province: "Badajoz", community: "Extremadura", latitude: 38.8794, longitude: -6.9707 },
  { city: "Caceres", province: "Caceres", community: "Extremadura", latitude: 39.4753, longitude: -6.3724 },
  { city: "Salamanca", province: "Salamanca", community: "Castilla y Leon", latitude: 40.9701, longitude: -5.6635 },
  { city: "Burgos", province: "Burgos", community: "Castilla y Leon", latitude: 42.3439, longitude: -3.6969 },
  { city: "Leon", province: "Leon", community: "Castilla y Leon", latitude: 42.5987, longitude: -5.5671 },
  { city: "Jaen", province: "Jaen", community: "Andalucia", latitude: 37.7796, longitude: -3.7849 },
  { city: "Lleida", province: "Lleida", community: "Catalunya", latitude: 41.6176, longitude: 0.62 },
  { city: "Tarragona", province: "Tarragona", community: "Catalunya", latitude: 41.1189, longitude: 1.2445 },
  { city: "Girona", province: "Girona", community: "Catalunya", latitude: 41.9794, longitude: 2.8214 },
  { city: "Castellon", province: "Castellon", community: "Comunitat Valenciana", latitude: 39.9864, longitude: -0.0513 },
  { city: "Lorca", province: "Murcia", community: "Region de Murcia", latitude: 37.6712, longitude: -1.7017 },
  { city: "Albacete", province: "Albacete", community: "Castilla-La Mancha", latitude: 38.9943, longitude: -1.8585 },
  { city: "Ciudad Real", province: "Ciudad Real", community: "Castilla-La Mancha", latitude: 38.9848, longitude: -3.9274 },
  { city: "Cuenca", province: "Cuenca", community: "Castilla-La Mancha", latitude: 40.0704, longitude: -2.1374 },
  { city: "Guadalajara", province: "Guadalajara", community: "Castilla-La Mancha", latitude: 40.6325, longitude: -3.1602 },
  { city: "Huesca", province: "Huesca", community: "Aragon", latitude: 42.1401, longitude: -0.4089 },
  { city: "Teruel", province: "Teruel", community: "Aragon", latitude: 40.3457, longitude: -1.1065 },
  { city: "Avila", province: "Avila", community: "Castilla y Leon", latitude: 40.6565, longitude: -4.6818 },
  { city: "Palencia", province: "Palencia", community: "Castilla y Leon", latitude: 42.0097, longitude: -4.5288 },
  { city: "Segovia", province: "Segovia", community: "Castilla y Leon", latitude: 40.9429, longitude: -4.1088 },
  { city: "Soria", province: "Soria", community: "Castilla y Leon", latitude: 41.7666, longitude: -2.479 },
  { city: "Zamora", province: "Zamora", community: "Castilla y Leon", latitude: 41.5035, longitude: -5.7446 },
  { city: "Lugo", province: "Lugo", community: "Galicia", latitude: 43.0097, longitude: -7.5568 },
  { city: "Ourense", province: "Ourense", community: "Galicia", latitude: 42.3358, longitude: -7.8639 },
  { city: "Pontevedra", province: "Pontevedra", community: "Galicia", latitude: 42.431, longitude: -8.6444 },
  { city: "Santiago de Compostela", province: "A Coruna", community: "Galicia", latitude: 42.8782, longitude: -8.5448 },
  { city: "Merida", province: "Badajoz", community: "Extremadura", latitude: 38.917, longitude: -6.3443 },
  { city: "Ceuta", province: "Ceuta", community: "Ceuta", latitude: 35.8894, longitude: -5.3213 },
  { city: "Melilla", province: "Melilla", community: "Melilla", latitude: 35.2923, longitude: -2.9381 },
];

const SPORTS_CENTER_CATEGORIES: SportsCenterCategorySeed[] = [
  { category: "gym", namePrefix: "Gimnasio Fit", type: "Gimnasio", address: "Zona fitness", latOffset: 0.001, lngOffset: 0.001 },
  { category: "sports_center", namePrefix: "Polideportivo Municipal", type: "Polideportivo", address: "Zona deportiva municipal", latOffset: -0.001, lngOffset: 0.001 },
  { category: "boxing", namePrefix: "Club Boxeo", type: "Boxeo", address: "Club de combate", latOffset: 0.001, lngOffset: -0.001 },
  { category: "kickboxing", namePrefix: "Kickboxing Team", type: "Kickboxing", address: "Escuela de striking", latOffset: -0.001, lngOffset: -0.001 },
  { category: "crossfit", namePrefix: "CrossFit Box", type: "CrossFit", address: "Box de entrenamiento funcional", latOffset: 0.002, lngOffset: 0.001 },
  { category: "martial_arts", namePrefix: "Dojo Artes Marciales", type: "Artes marciales", address: "Dojo y tatami", latOffset: -0.002, lngOffset: 0.001 },
  { category: "swimming", namePrefix: "Piscina Municipal", type: "Piscina", address: "Piscina cubierta", latOffset: 0.001, lngOffset: 0.002 },
  { category: "padel", namePrefix: "Club Padel", type: "Padel", address: "Pistas de padel", latOffset: -0.001, lngOffset: -0.002 },
  { category: "tennis", namePrefix: "Club Tenis", type: "Tenis", address: "Pistas de tenis", latOffset: 0.002, lngOffset: -0.002 },
  { category: "football", namePrefix: "Campo Futbol", type: "Futbol", address: "Campo de futbol", latOffset: -0.002, lngOffset: 0.002 },
  { category: "basketball", namePrefix: "Pabellon Basket", type: "Baloncesto", address: "Pabellon de baloncesto", latOffset: 0.003, lngOffset: 0.002 },
  { category: "yoga_pilates", namePrefix: "Estudio Yoga Pilates", type: "Yoga/Pilates", address: "Estudio de bienestar", latOffset: -0.003, lngOffset: -0.002 },
  { category: "calisthenics", namePrefix: "Parque Calistenia", type: "Calistenia", address: "Parque de entrenamiento exterior", latOffset: 0.000, lngOffset: -0.003 },
];

const SPORTS_CENTER_VARIANTS: SportsCenterVariantSeed[] = [
  { id: "central", nameSuffix: "Centro", addressSuffix: "Centro", latOffset: 0, lngOffset: 0 },
  { id: "norte", nameSuffix: "Norte", addressSuffix: "Zona norte", latOffset: 0.001, lngOffset: -0.001 },
  { id: "sur", nameSuffix: "Sur", addressSuffix: "Zona sur", latOffset: -0.001, lngOffset: 0.001 },
  { id: "performance", nameSuffix: "Performance", addressSuffix: "Area performance", latOffset: 0.001, lngOffset: 0.001 },
];

async function ensureUserColumns(): Promise<void> {
  await pool.query('ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "bio" TEXT');
  await pool.query('ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "imagePath" TEXT');
  await pool.query('ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "sport" TEXT');
  await pool.query('ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "gender" TEXT');
  await pool.query('ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "isPrivate" BOOLEAN DEFAULT false');
  await pool.query(`ALTER TABLE "User" ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'user'`);
  await pool.query(
    'ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "isActive" BOOLEAN DEFAULT true',
  );
  await pool.query('ALTER TABLE "User" ADD COLUMN IF NOT EXISTS xp INTEGER DEFAULT 0');
  await pool.query('ALTER TABLE "User" ADD COLUMN IF NOT EXISTS level INTEGER DEFAULT 1');
  await pool.query(
    'ALTER TABLE "User" ADD COLUMN IF NOT EXISTS fitcoins INTEGER DEFAULT 0',
  );
  await pool.query('ALTER TABLE "User" ADD COLUMN IF NOT EXISTS streak INTEGER DEFAULT 0');
  await pool.query(
    'ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "lastWorkoutAt" TIMESTAMP(3)',
  );
  await pool.query(`
    UPDATE "User"
    SET
      xp = COALESCE(xp, 0),
      level = COALESCE(level, 1),
      fitcoins = COALESCE(fitcoins, 0),
      streak = COALESCE(streak, 0)
    WHERE xp IS NULL
      OR level IS NULL
      OR fitcoins IS NULL
      OR streak IS NULL
  `);
  await pool.query(
    'ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "twoFactorEnabled" BOOLEAN DEFAULT false',
  );
  await pool.query(
    'ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "twoFactorSecret" TEXT',
  );
  await pool.query(
    'ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "loginAlertsEnabled" BOOLEAN DEFAULT true',
  );
  await pool.query('ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "oauthProvider" TEXT');
  await pool.query('ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "oauthSubject" TEXT');
  await pool.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS "User_oauth_provider_subject_key"
    ON "User" ("oauthProvider", "oauthSubject")
    WHERE "oauthSubject" IS NOT NULL
  `);
}

async function ensureAccountSupportTables(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "UserSession" (
      "id" SERIAL NOT NULL,
      "userId" INTEGER NOT NULL,
      "deviceLabel" TEXT,
      "userAgent" TEXT,
      "ipMasked" TEXT,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "revokedAt" TIMESTAMP(3),
      CONSTRAINT "UserSession_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "UserSession_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE CASCADE ON UPDATE CASCADE
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "UserLoginEvent" (
      "id" SERIAL NOT NULL,
      "userId" INTEGER NOT NULL,
      "userAgent" TEXT,
      "ipMasked" TEXT,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "UserLoginEvent_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "UserLoginEvent_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE CASCADE ON UPDATE CASCADE
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "UserBlock" (
      "blockerId" INTEGER NOT NULL,
      "blockedId" INTEGER NOT NULL,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "UserBlock_pkey" PRIMARY KEY ("blockerId","blockedId"),
      CONSTRAINT "UserBlock_blockerId_fkey"
        FOREIGN KEY ("blockerId") REFERENCES "User"("id") ON DELETE CASCADE,
      CONSTRAINT "UserBlock_blockedId_fkey"
        FOREIGN KEY ("blockedId") REFERENCES "User"("id") ON DELETE CASCADE
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "PaymentMethod" (
      "id" SERIAL NOT NULL,
      "userId" INTEGER NOT NULL,
      "brand" TEXT NOT NULL,
      "last4" TEXT NOT NULL,
      "expMonth" INTEGER,
      "expYear" INTEGER,
      "holderName" TEXT,
      "isDefault" BOOLEAN NOT NULL DEFAULT false,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "PaymentMethod_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "PaymentMethod_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE
    )
  `);
}

async function ensureFollowStatusColumn(): Promise<void> {
  await pool.query(
    `ALTER TABLE "Follow" ADD COLUMN IF NOT EXISTS "status" TEXT NOT NULL DEFAULT 'accepted'`,
  );
}

async function ensurePasswordResetSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "PasswordResetToken" (
      "id" SERIAL NOT NULL,
      "userId" INTEGER NOT NULL,
      "tokenHash" TEXT NOT NULL,
      "expiresAt" TIMESTAMP(3) NOT NULL,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "PasswordResetToken_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "PasswordResetToken_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE CASCADE
        ON UPDATE CASCADE
    )
  `);

  await pool.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS "PasswordResetToken_tokenHash_key"
    ON "PasswordResetToken"("tokenHash")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "PasswordResetToken_userId_idx"
    ON "PasswordResetToken"("userId")
  `);
}

async function ensureStorySupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "Story" (
      "id" SERIAL NOT NULL,
      "userId" INTEGER NOT NULL,
      "imagePath" TEXT,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "expiresAt" TIMESTAMP(3) NOT NULL,
      "deletedAt" TIMESTAMP(3),
      "imageDeletedAt" TIMESTAMP(3),
      "deleteReason" TEXT,
      CONSTRAINT "Story_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "Story_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE CASCADE
        ON UPDATE CASCADE
    )
  `);

  await pool.query('ALTER TABLE "Story" ADD COLUMN IF NOT EXISTS "imagePath" TEXT');
  await pool.query('ALTER TABLE "Story" ADD COLUMN IF NOT EXISTS "expiresAt" TIMESTAMP(3)');
  await pool.query('ALTER TABLE "Story" ADD COLUMN IF NOT EXISTS "deletedAt" TIMESTAMP(3)');
  await pool.query('ALTER TABLE "Story" ADD COLUMN IF NOT EXISTS "imageDeletedAt" TIMESTAMP(3)');
  await pool.query('ALTER TABLE "Story" ADD COLUMN IF NOT EXISTS "deleteReason" TEXT');
  await pool.query(`
    UPDATE "Story"
    SET "expiresAt" = COALESCE("expiresAt", "createdAt" + INTERVAL '24 hours')
    WHERE "expiresAt" IS NULL
  `);
  await pool.query('ALTER TABLE "Story" ALTER COLUMN "expiresAt" SET NOT NULL');

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "Story_userId_idx"
    ON "Story"("userId")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "Story_expiresAt_idx"
    ON "Story"("expiresAt")
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "Story_active_idx"
    ON "Story"("deletedAt", "expiresAt")
  `);
}

async function ensureMessageSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "Message" (
      "id" SERIAL NOT NULL,
      "senderId" INTEGER NOT NULL,
      "receiverId" INTEGER NOT NULL,
      "content" TEXT NOT NULL,
      "read" BOOLEAN NOT NULL DEFAULT false,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "Message_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "Message_senderId_fkey"
        FOREIGN KEY ("senderId") REFERENCES "User"("id")
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
      CONSTRAINT "Message_receiverId_fkey"
        FOREIGN KEY ("receiverId") REFERENCES "User"("id")
        ON DELETE RESTRICT
        ON UPDATE CASCADE
    )
  `);
}

async function ensureConversationClearSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "ConversationClear" (
      "userId" INTEGER NOT NULL,
      "otherUserId" INTEGER NOT NULL,
      "clearedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "ConversationClear_pkey" PRIMARY KEY ("userId", "otherUserId"),
      CONSTRAINT "ConversationClear_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE CASCADE
        ON UPDATE CASCADE,
      CONSTRAINT "ConversationClear_otherUserId_fkey"
        FOREIGN KEY ("otherUserId") REFERENCES "User"("id")
        ON DELETE CASCADE
        ON UPDATE CASCADE
    )
  `);
}

async function ensureBookmarkSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "Bookmark" (
      "id" SERIAL NOT NULL,
      "postId" INTEGER NOT NULL,
      "userId" INTEGER NOT NULL,
      CONSTRAINT "Bookmark_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "Bookmark_postId_fkey"
        FOREIGN KEY ("postId") REFERENCES "Post"("id")
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
      CONSTRAINT "Bookmark_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE RESTRICT
        ON UPDATE CASCADE
    )
  `);

  await pool.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS "Bookmark_userId_postId_key"
    ON "Bookmark"("userId", "postId")
  `);
}

async function ensureCommentLikeSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "CommentLike" (
      "id" SERIAL NOT NULL,
      "userId" INTEGER NOT NULL,
      "commentId" INTEGER NOT NULL,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "CommentLike_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "CommentLike_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE CASCADE
        ON UPDATE CASCADE,
      CONSTRAINT "CommentLike_commentId_fkey"
        FOREIGN KEY ("commentId") REFERENCES "Comment"("id")
        ON DELETE CASCADE
        ON UPDATE CASCADE
    )
  `);

  await pool.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS "CommentLike_userId_commentId_key"
    ON "CommentLike"("userId", "commentId")
  `);
}

async function ensureReportSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "Report" (
      "id" SERIAL NOT NULL,
      "userId" INTEGER NOT NULL,
      "targetId" INTEGER NOT NULL,
      "type" TEXT NOT NULL,
      "reason" TEXT,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "Report_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "Report_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE RESTRICT
        ON UPDATE CASCADE
    )
  `);

  await pool.query(`ALTER TABLE "Report" ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'open'`);
  await pool.query(`ALTER TABLE "Report" ADD COLUMN IF NOT EXISTS "reviewedBy" INTEGER`);
  await pool.query(`ALTER TABLE "Report" ADD COLUMN IF NOT EXISTS "reviewedAt" TIMESTAMP(3)`);
  await pool.query(`ALTER TABLE "Report" ADD COLUMN IF NOT EXISTS "resolutionNotes" TEXT`);
  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'Report_reviewedBy_fkey'
      ) THEN
        ALTER TABLE "Report"
        ADD CONSTRAINT "Report_reviewedBy_fkey"
        FOREIGN KEY ("reviewedBy") REFERENCES "User"("id")
        ON DELETE SET NULL
        ON UPDATE CASCADE;
      END IF;
    END $$;
  `);
}

async function ensureHighlightSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "Highlight" (
      "id" SERIAL NOT NULL,
      "userId" INTEGER NOT NULL,
      "title" TEXT NOT NULL,
      "image" TEXT NOT NULL,
      "storyImages" JSONB DEFAULT '[]'::jsonb,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "Highlight_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "Highlight_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE RESTRICT
        ON UPDATE CASCADE
    )
  `);
  // Ensure storyImages column exists for older databases
  await pool.query('ALTER TABLE "Highlight" ADD COLUMN IF NOT EXISTS "storyImages" JSONB DEFAULT \'[]\'::jsonb');
}

async function ensureMetricsSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "user_profiles_metrics" (
      "userId" INTEGER NOT NULL,
      "weight" DOUBLE PRECISION NOT NULL,
      "height" DOUBLE PRECISION NOT NULL,
      "age" INTEGER NOT NULL,
       sex TEXT NOT NULL,
      "activityLevel" TEXT NOT NULL,
       goal TEXT NOT NULL,
       calories INTEGER NOT NULL,
       protein INTEGER NOT NULL,
       carbs INTEGER NOT NULL,
       fat INTEGER NOT NULL,
      "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "user_profiles_metrics_pkey" PRIMARY KEY ("userId"),
      CONSTRAINT "user_profiles_metrics_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE CASCADE
        ON UPDATE CASCADE
    )
  `);
}

async function ensureMealAiEntrySupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "MealAiEntry" (
      "id" SERIAL NOT NULL,
      "userId" INTEGER NOT NULL,
      "date" DATE NOT NULL DEFAULT CURRENT_DATE,
      "mealType" TEXT NOT NULL,
      "comida" TEXT NOT NULL,
      "image" TEXT,
      "proteinas" INTEGER NOT NULL DEFAULT 0,
      "carbohidratos" INTEGER NOT NULL DEFAULT 0,
      "grasas" INTEGER NOT NULL DEFAULT 0,
      "calorias" INTEGER NOT NULL DEFAULT 0,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "MealAiEntry_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "MealAiEntry_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE CASCADE
        ON UPDATE CASCADE
    )
  `);

  await pool.query('ALTER TABLE "MealAiEntry" ADD COLUMN IF NOT EXISTS "image" TEXT');

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "MealAiEntry_userId_date_idx"
    ON "MealAiEntry"("userId", "date")
  `);

  // Enforce 1 meal per slot/day (keeps legacy mealType values like "IA" allowed multiple times).
  await pool.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS "MealAiEntry_user_date_slot_key"
      ON "MealAiEntry"("userId", "date", "mealType")
      WHERE "mealType" IN ('Desayuno', 'Almuerzo', 'Comida', 'Merienda', 'Cena')
  `);
}

async function ensureDailyNutritionTotalsSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "UserDailyNutritionTotals" (
      "id" SERIAL NOT NULL,
      "userId" INTEGER NOT NULL,
      "date" DATE NOT NULL DEFAULT CURRENT_DATE,
      "calories" INTEGER NOT NULL DEFAULT 0,
      "protein" INTEGER NOT NULL DEFAULT 0,
      "carbs" INTEGER NOT NULL DEFAULT 0,
      "fat" INTEGER NOT NULL DEFAULT 0,
      "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "UserDailyNutritionTotals_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "UserDailyNutritionTotals_user_date_key" UNIQUE ("userId", "date"),
      CONSTRAINT "UserDailyNutritionTotals_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE CASCADE
        ON UPDATE CASCADE
    )
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "UserDailyNutritionTotals_userId_date_idx"
    ON "UserDailyNutritionTotals"("userId", "date")
  `);
}

async function ensureWeeklyCoachSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "UserWeeklyCoachPlan" (
      "id" SERIAL NOT NULL,
      "userId" INTEGER NOT NULL,
      "weekStart" DATE NOT NULL,
      "planType" TEXT NOT NULL,
      "planJson" JSONB NOT NULL DEFAULT '{}'::jsonb,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "UserWeeklyCoachPlan_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "UserWeeklyCoachPlan_user_week_type_key" UNIQUE ("userId", "weekStart", "planType"),
      CONSTRAINT "UserWeeklyCoachPlan_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE CASCADE
        ON UPDATE CASCADE
    )
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "UserWeeklyCoachPlan_user_week_idx"
    ON "UserWeeklyCoachPlan"("userId", "weekStart")
  `);
}

async function ensureWeightEntrySupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "UserWeightEntry" (
      "id" SERIAL NOT NULL,
      "userId" INTEGER NOT NULL,
      "date" DATE NOT NULL DEFAULT CURRENT_DATE,
      "weightKg" DOUBLE PRECISION NOT NULL,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "UserWeightEntry_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "UserWeightEntry_user_date_key" UNIQUE ("userId", "date"),
      CONSTRAINT "UserWeightEntry_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE CASCADE
        ON UPDATE CASCADE
    )
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS "UserWeightEntry_user_date_idx"
    ON "UserWeightEntry"("userId", "date")
  `);
}

async function ensureReminderSettingsSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "UserReminderSettings" (
      "userId" INTEGER NOT NULL,
      "enabled" BOOLEAN NOT NULL DEFAULT true,
      "mealReminders" BOOLEAN NOT NULL DEFAULT true,
      "trainingReminders" BOOLEAN NOT NULL DEFAULT true,
      "hydrationReminders" BOOLEAN NOT NULL DEFAULT false,
      "quietHoursStart" TEXT DEFAULT '22:30',
      "quietHoursEnd" TEXT DEFAULT '08:30',
      "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "UserReminderSettings_pkey" PRIMARY KEY ("userId"),
      CONSTRAINT "UserReminderSettings_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE CASCADE
        ON UPDATE CASCADE
    )
  `);
}

async function ensureTrainingHistorySupport(): Promise<void> {
    await pool.query(`
        CREATE TABLE IF NOT EXISTS "user_training_history" (
            "id" SERIAL PRIMARY KEY,
            "userId" INTEGER NOT NULL,
            "workoutId" INTEGER,
            "isCompleted" BOOLEAN DEFAULT false,
            "exercisesList" JSONB DEFAULT '[]'::jsonb,
            "date" DATE DEFAULT CURRENT_DATE,
            "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
            CONSTRAINT "user_training_history_userId_fkey" 
                FOREIGN KEY ("userId") REFERENCES "User"("id") 
                ON DELETE CASCADE
        )
    `);
    
    // Add unique constraint per user and date to avoid duplicates
    try {
        await pool.query('CREATE UNIQUE INDEX IF NOT EXISTS "user_training_history_userId_date_key" ON "user_training_history"("userId", "date")');
    } catch (e) {
        console.warn("Could not create unique index for training history:", e);
    }
}

async function ensureDuelChallengeSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "UserDuelChallengeProgress" (
      "id" SERIAL PRIMARY KEY,
      "userId" INTEGER NOT NULL,
      "challengeStartDate" DATE NOT NULL DEFAULT CURRENT_DATE,
      "completedDays" INTEGER NOT NULL DEFAULT 0,
      "totalPoints" INTEGER NOT NULL DEFAULT 0,
      "completedDates" JSONB NOT NULL DEFAULT '[]'::jsonb,
      "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "UserDuelChallengeProgress_userId_key" UNIQUE ("userId"),
      CONSTRAINT "UserDuelChallengeProgress_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE CASCADE
        ON UPDATE CASCADE
    )
  `);
}

async function ensureAdminSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "AdminAuditLog" (
      "id" SERIAL NOT NULL,
      "adminUserId" INTEGER NOT NULL,
      action TEXT NOT NULL,
      "targetType" TEXT NOT NULL,
      "targetId" INTEGER,
      metadata JSONB,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "AdminAuditLog_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "AdminAuditLog_adminUserId_fkey"
        FOREIGN KEY ("adminUserId") REFERENCES "User"("id")
        ON DELETE CASCADE
        ON UPDATE CASCADE
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "SportCategory" (
      "id" SERIAL NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      "isActive" BOOLEAN NOT NULL DEFAULT true,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "SportCategory_pkey" PRIMARY KEY ("id")
    )
  `);

  await pool.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS "SportCategory_name_key"
    ON "SportCategory"(name)
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "WorkoutTemplate" (
      "id" SERIAL NOT NULL,
      title TEXT NOT NULL,
      description TEXT,
      sport TEXT,
      difficulty TEXT,
      "exercisesJson" JSONB NOT NULL DEFAULT '[]'::jsonb,
      "isActive" BOOLEAN NOT NULL DEFAULT true,
      "createdBy" INTEGER,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "WorkoutTemplate_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "WorkoutTemplate_createdBy_fkey"
        FOREIGN KEY ("createdBy") REFERENCES "User"("id")
        ON DELETE SET NULL
        ON UPDATE CASCADE
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS "NutritionTemplate" (
      "id" SERIAL NOT NULL,
      title TEXT NOT NULL,
      goal TEXT,
      calories INTEGER,
      protein INTEGER,
      carbs INTEGER,
      fat INTEGER,
      notes TEXT,
      "isActive" BOOLEAN NOT NULL DEFAULT true,
      "createdBy" INTEGER,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "NutritionTemplate_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "NutritionTemplate_createdBy_fkey"
        FOREIGN KEY ("createdBy") REFERENCES "User"("id")
        ON DELETE SET NULL
        ON UPDATE CASCADE
    )
  `);
}

async function ensureNotificationSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "Notification" (
      "id" SERIAL PRIMARY KEY,
      "userId" INTEGER NOT NULL,
      "type" TEXT NOT NULL,
      "content" TEXT NOT NULL,
      "senderId" INTEGER,
      "postId" INTEGER,
      "read" BOOLEAN DEFAULT false,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "Notification_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE,
      CONSTRAINT "Notification_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "User"("id") ON DELETE SET NULL,
      CONSTRAINT "Notification_postId_fkey" FOREIGN KEY ("postId") REFERENCES "Post"("id") ON DELETE CASCADE
    )
  `);
}

async function ensureWearableSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "UserWearableData" (
      "id" SERIAL NOT NULL,
      "userId" INTEGER NOT NULL,
      "date" DATE NOT NULL DEFAULT CURRENT_DATE,
      "steps" INTEGER DEFAULT 0,
      "burnedCalories" INTEGER DEFAULT 0,
      "heartRate" INTEGER DEFAULT 0,
      "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "UserWearableData_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "UserWearableData_userId_date_key" UNIQUE ("userId", "date"),
      CONSTRAINT "UserWearableData_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE CASCADE
        ON UPDATE CASCADE
    )
  `);
}

async function ensureSportsCenterSupport(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS "SportsCenter" (
      "id" SERIAL NOT NULL,
      "sourceId" TEXT NOT NULL,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      city TEXT NOT NULL,
      province TEXT,
      community TEXT NOT NULL,
      category TEXT NOT NULL,
      address TEXT,
      website TEXT,
      phone TEXT,
      "openingHours" TEXT,
      image TEXT,
      latitude DOUBLE PRECISION NOT NULL,
      longitude DOUBLE PRECISION NOT NULL,
      "isActive" BOOLEAN NOT NULL DEFAULT true,
      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "SportsCenter_pkey" PRIMARY KEY ("id")
    )
  `);

  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS "sourceId" TEXT');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS name TEXT');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS type TEXT');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS city TEXT');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS province TEXT');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS community TEXT');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS category TEXT');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS address TEXT');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS website TEXT');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS phone TEXT');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS "openingHours" TEXT');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS image TEXT');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS "isActive" BOOLEAN NOT NULL DEFAULT true');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP');
  await pool.query('ALTER TABLE "SportsCenter" ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP');

  await pool.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS "SportsCenter_sourceId_key"
    ON "SportsCenter"("sourceId")
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS "SportsCenter_city_category_idx"
    ON "SportsCenter"(city, category)
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS "SportsCenter_community_category_idx"
    ON "SportsCenter"(community, category)
  `);
}

async function ensureSocialTables(): Promise<void> {
  await ensureFollowStatusColumn();
  await ensurePasswordResetSupport();
  await ensureStorySupport();
  await ensureMessageSupport();
  await ensureConversationClearSupport();
  await ensureBookmarkSupport();
  await ensureCommentLikeSupport();
  await ensureReportSupport();
  await ensureHighlightSupport();
  await ensureMetricsSupport();
  await ensureMealAiEntrySupport();
  await ensureDailyNutritionTotalsSupport();
  await ensureWeeklyCoachSupport();
  await ensureWeightEntrySupport();
  await ensureReminderSettingsSupport();
  await ensureTrainingHistorySupport();
  await ensureDuelChallengeSupport();
  await ensureWearableSupport();
  await ensureNotificationSupport();
  await ensureAdminSupport();
  await ensureSportsCenterSupport();
}

async function normalizePassword(password: string): Promise<string> {
  if (password.startsWith("$2a$") || password.startsWith("$2b$")) {
    return password;
  }

  return bcrypt.hash(password, 10);
}

async function upsertDemoUser(user: DemoUser): Promise<number> {
  const normalizedPassword = await normalizePassword(user.password);
  const existingUserResult = await pool.query<{ id: number }>(
    'SELECT id FROM "User" WHERE email = $1 OR username = $2 LIMIT 1',
    [user.email, user.username],
  );

  if (existingUserResult.rows.length > 0) {
    const existingUserId = existingUserResult.rows[0].id;
    await pool.query(
      `
        UPDATE "User"
        SET
          email = $1,
          username = $2,
          password = CASE
            WHEN COALESCE(password, '') = '' OR password NOT LIKE '$2%' THEN $3
            ELSE password
          END,
          name = CASE
            WHEN COALESCE(name, '') = '' OR name = username THEN $4
            ELSE name
          END,
          bio = CASE
            WHEN COALESCE(bio, '') = '' THEN $5
            ELSE bio
          END,
          sport = CASE
            WHEN COALESCE(sport, '') = '' THEN $6
            ELSE sport
          END,
          "imagePath" = CASE
            WHEN COALESCE("imagePath", '') = '' THEN $7
            ELSE "imagePath"
          END,
          role = $8,
          "isActive" = $9,
          "updatedAt" = NOW()
        WHERE id = $10
      `,
      [
        user.email,
        user.username,
        normalizedPassword,
        user.name,
        user.bio,
        user.sport,
        user.imagePath,
        user.role,
        user.isActive,
        existingUserId,
      ],
    );
    return existingUserId;
  }

  const insertUserResult = await pool.query<{ id: number }>(
    `
      INSERT INTO "User" (
        email,
        username,
        password,
        name,
        bio,
        sport,
        "imagePath",
        role,
        "isActive",
        "updatedAt"
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
      RETURNING id
    `,
    [
      user.email,
      user.username,
      normalizedPassword,
      user.name,
      user.bio,
      user.sport,
      user.imagePath,
      user.role,
      user.isActive,
    ],
  );

  return insertUserResult.rows[0].id;
}

/** Cuenta admin + mapa de usuarios existentes (registros reales no se tocan). */
async function ensureAdminAccount(): Promise<Map<string, number>> {
  const userIds = new Map<string, number>();
  const adminId = await upsertDemoUser(ADMIN_USER);
  userIds.set(ADMIN_USER.username, adminId);

  const existingUsersResult = await pool.query<{ id: number; username: string }>(
    'SELECT id, username FROM "User"',
  );
  for (const user of existingUsersResult.rows) {
    userIds.set(user.username, user.id);
  }
  return userIds;
}

async function ensureDemoSportCategories(): Promise<void> {
  for (const category of DEMO_SPORT_CATEGORIES) {
    await pool.query(
      `
        INSERT INTO "SportCategory" (name, description, "isActive", "createdAt", "updatedAt")
        VALUES ($1, $2, true, NOW(), NOW())
        ON CONFLICT (name) DO UPDATE
        SET
          description = EXCLUDED.description,
          "isActive" = true,
          "updatedAt" = NOW()
      `,
      [category.name, category.description],
    );
  }
}

async function ensureDemoWorkoutTemplates(userIds: Map<string, number>): Promise<void> {
  const adminUserId = userIds.get("admin") ?? null;

  for (const template of DEMO_WORKOUT_TEMPLATES) {
    const existingResult = await pool.query<{ id: number }>(
      'SELECT id FROM "WorkoutTemplate" WHERE title = $1 LIMIT 1',
      [template.title],
    );

    if (existingResult.rows.length > 0) {
      await pool.query(
        `
          UPDATE "WorkoutTemplate"
          SET
            description = $1,
            sport = $2,
            difficulty = $3,
            "exercisesJson" = $4,
            "isActive" = true,
            "updatedAt" = NOW()
          WHERE id = $5
        `,
        [
          template.description,
          template.sport,
          template.difficulty,
          JSON.stringify(template.exercises),
          existingResult.rows[0].id,
        ],
      );
      continue;
    }

    await pool.query(
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
        VALUES ($1, $2, $3, $4, $5, true, $6, NOW(), NOW())
      `,
      [
        template.title,
        template.description,
        template.sport,
        template.difficulty,
        JSON.stringify(template.exercises),
        adminUserId,
      ],
    );
  }
}

async function ensureDemoNutritionTemplates(userIds: Map<string, number>): Promise<void> {
  const adminUserId = userIds.get("admin") ?? null;

  for (const template of DEMO_NUTRITION_TEMPLATES) {
    const existingResult = await pool.query<{ id: number }>(
      'SELECT id FROM "NutritionTemplate" WHERE title = $1 LIMIT 1',
      [template.title],
    );

    if (existingResult.rows.length > 0) {
      await pool.query(
        `
          UPDATE "NutritionTemplate"
          SET
            goal = $1,
            calories = $2,
            protein = $3,
            carbs = $4,
            fat = $5,
            notes = $6,
            "isActive" = true,
            "updatedAt" = NOW()
          WHERE id = $7
        `,
        [
          template.goal,
          template.calories,
          template.protein,
          template.carbs,
          template.fat,
          template.notes,
          existingResult.rows[0].id,
        ],
      );
      continue;
    }

    await pool.query(
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
        VALUES ($1, $2, $3, $4, $5, $6, $7, true, $8, NOW(), NOW())
      `,
      [
        template.title,
        template.goal,
        template.calories,
        template.protein,
        template.carbs,
        template.fat,
        template.notes,
        adminUserId,
      ],
    );
  }
}

function normalizeSeedKey(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

async function ensureDemoSportsCenters(): Promise<void> {
  // Limpiar centros antiguos antes de generar nuevos
  await pool.query('DELETE FROM "SportsCenter"');
  
  // Categorías con su "peso" de popularidad (0.0 a 1.0)
  const categoryPopularity: Record<string, number> = {
    'gym': 0.9,
    'padel': 0.8,
    'swimming': 0.6,
    'crossfit': 0.7,
    'football': 0.7,
    'basketball': 0.6,
    'tennis': 0.5,
    'yoga_pilates': 0.7,
    'boxing': 0.4,
    'kickboxing': 0.3,
    'martial_arts': 0.4,
    'calisthenics': 0.3,
    'sports_center': 0.8
  };

  // Ciudades principales que deben tener más densidad
  const majorCities = ['Madrid', 'Barcelona', 'Valencia', 'Sevilla', 'Zaragoza', 'Malaga', 'Bilbao'];

  for (const city of SPORTS_CENTER_CITIES) {
    const isMajorCity = majorCities.includes(city.city);
    
    for (const category of SPORTS_CENTER_CATEGORIES) {
      const popularity = categoryPopularity[category.category] || 0.5;
      
      // Decidir cuántos variantes crear basándose en popularidad y tamaño de ciudad
      // Ciudades grandes: entre 1 y 4 variantes según popularidad
      // Ciudades normales: entre 0 y 2 variantes según popularidad
      let variantCount = 0;
      const rand = Math.random();
      
      if (isMajorCity) {
        if (rand < popularity) variantCount = 4;
        else if (rand < popularity + 0.2) variantCount = 2;
        else variantCount = 1;
      } else {
        if (rand < popularity * 0.5) variantCount = 2;
        else if (rand < popularity) variantCount = 1;
        else variantCount = 0; // Algunas ciudades no tendrán ciertos deportes
      }

      for (let i = 0; i < variantCount; i++) {
        const variant = SPORTS_CENTER_VARIANTS[i];
        const cityKey = normalizeSeedKey(city.city);
        const sourceId = `seed:${cityKey}:${category.category}:${variant.id}`;
        const name = `${category.namePrefix} ${variant.nameSuffix} ${city.city}`;
        
        // Añadir una pequeña desviación aleatoria extra a la posición para que no se solapen perfectamente
        const randomOffsetLat = (Math.random() - 0.5) * 0.0005;
        const randomOffsetLng = (Math.random() - 0.5) * 0.0005;

        const latitude = Number(
          (city.latitude + category.latOffset + variant.latOffset + randomOffsetLat).toFixed(6),
        );
        const longitude = Number(
          (city.longitude + category.lngOffset + variant.lngOffset + randomOffsetLng).toFixed(6),
        );

        await pool.query(
          `
            INSERT INTO "SportsCenter" (
              "sourceId", name, type, city, province, community, category, 
              address, website, phone, "openingHours", latitude, longitude, "isActive"
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, '', '', '', $9, $10, true)
            ON CONFLICT ("sourceId") DO NOTHING
          `,
          [
            sourceId,
            name,
            category.type,
            city.city,
            city.province,
            city.community,
            category.category,
            `${category.address} - ${variant.addressSuffix}, ${city.city}`,
            latitude,
            longitude,
          ],
        );
      }
    }
  }
}

async function ensureSeedData(): Promise<void> {
  const userIds = await ensureAdminAccount();
  await ensureDemoSportCategories();
  await ensureDemoWorkoutTemplates(userIds);
  await ensureDemoNutritionTemplates(userIds);
  await ensureDemoSportsCenters();
}

async function ensureFoodCategoryColumn(): Promise<void> {
  await pool.query(
    'ALTER TABLE "Food" ADD COLUMN IF NOT EXISTS category TEXT',
  );
}

export async function ensureDatabaseSupport(): Promise<void> {
  await ensureUserColumns();
  await ensureAccountSupportTables();
  await ensureSocialTables();
  await ensureFoodCategoryColumn();
  await ensureSeedData();
}
