import Foundation

/// Estimates camera-to-subject distance from the nose→hip pixel span.
/// Port of the Kotlin `DistanceEstimator`.
///
/// On Android the focal length in pixels is derived from Camera2's reported
/// focal length (mm) and physical sensor height (mm). iOS does not expose the
/// physical sensor size, but AVFoundation can deliver the camera intrinsic matrix
/// per frame, whose `fx` term **is** the focal length in pixels directly — so the
/// `estimate(focalLengthPx:)` overload is the one the iOS pipeline actually uses.
enum DistanceEstimator {

    // Nose → hip midpoint accounts for ~37 % of standing body height.
    private static let TORSO_RATIO: Float = 0.37

    /// Distance in metres from the focal length already expressed in pixels.
    /// - Parameters:
    ///   - noseY/hipMidY: normalised Y (0–1) of nose and hip midpoint
    ///   - imageHeightPx: frame height in pixels (to convert the normalised span)
    ///   - focalLengthPx: focal length in pixels (camera intrinsics fx)
    ///   - personHeightCm: assumed standing height of the subject
    static func estimate(noseY: Float,
                         hipMidY: Float,
                         imageHeightPx: Int,
                         focalLengthPx: Float,
                         personHeightCm: Float = 170) -> Float? {
        let pixelHeight = (hipMidY - noseY) * Float(imageHeightPx)
        if pixelHeight < 20 || focalLengthPx <= 0 { return nil }
        let realTorsoHeightCm = personHeightCm * TORSO_RATIO
        let distanceCm = (realTorsoHeightCm * focalLengthPx) / pixelHeight
        return distanceCm / 100   // → metres
    }

    /// Original mm-based overload kept for parity with the Android engine, in case
    /// the iOS side ever obtains a real focal length / sensor height in millimetres.
    static func estimate(noseY: Float,
                         hipMidY: Float,
                         imageHeightPx: Int,
                         focalMm: Float,
                         sensorHeightMm: Float,
                         personHeightCm: Float = 170) -> Float? {
        let pixelHeight = (hipMidY - noseY) * Float(imageHeightPx)
        if pixelHeight < 20 || focalMm <= 0 || sensorHeightMm <= 0 { return nil }
        let focalLengthPx = (focalMm / sensorHeightMm) * Float(imageHeightPx)
        let realTorsoHeightCm = personHeightCm * TORSO_RATIO
        let distanceCm = (realTorsoHeightCm * focalLengthPx) / pixelHeight
        return distanceCm / 100
    }
}
