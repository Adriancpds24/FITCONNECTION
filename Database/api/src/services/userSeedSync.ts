import { promises as fs } from "fs";
import path from "path";
import pool from "../db";

type SeedUserRow = {
  id: number;
  email: string;
  username: string;
  password: string;
  name: string | null;
  bio: string | null;
  sport: string | null;
  gender: string | null;
  imagePath: string | null;
  updatedAt: string | Date | null;
  role: string | null;
  isActive: boolean | null;
  xp: number | null;
  level: number | null;
  fitcoins: number | null;
  streak: number | null;
};

const SEED_FILE_PATH = path.resolve(process.cwd(), "base de datos", "seed_data.sql");
const USERS_SECTION_HEADER = "-- Usuarios";
const NEXT_SECTION_HEADER = "-- Centros deportivos";

let syncQueue: Promise<void> = Promise.resolve();

function hasColumn(columns: Set<string>, columnName: string): boolean {
  return columns.has(columnName);
}

function buildUserSelectQuery(columns: Set<string>): string {
  const nameSelect = hasColumn(columns, "name")
    ? "name"
    : 'username AS name';
  const bioSelect = hasColumn(columns, "bio")
    ? "bio"
    : "NULL::text AS bio";
  const sportSelect = hasColumn(columns, "sport")
    ? "sport"
    : "NULL::text AS sport";
  const genderSelect = hasColumn(columns, "gender")
    ? "gender"
    : "NULL::text AS gender";
  const imagePathSelect = hasColumn(columns, "imagePath")
    ? '"imagePath"'
    : 'NULL::text AS "imagePath"';
  const updatedAtSelect = hasColumn(columns, "updatedAt")
    ? '"updatedAt"'
    : hasColumn(columns, "createdAt")
      ? '"createdAt" AS "updatedAt"'
      : 'CURRENT_TIMESTAMP AS "updatedAt"';
  const roleSelect = hasColumn(columns, "role")
    ? "role"
    : "'user'::text AS role";
  const isActiveSelect = hasColumn(columns, "isActive")
    ? '"isActive"'
    : 'true AS "isActive"';
  const xpSelect = hasColumn(columns, "xp")
    ? "xp"
    : "NULL::integer AS xp";
  const levelSelect = hasColumn(columns, "level")
    ? "level"
    : "NULL::integer AS level";
  const fitcoinsSelect = hasColumn(columns, "fitcoins")
    ? "fitcoins"
    : "NULL::integer AS fitcoins";
  const streakSelect = hasColumn(columns, "streak")
    ? "streak"
    : "NULL::integer AS streak";

  return `
    SELECT
      id,
      email,
      username,
      password,
      ${nameSelect},
      ${bioSelect},
      ${sportSelect},
      ${genderSelect},
      ${imagePathSelect},
      ${updatedAtSelect},
      ${roleSelect},
      ${isActiveSelect},
      ${xpSelect},
      ${levelSelect},
      ${fitcoinsSelect},
      ${streakSelect}
    FROM "User"
    ORDER BY id ASC
  `;
}

function normalizeKey(value: string | null): string | null {
  if (!value) {
    return null;
  }

  return value.trim().toLowerCase();
}

function escapeSqlValue(value: string): string {
  return value.replace(/\r?\n/g, " ").replace(/'/g, "''");
}

function formatNullableText(value: string | null): string {
  if (value == null) {
    return "NULL";
  }

  return `'${escapeSqlValue(value)}'`;
}

function formatTimestamp(value: string | Date | null): string {
  if (!value) {
    return "NOW()";
  }

  const date = value instanceof Date ? value : new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "NOW()";
  }

  return `'${date.toISOString()}'`;
}

function formatInteger(value: number | null | undefined, fallback: number): string {
  return String(value ?? fallback);
}

function isSmokeTestUser(user: Pick<SeedUserRow, "email" | "username">): boolean {
  return (
    user.username.startsWith("mobile_smoke_") ||
    user.email.startsWith("mobile_smoke_")
  );
}

function buildUsersSection(users: SeedUserRow[], eol: string): string {
  const values = users
    .filter((user) => !isSmokeTestUser(user))
    .map(
      (user) =>
        `(${user.id}, '${escapeSqlValue(user.email)}', '${escapeSqlValue(user.username)}', '${escapeSqlValue(user.password)}', ${formatNullableText(user.name)}, ${formatNullableText(user.bio)}, ${formatNullableText(user.sport)}, ${formatNullableText(user.gender)}, ${formatNullableText(user.imagePath)}, ${formatTimestamp(user.updatedAt)}, ${formatNullableText(user.role ?? "user")}, ${user.isActive === false ? "false" : "true"}, ${formatInteger(user.xp, 0)}, ${formatInteger(user.level, 1)}, ${formatInteger(user.fitcoins, 0)}, ${formatInteger(user.streak, 0)})`,
    )
    .join(`,${eol}`);

  return [
    USERS_SECTION_HEADER,
    'INSERT INTO "User" (id, email, username, password, name, bio, sport, gender, "imagePath", "updatedAt", role, "isActive", xp, level, fitcoins, streak) VALUES',
    values,
    "ON CONFLICT (id) DO UPDATE SET",
    "    email = EXCLUDED.email,",
    "    username = EXCLUDED.username,",
    "    password = EXCLUDED.password,",
    "    name = EXCLUDED.name,",
    "    bio = EXCLUDED.bio,",
    "    sport = EXCLUDED.sport,",
    "    gender = EXCLUDED.gender,",
    '    "imagePath" = EXCLUDED."imagePath",',
    '    "updatedAt" = EXCLUDED."updatedAt",',
    "    role = EXCLUDED.role,",
    '    "isActive" = EXCLUDED."isActive",',
    "    xp = EXCLUDED.xp,",
    "    level = EXCLUDED.level,",
    "    fitcoins = EXCLUDED.fitcoins,",
    "    streak = EXCLUDED.streak;",
    "",
  ].join(eol);
}

function splitSqlTuples(valuesBlock: string): string[] {
  const tuples: string[] = [];
  let inString = false;
  let depth = 0;
  let current = "";

  for (let i = 0; i < valuesBlock.length; i += 1) {
    const char = valuesBlock[i];
    const nextChar = valuesBlock[i + 1];

    if (char === "'" && nextChar === "'") {
      if (depth > 0) {
        current += "''";
      }
      i += 1;
      continue;
    }

    if (depth === 0) {
      if (char === "(") {
        current = "(";
        depth = 1;
      }
      continue;
    }

    current += char;

    if (char === "'") {
      inString = !inString;
      continue;
    }

    if (inString) {
      continue;
    }

    if (char === "(") {
      depth += 1;
      continue;
    }

    if (char === ")") {
      depth -= 1;
      if (depth === 0) {
        tuples.push(current.trim());
        current = "";
      }
    }
  }

  return tuples;
}

function splitSqlFields(tuple: string): string[] {
  const content = tuple.trim().replace(/^\(/, "").replace(/\)$/, "");
  const fields: string[] = [];
  let inString = false;
  let current = "";

  for (let i = 0; i < content.length; i += 1) {
    const char = content[i];
    const nextChar = content[i + 1];

    if (char === "'" && nextChar === "'") {
      current += "''";
      i += 1;
      continue;
    }

    if (char === "'") {
      inString = !inString;
      current += char;
      continue;
    }

    if (char === "," && !inString) {
      fields.push(current.trim());
      current = "";
      continue;
    }

    current += char;
  }

  if (current.trim().length > 0) {
    fields.push(current.trim());
  }

  return fields;
}

function parseSqlText(value: string): string | null {
  if (value === "NULL") {
    return null;
  }

  if (value.startsWith("'") && value.endsWith("'")) {
    return value.slice(1, -1).replace(/''/g, "'");
  }

  return value;
}

function parseSqlInteger(value: string | undefined): number | null {
  if (value == null || value === "NULL") {
    return null;
  }

  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function parseUsersSection(seedContent: string): SeedUserRow[] {
  const usersSectionStart = seedContent.indexOf(USERS_SECTION_HEADER);
  const nextSectionStart = seedContent.indexOf(NEXT_SECTION_HEADER);

  if (usersSectionStart === -1 || nextSectionStart === -1 || nextSectionStart <= usersSectionStart) {
    throw new Error("No se pudo localizar la seccion de usuarios en seed_data.sql");
  }

  const section = seedContent.slice(usersSectionStart, nextSectionStart);
  const valuesIndex = section.indexOf("VALUES");
  const lastSemicolonIndex = section.lastIndexOf(";");

  if (valuesIndex === -1 || lastSemicolonIndex === -1 || lastSemicolonIndex <= valuesIndex) {
    return [];
  }

  const valuesBlock = section.slice(valuesIndex + "VALUES".length, lastSemicolonIndex).trim();

  return splitSqlTuples(valuesBlock)
    .map(splitSqlFields)
    .filter((fields) =>
      [9, 11, 12, 15, 16].includes(fields.length),
    )
    .map((fields) => {
      const hasGender = fields.length === 12 || fields.length === 16;
      const imagePathIndex = hasGender ? 8 : 7;
      const updatedAtIndex = hasGender ? 9 : 8;
      const roleIndex = hasGender ? 10 : 9;
      const isActiveIndex = hasGender ? 11 : 10;
      const xpIndex = isActiveIndex + 1;
      const levelIndex = isActiveIndex + 2;
      const fitcoinsIndex = isActiveIndex + 3;
      const streakIndex = isActiveIndex + 4;
      const role = fields.length > roleIndex ? parseSqlText(fields[roleIndex]) : "user";
      const isActiveRaw = fields.length > isActiveIndex ? fields[isActiveIndex] : "true";

      return {
        id: Number(fields[0]),
        email: parseSqlText(fields[1]) ?? "",
        username: parseSqlText(fields[2]) ?? "",
        password: parseSqlText(fields[3]) ?? "",
        name: parseSqlText(fields[4]),
        bio: parseSqlText(fields[5]),
        sport: parseSqlText(fields[6]),
        gender: hasGender ? parseSqlText(fields[7]) : null,
        imagePath: parseSqlText(fields[imagePathIndex]),
        updatedAt: parseSqlText(fields[updatedAtIndex]),
        role,
        isActive: isActiveRaw === "false" ? false : true,
        xp: parseSqlInteger(fields[xpIndex]),
        level: parseSqlInteger(fields[levelIndex]),
        fitcoins: parseSqlInteger(fields[fitcoinsIndex]),
        streak: parseSqlInteger(fields[streakIndex]),
      };
    })
    .filter((user) => Number.isInteger(user.id) && user.email && user.username);
}

function mergeUsers(existingUsers: SeedUserRow[], databaseUsers: SeedUserRow[]): SeedUserRow[] {
  const mergedUsers = existingUsers.filter((user) => !isSmokeTestUser(user));
  const usedIds = new Set(mergedUsers.map((user) => user.id));
  let nextId = mergedUsers.reduce((maxId, user) => Math.max(maxId, user.id), 0) + 1;

  for (const databaseUser of databaseUsers) {
    if (isSmokeTestUser(databaseUser)) {
      continue;
    }

    const emailKey = normalizeKey(databaseUser.email);
    const usernameKey = normalizeKey(databaseUser.username);
    const existingIndex = mergedUsers.findIndex((user) => {
      return (
        (emailKey !== null && normalizeKey(user.email) === emailKey) ||
        (usernameKey !== null && normalizeKey(user.username) === usernameKey)
      );
    });

    if (existingIndex >= 0) {
      const existingUser = mergedUsers[existingIndex];
      mergedUsers[existingIndex] = {
        ...existingUser,
        email: databaseUser.email,
        username: databaseUser.username,
        password: databaseUser.password || existingUser.password,
        name: databaseUser.name ?? existingUser.name,
        bio: databaseUser.bio ?? existingUser.bio,
        sport: databaseUser.sport ?? existingUser.sport,
        gender: databaseUser.gender ?? existingUser.gender,
        imagePath: databaseUser.imagePath ?? existingUser.imagePath,
        updatedAt: databaseUser.updatedAt ?? existingUser.updatedAt,
        role: databaseUser.role ?? existingUser.role,
        isActive: databaseUser.isActive ?? existingUser.isActive,
        xp: databaseUser.xp ?? existingUser.xp,
        level: databaseUser.level ?? existingUser.level,
        fitcoins: databaseUser.fitcoins ?? existingUser.fitcoins,
        streak: databaseUser.streak ?? existingUser.streak,
      };
      continue;
    }

    let assignedId = databaseUser.id;
    if (usedIds.has(assignedId)) {
      assignedId = nextId;
    }

    while (usedIds.has(assignedId)) {
      assignedId += 1;
    }

    usedIds.add(assignedId);
    nextId = Math.max(nextId, assignedId + 1);
    mergedUsers.push({
      ...databaseUser,
      id: assignedId,
    });
  }

  return mergedUsers.sort((left, right) => left.id - right.id);
}

async function doSyncUsersToSeedFile(): Promise<void> {
  const columnsResult = await pool.query<{ column_name: string }>(
    `
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'User'
    `,
  );
  const columns = new Set(columnsResult.rows.map((row) => row.column_name));
  const usersResult = await pool.query<SeedUserRow>(buildUserSelectQuery(columns));

  if (usersResult.rows.length === 0) {
    return;
  }

  const currentSeed = await fs.readFile(SEED_FILE_PATH, "utf8");
  const eol = currentSeed.includes("\r\n") ? "\r\n" : "\n";
  const usersSectionStart = currentSeed.indexOf(USERS_SECTION_HEADER);
  const nextSectionStart = currentSeed.indexOf(NEXT_SECTION_HEADER);
  const existingUsers = parseUsersSection(currentSeed);
  const mergedUsers = mergeUsers(existingUsers, usersResult.rows);

  if (usersSectionStart === -1 || nextSectionStart === -1 || nextSectionStart <= usersSectionStart) {
    throw new Error("No se pudo localizar la seccion de usuarios en seed_data.sql");
  }

  const updatedSeed =
    currentSeed.slice(0, usersSectionStart) +
    buildUsersSection(mergedUsers, eol) +
    currentSeed.slice(nextSectionStart);

  await fs.writeFile(SEED_FILE_PATH, updatedSeed, "utf8");
}

export function syncUsersToSeedFile(): Promise<void> {
  syncQueue = syncQueue.catch(() => undefined).then(doSyncUsersToSeedFile);
  return syncQueue;
}
