import fs from "fs/promises";
import path from "path";

const UPLOADS_ROOT = path.resolve(
  process.env.UPLOADS_DIR || path.join(process.cwd(), "uploads"),
);

export function getUploadsRoot(): string {
  return UPLOADS_ROOT;
}

export function postsUploadDir(): string {
  return path.join(UPLOADS_ROOT, "posts");
}

export function storiesUploadDir(): string {
  return path.join(UPLOADS_ROOT, "stories");
}

export function nutritionUploadDir(): string {
  return path.join(UPLOADS_ROOT, "nutrition");
}

export async function ensureAllUploadDirs(): Promise<void> {
  await Promise.all([
    fs.mkdir(postsUploadDir(), { recursive: true }),
    fs.mkdir(storiesUploadDir(), { recursive: true }),
    fs.mkdir(nutritionUploadDir(), { recursive: true }),
  ]);
}

/** Ruta absoluta en disco a partir de `/uploads/posts/xxx.jpg` */
export function resolveUploadAbsolute(publicPath: string): string | null {
  if (!publicPath || !publicPath.startsWith("/uploads/")) {
    return null;
  }
  const relative = publicPath.replace(/^\/uploads\/?/, "");
  const absolute = path.join(UPLOADS_ROOT, relative);
  const normalizedRoot = path.resolve(UPLOADS_ROOT);
  const normalizedFile = path.resolve(absolute);
  if (!normalizedFile.startsWith(normalizedRoot)) {
    return null;
  }
  return normalizedFile;
}

export async function uploadFileExists(publicPath: string): Promise<boolean> {
  const absolute = resolveUploadAbsolute(publicPath);
  if (!absolute) return false;
  try {
    await fs.access(absolute);
    return true;
  } catch {
    return false;
  }
}
