import Foundation

/// Computes the ROSA-relevant body angles from a side-view set of landmarks.
/// Direct port of the Kotlin `RosaAnglesCalculator`.
enum RosaAnglesCalculator {

    private static let NOSE = 0
    private static let LEFT_EAR = 7
    private static let RIGHT_EAR = 8
    private static let LEFT_SHOULDER = 11
    private static let RIGHT_SHOULDER = 12
    private static let LEFT_ELBOW = 13
    private static let RIGHT_ELBOW = 14
    private static let LEFT_WRIST = 15
    private static let RIGHT_WRIST = 16
    private static let LEFT_HIP = 23
    private static let RIGHT_HIP = 24
    private static let LEFT_KNEE = 25
    private static let RIGHT_KNEE = 26
    private static let LEFT_ANKLE = 27
    private static let RIGHT_ANKLE = 28

    enum NeckState { case neutral, forwardHead, mildFlexion, severeFlexion, headBack }

    /// HIGH = knee angle is measured (or proxied from a visible knee); LOW = the
    /// knee itself was occluded and reconstructed, so the seat-height score is a
    /// best-effort guess. Raw value mirrors the Kotlin enum name for the bridge.
    enum LowerBodyConfidence: String { case high = "HIGH", low = "LOW" }

    struct Angles {
        let isLeftSide: Bool
        let kneeAngle: Float
        let trunkAngle: Float
        let elbowAngle: Float
        let neckAngle: Float
        let shrugGap: Float
        let neckFlexY: Float
        let neckState: NeckState
        let wristExtension: Float
        let mouseReach: Float
        let lowerBodyConfidence: LowerBodyConfidence
    }

    static func compute(_ lm: [LandmarkPoint]) -> Angles? {
        if lm.count < 29 { return nil }

        let nose = lm[NOSE]

        // Near (visible) side — in a side view the near ear sits farther from
        // the nose in 2D than the occluded far ear.
        let leftEarDist = hypotf(nose.x - lm[LEFT_EAR].x, nose.y - lm[LEFT_EAR].y)
        let rightEarDist = hypotf(nose.x - lm[RIGHT_EAR].x, nose.y - lm[RIGHT_EAR].y)
        let useLeft = leftEarDist >= rightEarDist

        let ear = useLeft ? lm[LEFT_EAR] : lm[RIGHT_EAR]
        let shoulder = useLeft ? lm[LEFT_SHOULDER] : lm[RIGHT_SHOULDER]
        let elbow = useLeft ? lm[LEFT_ELBOW] : lm[RIGHT_ELBOW]
        let wrist = useLeft ? lm[LEFT_WRIST] : lm[RIGHT_WRIST]
        let hip = useLeft ? lm[LEFT_HIP] : lm[RIGHT_HIP]
        let knee = useLeft ? lm[LEFT_KNEE] : lm[RIGHT_KNEE]
        let ankle = useLeft ? lm[LEFT_ANKLE] : lm[RIGHT_ANKLE]

        // Knee/ankle may be reconstructed (LegEstimator) when occluded. A fabricated
        // ankle straight below the knee distorts angleBetween(), so when only the
        // ankle is estimated, fall back to a hip-knee vertical-gap proxy.
        let gapProxyAngle: Float
        if (knee.y - hip.y) < -0.02 {
            gapProxyAngle = 70
        } else if (knee.y - hip.y) > 0.15 {
            gapProxyAngle = 115
        } else {
            gapProxyAngle = 92
        }

        let kneeAngle: Float
        let lowerBodyConfidence: LowerBodyConfidence
        if knee.estimated {
            kneeAngle = gapProxyAngle
            lowerBodyConfidence = .low
        } else if ankle.estimated {
            kneeAngle = gapProxyAngle
            lowerBodyConfidence = .high
        } else {
            let measured = angleBetween(hip, knee, ankle)
            // >160° is essentially a straight leg — implausible while seated and
            // more likely a pose-estimation glitch than a real measurement.
            if measured > 160 {
                kneeAngle = gapProxyAngle
                lowerBodyConfidence = .low
            } else {
                kneeAngle = measured
                lowerBodyConfidence = .high
            }
        }

        let elbowAngle = angleBetween(shoulder, elbow, wrist)

        let dx = Double(abs(hip.x - shoulder.x))
        let dy = Double(abs(hip.y - shoulder.y))
        let trunkAngle: Float = dy < 1e-6 ? 90 : Float(atan2(dx, dy) * (180.0 / .pi))

        let neckDx = Double(abs(ear.x - shoulder.x))
        let neckDy = Double(abs(shoulder.y - ear.y))
        let neckAngle: Float = neckDy < 1e-6 ? 90 : Float(atan2(neckDx, neckDy) * (180.0 / .pi))

        let shrugGap = ear.y - shoulder.y
        let neckFlexY = ear.y - nose.y
        let noseAboveEar = nose.y - ear.y
        let earForward = shoulder.x - ear.x
        let earShoulderVert = abs(ear.y - shoulder.y)

        let neckState: NeckState
        if noseAboveEar > 0.03 {
            neckState = .headBack
        } else if earShoulderVert < 0.06 && neckFlexY > 0 {
            neckState = .severeFlexion
        } else if neckFlexY > 0.04 {
            neckState = .mildFlexion
        } else if earForward > 0.04 {
            neckState = .forwardHead
        } else {
            neckState = .neutral
        }

        let wristExtension = elbow.y - wrist.y
        let mouseReach = abs(wrist.x - shoulder.x)

        return Angles(
            isLeftSide: useLeft,
            kneeAngle: kneeAngle,
            trunkAngle: trunkAngle,
            elbowAngle: elbowAngle,
            neckAngle: neckAngle,
            shrugGap: shrugGap,
            neckFlexY: neckFlexY,
            neckState: neckState,
            wristExtension: wristExtension,
            mouseReach: mouseReach,
            lowerBodyConfidence: lowerBodyConfidence
        )
    }

    private static func angleBetween(_ p1: LandmarkPoint, _ vertex: LandmarkPoint, _ p2: LandmarkPoint) -> Float {
        let ax = Double(p1.x - vertex.x)
        let ay = Double(p1.y - vertex.y)
        let bx = Double(p2.x - vertex.x)
        let by = Double(p2.y - vertex.y)
        let dot = ax * bx + ay * by
        let m1 = (ax * ax + ay * ay).squareRoot()
        let m2 = (bx * bx + by * by).squareRoot()
        if m1 < 1e-6 || m2 < 1e-6 { return 90 }
        let cosv = min(max(dot / (m1 * m2), -1.0), 1.0)
        return Float(acos(cosv) * (180.0 / .pi))
    }
}
