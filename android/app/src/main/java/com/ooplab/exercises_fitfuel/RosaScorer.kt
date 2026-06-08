package com.ooplab.exercises_fitfuel

object RosaScorer {

    // ── Lookup tables (Cornell / Sonne 2012, verified against 71-photo reference) ──

    private val tableA = mapOf(
        2 to mapOf(2 to 2, 3 to 2, 4 to 3, 5 to 4, 6 to 5, 7 to 6, 8 to 7, 9 to 8),
        3 to mapOf(2 to 2, 3 to 2, 4 to 3, 5 to 4, 6 to 5, 7 to 6, 8 to 7, 9 to 8),
        4 to mapOf(2 to 3, 3 to 3, 4 to 3, 5 to 4, 6 to 5, 7 to 6, 8 to 7, 9 to 8),
        5 to mapOf(2 to 4, 3 to 4, 4 to 4, 5 to 4, 6 to 5, 7 to 6, 8 to 7, 9 to 8),
        6 to mapOf(2 to 5, 3 to 5, 4 to 5, 5 to 5, 6 to 6, 7 to 7, 8 to 8, 9 to 9),
        7 to mapOf(2 to 6, 3 to 6, 4 to 6, 5 to 7, 6 to 7, 7 to 8, 8 to 8, 9 to 9),
        8 to mapOf(2 to 7, 3 to 7, 4 to 7, 5 to 8, 6 to 8, 7 to 9, 8 to 9, 9 to 9),
    )

    private val tableB = mapOf(
        0 to mapOf(0 to 1, 1 to 1, 2 to 1, 3 to 2, 4 to 3, 5 to 4, 6 to 5, 7 to 6),
        1 to mapOf(0 to 1, 1 to 1, 2 to 2, 3 to 2, 4 to 3, 5 to 4, 6 to 5, 7 to 6),
        2 to mapOf(0 to 1, 1 to 2, 2 to 2, 3 to 3, 4 to 3, 5 to 4, 6 to 6, 7 to 7),
        3 to mapOf(0 to 2, 1 to 2, 2 to 3, 3 to 3, 4 to 4, 5 to 5, 6 to 6, 7 to 8),
        4 to mapOf(0 to 3, 1 to 3, 2 to 4, 3 to 4, 4 to 5, 5 to 6, 6 to 7, 7 to 8),
        5 to mapOf(0 to 4, 1 to 4, 2 to 5, 3 to 5, 4 to 6, 5 to 7, 6 to 8, 7 to 9),
        6 to mapOf(0 to 5, 1 to 5, 2 to 6, 3 to 7, 4 to 8, 5 to 8, 6 to 9, 7 to 9),
    )

    private val tableC = mapOf(
        0 to mapOf(0 to 1, 1 to 1, 2 to 1, 3 to 2, 4 to 3, 5 to 4, 6 to 5, 7 to 6),
        1 to mapOf(0 to 1, 1 to 1, 2 to 2, 3 to 3, 4 to 4, 5 to 5, 6 to 6, 7 to 7),
        2 to mapOf(0 to 1, 1 to 2, 2 to 2, 3 to 3, 4 to 4, 5 to 5, 6 to 6, 7 to 7),
        3 to mapOf(0 to 2, 1 to 3, 2 to 3, 3 to 3, 4 to 5, 5 to 6, 6 to 7, 7 to 8),
        4 to mapOf(0 to 3, 1 to 4, 2 to 4, 3 to 5, 4 to 5, 5 to 6, 6 to 7, 7 to 8),
        5 to mapOf(0 to 4, 1 to 5, 2 to 5, 3 to 6, 4 to 6, 5 to 7, 6 to 8, 7 to 9),
        6 to mapOf(0 to 5, 1 to 6, 2 to 6, 3 to 7, 4 to 7, 5 to 8, 6 to 8, 7 to 9),
        7 to mapOf(0 to 6, 1 to 7, 2 to 7, 3 to 8, 4 to 8, 5 to 9, 6 to 9, 7 to 9),
    )

    // Clamps row and col to the table's actual key range, then returns the value.
    private fun tlu(table: Map<Int, Map<Int, Int>>, row: Int, col: Int): Int {
        val r = row.coerceIn(table.keys.min(), table.keys.max())
        val c = col.coerceIn(table[r]!!.keys.min(), table[r]!!.keys.max())
        return table[r]!![c]!!
    }

    // ── Result ────────────────────────────────────────────────────────────────────

    data class Result(
        val finalScore: Int,
        val riskLevel: String,
        val chairScore: Int,
        val peripheralScore: Int,
        val seatHeightScore: Int,
        val backrestScore: Int,
        val armrestScore: Int,
        val monitorScore: Int,
        val keyboardScore: Int,
        val mouseScore: Int,
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "finalScore"      to finalScore,
            "riskLevel"       to riskLevel,
            "chairScore"      to chairScore,
            "peripheralScore" to peripheralScore,
            "seatHeightScore" to seatHeightScore,
            "backrestScore"   to backrestScore,
            "armrestScore"    to armrestScore,
            "monitorScore"    to monitorScore,
            "keyboardScore"   to keyboardScore,
            "mouseScore"      to mouseScore,
        )
    }

    // ── Scoring ───────────────────────────────────────────────────────────────────

    fun score(
        angles: RosaAnglesCalculator.Angles,
        durationMod: Int = 0,
        mouseCb: Int = 1,
    ): Result {
        // ── CHAIR ─────────────────────────────────────────────────────────────────
        val seatHeightScore = when {
            angles.kneeAngle < 80f  -> 2  // chair too low
            angles.kneeAngle > 130f -> 3  // legs nearly extended — feet off floor
            angles.kneeAngle > 100f -> 2  // chair too high
            else                    -> 1  // neutral
        }
        val backrestScore = if (angles.trunkAngle > 28f) 2 else 1
        // shrugGap = ear.y − shoulder.y; > −0.06 means shoulder hiked toward ear
        val armrestScore  = if (angles.shrugGap > -0.06f) 2 else 1

        val seatCombined = (seatHeightScore + 1).coerceIn(2, 8)
        val armsCombined = (armrestScore + backrestScore).coerceIn(2, 9)
        val chairScore   = (tlu(tableA, seatCombined, armsCombined) + durationMod).coerceIn(1, 10)

        // ── MONITOR ───────────────────────────────────────────────────────────────
        val monitorScore = when (angles.neckState) {
            RosaAnglesCalculator.NeckState.HEAD_BACK      -> 3
            RosaAnglesCalculator.NeckState.SEVERE_FLEXION -> 3
            RosaAnglesCalculator.NeckState.MILD_FLEXION   -> 2
            RosaAnglesCalculator.NeckState.FORWARD_HEAD   -> 2
            RosaAnglesCalculator.NeckState.NEUTRAL        -> 1
        }
        val sectB = tlu(tableB,
            (durationMod).coerceIn(0, 6),
            (monitorScore + durationMod).coerceIn(0, 7))

        // ── KEYBOARD ──────────────────────────────────────────────────────────────
        val keyboardScore = when {
            angles.wristExtension > 0.07f -> 3
            angles.wristExtension > 0.03f -> 2
            else                          -> 1
        }

        // ── MOUSE ─────────────────────────────────────────────────────────────────
        var mouseScore = when {
            mouseCb == 0              -> 1
            angles.mouseReach > 0.18f -> 2
            else                      -> 1
        }
        if (mouseCb == 2) mouseScore = (mouseScore + 1).coerceAtMost(3)

        val sectC = tlu(tableC,
            (mouseScore + durationMod).coerceIn(0, 7),
            (keyboardScore + durationMod).coerceIn(0, 7))

        // ── COMBINE ───────────────────────────────────────────────────────────────
        // Table D and E both use max(row, col) — "worst section wins"
        val peripheralScore = maxOf(sectB, sectC).coerceIn(1, 9)
        val finalScore      = maxOf(chairScore, peripheralScore).coerceIn(1, 10)

        val riskLevel = when {
            finalScore <= 2 -> "Low Risk"
            finalScore <= 4 -> "Medium Risk"
            finalScore <= 6 -> "High Risk"
            else            -> "Very High Risk"
        }

        return Result(
            finalScore, riskLevel, chairScore, peripheralScore,
            seatHeightScore, backrestScore, armrestScore,
            monitorScore, keyboardScore, mouseScore,
        )
    }
}
