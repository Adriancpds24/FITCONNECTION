import { Router } from 'express';
import { randomUUID } from 'crypto';
import fs from 'fs/promises';
import path from 'path';
import pool from '../db';
import { authenticateToken, AuthRequest } from '../middleware/auth';
import {
  FITCONNECTION_MEAL_IMAGE_JSON_PROMPT,
  FITCONNECTION_NUTRITION_ONLY_CHAT_PROMPT,
  FITCONNECTION_TEXT_MEAL_ESTIMATE_JSON_PROMPT,
  FITCONNECTION_WEEKLY_DIET_SHOPPING_JSON_PROMPT,
} from '../ai/prompts';
import { createRateLimiter } from '../middleware/rateLimit';
import { fetchWithRetry } from '../services/aiFetch';

const router = Router();
import { ensureAllUploadDirs, nutritionUploadDir } from '../config/uploads';

const NUTRITION_UPLOAD_DIR = nutritionUploadDir();
const aiChatRateLimit = createRateLimiter({
  limit: Number(process.env.AI_RATE_LIMIT_PER_MINUTE || 30),
  windowMs: 60_000,
  keyPrefix: 'ai-nutrition-chat',
});
const aiImageRateLimit = createRateLimiter({
  limit: Number(process.env.AI_IMAGE_RATE_LIMIT_PER_MINUTE || 10),
  windowMs: 60_000,
  keyPrefix: 'ai-nutrition-image',
});

type NutritionAnalysis = {
  comida: string;
  proteinas: number;
  carbohidratos: number;
  grasas: number;
  calorias: number;
};

type TextMealEstimate = {
  comida: string;
  caloriasMin: number;
  caloriasMax: number;
  proteinas: number;
  carbohidratos: number;
  grasas: number;
  desglose: Array<{ item: string; calorias: number }>;
  confianza: 'baja' | 'media' | 'alta';
  faltariaParaMejorar: string[];
};

function pad2(value: number): string {
  return String(value).padStart(2, '0');
}

function isIsoDate(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  return /^\d{4}-\d{2}-\d{2}$/.test(value);
}

async function ensureNutritionUploadDir(): Promise<void> {
  await ensureAllUploadDirs();
}

function extensionFromMimeType(mimeType: string): string | null {
  const normalized = (mimeType || '').toLowerCase().trim();
  const map: Record<string, string> = {
    'image/png': 'png',
    'image/jpeg': 'jpg',
    'image/jpg': 'jpg',
    'image/webp': 'webp',
  };
  return map[normalized] ?? null;
}

async function saveNutritionImageBase64({
  imageBase64,
  mimeType,
}: {
  imageBase64: string;
  mimeType: string;
}): Promise<string> {
  await ensureNutritionUploadDir();
  const ext = extensionFromMimeType(mimeType);
  if (!ext) {
    throw new Error('Formato de imagen no soportado (solo png/jpg/webp).');
  }

  const binary = Buffer.from(imageBase64, 'base64');
  if (binary.length === 0 || binary.length > 10 * 1024 * 1024) {
    throw new Error('Imagen inválida o demasiado grande (máx 10MB).');
  }

  const fileName = `${randomUUID()}.${ext}`;
  const filePath = path.join(NUTRITION_UPLOAD_DIR, fileName);
  await fs.writeFile(filePath, binary);
  return `/uploads/nutrition/${fileName}`;
}

async function recomputeAndPersistDailyTotals(userId: number, date: string) {
  const totalsQuery = await pool.query(
    `
      SELECT
        COALESCE(SUM(calorias), 0)::int AS calories,
        COALESCE(SUM(proteinas), 0)::int AS protein,
        COALESCE(SUM(carbohidratos), 0)::int AS carbs,
        COALESCE(SUM(grasas), 0)::int AS fat
      FROM "MealAiEntry"
      WHERE "userId" = $1 AND date = $2
    `,
    [userId, date],
  );

  const totals = totalsQuery.rows[0] as {
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
  };

  const upserted = await pool.query(
    `
      INSERT INTO "UserDailyNutritionTotals" (
        "userId",
        date,
        calories,
        protein,
        carbs,
        fat,
        "updatedAt"
      )
      VALUES ($1, $2, $3, $4, $5, $6, NOW())
      ON CONFLICT ("userId", date)
      DO UPDATE SET
        calories = EXCLUDED.calories,
        protein = EXCLUDED.protein,
        carbs = EXCLUDED.carbs,
        fat = EXCLUDED.fat,
        "updatedAt" = NOW()
      RETURNING *
    `,
    [userId, date, totals.calories, totals.protein, totals.carbs, totals.fat],
  );

  return upserted.rows[0];
}

function extractFirstJsonObject(text: string): Record<string, unknown> | null {
  for (let start = 0; start < text.length; start++) {
    if (text[start] !== '{') continue;

    let depth = 0;
    let inString = false;
    let escaped = false;

    for (let index = start; index < text.length; index++) {
      const char = text[index];

      if (inString) {
        if (escaped) {
          escaped = false;
          continue;
        }

        if (char === '\\') {
          escaped = true;
          continue;
        }

        if (char === '"') {
          inString = false;
        }

        continue;
      }

      if (char === '"') {
        inString = true;
        continue;
      }

      if (char === '{') {
        depth += 1;
        continue;
      }

      if (char === '}') {
        depth -= 1;

        if (depth === 0) {
          try {
            return JSON.parse(text.slice(start, index + 1));
          } catch {
            break;
          }
        }
      }
    }
  }

  return null;
}

function buildProviderErrorMessage(providerName: string, bodyText: string): string {
  try {
    const parsed = JSON.parse(bodyText) as any;
    const message = parsed?.error?.message as string | undefined;
    const details = Array.isArray(parsed?.error?.details) ? parsed.error.details : [];
    const reason = details.find((detail: any) => typeof detail?.reason === 'string')?.reason;

    if (providerName === 'Gemini' && reason === 'API_KEY_INVALID') {
      return 'La API key de Gemini no es valida o no tiene acceso a Gemini API.';
    }

    if (typeof message === 'string' && message.trim().length > 0) {
      return `Error llamando al proveedor IA (${providerName}): ${message.trim()}`;
    }
  } catch {
    // If the provider body is not JSON, fall back to the generic message below.
  }

  return `Error llamando al proveedor IA (${providerName})`;
}

function toSafeNutritionNumber(value: unknown): number {
  const parsed =
    typeof value === 'number'
      ? value
      : typeof value === 'string'
        ? Number(value.replace(',', '.'))
        : NaN;

  if (!Number.isFinite(parsed)) {
    return 0;
  }

  return Math.max(0, Math.round(parsed));
}

function normalizeNutritionAnalysis(value: unknown): NutritionAnalysis | null {
  if (!value || typeof value !== 'object') {
    return null;
  }

  const raw = value as Record<string, unknown>;
  const comida =
    typeof raw.comida === 'string' && raw.comida.trim().length > 0
      ? raw.comida.trim()
      : 'Comida detectada';

  return {
    comida,
    proteinas: toSafeNutritionNumber(raw.proteinas),
    carbohidratos: toSafeNutritionNumber(raw.carbohidratos),
    grasas: toSafeNutritionNumber(raw.grasas),
    calorias: toSafeNutritionNumber(raw.calorias),
  };
}

function normalizeTextMealEstimate(value: unknown): TextMealEstimate | null {
  if (!value || typeof value !== 'object') {
    return null;
  }
  const raw = value as Record<string, unknown>;
  const comida =
    typeof raw.comida === 'string' && raw.comida.trim().length > 0
      ? raw.comida.trim()
      : 'Comida estimada';

  const caloriasMin = toSafeNutritionNumber(raw.caloriasMin);
  const caloriasMax = toSafeNutritionNumber(raw.caloriasMax);
  const min = Math.min(caloriasMin, caloriasMax);
  const max = Math.max(caloriasMin, caloriasMax);

  const desgloseRaw = Array.isArray(raw.desglose) ? raw.desglose : [];
  const desglose = desgloseRaw
    .map((d) => {
      if (!d || typeof d !== 'object') return null;
      const item = String((d as any).item ?? '').trim();
      const calorias = toSafeNutritionNumber((d as any).calorias);
      if (!item) return null;
      return { item, calorias };
    })
    .filter((x): x is { item: string; calorias: number } => !!x)
    .slice(0, 10);

  const confianzaRaw = String(raw.confianza ?? '').trim().toLowerCase();
  const confianza =
    confianzaRaw === 'alta' ? 'alta' : confianzaRaw === 'baja' ? 'baja' : 'media';

  const faltariaRaw = Array.isArray(raw.faltariaParaMejorar)
    ? raw.faltariaParaMejorar
    : [];
  const faltariaParaMejorar = faltariaRaw
    .map((x) => String(x ?? '').trim())
    .filter((x) => x.length > 0)
    .slice(0, 5);

  return {
    comida,
    caloriasMin: min,
    caloriasMax: max,
    proteinas: toSafeNutritionNumber(raw.proteinas),
    carbohidratos: toSafeNutritionNumber(raw.carbohidratos),
    grasas: toSafeNutritionNumber(raw.grasas),
    desglose,
    confianza,
    faltariaParaMejorar,
  };
}

function todayKey(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function normalizeNutritionChatReply(rawReply: unknown): string | null {
  if (typeof rawReply !== 'string') {
    return null;
  }

  const reply = rawReply.replace(/\s+/g, ' ').trim();
  if (reply.length === 0) {
    return null;
  }

  if (!/[.!?]$/.test(reply)) {
    return `${reply}.`;
  }

  return reply;
}

type NutritionChatMessage = { role: 'user' | 'assistant'; content: string };

function normalizeNutritionChatMessages(rawMessages: unknown): NutritionChatMessage[] {
  if (!Array.isArray(rawMessages)) {
    return [];
  }

  return rawMessages
    .map((m) => {
      if (!m || typeof m !== 'object') return null;
      const role = (m as any).role;
      const content = String((m as any).content ?? '').trim();
      if (role !== 'user' && role !== 'assistant') return null;
      if (!content) return null;
      return { role, content } as NutritionChatMessage;
    })
    .filter((m): m is NutritionChatMessage => !!m);
}

// Obtener lista de alimentos base
router.get('/foods', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const query = 'SELECT * FROM "Food" ORDER BY name ASC';
        const result = await pool.query(query);
        res.json(result.rows);
    } catch (error) {
        console.error('Error fetching foods:', error);
        res.status(500).json({ error: 'Error del servidor al obtener alimentos' });
    }
});

// Guardar una nueva comida registrada por el usuario
router.post('/meals', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const { type, items } = req.body; // type: "Breakfast", "Lunch", etc.

        if (!type || !items || !Array.isArray(items) || items.length === 0) {
             return res.status(400).json({ error: 'Tipo de comida y alimentos son obligatorios' });
        }

        await pool.query('BEGIN');

        // 1. Crear Meal (La comida del día)
        const mealQuery = `
            INSERT INTO "Meal" ("userId", type, date)
            VALUES ($1, $2, NOW())
            RETURNING *
        `;
        const mealResult = await pool.query(mealQuery, [userId, type]);
        const meal = mealResult.rows[0];

        // 2. Insertar los alimentos de esa comida
        for (const item of items) {
             const itemQuery = `
                 INSERT INTO "MealItem" ("mealId", "foodId", quantity)
                 VALUES ($1, $2, $3)
             `;
             await pool.query(itemQuery, [meal.id, item.foodId, item.quantity]);
        }

        await pool.query('COMMIT');

        res.status(201).json({
             message: 'Comida registrada con éxito',
             meal
        });

    } catch (error) {
        await pool.query('ROLLBACK');
        console.error('Error creating meal:', error);
        res.status(500).json({ error: 'Error del servidor al registrar comida' });
    }
});

// Obtener historial de comidas del usuario
router.get('/meals', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const query = 'SELECT * FROM "Meal" WHERE "userId" = $1 ORDER BY date DESC';
        const result = await pool.query(query, [userId]);
        res.json(result.rows);
    } catch (error) {
        console.error('Error fetching user meals:', error);
        res.status(500).json({ error: 'Error del servidor' });
    }
});

// Obtener métricas y plan del usuario
router.get('/metrics', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const result = await pool.query('SELECT * FROM "user_profiles_metrics" WHERE "userId" = $1', [userId]);

        if (result.rows.length === 0) {
            return res.json({ hasMetrics: false });
        }

        return res.json({ hasMetrics: true, metrics: result.rows[0] });
    } catch (error) {
        console.error('Error fetching metrics:', error);
        res.status(500).json({ error: 'Error del servidor' });
    }
});

// Nutrition chat (diet/calories guidance). Constrained to nutrition topics only.
router.post('/chat', authenticateToken, aiChatRateLimit, async (req: AuthRequest, res) => {
  try {
    const provider = (process.env.AI_PROVIDER || '').toLowerCase().trim();
    const geminiKey = process.env.GEMINI_API_KEY || '';
    const openaiKey = process.env.OPENAI_API_KEY || '';
    const openrouterKey = process.env.OPENROUTER_API_KEY || '';
    const groqKey = process.env.GROQ_API_KEY || '';

    const message = String(req.body?.message ?? '').trim();
    const normalizedMessages = normalizeNutritionChatMessages(req.body?.messages);
    const effectiveMessages =
      normalizedMessages.length > 0
        ? normalizedMessages
        : message.length > 0
          ? [{ role: 'user', content: message } as NutritionChatMessage]
          : [];
    if (effectiveMessages.length === 0) {
      return res.status(400).json({ error: 'message o messages es obligatorio' });
    }

    let system = FITCONNECTION_NUTRITION_ONLY_CHAT_PROMPT;
    try {
      const userId = req.user!.userId;
      const metrics = await pool.query(
        'SELECT goal, calories, protein, carbs, fat FROM "user_profiles_metrics" WHERE "userId" = $1 LIMIT 1',
        [userId],
      );
      if (metrics.rows.length > 0) {
        const row = metrics.rows[0] as any;
        system +=
          '\n\nCONTEXTO DEL USUARIO (objetivo diario):' +
          `\n- Objetivo: ${String(row.goal ?? '')}` +
          `\n- Calorias objetivo: ${Number(row.calories ?? 0)}` +
          `\n- Proteina objetivo (g): ${Number(row.protein ?? 0)}` +
          `\n- Carbos objetivo (g): ${Number(row.carbs ?? 0)}` +
          `\n- Grasas objetivo (g): ${Number(row.fat ?? 0)}` +
          '\nAlinea tus recomendaciones con estos objetivos cuando sea posible.';
      }
    } catch (e) {
      console.warn('Could not load nutrition metrics for chat:', e);
    }

    const selectedProvider =
      provider ||
      (openrouterKey ? 'openrouter' : '') ||
      (geminiKey ? 'gemini' : '') ||
      (openaiKey ? 'openai' : '') ||
      (groqKey ? 'groq' : '');

    if (selectedProvider === 'openrouter') {
      if (!openrouterKey) {
        return res.status(503).json({
          error: 'IA no configurada en el servidor. Configura OPENROUTER_API_KEY en el backend.',
        });
      }

      const model = process.env.OPENROUTER_CHAT_MODEL || 'openai/gpt-4o-mini';
      const referer = process.env.OPENROUTER_SITE_URL || '';
      const title = process.env.OPENROUTER_APP_NAME || 'FitConnect';

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${openrouterKey}`,
      };
      if (referer) headers['HTTP-Referer'] = referer;
      if (title) headers['X-Title'] = title;

      const r = await fetchWithRetry(
        'https://openrouter.ai/api/v1/chat/completions',
        {
        method: 'POST',
        headers,
        body: JSON.stringify({
          model,
          messages: [
            { role: 'system', content: system },
              ...effectiveMessages,
          ],
          max_tokens: 260,
          temperature: 0.6,
        }),
        },
        {
          timeoutMs: Number(process.env.AI_FETCH_TIMEOUT_MS || 20_000),
          retries: Number(process.env.AI_FETCH_RETRIES || 2),
        },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('OpenRouter nutrition chat error:', r.status, bodyText);
        return res.status(502).json({
          error: buildProviderErrorMessage('OpenRouter', bodyText),
        });
      }

      const data = JSON.parse(bodyText) as any;
      const reply = normalizeNutritionChatReply(data?.choices?.[0]?.message?.content ?? null);
      if (!reply) {
        return res.status(502).json({ error: 'Respuesta IA invalida' });
      }

      return res.json({ reply });
    }

    if (selectedProvider === 'gemini') {
      if (!geminiKey) {
        return res.status(503).json({
          error:
            'IA no configurada en el servidor. Configura GEMINI_API_KEY (o usa OpenRouter/OpenAI/Groq) en el backend.',
        });
      }

      const model = process.env.GEMINI_CHAT_MODEL || 'gemini-2.5-flash';
      const url =
        `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent` +
        `?key=${encodeURIComponent(geminiKey)}`;

      const r = await fetchWithRetry(
        url,
        {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          system_instruction: {
            parts: [{ text: system }],
          },
            contents: effectiveMessages.map((msg) => ({
              role: msg.role === 'assistant' ? 'model' : 'user',
              parts: [{ text: msg.content }],
            })),
          generationConfig: {
            responseMimeType: 'application/json',
            responseSchema: {
              type: 'object',
              properties: {
                reply: { type: 'string' },
              },
              required: ['reply'],
            },
            temperature: 0.6,
            maxOutputTokens: 260,
          },
        }),
        },
        {
          timeoutMs: Number(process.env.AI_FETCH_TIMEOUT_MS || 20_000),
          retries: Number(process.env.AI_FETCH_RETRIES || 2),
        },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('Gemini nutrition chat error:', r.status, bodyText);
        return res.status(502).json({
          error: buildProviderErrorMessage('Gemini', bodyText),
        });
      }

      const data = JSON.parse(bodyText) as any;
      const rawText =
        data?.candidates?.[0]?.content?.parts?.find((part: any) => typeof part?.text === 'string')?.text ?? null;
      if (typeof rawText !== 'string') {
        return res.status(502).json({ error: 'Respuesta IA invalida' });
      }

      let reply: string | null = null;
      try {
        const parsed = JSON.parse(rawText) as { reply?: unknown };
        reply = normalizeNutritionChatReply(parsed?.reply);
      } catch {
        const extracted = extractFirstJsonObject(rawText);
        reply = normalizeNutritionChatReply((extracted as any)?.reply ?? rawText);
      }

      if (!reply) {
        return res.status(502).json({ error: 'Respuesta IA invalida' });
      }

      return res.json({ reply });
    }

    if (selectedProvider === 'groq') {
      if (!groqKey) {
        return res.status(503).json({
          error: 'IA no configurada en el servidor. Configura GROQ_API_KEY en el backend.',
        });
      }

      const model = process.env.GROQ_CHAT_MODEL || 'llama-3.1-8b-instant';
      const r = await fetchWithRetry(
        'https://api.groq.com/openai/v1/chat/completions',
        {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${groqKey}`,
        },
        body: JSON.stringify({
          model,
          messages: [
            { role: 'system', content: system },
              ...effectiveMessages,
          ],
          max_tokens: 260,
          temperature: 0.6,
        }),
        },
        {
          timeoutMs: Number(process.env.AI_FETCH_TIMEOUT_MS || 20_000),
          retries: Number(process.env.AI_FETCH_RETRIES || 2),
        },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('Groq nutrition chat error:', r.status, bodyText);
        return res.status(502).json({
          error: buildProviderErrorMessage('Groq', bodyText),
        });
      }

      const data = JSON.parse(bodyText) as any;
      const reply = normalizeNutritionChatReply(data?.choices?.[0]?.message?.content ?? null);
      if (!reply) {
        return res.status(502).json({ error: 'Respuesta IA invalida' });
      }

      return res.json({ reply });
    }

    if (!openaiKey) {
      return res.status(503).json({
        error:
          'IA no configurada en el servidor. Configura OPENROUTER_API_KEY o GEMINI_API_KEY o OPENAI_API_KEY o GROQ_API_KEY, o define AI_PROVIDER.',
      });
    }

    const model = process.env.OPENAI_CHAT_MODEL || 'gpt-4o-mini';
    const r = await fetchWithRetry(
      'https://api.openai.com/v1/chat/completions',
      {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${openaiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: system },
            ...effectiveMessages,
        ],
        max_tokens: 260,
        temperature: 0.6,
      }),
      },
      {
        timeoutMs: Number(process.env.AI_FETCH_TIMEOUT_MS || 20_000),
        retries: Number(process.env.AI_FETCH_RETRIES || 2),
      },
    );

    const bodyText = await r.text();
    if (!r.ok) {
      console.error('OpenAI nutrition chat error:', r.status, bodyText);
      return res.status(502).json({
        error: buildProviderErrorMessage('OpenAI', bodyText),
      });
    }

    const data = JSON.parse(bodyText) as any;
    const reply = normalizeNutritionChatReply(data?.choices?.[0]?.message?.content ?? null);
    if (!reply) {
      return res.status(502).json({ error: 'Respuesta IA invalida' });
    }

    return res.json({ reply });
  } catch (error) {
    console.error('Error in nutrition chat:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

// Guardar/Actualizar métricas y calcular plan
router.post('/metrics', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const { weight, height, age, sex, activityLevel, goal } = req.body;

        // 1. Calcular TMB (Mifflin-St Jeor)
        let tmb = (10 * weight) + (6.25 * height) - (5 * age);
        tmb = (sex === 'masculino') ? tmb + 5 : tmb - 161;

        // 2. Factor de actividad
        const activityFactors: { [key: string]: number } = {
            'sedentario': 1.2,
            'ligero': 1.375,
            'moderado': 1.55,
            'activo': 1.725,
            'muy_activo': 1.9
        };
        let calories = tmb * (activityFactors[activityLevel] || 1.2);

        // 3. Ajuste por objetivo
        if (goal === 'Definición') calories -= 500;
        if (goal === 'Volumen') calories += 500;

        // 4. Macros (Aprox: 30% Prot, 40% Carb, 30% Grasa)
        const protein = (calories * 0.30) / 4;
        const carbs = (calories * 0.40) / 4;
        const fat = (calories * 0.30) / 9;

        const query = `
            INSERT INTO "user_profiles_metrics" 
            ("userId", weight, height, age, sex, "activityLevel", goal, calories, protein, carbs, fat, "updatedAt")
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW())
            ON CONFLICT ("userId") DO UPDATE SET
            weight = EXCLUDED.weight, height = EXCLUDED.height, age = EXCLUDED.age,
            sex = EXCLUDED.sex, "activityLevel" = EXCLUDED."activityLevel", goal = EXCLUDED.goal,
            calories = EXCLUDED.calories, protein = EXCLUDED.protein, carbs = EXCLUDED.carbs,
            fat = EXCLUDED.fat, "updatedAt" = NOW()
            RETURNING *
        `;

        const result = await pool.query(query, [
            userId, weight, height, age, sex, activityLevel, goal,
            Math.round(calories), Math.round(protein), Math.round(carbs), Math.round(fat)
        ]);

        res.json(result.rows[0]);
    } catch (error) {
        console.error('Error saving metrics:', error);
        res.status(500).json({ error: 'Error del servidor al guardar métricas' });
    }
});

// Escaner de comida por texto (devuelve estimacion estructurada y lista para guardar).
router.post('/estimate-text', authenticateToken, aiChatRateLimit, async (req: AuthRequest, res) => {
  try {
    const provider = (process.env.AI_PROVIDER || '').toLowerCase().trim();
    const geminiKey = process.env.GEMINI_API_KEY || '';
    const openaiKey = process.env.OPENAI_API_KEY || '';
    const openrouterKey = process.env.OPENROUTER_API_KEY || '';
    const groqKey = process.env.GROQ_API_KEY || '';

    const text = String(req.body?.text ?? '').trim();
    if (!text) {
      return res.status(400).json({ error: 'text es obligatorio' });
    }

    let system = FITCONNECTION_TEXT_MEAL_ESTIMATE_JSON_PROMPT;
    try {
      const userId = req.user!.userId;
      const metrics = await pool.query(
        'SELECT goal, calories, protein, carbs, fat FROM "user_profiles_metrics" WHERE "userId" = $1 LIMIT 1',
        [userId],
      );
      if (metrics.rows.length > 0) {
        const row = metrics.rows[0] as any;
        system +=
          '\n\nCONTEXTO DEL USUARIO (objetivo diario):' +
          `\n- Objetivo: ${String(row.goal ?? '')}` +
          `\n- Calorias objetivo: ${Number(row.calories ?? 0)}` +
          `\n- Proteina objetivo (g): ${Number(row.protein ?? 0)}` +
          `\n- Carbos objetivo (g): ${Number(row.carbs ?? 0)}` +
          `\n- Grasas objetivo (g): ${Number(row.fat ?? 0)}`;
      }
    } catch (e) {
      console.warn('Could not load nutrition metrics for estimate-text:', e);
    }

    const selectedProvider =
      provider ||
      (openrouterKey ? 'openrouter' : '') ||
      (geminiKey ? 'gemini' : '') ||
      (openaiKey ? 'openai' : '') ||
      (groqKey ? 'groq' : '');

    if (selectedProvider === 'openrouter') {
      if (!openrouterKey) {
        return res.status(503).json({ error: 'IA no configurada. Falta OPENROUTER_API_KEY.' });
      }
      const model = process.env.OPENROUTER_CHAT_MODEL || 'openai/gpt-4o-mini';
      const referer = process.env.OPENROUTER_SITE_URL || '';
      const title = process.env.OPENROUTER_APP_NAME || 'FitConnect';

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${openrouterKey}`,
      };
      if (referer) headers['HTTP-Referer'] = referer;
      if (title) headers['X-Title'] = title;

      const r = await fetchWithRetry(
        'https://openrouter.ai/api/v1/chat/completions',
        {
          method: 'POST',
          headers,
          body: JSON.stringify({
            model,
            messages: [
              { role: 'system', content: system },
              { role: 'user', content: `Comida (texto): ${text}` },
            ],
            max_tokens: 500,
            temperature: 0.2,
          }),
        },
        {
          timeoutMs: Number(process.env.AI_FETCH_TIMEOUT_MS || 20_000),
          retries: Number(process.env.AI_FETCH_RETRIES || 2),
        },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('OpenRouter estimate-text error:', r.status, bodyText);
        return res.status(502).json({ error: buildProviderErrorMessage('OpenRouter', bodyText) });
      }

      const data = JSON.parse(bodyText) as any;
      const content = data?.choices?.[0]?.message?.content ?? null;
      if (typeof content !== 'string') {
        return res.status(502).json({ error: 'Respuesta IA invalida' });
      }
      const extracted = extractFirstJsonObject(content);
      const normalized = normalizeTextMealEstimate(extracted);
      if (!normalized) {
        return res.status(502).json({ error: 'No se pudo parsear JSON de IA' });
      }
      return res.json(normalized);
    }

    if (selectedProvider === 'gemini') {
      if (!geminiKey) {
        return res.status(503).json({ error: 'IA no configurada. Falta GEMINI_API_KEY.' });
      }

      const model = process.env.GEMINI_CHAT_MODEL || 'gemini-2.5-flash';
      const url =
        `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent` +
        `?key=${encodeURIComponent(geminiKey)}`;

      const r = await fetchWithRetry(
        url,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            system_instruction: { parts: [{ text: system }] },
            contents: [{ role: 'user', parts: [{ text: `Comida (texto): ${text}` }] }],
            generationConfig: {
              responseMimeType: 'application/json',
              responseSchema: {
                type: 'object',
                properties: {
                  comida: { type: 'string' },
                  caloriasMin: { type: 'number' },
                  caloriasMax: { type: 'number' },
                  proteinas: { type: 'number' },
                  carbohidratos: { type: 'number' },
                  grasas: { type: 'number' },
                  desglose: {
                    type: 'array',
                    items: {
                      type: 'object',
                      properties: { item: { type: 'string' }, calorias: { type: 'number' } },
                      required: ['item', 'calorias'],
                    },
                  },
                  confianza: { type: 'string' },
                  faltariaParaMejorar: { type: 'array', items: { type: 'string' } },
                },
                required: [
                  'comida',
                  'caloriasMin',
                  'caloriasMax',
                  'proteinas',
                  'carbohidratos',
                  'grasas',
                  'desglose',
                  'confianza',
                  'faltariaParaMejorar',
                ],
              },
              temperature: 0.2,
              maxOutputTokens: 500,
            },
          }),
        },
        {
          timeoutMs: Number(process.env.AI_FETCH_TIMEOUT_MS || 20_000),
          retries: Number(process.env.AI_FETCH_RETRIES || 2),
        },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('Gemini estimate-text error:', r.status, bodyText);
        return res.status(502).json({ error: buildProviderErrorMessage('Gemini', bodyText) });
      }

      const data = JSON.parse(bodyText) as any;
      const rawText =
        data?.candidates?.[0]?.content?.parts?.find((part: any) => typeof part?.text === 'string')?.text ?? null;
      if (typeof rawText !== 'string') {
        return res.status(502).json({ error: 'Respuesta IA invalida' });
      }

      let parsed: unknown = null;
      try {
        parsed = JSON.parse(rawText);
      } catch {
        parsed = extractFirstJsonObject(rawText);
      }
      const normalized = normalizeTextMealEstimate(parsed);
      if (!normalized) {
        return res.status(502).json({ error: 'No se pudo parsear JSON de IA' });
      }
      return res.json(normalized);
    }

    if (selectedProvider === 'groq') {
      if (!groqKey) {
        return res.status(503).json({ error: 'IA no configurada. Falta GROQ_API_KEY.' });
      }
      const model = process.env.GROQ_CHAT_MODEL || 'llama-3.1-8b-instant';
      const r = await fetchWithRetry(
        'https://api.groq.com/openai/v1/chat/completions',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${groqKey}` },
          body: JSON.stringify({
            model,
            messages: [
              { role: 'system', content: system },
              { role: 'user', content: `Comida (texto): ${text}` },
            ],
            max_tokens: 500,
            temperature: 0.2,
          }),
        },
        {
          timeoutMs: Number(process.env.AI_FETCH_TIMEOUT_MS || 20_000),
          retries: Number(process.env.AI_FETCH_RETRIES || 2),
        },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('Groq estimate-text error:', r.status, bodyText);
        return res.status(502).json({ error: buildProviderErrorMessage('Groq', bodyText) });
      }
      const data = JSON.parse(bodyText) as any;
      const content = data?.choices?.[0]?.message?.content ?? null;
      if (typeof content !== 'string') {
        return res.status(502).json({ error: 'Respuesta IA invalida' });
      }
      const extracted = extractFirstJsonObject(content);
      const normalized = normalizeTextMealEstimate(extracted);
      if (!normalized) {
        return res.status(502).json({ error: 'No se pudo parsear JSON de IA' });
      }
      return res.json(normalized);
    }

    if (!openaiKey) {
      return res.status(503).json({
        error: 'IA no configurada. Configura OPENROUTER_API_KEY o GEMINI_API_KEY o OPENAI_API_KEY o GROQ_API_KEY.',
      });
    }

    const model = process.env.OPENAI_CHAT_MODEL || 'gpt-4o-mini';
    const r = await fetchWithRetry(
      'https://api.openai.com/v1/chat/completions',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${openaiKey}` },
        body: JSON.stringify({
          model,
          messages: [
            { role: 'system', content: system },
            { role: 'user', content: `Comida (texto): ${text}` },
          ],
          max_tokens: 500,
          temperature: 0.2,
        }),
      },
      {
        timeoutMs: Number(process.env.AI_FETCH_TIMEOUT_MS || 20_000),
        retries: Number(process.env.AI_FETCH_RETRIES || 2),
      },
    );

    const bodyText = await r.text();
    if (!r.ok) {
      console.error('OpenAI estimate-text error:', r.status, bodyText);
      return res.status(502).json({ error: buildProviderErrorMessage('OpenAI', bodyText) });
    }
    const data = JSON.parse(bodyText) as any;
    const content = data?.choices?.[0]?.message?.content ?? null;
    if (typeof content !== 'string') {
      return res.status(502).json({ error: 'Respuesta IA invalida' });
    }
    const extracted = extractFirstJsonObject(content);
    const normalized = normalizeTextMealEstimate(extracted);
    if (!normalized) {
      return res.status(502).json({ error: 'No se pudo parsear JSON de IA' });
    }
    return res.json(normalized);
  } catch (error) {
    console.error('Error in estimate-text:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

// Recomendaciones por contexto ("que me falta hoy") en base a lo registrado con IA + objetivo.
router.get('/suggest-today', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const metrics = await pool.query(
      'SELECT calories, protein, carbs, fat, goal FROM "user_profiles_metrics" WHERE "userId" = $1 LIMIT 1',
      [userId],
    );
    if (metrics.rows.length === 0) {
      return res.status(404).json({ error: 'No hay métricas del usuario' });
    }

    const m = metrics.rows[0] as any;
    const goalCalories = Number(m.calories ?? 0);
    const goalProtein = Number(m.protein ?? 0);
    const goalCarbs = Number(m.carbs ?? 0);
    const goalFat = Number(m.fat ?? 0);

    const todayMeals = await pool.query(
      `
        SELECT
          COALESCE(SUM(calorias),0) AS kcal,
          COALESCE(SUM(proteinas),0) AS p,
          COALESCE(SUM(carbohidratos),0) AS c,
          COALESCE(SUM(grasas),0) AS g
        FROM "MealAiEntry"
        WHERE "userId" = $1 AND date = CURRENT_DATE
      `,
      [userId],
    );

    const totals = todayMeals.rows[0] as any;
    const eaten = {
      calorias: Number(totals.kcal ?? 0),
      proteinas: Number(totals.p ?? 0),
      carbohidratos: Number(totals.c ?? 0),
      grasas: Number(totals.g ?? 0),
    };

    const remaining = {
      calorias: Math.max(0, Math.round(goalCalories - eaten.calorias)),
      proteinas: Math.max(0, Math.round(goalProtein - eaten.proteinas)),
      carbohidratos: Math.max(0, Math.round(goalCarbs - eaten.carbohidratos)),
      grasas: Math.max(0, Math.round(goalFat - eaten.grasas)),
    };

    const suggestions: Array<{ title: string; items: string[]; approx: string }> = [];
    if (remaining.proteinas >= 25) {
      suggestions.push({
        title: 'Sube proteina facil',
        items: ['Yogur griego + 1 fruta', 'Atun + pan', 'Pechuga de pollo + ensalada'],
        approx: '20-45g proteina',
      });
    }
    if (remaining.carbohidratos >= 40 && remaining.calorias >= 250) {
      suggestions.push({
        title: 'Te faltan carbs/energia',
        items: ['Arroz/pasta + algo de proteina', 'Avena con leche', 'Patata cocida + huevos'],
        approx: '40-80g carbs',
      });
    }
    if (remaining.grasas >= 15 && remaining.calorias >= 200) {
      suggestions.push({
        title: 'Te faltan grasas',
        items: ['Aguacate', 'Frutos secos (30g)', 'Aceite de oliva en ensalada'],
        approx: '10-25g grasas',
      });
    }
    if (suggestions.length === 0) {
      suggestions.push({
        title: 'Vas bastante bien',
        items: ['Si tienes hambre: fruta + yogur', 'Si no: mantente y bebe agua'],
        approx: 'snack ligero',
      });
    }

    return res.json({
      objetivo: { calorias: goalCalories, proteinas: goalProtein, carbohidratos: goalCarbs, grasas: goalFat },
      consumido: eaten,
      restante: remaining,
      suggestions,
    });
  } catch (error) {
    console.error('Error in suggest-today:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

// Lista compra + meal-prep (y plan semanal de comidas) generado por IA.
router.post('/weekly-diet', authenticateToken, aiChatRateLimit, async (req: AuthRequest, res) => {
  try {
    const provider = (process.env.AI_PROVIDER || '').toLowerCase().trim();
    const geminiKey = process.env.GEMINI_API_KEY || '';
    const openaiKey = process.env.OPENAI_API_KEY || '';
    const openrouterKey = process.env.OPENROUTER_API_KEY || '';
    const groqKey = process.env.GROQ_API_KEY || '';

    const userId = req.user!.userId;
    const metrics = await pool.query(
      'SELECT goal, calories, protein, carbs, fat FROM "user_profiles_metrics" WHERE "userId" = $1 LIMIT 1',
      [userId],
    );
    if (metrics.rows.length === 0) {
      return res.status(404).json({ error: 'No hay métricas del usuario' });
    }

    const row = metrics.rows[0] as any;
    const system =
      FITCONNECTION_WEEKLY_DIET_SHOPPING_JSON_PROMPT +
      '\n\nCONTEXTO DEL USUARIO (objetivo diario):' +
      `\n- Objetivo: ${String(row.goal ?? '')}` +
      `\n- Calorias objetivo: ${Number(row.calories ?? 0)}` +
      `\n- Proteina objetivo (g): ${Number(row.protein ?? 0)}` +
      `\n- Carbos objetivo (g): ${Number(row.carbs ?? 0)}` +
      `\n- Grasas objetivo (g): ${Number(row.fat ?? 0)}`;

    const selectedProvider =
      provider ||
      (openrouterKey ? 'openrouter' : '') ||
      (geminiKey ? 'gemini' : '') ||
      (openaiKey ? 'openai' : '') ||
      (groqKey ? 'groq' : '');

    const userMsg = 'Genera el plan semanal y la lista de compra.';

    const timeoutMs = Number(process.env.AI_FETCH_TIMEOUT_MS || 25_000);
    const retries = Number(process.env.AI_FETCH_RETRIES || 2);

    if (selectedProvider === 'openrouter') {
      if (!openrouterKey) {
        return res.status(503).json({ error: 'IA no configurada. Falta OPENROUTER_API_KEY.' });
      }
      const model = process.env.OPENROUTER_CHAT_MODEL || 'openai/gpt-4o-mini';
      const referer = process.env.OPENROUTER_SITE_URL || '';
      const title = process.env.OPENROUTER_APP_NAME || 'FitConnect';

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${openrouterKey}`,
      };
      if (referer) headers['HTTP-Referer'] = referer;
      if (title) headers['X-Title'] = title;

      const r = await fetchWithRetry(
        'https://openrouter.ai/api/v1/chat/completions',
        {
          method: 'POST',
          headers,
          body: JSON.stringify({
            model,
            messages: [
              { role: 'system', content: system },
              { role: 'user', content: userMsg },
            ],
            max_tokens: 1400,
            temperature: 0.5,
          }),
        },
        { timeoutMs, retries },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('OpenRouter weekly-diet error:', r.status, bodyText);
        return res.status(502).json({ error: buildProviderErrorMessage('OpenRouter', bodyText) });
      }

      const data = JSON.parse(bodyText) as any;
      const content = data?.choices?.[0]?.message?.content ?? null;
      if (typeof content !== 'string') {
        return res.status(502).json({ error: 'Respuesta IA invalida' });
      }
      const extracted = extractFirstJsonObject(content);
      if (!extracted) {
        return res.status(502).json({ error: 'No se pudo parsear JSON de IA' });
      }
      // Persist plan for this week (nutrition).
      try {
        const now = new Date();
        const monday = new Date(now);
        const day = monday.getDay(); // 0 Sun..6 Sat
        const diffToMonday = day === 0 ? -6 : 1 - day;
        monday.setDate(monday.getDate() + diffToMonday);
        const weekStart = todayKey(monday);

        await pool.query(
          `
            INSERT INTO "UserWeeklyCoachPlan" ("userId","weekStart","planType","planJson","createdAt","updatedAt")
            VALUES ($1,$2,'nutrition',$3::jsonb,NOW(),NOW())
            ON CONFLICT ("userId","weekStart","planType")
            DO UPDATE SET "planJson" = EXCLUDED."planJson", "updatedAt" = NOW()
          `,
          [userId, weekStart, JSON.stringify(extracted)],
        );
      } catch (e) {
        console.warn('Could not persist weekly nutrition plan:', e);
      }

      return res.json(extracted);
    }

    if (selectedProvider === 'gemini') {
      if (!geminiKey) {
        return res.status(503).json({ error: 'IA no configurada. Falta GEMINI_API_KEY.' });
      }
      const model = process.env.GEMINI_CHAT_MODEL || 'gemini-2.5-flash';
      const url =
        `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent` +
        `?key=${encodeURIComponent(geminiKey)}`;

      const r = await fetchWithRetry(
        url,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            system_instruction: { parts: [{ text: system }] },
            contents: [{ role: 'user', parts: [{ text: userMsg }] }],
            generationConfig: {
              responseMimeType: 'application/json',
              temperature: 0.5,
              maxOutputTokens: 1400,
            },
          }),
        },
        { timeoutMs, retries },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('Gemini weekly-diet error:', r.status, bodyText);
        return res.status(502).json({ error: buildProviderErrorMessage('Gemini', bodyText) });
      }

      const data = JSON.parse(bodyText) as any;
      const rawText =
        data?.candidates?.[0]?.content?.parts?.find((part: any) => typeof part?.text === 'string')?.text ?? null;
      if (typeof rawText !== 'string') {
        return res.status(502).json({ error: 'Respuesta IA invalida' });
      }
      let parsed: unknown = null;
      try {
        parsed = JSON.parse(rawText);
      } catch {
        parsed = extractFirstJsonObject(rawText);
      }
      if (!parsed || typeof parsed !== 'object') {
        return res.status(502).json({ error: 'No se pudo parsear JSON de IA' });
      }
      // Persist plan for this week (nutrition).
      try {
        const now = new Date();
        const monday = new Date(now);
        const day = monday.getDay();
        const diffToMonday = day === 0 ? -6 : 1 - day;
        monday.setDate(monday.getDate() + diffToMonday);
        const weekStart = todayKey(monday);

        await pool.query(
          `
            INSERT INTO "UserWeeklyCoachPlan" ("userId","weekStart","planType","planJson","createdAt","updatedAt")
            VALUES ($1,$2,'nutrition',$3::jsonb,NOW(),NOW())
            ON CONFLICT ("userId","weekStart","planType")
            DO UPDATE SET "planJson" = EXCLUDED."planJson", "updatedAt" = NOW()
          `,
          [userId, weekStart, JSON.stringify(parsed)],
        );
      } catch (e) {
        console.warn('Could not persist weekly nutrition plan:', e);
      }

      return res.json(parsed);
    }

    if (selectedProvider === 'groq') {
      if (!groqKey) {
        return res.status(503).json({ error: 'IA no configurada. Falta GROQ_API_KEY.' });
      }
      const model = process.env.GROQ_CHAT_MODEL || 'llama-3.1-8b-instant';
      const r = await fetchWithRetry(
        'https://api.groq.com/openai/v1/chat/completions',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${groqKey}` },
          body: JSON.stringify({
            model,
            messages: [
              { role: 'system', content: system },
              { role: 'user', content: userMsg },
            ],
            max_tokens: 1400,
            temperature: 0.5,
          }),
        },
        { timeoutMs, retries },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('Groq weekly-diet error:', r.status, bodyText);
        return res.status(502).json({ error: buildProviderErrorMessage('Groq', bodyText) });
      }
      const data = JSON.parse(bodyText) as any;
      const content = data?.choices?.[0]?.message?.content ?? null;
      if (typeof content !== 'string') {
        return res.status(502).json({ error: 'Respuesta IA invalida' });
      }
      const extracted = extractFirstJsonObject(content);
      if (!extracted) {
        return res.status(502).json({ error: 'No se pudo parsear JSON de IA' });
      }
      // Persist plan for this week (nutrition).
      try {
        const now = new Date();
        const monday = new Date(now);
        const day = monday.getDay();
        const diffToMonday = day === 0 ? -6 : 1 - day;
        monday.setDate(monday.getDate() + diffToMonday);
        const weekStart = todayKey(monday);

        await pool.query(
          `
            INSERT INTO "UserWeeklyCoachPlan" ("userId","weekStart","planType","planJson","createdAt","updatedAt")
            VALUES ($1,$2,'nutrition',$3::jsonb,NOW(),NOW())
            ON CONFLICT ("userId","weekStart","planType")
            DO UPDATE SET "planJson" = EXCLUDED."planJson", "updatedAt" = NOW()
          `,
          [userId, weekStart, JSON.stringify(extracted)],
        );
      } catch (e) {
        console.warn('Could not persist weekly nutrition plan:', e);
      }

      return res.json(extracted);
    }

    if (!openaiKey) {
      return res.status(503).json({
        error: 'IA no configurada. Configura OPENROUTER_API_KEY o GEMINI_API_KEY o OPENAI_API_KEY o GROQ_API_KEY.',
      });
    }

    const model = process.env.OPENAI_CHAT_MODEL || 'gpt-4o-mini';
    const r = await fetchWithRetry(
      'https://api.openai.com/v1/chat/completions',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${openaiKey}` },
        body: JSON.stringify({
          model,
          messages: [
            { role: 'system', content: system },
            { role: 'user', content: userMsg },
          ],
          max_tokens: 1400,
          temperature: 0.5,
        }),
      },
      { timeoutMs, retries },
    );

    const bodyText = await r.text();
    if (!r.ok) {
      console.error('OpenAI weekly-diet error:', r.status, bodyText);
      return res.status(502).json({ error: buildProviderErrorMessage('OpenAI', bodyText) });
    }
    const data = JSON.parse(bodyText) as any;
    const content = data?.choices?.[0]?.message?.content ?? null;
    if (typeof content !== 'string') {
      return res.status(502).json({ error: 'Respuesta IA invalida' });
    }
    const extracted = extractFirstJsonObject(content);
    if (!extracted) {
      return res.status(502).json({ error: 'No se pudo parsear JSON de IA' });
    }
    // Persist plan for this week (nutrition).
    try {
      const now = new Date();
      const monday = new Date(now);
      const day = monday.getDay();
      const diffToMonday = day === 0 ? -6 : 1 - day;
      monday.setDate(monday.getDate() + diffToMonday);
      const weekStart = todayKey(monday);

      await pool.query(
        `
          INSERT INTO "UserWeeklyCoachPlan" ("userId","weekStart","planType","planJson","createdAt","updatedAt")
          VALUES ($1,$2,'nutrition',$3::jsonb,NOW(),NOW())
          ON CONFLICT ("userId","weekStart","planType")
          DO UPDATE SET "planJson" = EXCLUDED."planJson", "updatedAt" = NOW()
        `,
        [userId, weekStart, JSON.stringify(extracted)],
      );
    } catch (e) {
      console.warn('Could not persist weekly nutrition plan:', e);
    }

    return res.json(extracted);
  } catch (error) {
    console.error('Error in weekly-diet:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

// Get the persisted weekly nutrition plan for current week (if any).
router.get('/weekly-diet', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const now = new Date();
    const monday = new Date(now);
    const day = monday.getDay();
    const diffToMonday = day === 0 ? -6 : 1 - day;
    monday.setDate(monday.getDate() + diffToMonday);
    const weekStart = todayKey(monday);

    const result = await pool.query(
      `
        SELECT "weekStart", "planJson", "updatedAt"
        FROM "UserWeeklyCoachPlan"
        WHERE "userId" = $1 AND "weekStart" = $2 AND "planType" = 'nutrition'
        LIMIT 1
      `,
      [userId, weekStart],
    );

    if (result.rows.length === 0) {
      return res.json({ weekStart, plan: null });
    }

    return res.json({ weekStart, plan: result.rows[0].planJson, updatedAt: result.rows[0].updatedAt });
  } catch (error) {
    console.error('Error fetching weekly nutrition plan:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

// Mini dashboard: resumen semanal (calorias/prote por dia) + entrenos completados + racha.
router.get('/weekly-summary', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const now = new Date();
    const end = todayKey(now);
    const startDate = new Date(now);
    startDate.setDate(startDate.getDate() - 6);
    const start = todayKey(startDate);

    const meals = await pool.query(
      `
        SELECT
          date,
          COALESCE(SUM(calorias),0) AS kcal,
          COALESCE(SUM(proteinas),0) AS p
        FROM "MealAiEntry"
        WHERE "userId" = $1 AND date BETWEEN $2 AND $3
        GROUP BY date
        ORDER BY date ASC
      `,
      [userId, start, end],
    );

    const training = await pool.query(
      `
        SELECT date, "isCompleted"
        FROM "user_training_history"
        WHERE "userId" = $1 AND date BETWEEN $2 AND $3 AND "isCompleted" = true
        ORDER BY date ASC
      `,
      [userId, start, end],
    );

    const trainingDates = new Set(training.rows.map((r) => String(r.date)));

    // streak simple: consecutive days with completed workout ending today (or yesterday if no today)
    const sorted = Array.from(trainingDates)
      .map((d) => new Date(d))
      .sort((a, b) => a.getTime() - b.getTime());
    let streak = 0;
    if (sorted.length > 0) {
      const hasToday = trainingDates.has(end);
      const base = new Date(hasToday ? end : todayKey(new Date(now.getTime() - 24 * 60 * 60 * 1000)));
      let cursor = base;
      while (trainingDates.has(todayKey(cursor))) {
        streak += 1;
        cursor = new Date(cursor);
        cursor.setDate(cursor.getDate() - 1);
      }
    }

    return res.json({
      range: { start, end },
      nutrition: meals.rows,
      trainingCompletedDays: Array.from(trainingDates),
      streak,
    });
  } catch (error) {
    console.error('Error in weekly-summary:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

// Get today's AI meals for the user (for "Hoy" totals / timeline persistence).
router.get('/today', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const date = await pool.query<{ today: string }>('SELECT CURRENT_DATE::text as today');
    const today = date.rows[0]?.today;

    const result = await pool.query(
      `
        SELECT
          id,
          date,
          "mealType",
          comida,
          image,
          proteinas,
          carbohidratos,
          grasas,
          calorias,
          "createdAt"
        FROM "MealAiEntry"
        WHERE "userId" = $1 AND date = CURRENT_DATE
        ORDER BY "createdAt" ASC
      `,
      [userId],
    );

    const totals = today ? await recomputeAndPersistDailyTotals(userId, today) : null;
    return res.json({ meals: result.rows, totals });
  } catch (error) {
    console.error('Error fetching today AI meals:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

// Get AI meals for a specific day (YYYY-MM-DD) + totals.
router.get('/day', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const date = req.query?.date;

    if (!isIsoDate(date)) {
      return res.status(400).json({ error: 'date es obligatorio (YYYY-MM-DD)' });
    }

    const meals = await pool.query(
      `
        SELECT
          id,
          date,
          "mealType",
          comida,
          image,
          proteinas,
          carbohidratos,
          grasas,
          calorias,
          "createdAt"
        FROM "MealAiEntry"
        WHERE "userId" = $1 AND date = $2
        ORDER BY "createdAt" ASC
      `,
      [userId, date],
    );

    const totals = await recomputeAndPersistDailyTotals(userId, date);
    return res.json({ date, meals: meals.rows, totals });
  } catch (error) {
    console.error('Error fetching day meals:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

// Monthly summary for calendar view: calories per day.
router.get('/monthly-summary', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const year = Number(req.query?.year);
    const month = Number(req.query?.month); // 1-12

    if (!Number.isFinite(year) || !Number.isFinite(month) || month < 1 || month > 12) {
      return res.status(400).json({ error: 'year y month son obligatorios' });
    }

    const start = `${year}-${pad2(month)}-01`;
    const nextMonth = month === 12 ? 1 : month + 1;
    const nextYear = month === 12 ? year + 1 : year;
    const end = `${nextYear}-${pad2(nextMonth)}-01`;

    const result = await pool.query(
      `
        SELECT date::text as date, calories
        FROM "UserDailyNutritionTotals"
        WHERE "userId" = $1 AND date >= $2 AND date < $3
        ORDER BY date ASC
      `,
      [userId, start, end],
    );

    return res.json({ month: `${year}-${pad2(month)}`, days: result.rows });
  } catch (error) {
    console.error('Error fetching monthly summary:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

// Save an AI meal analysis to the user's day plan.
router.post('/meal-from-ai', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const mealType = String(req.body?.mealType ?? '').trim();
    const comida = String(req.body?.comida ?? '').trim();
    const proteinas = toSafeNutritionNumber(req.body?.proteinas);
    const carbohidratos = toSafeNutritionNumber(req.body?.carbohidratos);
    const grasas = toSafeNutritionNumber(req.body?.grasas);
    const calorias = toSafeNutritionNumber(req.body?.calorias);
    const imageBase64 = req.body?.imageBase64;
    const mimeType = (req.body?.mimeType as string | undefined) || 'image/jpeg';

    if (!mealType) {
      return res.status(400).json({ error: 'mealType es obligatorio' });
    }
    if (!comida) {
      return res.status(400).json({ error: 'comida es obligatorio' });
    }

    const slotMealTypes = new Set(['Desayuno', 'Almuerzo', 'Comida', 'Merienda', 'Cena']);
    const isSlot = slotMealTypes.has(mealType);

    if (isSlot) {
      const exists = await pool.query(
        `
          SELECT id
          FROM "MealAiEntry"
          WHERE "userId" = $1 AND date = CURRENT_DATE AND "mealType" = $2
          LIMIT 1
        `,
        [userId, mealType],
      );

      if (exists.rowCount && exists.rowCount > 0) {
        return res.status(409).json({
          error: `Ya has registrado una comida en "${mealType}" hoy. Elige otro apartado.`,
        });
      }
    }

    let image: string | null = null;
    if (typeof imageBase64 === 'string' && imageBase64.trim().length > 0) {
      image = await saveNutritionImageBase64({
        imageBase64: imageBase64.trim(),
        mimeType,
      });
    }

    let inserted;
    try {
      inserted = await pool.query(
        `
          INSERT INTO "MealAiEntry" (
            "userId",
            date,
            "mealType",
            comida,
            image,
            proteinas,
            carbohidratos,
            grasas,
            calorias,
            "createdAt"
          )
          VALUES ($1, CURRENT_DATE, $2, $3, $4, $5, $6, $7, $8, NOW())
          RETURNING *
        `,
        [userId, mealType, comida, image, proteinas, carbohidratos, grasas, calorias],
      );
    } catch (e: any) {
      // Unique index for slot types only.
      if (e && (e.code === '23505' || e.constraint === 'MealAiEntry_user_date_slot_key')) {
        return res.status(409).json({
          error: `Ya has registrado una comida en "${mealType}" hoy. Elige otro apartado.`,
        });
      }
      throw e;
    }

    const date = await pool.query<{ today: string }>('SELECT CURRENT_DATE::text as today');
    const today = date.rows[0]?.today;
    const totals = today ? await recomputeAndPersistDailyTotals(userId, today) : null;

    return res.status(201).json({ meal: inserted.rows[0], totals });
  } catch (error) {
    console.error('Error saving AI meal:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

// Analyze a meal image with AI (server-side) to avoid exposing API keys in clients.
router.post('/analyze-image', authenticateToken, aiImageRateLimit, async (req: AuthRequest, res) => {
  try {
    const imageBase64 = req.body?.imageBase64;
    const mimeType = (req.body?.mimeType as string | undefined) || 'image/jpeg';

    if (typeof imageBase64 !== 'string' || imageBase64.trim().length < 20) {
      return res.status(400).json({ error: 'imageBase64 es obligatorio' });
    }

    const provider = (process.env.AI_PROVIDER || '').toLowerCase().trim();
    const geminiKey = process.env.GEMINI_API_KEY || '';
    const openaiKey = process.env.OPENAI_API_KEY || '';
    const openrouterKey = process.env.OPENROUTER_API_KEY || '';

    const prompt = FITCONNECTION_MEAL_IMAGE_JSON_PROMPT;

    const selectedProvider =
      provider ||
      (openrouterKey ? 'openrouter' : '') ||
      (geminiKey ? 'gemini' : '') ||
      (openaiKey ? 'openai' : '');

    if (selectedProvider === 'openrouter') {
      if (!openrouterKey) {
        return res.status(503).json({
          error: 'IA no configurada en el servidor. Configura OPENROUTER_API_KEY en el backend.',
        });
      }

      const model = process.env.OPENROUTER_VISION_MODEL || 'openai/gpt-4o-mini';
      const imageUrl = `data:${mimeType};base64,${imageBase64}`;
      const referer = process.env.OPENROUTER_SITE_URL || '';
      const title = process.env.OPENROUTER_APP_NAME || 'FitConnect';

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${openrouterKey}`,
      };
      if (referer) headers['HTTP-Referer'] = referer;
      if (title) headers['X-Title'] = title;

      const r = await fetchWithRetry(
        'https://openrouter.ai/api/v1/chat/completions',
        {
        method: 'POST',
        headers,
        body: JSON.stringify({
          model,
          messages: [
            { role: 'system', content: prompt },
            {
              role: 'user',
              content: [
                { type: 'text', text: 'Analiza la comida de esta imagen y devuelve solo el JSON solicitado.' },
                { type: 'image_url', image_url: { url: imageUrl } },
              ],
            },
          ],
          max_tokens: 500,
          temperature: 0.2,
        }),
        },
        {
          timeoutMs: Number(process.env.AI_FETCH_TIMEOUT_MS || 20_000),
          retries: Number(process.env.AI_FETCH_RETRIES || 2),
        },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('OpenRouter vision error:', r.status, bodyText);
        return res.status(502).json({
          error: buildProviderErrorMessage('OpenRouter', bodyText),
        });
      }

      const data = JSON.parse(bodyText) as any;
      const content = data?.choices?.[0]?.message?.content ?? null;
      if (typeof content !== 'string') {
        return res.status(502).json({ error: 'Respuesta IA invalida' });
      }

      const extracted = extractFirstJsonObject(content);
      const normalized = normalizeNutritionAnalysis(extracted);
      if (!normalized) {
        return res.status(502).json({ error: 'No se pudo parsear JSON de IA' });
      }

      return res.json(normalized);
    }

    if (selectedProvider === 'gemini') {
      if (!geminiKey) {
        return res.status(503).json({
          error:
            'IA no configurada en el servidor. Configura GEMINI_API_KEY (o usa OpenRouter/OpenAI) en el backend.',
        });
      }
      const model = process.env.GEMINI_VISION_MODEL || 'gemini-2.5-flash';
      const url =
        `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent` +
        `?key=${encodeURIComponent(geminiKey)}`;

      const r = await fetchWithRetry(
        url,
        {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          system_instruction: {
            parts: [{ text: prompt }],
          },
          contents: [
            {
              parts: [
                { text: 'Analiza la comida principal de esta imagen y devuelve solo el objeto JSON solicitado.' },
                { inline_data: { mime_type: mimeType, data: imageBase64 } },
              ],
            },
          ],
          generationConfig: {
            responseMimeType: 'application/json',
            responseSchema: {
              type: 'object',
              properties: {
                comida: {
                  type: 'string',
                  description: 'Nombre breve del plato o comida principal.',
                },
                proteinas: {
                  type: 'number',
                  description: 'Proteinas estimadas en gramos.',
                },
                carbohidratos: {
                  type: 'number',
                  description: 'Carbohidratos estimados en gramos.',
                },
                grasas: {
                  type: 'number',
                  description: 'Grasas estimadas en gramos.',
                },
                calorias: {
                  type: 'number',
                  description: 'Calorias estimadas del plato.',
                },
              },
              required: ['comida', 'proteinas', 'carbohidratos', 'grasas', 'calorias'],
            },
            temperature: 0.2,
            maxOutputTokens: 300,
          },
        }),
        },
        {
          timeoutMs: Number(process.env.AI_FETCH_TIMEOUT_MS || 20_000),
          retries: Number(process.env.AI_FETCH_RETRIES || 2),
        },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('Gemini error:', r.status, bodyText);
        return res
          .status(502)
          .json({ error: buildProviderErrorMessage('Gemini', bodyText) });
      }

      const data = JSON.parse(bodyText) as any;
      const textContent =
        data?.candidates?.[0]?.content?.parts?.find((part: any) => typeof part?.text === 'string')?.text ?? null;

      if (typeof textContent !== 'string') {
        return res.status(502).json({ error: 'Respuesta IA invalida' });
      }

      let parsed: unknown = null;
      try {
        parsed = JSON.parse(textContent);
      } catch {
        parsed = extractFirstJsonObject(textContent);
      }

      const normalized = normalizeNutritionAnalysis(parsed);
      if (!normalized) {
        console.error('Gemini nutrition raw response:', textContent);
        return res.status(502).json({ error: 'No se pudo parsear JSON de IA' });
      }

      return res.json(normalized);
    }

    if (selectedProvider !== 'openai') {
      return res.status(503).json({
        error:
          'IA no configurada en el servidor. Configura OPENROUTER_API_KEY o GEMINI_API_KEY o OPENAI_API_KEY, o define AI_PROVIDER.',
      });
    }

    if (!openaiKey) {
      return res.status(503).json({
        error:
          'IA no configurada en el servidor. Configura OPENAI_API_KEY (o usa OpenRouter/Gemini) en el backend.',
      });
    }

    const model = process.env.OPENAI_VISION_MODEL || 'gpt-4o-mini';
    const imageUrl = `data:${mimeType};base64,${imageBase64}`;

    const r = await fetchWithRetry(
      'https://api.openai.com/v1/chat/completions',
      {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${openaiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: prompt },
          {
            role: 'user',
            content: [
              { type: 'text', text: 'Analiza la comida de esta imagen.' },
              { type: 'image_url', image_url: { url: imageUrl } },
            ],
          },
        ],
        max_tokens: 500,
        temperature: 0.1,
      }),
      },
      {
        timeoutMs: Number(process.env.AI_FETCH_TIMEOUT_MS || 20_000),
        retries: Number(process.env.AI_FETCH_RETRIES || 2),
      },
    );

    const bodyText = await r.text();
    if (!r.ok) {
      console.error('OpenAI error:', r.status, bodyText);
      return res
        .status(502)
        .json({ error: 'Error llamando al proveedor IA (OpenAI)' });
    }

    const data = JSON.parse(bodyText) as any;
    const content = data?.choices?.[0]?.message?.content ?? null;
    if (typeof content !== 'string') {
      return res.status(502).json({ error: 'Respuesta IA invalida' });
    }

    const extracted = extractFirstJsonObject(content);
    const normalized = normalizeNutritionAnalysis(extracted);
    if (!normalized) {
      return res.status(502).json({ error: 'No se pudo parsear JSON de IA' });
    }

    return res.json(normalized);
  } catch (error) {
    console.error('Error analyzing meal image:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

export default router;
