import { Router } from 'express';
import pool from '../db';
import { authenticateToken, AuthRequest } from '../middleware/auth';

const router = Router();

// Obtener datos de wearable de hoy
router.get('/today', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user?.userId;
        const query = 'SELECT * FROM "UserWearableData" WHERE "userId" = $1 AND "date" = CURRENT_DATE';
        const result = await pool.query(query, [userId]);
        
        if (result.rows.length === 0) {
            return res.json({ steps: 0, burnedCalories: 0, heartRate: 0 });
        }
        
        res.json(result.rows[0]);
    } catch (error) {
        console.error('Error fetching wearable data:', error);
        res.status(500).json({ error: 'Error al obtener datos de salud' });
    }
});

// Actualizar o crear datos de wearable para hoy
router.post('/sync', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user?.userId;
        const { steps, burnedCalories, heartRate } = req.body;
        
        const query = `
            INSERT INTO "UserWearableData" ("userId", "date", "steps", "burnedCalories", "heartRate", "updatedAt")
            VALUES ($1, CURRENT_DATE, $2, $3, $4, CURRENT_TIMESTAMP)
            ON CONFLICT ("userId", "date") DO UPDATE
            SET 
                "steps" = EXCLUDED."steps",
                "burnedCalories" = EXCLUDED."burnedCalories",
                "heartRate" = EXCLUDED."heartRate",
                "updatedAt" = EXCLUDED."updatedAt"
            RETURNING *
        `;
        
        const result = await pool.query(query, [userId, steps, burnedCalories, heartRate]);
        res.status(201).json(result.rows[0]);
    } catch (error) {
        console.error('Error syncing wearable data:', error);
        res.status(500).json({ error: 'Error al sincronizar datos de salud' });
    }
});

export default router;
