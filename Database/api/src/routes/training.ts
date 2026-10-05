import { Router } from 'express';
import pool from '../db';
import { authenticateToken, AuthRequest } from '../middleware/auth';
import { GamificationService } from '../services/gamificationService';
import { FITCONNECTION_FITNESS_NUTRITION_SYSTEM_PROMPT } from '../ai/prompts';
import { FITCONNECTION_WEEKLY_COACH_TRAINING_JSON_PROMPT } from '../ai/prompts';
import { createRateLimiter } from '../middleware/rateLimit';
import { fetchWithRetry } from '../services/aiFetch';

const router = Router();
const aiChatRateLimit = createRateLimiter({
  limit: Number(process.env.AI_RATE_LIMIT_PER_MINUTE || 30),
  windowMs: 60_000,
  keyPrefix: 'ai-chat',
});

type FitBotMessage = { role: 'user' | 'bot'; text: string };
type OpenAIStyleMessage = { role: string; content: any };

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

function normalizeChatMessages(rawMessages: unknown): Array<{ role: 'user' | 'assistant'; content: string }> {
  if (!Array.isArray(rawMessages)) {
    return [];
  }

  return rawMessages
    .map((message) => {
      if (!message || typeof message !== 'object') {
        return null;
      }

      if ('content' in message) {
        const msg = message as OpenAIStyleMessage;
        if (msg.role === 'system') {
          return null;
        }

        return {
          role: msg.role === 'assistant' ? 'assistant' : 'user',
          content: String(msg.content ?? '').trim(),
        };
      }

      const msg = message as FitBotMessage;
      return {
        role: msg.role === 'bot' ? 'assistant' : 'user',
        content: String((msg as any).text ?? '').trim(),
      };
    })
    .filter((message): message is { role: 'user' | 'assistant'; content: string } => {
      return !!message && message.content.length > 0;
    });
}

function normalizeFitBotReply(rawReply: unknown): string | null {
  if (typeof rawReply !== 'string') {
    return null;
  }

  const reply = rawReply.replace(/\s+/g, ' ').trim();
  if (reply.length === 0) {
    return null;
  }

  const endsMidSentence = /\b(y|o|pero|porque|que|si|aunque|para)\s*$/i.test(reply);
  if (endsMidSentence) {
    return 'Vamos a enfocarlo mejor: dime si buscas perder grasa, ganar musculo o rendir mejor en el gym y te ayudo paso a paso.';
  }

  if (!/[.!?]$/.test(reply)) {
    return `${reply}.`;
  }

  return reply;
}

function todayKey(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function currentWeekStart(): string {
  const now = new Date();
  const monday = new Date(now);
  const day = monday.getDay(); // 0 Sun..6 Sat
  const diffToMonday = day === 0 ? -6 : 1 - day;
  monday.setDate(monday.getDate() + diffToMonday);
  return todayKey(monday);
}

// Coach semanal automatico (entreno). Genera y persiste el plan de esta semana.
router.post('/coach/weekly', authenticateToken, aiChatRateLimit, async (req: AuthRequest, res) => {
  try {
    const provider = (process.env.AI_PROVIDER || '').toLowerCase().trim();
    const geminiKey = process.env.GEMINI_API_KEY || '';
    const openaiKey = process.env.OPENAI_API_KEY || '';
    const groqKey = process.env.GROQ_API_KEY || '';
    const openrouterKey = process.env.OPENROUTER_API_KEY || '';

    const userId = req.user!.userId;

    // Optional: grab user context
    let system = FITCONNECTION_WEEKLY_COACH_TRAINING_JSON_PROMPT;
    try {
      const metrics = await pool.query(
        'SELECT goal, calories, protein, carbs, fat FROM "user_profiles_metrics" WHERE "userId" = $1 LIMIT 1',
        [userId],
      );
      if (metrics.rows.length > 0) {
        const row = metrics.rows[0] as any;
        system +=
          '\n\nCONTEXTO DEL USUARIO:' +
          `\n- Objetivo: ${String(row.goal ?? '')}` +
          `\n- Calorias objetivo: ${Number(row.calories ?? 0)}` +
          `\n- Proteina objetivo (g): ${Number(row.protein ?? 0)}` +
          `\n- Carbos objetivo (g): ${Number(row.carbs ?? 0)}` +
          `\n- Grasas objetivo (g): ${Number(row.fat ?? 0)}`;
      }
    } catch (e) {
      console.warn('Could not load metrics for weekly coach:', e);
    }

    const selectedProvider =
      provider ||
      (openrouterKey ? 'openrouter' : '') ||
      (geminiKey ? 'gemini' : '') ||
      (openaiKey ? 'openai' : '') ||
      (groqKey ? 'groq' : '');

    const timeoutMs = Number(process.env.AI_FETCH_TIMEOUT_MS || 25_000);
    const retries = Number(process.env.AI_FETCH_RETRIES || 2);

    const weekStart = currentWeekStart();

    const userMsg =
      'Genera un plan semanal de entrenamiento (7 dias) listo para seguir. Si no sabes el material, asume gimnasio basico y da alternativas.';

    const savePlan = async (plan: unknown) => {
      await pool.query(
        `
          INSERT INTO "UserWeeklyCoachPlan" ("userId","weekStart","planType","planJson","createdAt","updatedAt")
          VALUES ($1,$2,'training',$3::jsonb,NOW(),NOW())
          ON CONFLICT ("userId","weekStart","planType")
          DO UPDATE SET "planJson" = EXCLUDED."planJson", "updatedAt" = NOW()
        `,
        [userId, weekStart, JSON.stringify(plan ?? {})],
      );
    };

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
            max_tokens: 1600,
            temperature: 0.55,
          }),
        },
        { timeoutMs, retries },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('OpenRouter weekly coach error:', r.status, bodyText);
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

      await savePlan(extracted);
      return res.json({ weekStart, plan: extracted });
    }

    if (selectedProvider === 'gemini') {
      if (!geminiKey) {
        return res.status(503).json({ error: 'IA no configurada. Falta GEMINI_API_KEY.' });
      }

      const model = process.env.GEMINI_CHAT_MODEL || 'gemini-2.5-flash';
      const r = await fetchWithRetry(
        `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(geminiKey)}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            system_instruction: { parts: [{ text: system }] },
            contents: [{ role: 'user', parts: [{ text: userMsg }] }],
            generationConfig: {
              responseMimeType: 'application/json',
              temperature: 0.55,
              maxOutputTokens: 1600,
            },
          }),
        },
        { timeoutMs, retries },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('Gemini weekly coach error:', r.status, bodyText);
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

      await savePlan(parsed);
      return res.json({ weekStart, plan: parsed });
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
            max_tokens: 1600,
            temperature: 0.55,
          }),
        },
        { timeoutMs, retries },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('Groq weekly coach error:', r.status, bodyText);
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

      await savePlan(extracted);
      return res.json({ weekStart, plan: extracted });
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
          max_tokens: 1600,
          temperature: 0.55,
        }),
      },
      { timeoutMs, retries },
    );

    const bodyText = await r.text();
    if (!r.ok) {
      console.error('OpenAI weekly coach error:', r.status, bodyText);
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

    await savePlan(extracted);
    return res.json({ weekStart, plan: extracted });
  } catch (error) {
    console.error('Error in /coach/weekly:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

// Get persisted training coach plan for current week.
router.get('/coach/weekly', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const weekStart = currentWeekStart();
    const result = await pool.query(
      `
        SELECT "weekStart", "planJson", "updatedAt"
        FROM "UserWeeklyCoachPlan"
        WHERE "userId" = $1 AND "weekStart" = $2 AND "planType" = 'training'
        LIMIT 1
      `,
      [userId, weekStart],
    );

    if (result.rows.length === 0) {
      return res.json({ weekStart, plan: null });
    }

    return res.json({ weekStart, plan: result.rows[0].planJson, updatedAt: result.rows[0].updatedAt });
  } catch (error) {
    console.error('Error fetching weekly coach plan:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

// Obtener todos los ejercicios disponibles
router.get('/exercises', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const query = 'SELECT * FROM "Exercise" ORDER BY name ASC';
        const result = await pool.query(query);
        res.json(result.rows);
    } catch (error) {
        console.error('Error fetching exercises:', error);
        res.status(500).json({ error: 'Error del servidor al obtener ejercicios' });
    }
});

// Crear un nuevo entrenamiento/rutina
router.post('/workouts', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const { title, description, exercises } = req.body;

        if (!title) {
            return res.status(400).json({ error: 'El título es obligatorio' });
        }

        // Iniciar transacción
        await pool.query('BEGIN');

        // Insertar Workout
        const workoutQuery = `
            INSERT INTO "Workout" (title, description, "userId", "createdAt")
            VALUES ($1, $2, $3, NOW())
            RETURNING *
        `;
        const workoutResult = await pool.query(workoutQuery, [title, description, userId]);
        const workout = workoutResult.rows[0];

        // Insertar Ejercicios si existen
        if (exercises && Array.isArray(exercises)) {
            for (const ex of exercises) {
                const exQuery = `
                    INSERT INTO "WorkoutExercise" ("workoutId", "exerciseId", sets, reps, weight, duration)
                    VALUES ($1, $2, $3, $4, $5, $6)
                `;
                await pool.query(exQuery, [
                    workout.id,
                    ex.exerciseId,
                    ex.sets || 1, // Default 1 set si no se especifica
                    ex.reps || null,
                    ex.weight || null,
                    ex.duration || null
                ]);
            }
        }

        await pool.query('COMMIT');

        // Devolver el workout completo
        res.status(201).json({
            message: 'Rutina creada con éxito',
            workout
        });

    } catch (error) {
        await pool.query('ROLLBACK');
        console.error('Error creating workout:', error);
        res.status(500).json({ error: 'Error del servidor al crear rutina' });
    }
});

// Obtener los entrenamientos del usuario logueado
router.get('/workouts', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        const query = 'SELECT * FROM "Workout" WHERE "userId" = $1 ORDER BY "createdAt" DESC';
        const result = await pool.query(query, [userId]);
        res.json(result.rows);
    } catch (error) {
         console.error('Error fetching user workouts:', error);
         res.status(500).json({ error: 'Error del servidor al obtener las rutinas' });
    }
});

// Obtener el entrenamiento de hoy y su estado
router.get('/today', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        
        // 1. Ver si ya existe una entrada de hoy en el historial
        const historyQuery = `
            SELECT h.*, w.title as "workoutTitle", w.description as "workoutDescription"
            FROM "user_training_history" h
            LEFT JOIN "Workout" w ON h."workoutId" = w.id
            WHERE h."userId" = $1 AND h."date" = CURRENT_DATE
        `;
        const historyResult = await pool.query(historyQuery, [userId]);

        if (historyResult.rows.length > 0) {
            return res.json(historyResult.rows[0]);
        }

        // 2. Si no hay historial de hoy, buscar o generar una rutina
        const workoutQuery = 'SELECT * FROM "Workout" WHERE "userId" = $1 OR "userId" = 1 LIMIT 1';
        const workoutResult = await pool.query(workoutQuery, [userId]);
        const workout = workoutResult.rows[0];

        if (!workout) {
            // Generar rutina por defecto si no hay nada
            return res.json({
                userId,
                workoutId: null,
                workoutTitle: 'Rutina de Mantenimiento',
                workoutDescription: 'Una rutina básica para mantenerte activo hoy.',
                isCompleted: false,
                date: new Date().toISOString().split('T')[0],
                exercisesList: [
                    { nombre: 'Flexiones', series: '3 x 15', completado: false },
                    { nombre: 'Sentadillas', series: '3 x 20', completado: false },
                    { nombre: 'Plancha', series: '3 x 45s', completado: false },
                    { nombre: 'Zancadas', series: '3 x 12 por pierna', completado: false },
                    { nombre: 'Remo con Mancuernas', series: '3 x 12', completado: false },
                    { nombre: 'Jumping Jacks', series: '3 x 40', completado: false }
                ]
            });
        }

        // Devolver una sesión "potencial" no guardada aún
        res.json({
            userId,
            workoutId: workout.id,
            workoutTitle: workout.title,
            workoutDescription: workout.description,
            isCompleted: false,
            date: new Date().toISOString().split('T')[0],
            exercisesList: [] // El frontend cargará los detalles si workoutId está presente, o podemos enviarlos aquí
        });

    } catch (error) {
        console.error('Error fetching today workout:', error);
        res.status(500).json({ error: 'Error al obtener entrenamiento de hoy' });
    }
});

async function ensureTrainingDurationColumn(): Promise<void> {
    try {
        await pool.query(
            'ALTER TABLE "user_training_history" ADD COLUMN IF NOT EXISTS "durationSeconds" INTEGER NOT NULL DEFAULT 0',
        );
    } catch (error) {
        console.warn('Could not ensure durationSeconds column:', error);
    }
}

async function ensureTrainingCompletedAtColumn(): Promise<void> {
    try {
        await pool.query(
            'ALTER TABLE "user_training_history" ADD COLUMN IF NOT EXISTS "completedAt" TIMESTAMP(3)',
        );
    } catch (error) {
        console.warn('Could not ensure completedAt column:', error);
    }
}

async function ensureTrainingHistoryColumns(): Promise<void> {
    await ensureTrainingDurationColumn();
    await ensureTrainingCompletedAtColumn();
}

// Guardar progreso parcial del día (sin marcar como completado)
router.put('/progress', authenticateToken, async (req: AuthRequest, res) => {
    try {
        await ensureTrainingHistoryColumns();
        const userId = req.user!.userId;
        const { workoutId, exercisesList, durationSeconds } = req.body;

        const existing = await pool.query(
            'SELECT "isCompleted" FROM "user_training_history" WHERE "userId" = $1 AND "date" = CURRENT_DATE',
            [userId],
        );
        if (existing.rows.length > 0 && existing.rows[0].isCompleted === true) {
            return res.status(409).json({ error: 'El entrenamiento de hoy ya está completado' });
        }

        const query = `
            INSERT INTO "user_training_history" ("userId", "workoutId", "isCompleted", "exercisesList", "date", "durationSeconds")
            VALUES ($1, $2, false, $3, CURRENT_DATE, $4)
            ON CONFLICT ("userId", "date")
            DO UPDATE SET
                "exercisesList" = $3,
                "workoutId" = COALESCE($2, "user_training_history"."workoutId"),
                "durationSeconds" = GREATEST(COALESCE("user_training_history"."durationSeconds", 0), $4)
            WHERE "user_training_history"."isCompleted" = false
            RETURNING *
        `;

        const result = await pool.query(query, [
            userId,
            workoutId ?? null,
            JSON.stringify(exercisesList || []),
            Number(durationSeconds) || 0,
        ]);

        if (result.rows.length === 0) {
            return res.status(409).json({ error: 'El entrenamiento de hoy ya está completado' });
        }

        return res.json(result.rows[0]);
    } catch (error) {
        console.error('Error saving training progress:', error);
        return res.status(500).json({ error: 'Error al guardar progreso' });
    }
});

// Obtener entrenamiento de un día concreto
router.get('/day/:date', authenticateToken, async (req: AuthRequest, res) => {
    try {
        await ensureTrainingHistoryColumns();
        const userId = req.user!.userId;
        const date = String(req.params.date ?? '');
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
            return res.status(400).json({ error: 'Fecha inválida' });
        }

        const historyQuery = `
            SELECT h.*, w.title as "workoutTitle", w.description as "workoutDescription"
            FROM "user_training_history" h
            LEFT JOIN "Workout" w ON h."workoutId" = w.id
            WHERE h."userId" = $1 AND h."date" = $2::date
        `;
        const historyResult = await pool.query(historyQuery, [userId, date]);
        if (historyResult.rows.length > 0) {
            return res.json(historyResult.rows[0]);
        }

        const today = todayKey(new Date());
        if (date !== today) {
            return res.json({
                userId,
                workoutId: null,
                workoutTitle: null,
                workoutDescription: null,
                isCompleted: false,
                date,
                exercisesList: [],
                durationSeconds: 0,
            });
        }

        const workoutQuery = 'SELECT * FROM "Workout" WHERE "userId" = $1 OR "userId" = 1 LIMIT 1';
        const workoutResult = await pool.query(workoutQuery, [userId]);
        const workout = workoutResult.rows[0];

        if (!workout) {
            return res.json({
                userId,
                workoutId: null,
                workoutTitle: 'Rutina de Mantenimiento',
                workoutDescription: 'Una rutina básica para mantenerte activo hoy.',
                isCompleted: false,
                date,
                exercisesList: [
                    { nombre: 'Flexiones', series: '3 x 15', completado: false },
                    { nombre: 'Sentadillas', series: '3 x 20', completado: false },
                    { nombre: 'Plancha', series: '3 x 45s', completado: false },
                ],
                durationSeconds: 0,
            });
        }

        return res.json({
            userId,
            workoutId: workout.id,
            workoutTitle: workout.title,
            workoutDescription: workout.description,
            isCompleted: false,
            date,
            exercisesList: [],
            durationSeconds: 0,
        });
    } catch (error) {
        console.error('Error fetching day workout:', error);
        return res.status(500).json({ error: 'Error al obtener entrenamiento del día' });
    }
});

// Marcar entrenamiento como completado
router.post('/complete', authenticateToken, async (req: AuthRequest, res) => {
    try {
        await ensureTrainingHistoryColumns();
        const userId = req.user!.userId;
        const { workoutId, exercisesList, durationSeconds } = req.body;

        const query = `
            INSERT INTO "user_training_history" ("userId", "workoutId", "isCompleted", "exercisesList", "date", "durationSeconds", "completedAt")
            VALUES ($1, $2, true, $3, CURRENT_DATE, $4, NOW())
            ON CONFLICT ("userId", "date") 
            DO UPDATE SET
                "isCompleted" = true,
                "exercisesList" = $3,
                "workoutId" = COALESCE($2, "user_training_history"."workoutId"),
                "durationSeconds" = GREATEST(COALESCE("user_training_history"."durationSeconds", 0), $4),
                "completedAt" = NOW()
            RETURNING *
        `;
        
        const result = await pool.query(query, [
            userId,
            workoutId ?? null,
            JSON.stringify(exercisesList || []),
            Number(durationSeconds) || 0,
        ]);
        
        // Gamification: Reward user
        const rewards = await GamificationService.handleWorkoutCompletion(userId);

        res.status(201).json({
            message: '¡Entrenamiento completado!',
            session: result.rows[0],
            rewards
        });
    } catch (error) {
        console.error('Error completing workout:', error);
        res.status(500).json({ error: 'Error al registrar entrenamiento' });
    }
});

// Obtener historial de entrenamientos para el calendario
router.get('/history', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user!.userId;
        await ensureTrainingHistoryColumns();
        const query = `
            SELECT
              h.date,
              h."isCompleted",
              h."exercisesList",
              COALESCE(h."durationSeconds", 0) AS "durationSeconds",
              COALESCE(h."completedAt", h."createdAt") AS "completedAt",
              w.title AS "workoutTitle"
            FROM "user_training_history" h
            LEFT JOIN "Workout" w ON h."workoutId" = w.id
            WHERE h."userId" = $1
            ORDER BY COALESCE(h."completedAt", h."createdAt") DESC
            LIMIT 90
        `;
        const result = await pool.query(query, [userId]);
        res.json(result.rows);
    } catch (error) {
        console.error('Error fetching history:', error);
        res.status(500).json({ error: 'Error al obtener historial' });
    }
});

// FitBot (AI chat) - server-side proxy to avoid exposing API keys in clients.
router.post('/fitbot/chat', authenticateToken, aiChatRateLimit, async (req: AuthRequest, res) => {
  try {
    const provider = (process.env.AI_PROVIDER || '').toLowerCase().trim();
    const geminiKey = process.env.GEMINI_API_KEY || '';
    const openaiKey = process.env.OPENAI_API_KEY || '';
    const groqKey = process.env.GROQ_API_KEY || '';
    const openrouterKey = process.env.OPENROUTER_API_KEY || '';
    const messages = req.body?.messages as unknown;
    const normalizedMessages = normalizeChatMessages(messages);
    if (normalizedMessages.length === 0) {
      return res.status(400).json({ error: 'messages es obligatorio' });
    }
    const system = FITCONNECTION_FITNESS_NUTRITION_SYSTEM_PROMPT;

    const selectedProvider =
      provider ||
      (openrouterKey ? 'openrouter' : '') ||
      (geminiKey ? 'gemini' : '') ||
      (openaiKey ? 'openai' : '') ||
      (groqKey ? 'groq' : '');

    if (selectedProvider === 'groq') {
      if (!groqKey) {
        return res.status(503).json({
          error: 'IA no configurada en el servidor. Configura GROQ_API_KEY en el backend.',
        });
      }

      const model = process.env.GROQ_CHAT_MODEL || 'llama-3.1-8b-instant';
      const chatMessages = [{ role: 'system', content: system }, ...normalizedMessages];
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
            messages: chatMessages,
            max_tokens: 220,
            temperature: 0.7,
          }),
        },
        {
          timeoutMs: Number(process.env.AI_FETCH_TIMEOUT_MS || 20_000),
          retries: Number(process.env.AI_FETCH_RETRIES || 2),
        },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('Groq FitBot error:', r.status, bodyText);
        return res.status(502).json({
          error: buildProviderErrorMessage('Groq', bodyText),
        });
      }

      const data = JSON.parse(bodyText) as any;
      const reply = normalizeFitBotReply(data?.choices?.[0]?.message?.content ?? null);
      if (!reply) {
        return res.status(502).json({ error: 'Respuesta IA invalida' });
      }

      return res.json({ choices: [{ message: { content: reply } }] });
    }

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

      const chatMessages = [{ role: 'system', content: system }, ...normalizedMessages];
      const r = await fetchWithRetry(
        'https://openrouter.ai/api/v1/chat/completions',
        {
          method: 'POST',
          headers,
          body: JSON.stringify({
            model,
            messages: chatMessages,
            max_tokens: 220,
            temperature: 0.7,
          }),
        },
        {
          timeoutMs: Number(process.env.AI_FETCH_TIMEOUT_MS || 20_000),
          retries: Number(process.env.AI_FETCH_RETRIES || 2),
        },
      );

      const bodyText = await r.text();
      if (!r.ok) {
        console.error('OpenRouter FitBot error:', r.status, bodyText);
        return res.status(502).json({
          error: buildProviderErrorMessage('OpenRouter', bodyText),
        });
      }

      const data = JSON.parse(bodyText) as any;
      const reply = normalizeFitBotReply(data?.choices?.[0]?.message?.content ?? null);
      if (!reply) {
        return res.status(502).json({ error: 'Respuesta IA invalida' });
      }

      return res.json({ choices: [{ message: { content: reply } }] });
    }

    if (selectedProvider === 'gemini') {
      if (!geminiKey) {
        return res.status(503).json({
          error:
            'IA no configurada en el servidor. Configura GEMINI_API_KEY (o usa OpenRouter/OpenAI/Groq) en el backend.',
        });
      }

      const model = process.env.GEMINI_CHAT_MODEL || 'gemini-2.5-flash';
      const r = await fetchWithRetry(
        `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(geminiKey)}`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            system_instruction: {
              parts: [{ text: system }],
            },
            contents: normalizedMessages.map((message) => ({
              role: message.role === 'assistant' ? 'model' : 'user',
              parts: [{ text: message.content }],
            })),
            generationConfig: {
              responseMimeType: 'application/json',
              responseSchema: {
                type: 'object',
                properties: {
                  reply: {
                    type: 'string',
                    description: 'Respuesta final del entrenador en espanol.',
                  },
                },
                required: ['reply'],
              },
              maxOutputTokens: 220,
              temperature: 0.45,
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
        console.error('Gemini FitBot error:', r.status, bodyText);
        return res.status(502).json({
          error: buildProviderErrorMessage('Gemini', bodyText),
        });
      }

      const data = JSON.parse(bodyText) as any;
      const rawText =
        data?.candidates?.[0]?.content?.parts?.find((part: any) => typeof part?.text === 'string')?.text ?? null;
      let reply: string | null = null;

      if (typeof rawText === 'string') {
        try {
          const parsed = JSON.parse(rawText) as { reply?: unknown };
          reply = normalizeFitBotReply(parsed?.reply);
        } catch {
          const extracted = extractFirstJsonObject(rawText);
          reply = normalizeFitBotReply(extracted?.reply ?? rawText);
        }
      }

      if (!reply) {
        return res.status(502).json({ error: 'Respuesta IA invalida' });
      }

      return res.json({ choices: [{ message: { content: reply } }] });
    }

    if (selectedProvider !== 'openai') {
      return res.status(503).json({
        error:
          'IA no configurada en el servidor. Configura OPENROUTER_API_KEY o GEMINI_API_KEY o OPENAI_API_KEY o GROQ_API_KEY, o define AI_PROVIDER.',
      });
    }

    if (!openaiKey) {
      return res.status(503).json({
        error:
          'IA no configurada en el servidor. Configura OPENAI_API_KEY (o usa OpenRouter/Gemini/Groq) en el backend.',
      });
    }

    const model = process.env.OPENAI_CHAT_MODEL || 'gpt-4o-mini';
    const chatMessages = [{ role: 'system', content: system }, ...normalizedMessages];

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
          messages: chatMessages,
          max_tokens: 180,
          temperature: 0.7,
        }),
      },
      {
        timeoutMs: Number(process.env.AI_FETCH_TIMEOUT_MS || 20_000),
        retries: Number(process.env.AI_FETCH_RETRIES || 2),
      },
    );

    const bodyText = await r.text();
    if (!r.ok) {
      console.error('OpenAI FitBot error:', r.status, bodyText);
      return res.status(502).json({
        error: buildProviderErrorMessage('OpenAI', bodyText),
      });
    }

    const data = JSON.parse(bodyText) as any;
    const reply = normalizeFitBotReply(data?.choices?.[0]?.message?.content ?? null);
    if (!reply) {
      return res.status(502).json({ error: 'Respuesta IA invalida' });
    }

    return res.json({ choices: [{ message: { content: reply } }] });
  } catch (error) {
    console.error('Error in FitBot chat:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

export default router;
