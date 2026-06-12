import UIKit

/// Blurs (pixelates) the face region of a captured photo using pose landmark
/// positions. Port of the Kotlin `FaceBlurrer` — nose + ear based bounding box
/// with a generous margin, MediaPipe 33-point indices (0 = nose, 7/8 = ears).
enum FaceBlurrer {

    private static let NOSE_INDEX = 0
    private static let LEFT_EAR_INDEX = 7
    private static let RIGHT_EAR_INDEX = 8

    private static let RADIUS_MARGIN: CGFloat = 1.25
    private static let FALLBACK_RADIUS_FRACTION: CGFloat = 0.06
    private static let DOWNSCALE_FACTOR: CGFloat = 12

    /// Returns a new image with the face region pixelated. If anything is
    /// degenerate it returns `source` unchanged.
    static func blurFace(_ source: UIImage, landmarks: [LandmarkPoint]) -> UIImage {
        guard landmarks.count > RIGHT_EAR_INDEX, let cg = source.cgImage else { return source }

        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let nose = landmarks[NOSE_INDEX]
        let cx = CGFloat(nose.x) * w
        let cy = CGFloat(nose.y) * h

        // In a side-on view the visible (near) ear sits farther from the nose in
        // 2D than the occluded (far) one — pick whichever is farther.
        let ears = [landmarks[LEFT_EAR_INDEX], landmarks[RIGHT_EAR_INDEX]]
        let ear = ears.max { a, b in
            hypot((CGFloat(nose.x) - CGFloat(a.x)) * w, (CGFloat(nose.y) - CGFloat(a.y)) * h) <
            hypot((CGFloat(nose.x) - CGFloat(b.x)) * w, (CGFloat(nose.y) - CGFloat(b.y)) * h)
        }

        let radius: CGFloat
        if let ear = ear {
            radius = hypot((CGFloat(nose.x) - CGFloat(ear.x)) * w,
                           (CGFloat(nose.y) - CGFloat(ear.y)) * h) * RADIUS_MARGIN
        } else {
            radius = h * FALLBACK_RADIUS_FRACTION
        }
        if radius < 1 { return source }

        let left = (cx - radius).rounded().clamped(0, w - 1)
        let top = (cy - radius).rounded().clamped(0, h - 1)
        let right = (cx + radius).rounded().clamped(0, w - 1)
        let bottom = (cy + radius).rounded().clamped(0, h - 1)
        let regionW = right - left
        let regionH = bottom - top
        if regionW <= 0 || regionH <= 0 { return source }

        let regionRect = CGRect(x: left, y: top, width: regionW, height: regionH)
        guard let regionCg = cg.cropping(to: regionRect) else { return source }

        // Pixelate: downscale hard, then upscale back to region size (nearest-ish).
        let smallW = max(1, Int(regionW / DOWNSCALE_FACTOR))
        let smallH = max(1, Int(regionH / DOWNSCALE_FACTOR))
        let regionImage = UIImage(cgImage: regionCg)
        let smallImage = regionImage.resized(to: CGSize(width: smallW, height: smallH))
        let pixelated = smallImage.resized(to: CGSize(width: regionW, height: regionH))

        // Composite the pixelated region back onto a full-size copy of the source.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        return renderer.image { _ in
            source.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
            pixelated.draw(in: regionRect)
        }
    }
}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}

private extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
