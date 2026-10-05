import pool from '../db';

export interface GamificationUpdate {
    xpEarned: number;
    coinsEarned: number;
    leveledUp: boolean;
    newLevel: number;
    newXp: number;
    newCoins: number;
    streak: number;
}

export class GamificationService {
    static async handleWorkoutCompletion(userId: number): Promise<GamificationUpdate> {
        const xpForWorkout = 100;
        const coinsForWorkout = 50;

        // 1. Get current user data
        const userResult = await pool.query(
            'SELECT xp, level, fitcoins, streak, "lastWorkoutAt" FROM "User" WHERE id = $1',
            [userId]
        );

        if (userResult.rows.length === 0) {
            throw new Error('User not found');
        }

        let { xp, level, fitcoins, streak, lastWorkoutAt } = userResult.rows[0];
        
        // 2. Handle Streak
        const now = new Date();
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        
        if (lastWorkoutAt) {
            const lastDate = new Date(lastWorkoutAt);
            const lastDay = new Date(lastDate.getFullYear(), lastDate.getMonth(), lastDate.getDate());
            const diffDays = Math.floor((today.getTime() - lastDay.getTime()) / (1000 * 60 * 60 * 24));

            if (diffDays === 1) {
                streak += 1;
            } else if (diffDays > 1) {
                streak = 1;
            }
            // if diffDays === 0, keep current streak (already did a workout today)
        } else {
            streak = 1;
        }

        // 3. Add XP and Coins
        xp += xpForWorkout;
        fitcoins += coinsForWorkout;

        // 4. Check Level Up
        // Simple formula: Level 1 -> XP 500, Level 2 -> XP 1000, etc.
        const xpThreshold = level * 500;
        let leveledUp = false;
        if (xp >= xpThreshold) {
            level += 1;
            leveledUp = true;
        }

        // 5. Update Database
        await pool.query(
            'UPDATE "User" SET xp = $1, level = $2, fitcoins = $3, streak = $4, "lastWorkoutAt" = NOW() WHERE id = $5',
            [xp, level, fitcoins, streak, userId]
        );

        return {
            xpEarned: xpForWorkout,
            coinsEarned: coinsForWorkout,
            leveledUp,
            newLevel: level,
            newXp: xp,
            newCoins: fitcoins,
            streak
        };
    }
}
