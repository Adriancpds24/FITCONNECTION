import { Router } from 'express';
import pool from '../db';
import { authenticateToken, AuthRequest } from '../middleware/auth';

const router = Router();

// Obtener mis reservaciones
router.get('/me', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user?.userId;
        if (!userId) {
            return res.status(401).json({ error: 'Usuario no autenticado' });
        }
        const query = `
            SELECT
                r.*,
                COALESCE(sc.name, 'Centro deportivo') as "centerName",
                COALESCE(sc.address, '') as "centerAddress",
                COALESCE(sc.image, '') as "centerImage"
            FROM "Reservation" r
            LEFT JOIN "SportsCenter" sc ON r."sportsCenterId" = sc.id
            WHERE r."userId" = $1
            ORDER BY r.date DESC, r.time DESC
        `;
        const result = await pool.query(query, [userId]);
        res.json(result.rows);
    } catch (error) {
        console.error('Error fetching reservations:', error);
        if ((error as { code?: string }).code === '42P01') {
            return res.json([]);
        }
        res.status(500).json({ error: 'Error al obtener reservaciones' });
    }
});

// Crear una reservación
router.post('/', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user?.userId;
        const { sportsCenterId, date, time, type } = req.body;
        
        const query = `
            INSERT INTO "Reservation" ("userId", "sportsCenterId", "date", "time", "type")
            VALUES ($1, $2, $3, $4, $5)
            RETURNING *
        `;
        
        const result = await pool.query(query, [userId, sportsCenterId, date, time, type]);
        
        // También podemos crear una notificación automática
        await pool.query(
            'INSERT INTO "Notification" ("userId", "type", "title", "content") VALUES ($1, $2, $3, $4)',
            [userId, 'reservation', 'Reserva Confirmada', `Tu reserva para el ${date} a las ${time} ha sido confirmada.`]
        );

        res.status(201).json(result.rows[0]);
    } catch (error) {
        console.error('Error creating reservation:', error);
        res.status(500).json({ error: 'Error al crear la reservación' });
    }
});

// Cancelar reservación
router.delete('/:id', authenticateToken, async (req: AuthRequest, res) => {
    try {
        const userId = req.user?.userId;
        const reservationId = req.params.id;
        
        const query = 'UPDATE "Reservation" SET "status" = \'Cancelada\' WHERE id = $1 AND "userId" = $2 RETURNING *';
        const result = await pool.query(query, [reservationId, userId]);
        
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Reservación no encontrada' });
        }
        
        res.json({ message: 'Reservación cancelada', reservation: result.rows[0] });
    } catch (error) {
        console.error('Error canceling reservation:', error);
        res.status(500).json({ error: 'Error al cancelar la reservación' });
    }
});

export default router;
