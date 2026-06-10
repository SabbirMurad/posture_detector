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

    // ── Manual checklist answers (things the camera can't see) ─────────────────────
    // Field names mirror the official ROSA form's +1/+2 modifiers and area scores.
    data class WorkstationModifiers(
        // Section A — Chair
        val chairHeightNonAdjustable: Boolean = false,
        val insufficientUnderDeskSpace: Boolean = false,
        val seatDepthScore: Int = 1,           // 1 = ~3in clearance, 2 = too long/short
        val seatPanNonAdjustable: Boolean = false,
        val armrestNonAdjustable: Boolean = false,
        val armrestHardDamaged: Boolean = false,
        val armrestTooWide: Boolean = false,
        val backrestNonAdjustable: Boolean = false,
        val workSurfaceTooHigh: Boolean = false,
        // Section B — Monitor & Telephone
        val monitorNonAdjustable: Boolean = false,
        val neckTwistOver30: Boolean = false,
        val monitorTooFar: Boolean = false,
        val screenGlare: Boolean = false,
        val noDocumentHolder: Boolean = false,
        val phoneScore: Int = 0,               // 0 = none, 1 = headset/one-hand, 2 = reach far
        val phoneCradleNeckShoulder: Boolean = false,
        val noHandsFreeOption: Boolean = false,
        // Section C — Mouse & Keyboard
        val mouseKeyboardDifferentSurfaces: Boolean = false,
        val mousePinchGrip: Boolean = false,
        val mousePalmrest: Boolean = false,
        val mouseNonAdjustable: Boolean = false,
        val keyboardDeviation: Boolean = false,
        val keyboardTooHigh: Boolean = false,
        val reachingOverhead: Boolean = false,
        val keyboardPlatformNonAdjustable: Boolean = false,
        // Duration: -1, 0, or +1 — applies to chair, monitor/phone, and mouse/keyboard
        val durationModifier: Int = 0,
    ) {
        companion object {
            fun fromMap(m: Map<*, *>?): WorkstationModifiers {
                if (m == null) return WorkstationModifiers()
                fun b(key: String) = (m[key] as? Boolean) ?: false
                fun i(key: String, default: Int) = (m[key] as? Int) ?: (m[key] as? Long)?.toInt() ?: default
                return WorkstationModifiers(
                    chairHeightNonAdjustable      = b("chair_height_non_adjustable"),
                    insufficientUnderDeskSpace    = b("insufficient_under_desk_space"),
                    seatDepthScore                = i("seat_depth_score", 1),
                    seatPanNonAdjustable          = b("seat_pan_non_adjustable"),
                    armrestNonAdjustable          = b("armrest_non_adjustable"),
                    armrestHardDamaged            = b("armrest_hard_damaged"),
                    armrestTooWide                = b("armrest_too_wide"),
                    backrestNonAdjustable         = b("backrest_non_adjustable"),
                    workSurfaceTooHigh            = b("work_surface_too_high"),
                    monitorNonAdjustable          = b("monitor_non_adjustable"),
                    neckTwistOver30               = b("neck_twist_over_30"),
                    monitorTooFar                 = b("monitor_too_far"),
                    screenGlare                   = b("screen_glare"),
                    noDocumentHolder              = b("no_document_holder"),
                    phoneScore                    = i("phone_score", 0),
                    phoneCradleNeckShoulder       = b("phone_cradle_neck_shoulder"),
                    noHandsFreeOption             = b("no_hands_free_option"),
                    mouseKeyboardDifferentSurfaces = b("mouse_keyboard_different_surfaces"),
                    mousePinchGrip                = b("mouse_pinch_grip"),
                    mousePalmrest                 = b("mouse_palmrest"),
                    mouseNonAdjustable            = b("mouse_non_adjustable"),
                    keyboardDeviation             = b("keyboard_deviation"),
                    keyboardTooHigh               = b("keyboard_too_high"),
                    reachingOverhead              = b("reaching_overhead"),
                    keyboardPlatformNonAdjustable = b("keyboard_platform_non_adjustable"),
                    durationModifier              = i("duration_modifier", 0),
                )
            }
        }
    }

    // ── Result ────────────────────────────────────────────────────────────────────

    data class Result(
        val finalScore: Int,
        val riskLevel: String,
        val chairScore: Int,
        val peripheralScore: Int,
        val monitorAreaScore: Int,
        val mouseKeyboardAreaScore: Int,
        val seatHeightScore: Int,
        val backrestScore: Int,
        val armrestScore: Int,
        val monitorScore: Int,
        val keyboardScore: Int,
        val mouseScore: Int,
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "finalScore"             to finalScore,
            "riskLevel"              to riskLevel,
            "chairScore"             to chairScore,
            "peripheralScore"        to peripheralScore,
            "monitorAreaScore"       to monitorAreaScore,
            "mouseKeyboardAreaScore" to mouseKeyboardAreaScore,
            "seatHeightScore"        to seatHeightScore,
            "backrestScore"          to backrestScore,
            "armrestScore"           to armrestScore,
            "monitorScore"           to monitorScore,
            "keyboardScore"          to keyboardScore,
            "mouseScore"             to mouseScore,
        )
    }

    // ── Scoring ───────────────────────────────────────────────────────────────────

    fun score(
        angles: RosaAnglesCalculator.Angles,
        mods: WorkstationModifiers = WorkstationModifiers(),
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

        // Area scores = camera-derived base + manual checklist modifiers (per ROSA form)
        val chairHeightArea = seatHeightScore +
            (if (mods.chairHeightNonAdjustable) 1 else 0) +
            (if (mods.insufficientUnderDeskSpace) 1 else 0)
        val panDepthArea = mods.seatDepthScore +
            (if (mods.seatPanNonAdjustable) 1 else 0)
        val armrestArea = armrestScore +
            (if (mods.armrestNonAdjustable) 1 else 0) +
            (if (mods.armrestHardDamaged) 1 else 0) +
            (if (mods.armrestTooWide) 1 else 0)
        val backSupportArea = backrestScore +
            (if (mods.backrestNonAdjustable) 1 else 0) +
            (if (mods.workSurfaceTooHigh) 1 else 0)

        val seatCombined = (chairHeightArea + panDepthArea).coerceIn(2, 8)
        val armsCombined = (armrestArea + backSupportArea).coerceIn(2, 9)
        val chairScore   = (tlu(tableA, seatCombined, armsCombined) + mods.durationModifier).coerceIn(1, 10)

        // ── MONITOR ───────────────────────────────────────────────────────────────
        val monitorScore = when (angles.neckState) {
            RosaAnglesCalculator.NeckState.HEAD_BACK      -> 3
            RosaAnglesCalculator.NeckState.SEVERE_FLEXION -> 3
            RosaAnglesCalculator.NeckState.MILD_FLEXION   -> 2
            RosaAnglesCalculator.NeckState.FORWARD_HEAD   -> 2
            RosaAnglesCalculator.NeckState.NEUTRAL        -> 1
        }
        val monitorArea = monitorScore +
            (if (mods.monitorNonAdjustable) 1 else 0) +
            (if (mods.neckTwistOver30) 1 else 0) +
            (if (mods.monitorTooFar) 1 else 0) +
            (if (mods.screenGlare) 1 else 0) +
            (if (mods.noDocumentHolder) 1 else 0)

        // Telephone — base score (none/headset/reach far) + cradle/hands-free modifiers
        val phoneArea = mods.phoneScore +
            (if (mods.phoneCradleNeckShoulder) 2 else 0) +
            (if (mods.noHandsFreeOption) 1 else 0)

        val sectB = tlu(tableB,
            (phoneArea + mods.durationModifier).coerceIn(0, 6),
            (monitorArea + mods.durationModifier).coerceIn(0, 7))

        // ── KEYBOARD ──────────────────────────────────────────────────────────────
        val keyboardScore = when {
            angles.wristExtension > 0.07f -> 3
            angles.wristExtension > 0.03f -> 2
            else                          -> 1
        }
        val keyboardArea = keyboardScore +
            (if (mods.keyboardDeviation) 1 else 0) +
            (if (mods.keyboardTooHigh) 1 else 0) +
            (if (mods.reachingOverhead) 1 else 0) +
            (if (mods.keyboardPlatformNonAdjustable) 1 else 0)

        // ── MOUSE ─────────────────────────────────────────────────────────────────
        val mouseScore = if (angles.mouseReach > 0.18f) 2 else 1
        val mouseArea = mouseScore +
            (if (mods.mouseKeyboardDifferentSurfaces) 2 else 0) +
            (if (mods.mousePinchGrip) 1 else 0) +
            (if (mods.mousePalmrest) 1 else 0) +
            (if (mods.mouseNonAdjustable) 1 else 0)

        val sectC = tlu(tableC,
            (mouseArea + mods.durationModifier).coerceIn(0, 7),
            (keyboardArea + mods.durationModifier).coerceIn(0, 7))

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
            sectB, sectC,
            seatHeightScore, backrestScore, armrestScore,
            monitorScore, keyboardScore, mouseScore,
        )
    }
}
