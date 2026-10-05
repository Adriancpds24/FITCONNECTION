import { Router } from 'express';
import pool from '../db';
import { authenticateToken, AuthRequest } from '../middleware/auth';

const router = Router();

function luhnValid(raw: string): boolean {
  const digits = raw.replace(/\D/g, '');
  if (digits.length < 12 || digits.length > 19) return false;
  let sum = 0;
  let alt = false;
  for (let i = digits.length - 1; i >= 0; i -= 1) {
    let n = Number.parseInt(digits[i]!, 10);
    if (Number.isNaN(n)) return false;
    if (alt) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    alt = !alt;
  }
  return sum % 10 === 0;
}

function guessBrand(pan: string): string {
  const d = pan.replace(/\D/g, '');
  if (d.startsWith('4')) return 'Visa';
  if (/^5[1-5]/.test(d)) return 'Mastercard';
  if (/^3[47]/.test(d)) return 'Amex';
  return 'Card';
}

router.get('/payments/methods', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const r = await pool.query(
      `
        SELECT id, brand, "last4", "expMonth", "expYear", "holderName", "isDefault", "createdAt"
        FROM "PaymentMethod"
        WHERE "userId" = $1
        ORDER BY "isDefault" DESC, "createdAt" DESC
      `,
      [req.user!.userId],
    );
    return res.json(r.rows);
  } catch (e) {
    console.error('payments list:', e);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

router.post('/payments/methods', authenticateToken, async (req: AuthRequest, res) => {
  try {
    const cardNumber = String(req.body?.cardNumber ?? '').replace(/\s/g, '');
    const holderName = String(req.body?.holderName ?? '').trim();
    const expMonth = Number(req.body?.expMonth);
    const expYear = Number(req.body?.expYear);
    const brandIn = String(req.body?.brand ?? '').trim();

    if (!holderName || holderName.length < 2) {
      return res.status(400).json({ error: 'Nombre del titular invalido' });
    }
    if (!Number.isFinite(expMonth) || expMonth < 1 || expMonth > 12) {
      return res.status(400).json({ error: 'Mes de caducidad invalido' });
    }
    if (!Number.isFinite(expYear) || expYear < new Date().getFullYear() - 1) {
      return res.status(400).json({ error: 'Ano de caducidad invalido' });
    }
    if (!luhnValid(cardNumber)) {
      return res.status(400).json({ error: 'Numero de tarjeta invalido' });
    }

    const last4 = cardNumber.replace(/\D/g, '').slice(-4);
    const brand = brandIn.length > 0 ? brandIn : guessBrand(cardNumber);

    const existing = await pool.query(
      `SELECT COUNT(*)::int AS c FROM "PaymentMethod" WHERE "userId" = $1`,
      [req.user!.userId],
    );
    const isDefault = Number(existing.rows[0]?.c ?? 0) === 0;

    const ins = await pool.query(
      `
        INSERT INTO "PaymentMethod" ("userId", brand, "last4", "expMonth", "expYear", "holderName", "isDefault")
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id, brand, "last4", "expMonth", "expYear", "holderName", "isDefault", "createdAt"
      `,
      [req.user!.userId, brand, last4, expMonth, expYear, holderName, isDefault],
    );

    return res.status(201).json(ins.rows[0]);
  } catch (e) {
    console.error('payments add:', e);
    return res.status(500).json({ error: 'Error del servidor' });
  }
});

export default router;
