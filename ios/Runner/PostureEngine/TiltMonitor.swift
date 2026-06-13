import CoreMotion
import Foundation

/// Reports phone tilt (inclination from horizontal) and lateral roll, derived from
/// the accelerometer. Port of the Kotlin `TiltMonitor`, using CoreMotion.
///
/// Axis note: iOS reports gravity as roughly (0, -1, 0) when held upright in
/// portrait, whereas Android's accelerometer reports (0, +g, 0). We negate the iOS
/// readings so the same formulas (tilt ≈ 90° upright, roll ≈ 0° level) hold.
final class TiltMonitor {

    static let MIN_TILT = 85.0
    static let MAX_TILT = 95.0
    static let MAX_ROLL = 15.0

    static func isTiltAcceptable(_ angle: Double) -> Bool { angle >= MIN_TILT && angle <= MAX_TILT }
    static func isRollAcceptable(_ roll: Double) -> Bool { abs(roll) <= MAX_ROLL }

    private static let ALPHA: Float = 0.1

    private let motionManager = CMMotionManager()
    private let onAnglesChanged: (_ tiltAngle: Double, _ rollAngle: Double) -> Void

    private var fx: Float = 0, fy: Float = 0, fz: Float = 0
    private var initialized = false

    init(onAnglesChanged: @escaping (_ tiltAngle: Double, _ rollAngle: Double) -> Void) {
        self.onAnglesChanged = onAnglesChanged
    }

    func start() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 1.0 / 30.0
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let a = data?.acceleration else { return }
            // Negate to match the Android accelerometer sign convention.
            self.onSample(x: Float(-a.x), y: Float(-a.y), z: Float(-a.z))
        }
    }

    func stop() {
        motionManager.stopAccelerometerUpdates()
    }

    private func onSample(x: Float, y: Float, z: Float) {
        if !initialized {
            fx = x; fy = y; fz = z; initialized = true
        } else {
            fx += Self.ALPHA * (x - fx)
            fy += Self.ALPHA * (y - fy)
            fz += Self.ALPHA * (z - fz)
        }

        // Inclination from horizontal: 0° = lying flat, 90° = perfectly upright portrait
        let tilt = atan2(Double(fy), Double((fx * fx + fz * fz).squareRoot())) * (180.0 / .pi)
        // Lateral roll: when upright fy ≈ g and fx ≈ 0; tilting left/right shifts fx.
        let roll = atan2(Double(fx), Double(fy)) * (180.0 / .pi)

        onAnglesChanged(tilt, roll)
    }
}
