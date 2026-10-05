type FetchRetryOptions = {
  timeoutMs: number;
  retries: number;
  retryDelayMs: number;
  retryOnStatuses: number[];
};

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function withTimeout(ms: number): AbortController {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), ms);
  // Avoid keeping event loop alive
  (timeout as any).unref?.();
  return controller;
}

export async function fetchWithRetry(
  url: string,
  init: RequestInit,
  options: Partial<FetchRetryOptions> = {},
): Promise<Response> {
  const timeoutMs = Number(options.timeoutMs ?? 20_000);
  const retries = Number(options.retries ?? 2);
  const retryDelayMs = Number(options.retryDelayMs ?? 650);
  const retryOnStatuses = options.retryOnStatuses ?? [429, 500, 502, 503, 504];

  let lastError: unknown = null;

  for (let attempt = 0; attempt <= retries; attempt++) {
    const controller = withTimeout(timeoutMs);
    const signal = controller.signal;

    try {
      const response = await fetch(url, { ...init, signal });
      if (attempt < retries && retryOnStatuses.includes(response.status)) {
        lastError = new Error(`retryable_status_${response.status}`);
        await sleep(retryDelayMs * Math.pow(1.5, attempt));
        continue;
      }
      return response;
    } catch (err) {
      lastError = err;
      const isAbort = err instanceof Error && err.name === 'AbortError';
      if (attempt < retries) {
        await sleep((isAbort ? 350 : retryDelayMs) * Math.pow(1.5, attempt));
        continue;
      }
    }
  }

  throw lastError ?? new Error('fetch_failed');
}

