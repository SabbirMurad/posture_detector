import Foundation

/// A smoothed / possibly-reconstructed 2D landmark in normalised image space (0–1).
/// Mirrors the Kotlin `LandmarkPoint`.
struct LandmarkPoint {
    let x: Float
    let y: Float
    let estimated: Bool

    init(x: Float, y: Float, estimated: Bool = false) {
        self.x = x
        self.y = y
        self.estimated = estimated
    }
}

/// A raw MediaPipe landmark reduced to the fields the engine needs.
/// The view controller converts MediaPipe's `NormalizedLandmark` into this so the
/// rest of the engine stays decoupled from the MediaPipe SDK types — the same role
/// `com.google.mediapipe...NormalizedLandmark` plays on Android, minus the coupling.
struct RawLandmark {
    let x: Float
    let y: Float
    let visibility: Float?   // 0–1, nil when MediaPipe didn't report it
}
