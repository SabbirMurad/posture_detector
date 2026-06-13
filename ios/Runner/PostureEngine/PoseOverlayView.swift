import UIKit

/// Live skeleton + ROSA-angle overlay drawn over the camera preview.
/// Port of the Kotlin `PoseOverlayView`. The actual skeleton/angle drawing lives
/// in `PoseRenderer` so the captured-photo baking path can reuse it verbatim
/// (mirroring how Android shares `drawAngles` between the view and bakeSkeleton).
final class PoseOverlayView: UIView {

    enum HeightGuideState { case hidden, tooHigh, tooLow, ok }

    private let TARGET_GUIDE_Y: CGFloat = 0.45

    private var landmarks: [LandmarkPoint] = []
    private var imageWidth: CGFloat = 1
    private var imageHeight: CGFloat = 1
    private var heightGuideState: HeightGuideState = .hidden
    private var rosaAngles: RosaAnglesCalculator.Angles?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateLandmarks(_ newLandmarks: [LandmarkPoint], imgWidth: Int, imgHeight: Int) {
        landmarks = newLandmarks
        imageWidth = CGFloat(max(imgWidth, 1))
        imageHeight = CGFloat(max(imgHeight, 1))
        setNeedsDisplay()
    }

    func updateRosaAngles(_ angles: RosaAnglesCalculator.Angles?) {
        rosaAngles = angles
        setNeedsDisplay()
    }

    func setHeightGuide(_ state: HeightGuideState) {
        if heightGuideState == state { return }
        heightGuideState = state
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), imageWidth > 1 else { return }

        let scale = min(bounds.width / imageWidth, bounds.height / imageHeight)
        let offsetX = (bounds.width - imageWidth * scale) / 2
        let offsetY = (bounds.height - imageHeight * scale) / 2
        let sx: (Float) -> CGFloat = { CGFloat($0) * self.imageWidth * scale + offsetX }
        let sy: (Float) -> CGFloat = { CGFloat($0) * self.imageHeight * scale + offsetY }

        // ── Height guide line ──────────────────────────────────────────────────
        if heightGuideState != .hidden {
            let lineY = sy(Float(TARGET_GUIDE_Y))
            let baseColor: UIColor = heightGuideState == .ok ? .green : .red
            let lineColor = baseColor.withAlphaComponent(200.0 / 255.0)
            ctx.setStrokeColor(lineColor.cgColor)
            ctx.setLineWidth(3)
            ctx.setLineDash(phase: 0, lengths: [22, 13])
            ctx.move(to: CGPoint(x: 0, y: lineY))
            ctx.addLine(to: CGPoint(x: bounds.width, y: lineY))
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])

            ctx.setStrokeColor(baseColor.cgColor)
            ctx.setLineWidth(5)
            let cx = bounds.width / 2
            for seg in [(cx - 40, lineY - 18, cx - 40, lineY + 18),
                        (cx + 40, lineY - 18, cx + 40, lineY + 18),
                        (cx - 40, lineY, cx - 14, lineY),
                        (cx + 14, lineY, cx + 40, lineY)] {
                ctx.move(to: CGPoint(x: seg.0, y: seg.1))
                ctx.addLine(to: CGPoint(x: seg.2, y: seg.3))
            }
            ctx.strokePath()

            let label: String
            switch heightGuideState {
            case .tooHigh: label = "▼  Lower phone"
            case .tooLow: label = "▲  Raise phone"
            case .ok: label = "✓  Height OK"
            case .hidden: label = ""
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 42),
                .foregroundColor: baseColor,
            ]
            (label as NSString).draw(at: CGPoint(x: cx + 56, y: lineY - 12 - 42), withAttributes: attrs)
        }

        if landmarks.isEmpty { return }

        PoseRenderer.drawScene(in: ctx, landmarks: landmarks, angles: rosaAngles, sx: sx, sy: sy, scale: 1)
    }

    static let poseConnections = PoseRenderer.poseConnections
}

/// Stateless skeleton/angle renderer shared by the live overlay and the
/// captured-photo baking step.
enum PoseRenderer {

    static let poseConnections: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 7),
        (0, 4), (4, 5), (5, 6), (6, 8),
        (9, 10),
        (7, 11), (8, 12),
        (11, 12),
        (11, 13), (13, 15), (15, 17), (17, 19), (19, 15), (15, 21),
        (12, 14), (14, 16), (16, 18), (18, 20), (20, 16), (16, 22),
        (11, 23), (12, 24), (23, 24),
        (23, 25), (25, 27), (27, 29), (29, 31), (31, 27),
        (24, 26), (26, 28), (28, 30), (30, 32), (32, 28),
    ]

    private static let arcColor = UIColor(red: 0xFF / 255, green: 0x57 / 255, blue: 0x22 / 255, alpha: 1)
    private static let vertRefColor = UIColor(red: 255 / 255, green: 87 / 255, blue: 34 / 255, alpha: 200 / 255)
    private static let estimatedDotColor = UIColor(red: 0, green: 220 / 255, blue: 0, alpha: 160 / 255)

    /// Draws skeleton connections, landmark dots, and ROSA angle arcs.
    /// `scale` multiplies stroke widths / dot radii / text sizes — 1 for the live
    /// overlay, `photoWidth / referenceWidth` for the baked photo.
    static func drawScene(in ctx: CGContext,
                          landmarks: [LandmarkPoint],
                          angles: RosaAnglesCalculator.Angles?,
                          sx: (Float) -> CGFloat,
                          sy: (Float) -> CGFloat,
                          scale: CGFloat) {
        // ── Skeleton connections ───────────────────────────────────────────────
        for (start, end) in poseConnections where start < landmarks.count && end < landmarks.count {
            let s = landmarks[start], e = landmarks[end]
            let estimated = s.estimated || e.estimated
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth((estimated ? 4 : 6) * scale)
            ctx.setLineDash(phase: 0, lengths: estimated ? [14 * scale, 9 * scale] : [])
            ctx.move(to: CGPoint(x: sx(s.x), y: sy(s.y)))
            ctx.addLine(to: CGPoint(x: sx(e.x), y: sy(e.y)))
            ctx.strokePath()
        }
        ctx.setLineDash(phase: 0, lengths: [])

        // ── Landmark dots ──────────────────────────────────────────────────────
        for lm in landmarks {
            let r = (lm.estimated ? 5 : 7) * scale
            ctx.setFillColor((lm.estimated ? estimatedDotColor : UIColor.green).cgColor)
            ctx.fillEllipse(in: CGRect(x: sx(lm.x) - r, y: sy(lm.y) - r, width: 2 * r, height: 2 * r))
        }

        // ── ROSA angle arcs ────────────────────────────────────────────────────
        if let ra = angles, landmarks.count >= 29 {
            drawAngles(in: ctx, landmarks: landmarks, angles: ra, sx: sx, sy: sy, scale: scale)
        }
    }

    static func drawAngles(in ctx: CGContext,
                           landmarks: [LandmarkPoint],
                           angles: RosaAnglesCalculator.Angles,
                           sx: (Float) -> CGFloat,
                           sy: (Float) -> CGFloat,
                           scale: CGFloat) {
        if landmarks.count < 29 { return }
        let left = angles.isLeftSide

        let ear = landmarks[left ? 7 : 8]
        let shoulder = landmarks[left ? 11 : 12]
        let elbow = landmarks[left ? 13 : 14]
        let wrist = landmarks[left ? 15 : 16]
        let hip = landmarks[left ? 23 : 24]
        let knee = landmarks[left ? 25 : 26]
        let ankle = landmarks[left ? 27 : 28]

        let shSx = sx(shoulder.x), shSy = sy(shoulder.y)
        let hipSx = sx(hip.x), hipSy = sy(hip.y)

        let torsoLen = hypot(shSx - hipSx, shSy - hipSy)
        let r = torsoLen * 0.22
        let textSize = 36 * scale

        // Knee angle — hip → knee ← ankle
        drawArc(ctx, p1: CGPoint(x: sx(hip.x), y: sy(hip.y)),
                v: CGPoint(x: sx(knee.x), y: sy(knee.y)),
                p2: CGPoint(x: sx(ankle.x), y: sy(ankle.y)),
                text: deg(angles.kneeAngle), radius: r, scale: scale, textSize: textSize)

        // Trunk angle — shoulder → hip ← vertical reference line
        let vRefSy = sy(hip.y - 0.18)
        strokeVertRef(ctx, from: CGPoint(x: hipSx, y: hipSy), to: CGPoint(x: hipSx, y: vRefSy), scale: scale)
        drawArc(ctx, p1: CGPoint(x: shSx, y: shSy), v: CGPoint(x: hipSx, y: hipSy),
                p2: CGPoint(x: hipSx, y: vRefSy),
                text: deg(angles.trunkAngle), radius: r, scale: scale, textSize: textSize)

        // Neck angle — ear → shoulder ← vertical reference line
        let neckVRefSy = sy(shoulder.y - 0.14)
        strokeVertRef(ctx, from: CGPoint(x: shSx, y: shSy), to: CGPoint(x: shSx, y: neckVRefSy), scale: scale)
        drawArc(ctx, p1: CGPoint(x: sx(ear.x), y: sy(ear.y)), v: CGPoint(x: shSx, y: shSy),
                p2: CGPoint(x: shSx, y: neckVRefSy),
                text: deg(angles.neckAngle), radius: r * 0.75, scale: scale, textSize: textSize)

        // Elbow angle — shoulder → elbow ← wrist
        drawArc(ctx, p1: CGPoint(x: shSx, y: shSy), v: CGPoint(x: sx(elbow.x), y: sy(elbow.y)),
                p2: CGPoint(x: sx(wrist.x), y: sy(wrist.y)),
                text: deg(angles.elbowAngle), radius: r, scale: scale, textSize: textSize)
    }

    private static func deg(_ value: Float) -> String { String(format: "%.0f°", value) }

    private static func strokeVertRef(_ ctx: CGContext, from: CGPoint, to: CGPoint, scale: CGFloat) {
        ctx.setStrokeColor(vertRefColor.cgColor)
        ctx.setLineWidth(3 * scale)
        ctx.setLineDash(phase: 0, lengths: [12 * scale, 8 * scale])
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
    }

    private static func drawArc(_ ctx: CGContext,
                                p1: CGPoint, v: CGPoint, p2: CGPoint,
                                text: String, radius: CGFloat, scale: CGFloat, textSize: CGFloat) {
        let v1 = CGPoint(x: p1.x - v.x, y: p1.y - v.y)
        let v2 = CGPoint(x: p2.x - v.x, y: p2.y - v.y)
        let m1 = hypot(v1.x, v1.y), m2 = hypot(v2.x, v2.y)
        if m1 < 1 || m2 < 1 { return }

        let startAngle = atan2(v1.y, v1.x)
        let cross = v1.x * v2.y - v1.y * v2.x
        let dot = v1.x * v2.x + v1.y * v2.y
        let sweep = atan2(cross, dot)

        // Approximate the arc with a polyline so the sweep direction matches Android's
        // drawArc exactly regardless of CG's clockwise convention.
        let steps = max(2, Int(abs(sweep) / (.pi / 60)))
        let arcPath = CGMutablePath()
        for i in 0...steps {
            let a = startAngle + sweep * CGFloat(i) / CGFloat(steps)
            let pt = CGPoint(x: v.x + radius * cos(a), y: v.y + radius * sin(a))
            if i == 0 { arcPath.move(to: pt) } else { arcPath.addLine(to: pt) }
        }

        // Black outline pass, then the coloured arc.
        ctx.addPath(arcPath)
        ctx.setStrokeColor(UIColor.black.cgColor)
        ctx.setLineWidth(4 * scale + 4)
        ctx.strokePath()
        ctx.addPath(arcPath)
        ctx.setStrokeColor(arcColor.cgColor)
        ctx.setLineWidth(4 * scale)
        ctx.strokePath()

        // Label at the arc bisector.
        let bisector = startAngle + sweep / 2
        let textDist = radius + textSize * 0.6
        let textX = v.x + textDist * cos(bisector)
        let textY = v.y + textDist * sin(bisector)
        drawCenteredOutlinedText(ctx, text: text, center: CGPoint(x: textX, y: textY),
                                 textSize: textSize, color: arcColor)
    }

    private static func drawCenteredOutlinedText(_ ctx: CGContext, text: String, center: CGPoint,
                                                 textSize: CGFloat, color: UIColor) {
        let font = UIFont.boldSystemFont(ofSize: textSize)
        let ns = text as NSString
        let outline: [NSAttributedString.Key: Any] = [
            .font: font,
            .strokeColor: UIColor.black,
            .strokeWidth: textSize * 0.22,   // positive = stroke (outline)
        ]
        let fill: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = ns.size(withAttributes: fill)
        let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        ns.draw(at: origin, withAttributes: outline)
        ns.draw(at: origin, withAttributes: fill)
    }
}
