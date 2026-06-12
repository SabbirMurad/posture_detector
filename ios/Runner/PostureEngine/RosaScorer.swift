import Foundation

/// Full ROSA checklist scoring. Direct port of the Kotlin `RosaScorer`.
enum RosaScorer {

    // ── Lookup tables (Cornell / Sonne 2012, verified against 71-photo reference) ──

    private static let tableA: [Int: [Int: Int]] = [
        2: [2: 2, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6, 8: 7, 9: 8],
        3: [2: 2, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6, 8: 7, 9: 8],
        4: [2: 3, 3: 3, 4: 3, 5: 4, 6: 5, 7: 6, 8: 7, 9: 8],
        5: [2: 4, 3: 4, 4: 4, 5: 4, 6: 5, 7: 6, 8: 7, 9: 8],
        6: [2: 5, 3: 5, 4: 5, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9],
        7: [2: 6, 3: 6, 4: 6, 5: 7, 6: 7, 7: 8, 8: 8, 9: 9],
        8: [2: 7, 3: 7, 4: 7, 5: 8, 6: 8, 7: 9, 8: 9, 9: 9],
    ]

    private static let tableB: [Int: [Int: Int]] = [
        0: [0: 1, 1: 1, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6],
        1: [0: 1, 1: 1, 2: 2, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6],
        2: [0: 1, 1: 2, 2: 2, 3: 3, 4: 3, 5: 4, 6: 6, 7: 7],
        3: [0: 2, 1: 2, 2: 3, 3: 3, 4: 4, 5: 5, 6: 6, 7: 8],
        4: [0: 3, 1: 3, 2: 4, 3: 4, 4: 5, 5: 6, 6: 7, 7: 8],
        5: [0: 4, 1: 4, 2: 5, 3: 5, 4: 6, 5: 7, 6: 8, 7: 9],
        6: [0: 5, 1: 5, 2: 6, 3: 7, 4: 8, 5: 8, 6: 9, 7: 9],
    ]

    private static let tableC: [Int: [Int: Int]] = [
        0: [0: 1, 1: 1, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6],
        1: [0: 1, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7],
        2: [0: 1, 1: 2, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7],
        3: [0: 2, 1: 3, 2: 3, 3: 3, 4: 5, 5: 6, 6: 7, 7: 8],
        4: [0: 3, 1: 4, 2: 4, 3: 5, 4: 5, 5: 6, 6: 7, 7: 8],
        5: [0: 4, 1: 5, 2: 5, 3: 6, 4: 6, 5: 7, 6: 8, 7: 9],
        6: [0: 5, 1: 6, 2: 6, 3: 7, 4: 7, 5: 8, 6: 8, 7: 9],
        7: [0: 6, 1: 7, 2: 7, 3: 8, 4: 8, 5: 9, 6: 9, 7: 9],
    ]

    /// Clamps row and col to the table's actual key range, then returns the value.
    private static func tlu(_ table: [Int: [Int: Int]], _ row: Int, _ col: Int) -> Int {
        let rowKeys = table.keys
        let r = min(max(row, rowKeys.min()!), rowKeys.max()!)
        let colKeys = table[r]!.keys
        let c = min(max(col, colKeys.min()!), colKeys.max()!)
        return table[r]![c]!
    }

    // ── Manual checklist answers (things the camera can't see) ─────────────────────
    struct WorkstationModifiers {
        // Section A — Chair
        var chairHeightNonAdjustable = false
        var insufficientUnderDeskSpace = false
        var seatDepthScore = 1            // 1 = ~3in clearance, 2 = too long/short
        var seatPanNonAdjustable = false
        var armrestNonAdjustable = false
        var armrestHardDamaged = false
        var armrestTooWide = false
        var backrestNonAdjustable = false
        var workSurfaceTooHigh = false
        // Section B — Monitor & Telephone
        var monitorNonAdjustable = false
        var neckTwistOver30 = false
        var monitorTooFar = false
        var screenGlare = false
        var noDocumentHolder = false
        var phoneScore = 0               // 0 = none, 1 = headset/one-hand, 2 = reach far
        var phoneCradleNeckShoulder = false
        var noHandsFreeOption = false
        // Section C — Mouse & Keyboard
        var mouseKeyboardDifferentSurfaces = false
        var mousePinchGrip = false
        var mousePalmrest = false
        var mouseNonAdjustable = false
        var keyboardDeviation = false
        var keyboardTooHigh = false
        var reachingOverhead = false
        var keyboardPlatformNonAdjustable = false
        // Duration: -1, 0, or +1 — applies to chair, monitor/phone, and mouse/keyboard
        var durationModifier = 0

        static func fromMap(_ m: [String: Any]?) -> WorkstationModifiers {
            guard let m = m else { return WorkstationModifiers() }
            func b(_ key: String) -> Bool { (m[key] as? Bool) ?? false }
            func i(_ key: String, _ def: Int) -> Int {
                if let v = m[key] as? Int { return v }
                if let v = m[key] as? NSNumber { return v.intValue }
                return def
            }
            var w = WorkstationModifiers()
            w.chairHeightNonAdjustable = b("chair_height_non_adjustable")
            w.insufficientUnderDeskSpace = b("insufficient_under_desk_space")
            w.seatDepthScore = i("seat_depth_score", 1)
            w.seatPanNonAdjustable = b("seat_pan_non_adjustable")
            w.armrestNonAdjustable = b("armrest_non_adjustable")
            w.armrestHardDamaged = b("armrest_hard_damaged")
            w.armrestTooWide = b("armrest_too_wide")
            w.backrestNonAdjustable = b("backrest_non_adjustable")
            w.workSurfaceTooHigh = b("work_surface_too_high")
            w.monitorNonAdjustable = b("monitor_non_adjustable")
            w.neckTwistOver30 = b("neck_twist_over_30")
            w.monitorTooFar = b("monitor_too_far")
            w.screenGlare = b("screen_glare")
            w.noDocumentHolder = b("no_document_holder")
            w.phoneScore = i("phone_score", 0)
            w.phoneCradleNeckShoulder = b("phone_cradle_neck_shoulder")
            w.noHandsFreeOption = b("no_hands_free_option")
            w.mouseKeyboardDifferentSurfaces = b("mouse_keyboard_different_surfaces")
            w.mousePinchGrip = b("mouse_pinch_grip")
            w.mousePalmrest = b("mouse_palmrest")
            w.mouseNonAdjustable = b("mouse_non_adjustable")
            w.keyboardDeviation = b("keyboard_deviation")
            w.keyboardTooHigh = b("keyboard_too_high")
            w.reachingOverhead = b("reaching_overhead")
            w.keyboardPlatformNonAdjustable = b("keyboard_platform_non_adjustable")
            w.durationModifier = i("duration_modifier", 0)
            return w
        }
    }

    // ── Result ────────────────────────────────────────────────────────────────────

    struct Result {
        let finalScore: Int
        let riskLevel: String
        let chairScore: Int
        let peripheralScore: Int
        let monitorAreaScore: Int
        let mouseKeyboardAreaScore: Int
        let seatHeightScore: Int
        let backrestScore: Int
        let armrestScore: Int
        let monitorScore: Int
        let keyboardScore: Int
        let mouseScore: Int
        let lowerBodyConfidence: String

        /// snake_case map matching what the Android `MainActivity` hands to Flutter,
        /// so `RosaScore.fromMap` on the Dart side parses it identically.
        func toMap() -> [String: Any] {
            [
                "final_score": finalScore,
                "risk_level": riskLevel,
                "chair_score": chairScore,
                "peripheral_score": peripheralScore,
                "monitor_area_score": monitorAreaScore,
                "mouse_keyboard_area_score": mouseKeyboardAreaScore,
                "seat_height_score": seatHeightScore,
                "backrest_score": backrestScore,
                "armrest_score": armrestScore,
                "monitor_score": monitorScore,
                "keyboard_score": keyboardScore,
                "mouse_score": mouseScore,
                "lower_body_confidence": lowerBodyConfidence,
            ]
        }
    }

    // ── Scoring ───────────────────────────────────────────────────────────────────

    static func score(_ angles: RosaAnglesCalculator.Angles,
                      mods: WorkstationModifiers = WorkstationModifiers()) -> Result {
        // ── CHAIR ─────────────────────────────────────────────────────────────────
        let seatHeightScore: Int
        if angles.kneeAngle < 80 {
            seatHeightScore = 2       // chair too low
        } else if angles.kneeAngle > 130 {
            seatHeightScore = 3       // legs nearly extended — feet off floor
        } else if angles.kneeAngle > 100 {
            seatHeightScore = 2       // chair too high
        } else {
            seatHeightScore = 1       // neutral
        }
        let backrestScore = angles.trunkAngle > 28 ? 2 : 1
        // shrugGap = ear.y − shoulder.y; > −0.06 means shoulder hiked toward ear
        let armrestScore = angles.shrugGap > -0.06 ? 2 : 1

        // Area scores = camera-derived base + manual checklist modifiers (per ROSA form)
        let chairHeightArea = seatHeightScore
            + (mods.chairHeightNonAdjustable ? 1 : 0)
            + (mods.insufficientUnderDeskSpace ? 1 : 0)
        let panDepthArea = mods.seatDepthScore
            + (mods.seatPanNonAdjustable ? 1 : 0)
        let armrestArea = armrestScore
            + (mods.armrestNonAdjustable ? 1 : 0)
            + (mods.armrestHardDamaged ? 1 : 0)
            + (mods.armrestTooWide ? 1 : 0)
        let backSupportArea = backrestScore
            + (mods.backrestNonAdjustable ? 1 : 0)
            + (mods.workSurfaceTooHigh ? 1 : 0)

        let seatCombined = clamp(chairHeightArea + panDepthArea, 2, 8)
        let armsCombined = clamp(armrestArea + backSupportArea, 2, 9)
        let chairScore = clamp(tlu(tableA, seatCombined, armsCombined) + mods.durationModifier, 1, 10)

        // ── MONITOR ───────────────────────────────────────────────────────────────
        let monitorScore: Int
        switch angles.neckState {
        case .headBack: monitorScore = 3
        case .severeFlexion: monitorScore = 3
        case .mildFlexion: monitorScore = 2
        case .forwardHead: monitorScore = 2
        case .neutral: monitorScore = 1
        }
        let monitorArea = monitorScore
            + (mods.monitorNonAdjustable ? 1 : 0)
            + (mods.neckTwistOver30 ? 1 : 0)
            + (mods.monitorTooFar ? 1 : 0)
            + (mods.screenGlare ? 1 : 0)
            + (mods.noDocumentHolder ? 1 : 0)

        // Telephone — base score (none/headset/reach far) + cradle/hands-free modifiers
        let phoneArea = mods.phoneScore
            + (mods.phoneCradleNeckShoulder ? 2 : 0)
            + (mods.noHandsFreeOption ? 1 : 0)

        let sectB = tlu(tableB,
                        clamp(phoneArea + mods.durationModifier, 0, 6),
                        clamp(monitorArea + mods.durationModifier, 0, 7))

        // ── KEYBOARD ──────────────────────────────────────────────────────────────
        let keyboardScore: Int
        if angles.wristExtension > 0.07 {
            keyboardScore = 3
        } else if angles.wristExtension > 0.03 {
            keyboardScore = 2
        } else {
            keyboardScore = 1
        }
        let keyboardArea = keyboardScore
            + (mods.keyboardDeviation ? 1 : 0)
            + (mods.keyboardTooHigh ? 1 : 0)
            + (mods.reachingOverhead ? 1 : 0)
            + (mods.keyboardPlatformNonAdjustable ? 1 : 0)

        // ── MOUSE ─────────────────────────────────────────────────────────────────
        let mouseScore = angles.mouseReach > 0.18 ? 2 : 1
        let mouseArea = mouseScore
            + (mods.mouseKeyboardDifferentSurfaces ? 2 : 0)
            + (mods.mousePinchGrip ? 1 : 0)
            + (mods.mousePalmrest ? 1 : 0)
            + (mods.mouseNonAdjustable ? 1 : 0)

        let sectC = tlu(tableC,
                        clamp(mouseArea + mods.durationModifier, 0, 7),
                        clamp(keyboardArea + mods.durationModifier, 0, 7))

        // ── COMBINE ───────────────────────────────────────────────────────────────
        // Table D and E both use max(row, col) — "worst section wins"
        let peripheralScore = clamp(max(sectB, sectC), 1, 9)
        let finalScore = clamp(max(chairScore, peripheralScore), 1, 10)

        let riskLevel: String
        if finalScore <= 2 {
            riskLevel = "Low Risk"
        } else if finalScore <= 4 {
            riskLevel = "Medium Risk"
        } else if finalScore <= 6 {
            riskLevel = "High Risk"
        } else {
            riskLevel = "Very High Risk"
        }

        return Result(
            finalScore: finalScore,
            riskLevel: riskLevel,
            chairScore: chairScore,
            peripheralScore: peripheralScore,
            monitorAreaScore: sectB,
            mouseKeyboardAreaScore: sectC,
            seatHeightScore: seatHeightScore,
            backrestScore: backrestScore,
            armrestScore: armrestScore,
            monitorScore: monitorScore,
            keyboardScore: keyboardScore,
            mouseScore: mouseScore,
            lowerBodyConfidence: angles.lowerBodyConfidence.rawValue
        )
    }

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
}
