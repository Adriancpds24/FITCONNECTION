import type { NextFunction, Request, Response } from 'express';

type RateLimitOptions = {
  limit: number;
  windowMs: number;
  keyPrefix: string;
};

type Bucket = {
  count: number;
  resetAt: number;
};

const buckets = new Map<string, Bucket>();

function nowMs(): number {
  return Date.now();
}

export function createRateLimiter(options: RateLimitOptions) {
  const limit = Number.isFinite(options.limit) ? options.limit : 30;
  const windowMs = Number.isFinite(options.windowMs) ? options.windowMs : 60_000;
  const keyPrefix = options.keyPrefix || 'rl';

  return function rateLimiter(req: Request, res: Response, next: NextFunction) {
    const userId =
      typeof (req as any).user?.userId === 'number' ? String((req as any).user.userId) : 'anon';
    const key = `${keyPrefix}:${userId}:${req.baseUrl}${req.path}`;
    const t = nowMs();

    let bucket = buckets.get(key);
    if (!bucket || t >= bucket.resetAt) {
      bucket = { count: 0, resetAt: t + windowMs };
      buckets.set(key, bucket);
    }

    bucket.count += 1;

    const remaining = Math.max(0, limit - bucket.count);
    res.setHeader('X-RateLimit-Limit', String(limit));
    res.setHeader('X-RateLimit-Remaining', String(remaining));
    res.setHeader('X-RateLimit-Reset', String(Math.ceil(bucket.resetAt / 1000)));

    if (bucket.count > limit) {
      const retryAfterSeconds = Math.max(1, Math.ceil((bucket.resetAt - t) / 1000));
      res.setHeader('Retry-After', String(retryAfterSeconds));
      return res.status(429).json({
        error: 'Demasiadas peticiones. Espera un momento y prueba de nuevo.',
      });
    }

    // Basic memory hygiene: occasionally prune old buckets.
    if (buckets.size > 5000) {
      for (const [k, b] of buckets) {
        if (t >= b.resetAt) buckets.delete(k);
      }
    }

    return next();
  };
}

