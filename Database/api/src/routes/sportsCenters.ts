import { Router } from "express";
import pool from "../db";

const router = Router();
const VALID_KINDS = new Set(["spain", "community", "city"]);
const MAX_LIMIT = 4000;

function readText(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function readLimit(value: unknown): number {
  const parsed = Number.parseInt(String(value ?? 500), 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return 500;
  return Math.min(parsed, MAX_LIMIT);
}

router.get("/", async (req, res) => {
  try {
    const destination = readText(req.query.destination);
    const kind = readText(req.query.kind);
    const category = readText(req.query.category);
    const limit = readLimit(req.query.limit);

    const clauses = ['"isActive" = true'];
    const params: Array<string | number> = [];

    if (category && category !== "all") {
      params.push(category);
      clauses.push(`category = $${params.length}`);
    }

    if (VALID_KINDS.has(kind) && kind !== "spain" && destination) {
      params.push(destination);
      clauses.push(kind === "city" ? `city = $${params.length}` : `community = $${params.length}`);
    }

    params.push(limit);
    const limitParam = `$${params.length}`;

    const result = await pool.query(
      `
        SELECT
          id,
          "sourceId",
          name,
          type,
          city,
          province,
          community,
          category,
          address,
          website,
          phone,
          "openingHours",
          image,
          latitude,
          longitude
        FROM "SportsCenter"
        WHERE ${clauses.join(" AND ")}
        ORDER BY community ASC, city ASC, name ASC
        LIMIT ${limitParam}
      `,
      params,
    );

    return res.json(result.rows);
  } catch (error) {
    console.error("Error fetching sports centers:", error);
    return res.status(500).json({ error: "Error al obtener centros deportivos" });
  }
});

export default router;
