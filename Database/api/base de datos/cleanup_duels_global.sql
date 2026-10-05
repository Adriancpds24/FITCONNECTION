-- Limpieza global de duelos para TODOS los usuarios.
-- Uso: ejecutar este script en la consola SQL de Railway/Postgres.
-- Fecha: 2026-05-18

BEGIN;

-- Asegura que cada usuario tenga un estado limpio de duelos.
INSERT INTO "UserDuelState" ("userId", "stateJson", "updatedAt")
SELECT
  u.id,
  jsonb_build_object(
    'invitations', '[]'::jsonb,
    'activeDuels', '[]'::jsonb,
    'stats', jsonb_build_object(
      'wins', 0,
      'points', 0,
      'pointsApplied', 0,
      'activeCount', 0,
      'rankPosition', 0
    )
  ),
  NOW()
FROM "User" u
ON CONFLICT ("userId")
DO UPDATE SET
  "stateJson" = EXCLUDED."stateJson",
  "updatedAt" = NOW();

-- Opcional: borrar notificaciones de duelos viejos para dejarlo 100% limpio.
DELETE FROM "Notification"
WHERE type IN ('duel', 'challenge');

COMMIT;

