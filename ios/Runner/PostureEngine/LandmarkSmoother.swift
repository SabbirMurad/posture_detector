import Foundation

/// Per-landmark One Euro smoothing of the x/y channels. Direct port of the Kotlin
/// `LandmarkSmoother`, but takes `[RawLandmark]` instead of MediaPipe types.
final class LandmarkSmoother {
    private let xFilters: [OneEuroFilter]
    private let yFilters: [OneEuroFilter]

    init(landmarkCount: Int = 33, minCutoff: Float = 1.5, beta: Float = 0.01) {
        xFilters = (0..<landmarkCount).map { _ in OneEuroFilter(minCutoff: minCutoff, beta: beta) }
        yFilters = (0..<landmarkCount).map { _ in OneEuroFilter(minCutoff: minCutoff, beta: beta) }
    }

    func smooth(_ landmarks: [RawLandmark], timestampSec: Double) -> [LandmarkPoint] {
        landmarks.enumerated().map { i, lm in
            LandmarkPoint(
                x: xFilters[i].filter(lm.x, timestampSec: timestampSec),
                y: yFilters[i].filter(lm.y, timestampSec: timestampSec)
            )
        }
    }

    func reset() {
        xFilters.forEach { $0.reset() }
        yFilters.forEach { $0.reset() }
    }
}
