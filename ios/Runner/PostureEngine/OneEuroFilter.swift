import Foundation

/// One Euro Filter for smoothing a single float signal in real-time.
///
/// minCutoff: lower → smoother when still, more lag (try 1.0–2.0)
/// beta:      higher → less lag during fast movement (try 0.005–0.05)
/// dCutoff:   cutoff for the derivative low-pass (1.0 is fine)
///
/// Direct port of the Kotlin `OneEuroFilter`.
final class OneEuroFilter {
    private let minCutoff: Float
    private let beta: Float
    private let dCutoff: Float

    private var xHat: Float?
    private var dxHat: Float = 0
    private var lastTimestamp: Double = 0

    init(minCutoff: Float = 1.5, beta: Float = 0.01, dCutoff: Float = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    func filter(_ x: Float, timestampSec: Double) -> Float {
        guard let prev = xHat else {
            xHat = x
            lastTimestamp = timestampSec
            return x
        }
        let dt = max(Float(timestampSec - lastTimestamp), 1e-6)
        lastTimestamp = timestampSec

        let dx = (x - prev) / dt
        dxHat = lowPass(dx, dxHat, alpha(dCutoff, dt))

        let cutoff = minCutoff + beta * abs(dxHat)
        let result = lowPass(x, prev, alpha(cutoff, dt))
        xHat = result
        return result
    }

    func reset() {
        xHat = nil
        dxHat = 0
        lastTimestamp = 0
    }

    private func alpha(_ cutoff: Float, _ dt: Float) -> Float {
        let r = 2 * Float.pi * cutoff * dt
        return r / (r + 1)
    }

    private func lowPass(_ x: Float, _ prev: Float, _ a: Float) -> Float {
        a * x + (1 - a) * prev
    }
}
