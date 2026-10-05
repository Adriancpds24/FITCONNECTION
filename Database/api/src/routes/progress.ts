import { Router } from 'express';
import pool from '../db';
import { authenticateToken, AuthRequest } from '../middleware/auth';

const router = Router();

function toSafeNumber(value: unknown): number | null {
  const parsed =
    typeof value === 'number'
      ? value
      : typeof value === 'string'
        ? Number(value.replace(',', '.'))
        : NaN;
  if (!Number.isFinite(parsed)) return null;
  return parsed;
}

// Weight log (upsert by day).
router.post('/weight', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const weightKg = toSafeNumber(req.body?.weightKg);
    const date = String(req.body?.date ?? '').trim(); // optional YYYY-MM-DD

    if (weightKg == null || weightKg <= 0 || weightKg > 500) {
      return res.status(400).json({ error: 'weightKg invalido' });
    }

    const targetDate = date ? date : null;
    const result = await pool.query(
      `
        INSERT INTO "UserWeightEntry" ("userId","date","weightKg","createdAt")
        VALUES ($1, COALESCE($2::date, CURRENT_DATE), $3, NOW())
        ON CONFLICT ("userId","date")
        DO UPDATE SET "weightKg" = EXCLUDED."weightKg"
        RETURNING *
      `,
      [userId, targetDate, weightKg],
    );

    return res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error saving weight:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

// Weight history (last N days).
router.get('/weight', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const days = Math.max(7, Math.min(365, Number(req.query?.days ?? 90) || 90));

    const result = await pool.query(
      `
        SELECT date, "weightKg"
        FROM "UserWeightEntry"
        WHERE "userId" = $1 AND date >= (CURRENT_DATE - ($2 || ' days')::interval)
        ORDER BY date ASC
      `,
      [userId, String(days)],
    );

    return res.json({ days, entries: result.rows });
  } catch (error) {
    console.error('Error fetching weight history:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

// Reminder settings (get or set).
router.get('/reminders', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const result = await pool.query(
      `
        SELECT
          "enabled","mealReminders","trainingReminders","hydrationReminders",
          "quietHoursStart","quietHoursEnd","updatedAt"
        FROM "UserReminderSettings"
        WHERE "userId" = $1
        LIMIT 1
      `,
      [userId],
    );
    if (result.rows.length === 0) {
      return res.json({
        enabled: true,
        mealReminders: true,
        trainingReminders: true,
        hydrationReminders: false,
        quietHoursStart: '22:30',
        quietHoursEnd: '08:30',
      });
    }
    return res.json(result.rows[0]);
  } catch (error) {
    console.error('Error fetching reminder settings:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

router.post('/reminders', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const enabled = req.body?.enabled;
    const mealReminders = req.body?.mealReminders;
    const trainingReminders = req.body?.trainingReminders;
    const hydrationReminders = req.body?.hydrationReminders;
    const quietHoursStart = String(req.body?.quietHoursStart ?? '').trim();
    const quietHoursEnd = String(req.body?.quietHoursEnd ?? '').trim();

    const result = await pool.query(
      `
        INSERT INTO "UserReminderSettings" (
          "userId","enabled","mealReminders","trainingReminders","hydrationReminders",
          "quietHoursStart","quietHoursEnd","updatedAt"
        )
        VALUES (
          $1,
          COALESCE($2::boolean, true),
          COALESCE($3::boolean, true),
          COALESCE($4::boolean, true),
          COALESCE($5::boolean, false),
          NULLIF($6,''),
          NULLIF($7,''),
          NOW()
        )
        ON CONFLICT ("userId")
        DO UPDATE SET
          "enabled" = COALESCE($2::boolean, "UserReminderSettings"."enabled"),
          "mealReminders" = COALESCE($3::boolean, "UserReminderSettings"."mealReminders"),
          "trainingReminders" = COALESCE($4::boolean, "UserReminderSettings"."trainingReminders"),
          "hydrationReminders" = COALESCE($5::boolean, "UserReminderSettings"."hydrationReminders"),
          "quietHoursStart" = COALESCE(NULLIF($6,''), "UserReminderSettings"."quietHoursStart"),
          "quietHoursEnd" = COALESCE(NULLIF($7,''), "UserReminderSettings"."quietHoursEnd"),
          "updatedAt" = NOW()
        RETURNING *
      `,
      [
        userId,
        typeof enabled === 'boolean' ? enabled : null,
        typeof mealReminders === 'boolean' ? mealReminders : null,
        typeof trainingReminders === 'boolean' ? trainingReminders : null,
        typeof hydrationReminders === 'boolean' ? hydrationReminders : null,
        quietHoursStart || null,
        quietHoursEnd || null,
      ],
    );

    return res.json(result.rows[0]);
  } catch (error) {
    console.error('Error saving reminder settings:', error);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

export default router;

