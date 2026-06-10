package com.ooplab.exercises_fitfuel

import kotlin.math.*

object RosaAnglesCalculator {

    private const val NOSE           = 0
    private const val LEFT_EAR       = 7
    private const val RIGHT_EAR      = 8
    private const val LEFT_SHOULDER  = 11
    private const val RIGHT_SHOULDER = 12
    private const val LEFT_ELBOW     = 13
    private const val RIGHT_ELBOW    = 14
    private const val LEFT_WRIST     = 15
    private const val RIGHT_WRIST    = 16
    private const val LEFT_HIP       = 23
    private const val RIGHT_HIP      = 24
    private const val LEFT_KNEE      = 25
    private const val RIGHT_KNEE     = 26
    private const val LEFT_ANKLE     = 27
    private const val RIGHT_ANKLE    = 28

    enum class NeckState { NEUTRAL, FORWARD_HEAD, MILD_FLEXION, SEVERE_FLEXION, HEAD_BACK }

    // HIGH = knee angle is measured (or proxied from a visible knee); LOW = the
    // knee itself was occluded and reconstructed, so the seat-height score is
    // a best-effort guess.
    enum class LowerBodyConfidence { HIGH, LOW }

    data class Angles(
        val isLeftSide: Boolean,    // which side was selected (true = left landmarks used)
        val kneeAngle: Float,       // degrees — seat height
        val trunkAngle: Float,      // degrees from vertical — backrest
        val elbowAngle: Float,      // degrees shoulder→elbow→wrist — arm/keyboard
        val neckAngle: Float,       // degrees from vertical — neck/monitor score
        val shrugGap: Float,        // ear.y − shoulder.y — armrest
        val neckFlexY: Float,       // ear.y − nose.y — neck flexion (raw)
        val neckState: NeckState,   // derived neck posture state — used for ROSA scoring
        val wristExtension: Float,  // elbow.y − wrist.y — keyboard
        val mouseReach: Float,      // |wrist.x − shoulder.x| — mouse
        val lowerBodyConfidence: LowerBodyConfidence, // reliability of kneeAngle
    )

    fun compute(lm: List<LandmarkPoint>): Angles? {
        if (lm.size < 29) return null

        val nose = lm[NOSE]

        // Near (visible) side — in a side view the near ear sits farther from
        // the nose in 2D than the occluded far ear.
        val leftEarDist  = hypot(nose.x - lm[LEFT_EAR].x,  nose.y - lm[LEFT_EAR].y)
        val rightEarDist = hypot(nose.x - lm[RIGHT_EAR].x, nose.y - lm[RIGHT_EAR].y)
        val useLeft = leftEarDist >= rightEarDist

        val ear      = if (useLeft) lm[LEFT_EAR]      else lm[RIGHT_EAR]
        val shoulder = if (useLeft) lm[LEFT_SHOULDER]  else lm[RIGHT_SHOULDER]
        val elbow    = if (useLeft) lm[LEFT_ELBOW]     else lm[RIGHT_ELBOW]
        val wrist    = if (useLeft) lm[LEFT_WRIST]     else lm[RIGHT_WRIST]
        val hip      = if (useLeft) lm[LEFT_HIP]       else lm[RIGHT_HIP]
        val knee     = if (useLeft) lm[LEFT_KNEE]      else lm[RIGHT_KNEE]
        val ankle    = if (useLeft) lm[LEFT_ANKLE]     else lm[RIGHT_ANKLE]

        // Knee/ankle may be reconstructed (LegEstimator) when occluded. A fabricated
        // ankle straight below the knee distorts angleBetween(), so when only the
        // ankle is estimated, fall back to a hip-knee vertical-gap proxy — the same
        // category a trained observer would read off a visible knee. If the knee
        // itself is estimated, keep the geometric angle but flag low confidence.
        val gapProxyAngle = when {
            (knee.y - hip.y) < -0.02f -> 70f
            (knee.y - hip.y) > 0.15f  -> 115f
            else                      -> 92f
        }
        val (kneeAngle, lowerBodyConfidence) = when {
            knee.estimated -> gapProxyAngle to LowerBodyConfidence.LOW
            ankle.estimated -> gapProxyAngle to LowerBodyConfidence.HIGH
            else -> {
                val measured = angleBetween(hip, knee, ankle)
                // >160° is essentially a straight leg — implausible while seated and
                // more likely a pose-estimation glitch than a real measurement.
                if (measured > 160f) gapProxyAngle to LowerBodyConfidence.LOW
                else measured to LowerBodyConfidence.HIGH
            }
        }
        val elbowAngle = angleBetween(shoulder, elbow, wrist)

        val dx = abs(hip.x - shoulder.x).toDouble()
        val dy = abs(hip.y - shoulder.y).toDouble()
        val trunkAngle = if (dy < 1e-6) 90f else (atan2(dx, dy) * (180.0 / PI)).toFloat()

        val neckDx    = abs(ear.x - shoulder.x).toDouble()
        val neckDy    = abs(shoulder.y - ear.y).toDouble()
        val neckAngle = if (neckDy < 1e-6) 90f else (atan2(neckDx, neckDy) * (180.0 / PI)).toFloat()

        val shrugGap        = ear.y - shoulder.y
        val neckFlexY       = ear.y - nose.y
        val noseAboveEar    = nose.y - ear.y
        val earForward      = shoulder.x - ear.x
        val earShoulderVert = abs(ear.y - shoulder.y)

        val neckState = when {
            noseAboveEar > 0.03f                               -> NeckState.HEAD_BACK
            earShoulderVert < 0.06f && neckFlexY > 0f         -> NeckState.SEVERE_FLEXION
            neckFlexY > 0.04f                                  -> NeckState.MILD_FLEXION
            earForward > 0.04f                                 -> NeckState.FORWARD_HEAD
            else                                               -> NeckState.NEUTRAL
        }

        val wristExtension = elbow.y - wrist.y
        val mouseReach     = abs(wrist.x - shoulder.x)

        return Angles(useLeft, kneeAngle, trunkAngle, elbowAngle, neckAngle, shrugGap, neckFlexY, neckState, wristExtension, mouseReach, lowerBodyConfidence)
    }

    private fun angleBetween(p1: LandmarkPoint, vertex: LandmarkPoint, p2: LandmarkPoint): Float {
        val ax = (p1.x - vertex.x).toDouble()
        val ay = (p1.y - vertex.y).toDouble()
        val bx = (p2.x - vertex.x).toDouble()
        val by = (p2.y - vertex.y).toDouble()
        val dot = ax * bx + ay * by
        val m1  = sqrt(ax * ax + ay * ay)
        val m2  = sqrt(bx * bx + by * by)
        if (m1 < 1e-6 || m2 < 1e-6) return 90f
        return (acos((dot / (m1 * m2)).coerceIn(-1.0, 1.0)) * (180.0 / PI)).toFloat()
    }
}
