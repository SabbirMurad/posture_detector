import UIKit
import AVFoundation
import CoreImage
import CoreVideo
import simd
import MediaPipeTasksVision

/// iOS counterpart of the Android `PoseDetectionActivity`.
///
/// Drives the three-phase pipeline — ambient-light check → YOLO person/monitor
/// detection → MediaPipe pose + ROSA scoring — then captures three guided photos
/// (face blurred, skeleton + angle arcs baked in) and hands the file paths and
/// ROSA scores back through `onComplete`.
///
/// All mutable detection state is touched only on `captureQueue`; the camera
/// delegate, the MediaPipe live-stream callback and the tilt callback all funnel
/// onto it, so there are no data races and no locks. UI work is dispatched to main.
final class PoseDetectionViewController: UIViewController {

    /// Result is `["photo_paths": [String], "rosa_scores": [[String: Any]]]`, or
    /// `nil` if the user cancelled — matching what the Android MainActivity returns.
    var onComplete: (([String: Any]?) -> Void)?

    private let workstationModifiers: RosaScorer.WorkstationModifiers

    init(workstationModifiers: RosaScorer.WorkstationModifiers) {
        self.workstationModifiers = workstationModifiers
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        // Let this screen drive the status bar (light icons over the black view)
        // while presented over the Flutter view controller.
        modalPresentationCapturesStatusBarAppearance = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - State machine

    private enum AppState { case lightCheck, detecting, pose }
    private var appState: AppState = .lightCheck

    private var confirmationCount = 0
    private let REQUIRED_CONFIRMATIONS = 4

    // MARK: - Camera

    private let session = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var cameraPosition: AVCaptureDevice.Position = .back
    private let captureQueue = DispatchQueue(label: "posture.capture")
    private let ciContext = CIContext(options: nil)

    // Aspect ratio (height / width) of the upright portrait video. Used to size
    // the preview so it sits at the top of the screen rather than centered.
    private var videoPortraitAspect: CGFloat = 0
    private let previewTopGap: CGFloat = 48

    private var lastImageWidth = 1
    private var lastImageHeight = 1
    private var lastFrameImage: UIImage?
    private var focalLengthPx: Float = 0      // from camera intrinsics; 0 = unknown
    private var fallbackFocalPx: Float = 0    // derived from field of view

    // MARK: - ML

    private var poseLandmarker: PoseLandmarker?
    private var yoloDetector: YoloDetector?
    private var poseTimestampMs = 0

    private let landmarkSmoother = LandmarkSmoother(minCutoff: 0.5, beta: 0.5)
    private let legEstimator = LegEstimator()

    // MARK: - Tilt

    private var tiltMonitor: TiltMonitor!

    // MARK: - Capture sequence

    private var capturedPhotos: [UIImage] = []
    private var capturedScores: [RosaScorer.Result?] = []
    private let TOTAL_SHOTS_NEEDED = 3
    private let CAPTURE_COOLDOWN_MS: Double = 2000
    private var nextCaptureEarliestAtMs: Double = 0
    private let SKELETON_REFERENCE_WIDTH: CGFloat = 1080
    private let SIDE_VIEW_THRESHOLD: Float = 0.35

    private var tiltIsOk = false
    private var rotationIsOk = false
    private var sideIsOk = false
    private var heightIsOk = false
    private var distanceIsOk = false
    private var successCount = 0
    private let SUCCESS_FRAMES_NEEDED = 20

    private let MIN_LUMINANCE = 0.25
    private let MAX_LUMINANCE = 0.85

    // MARK: - Colors

    private let colorDetected = UIColor(red: 0x43 / 255, green: 0xA0 / 255, blue: 0x47 / 255, alpha: 1)
    private let colorNotDetected = UIColor(red: 0xE5 / 255, green: 0x39 / 255, blue: 0x35 / 255, alpha: 1)
    private let colorNeutral = UIColor(red: 0x9E / 255, green: 0x9E / 255, blue: 0x9E / 255, alpha: 1)

    // MARK: - Views

    private var overlayView: PoseOverlayView!
    private let levelView = CameraLevelView()
    private var statusStack: UIStackView!
    private let tvLightStatus = UILabel()
    private let tvPersonStatus = UILabel()
    private let tvMonitorStatus = UILabel()
    private let confirmProgress = UIProgressView(progressViewStyle: .default)
    private let tvStatusMessage = UILabel()
    private let tvTiltStatus = UILabel()
    private let tvRotationStatus = UILabel()
    private let tvDistanceStatus = UILabel()
    private let tvSideViewStatus = UILabel()
    private let tvCaptureStatus = UILabel()
    private let flashOverlay = UIView()

    // =========================================================================
    // Lifecycle
    // =========================================================================

    override func viewDidLoad() {
        super.viewDidLoad()
        // #181818 — fills the status-bar area and the letterbox around the
        // top-anchored camera preview.
        view.backgroundColor = UIColor(white: 24.0 / 255.0, alpha: 1)
        buildUI()

        tiltMonitor = TiltMonitor { [weak self] tiltAngle, rollAngle, pitchAngle in
            self?.handleTilt(tiltAngle: tiltAngle, rollAngle: rollAngle, pitchAngle: pitchAngle)
        }

        captureQueue.async { [weak self] in
            self?.yoloDetector = YoloDetector()
        }

        updatePanel(lightOk: nil)
        requestCameraPermissionAndStart()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let rect = previewRect()
        previewLayer?.frame = rect
        flashOverlay.frame = rect
        overlayView?.frame = rect
        levelView.bounds = CGRect(x: 0, y: 0, width: 240, height: 220)
        levelView.center = CGPoint(x: rect.midX, y: rect.midY)
    }

    /// The frame for the (aspect-fitted) camera preview and its pose overlay,
    /// anchored to the top of the screen `previewTopGap` points below the safe
    /// area instead of being vertically centered. Until the video aspect ratio
    /// is known it falls back to the full bounds.
    private func previewRect() -> CGRect {
        let topInset = view.safeAreaInsets.top + previewTopGap
        let fullWidth = view.bounds.width
        let availableHeight = view.bounds.height - topInset
        guard videoPortraitAspect > 0, fullWidth > 0, availableHeight > 0 else {
            return view.bounds
        }
        var w = fullWidth
        var h = w * videoPortraitAspect
        if h > availableHeight {
            h = availableHeight
            w = h / videoPortraitAspect
        }
        let x = (view.bounds.width - w) / 2
        return CGRect(x: x, y: topInset, width: w, height: h)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tiltMonitor.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        tiltMonitor.stop()
    }

    // =========================================================================
    // Permissions + camera setup
    // =========================================================================

    private func requestCameraPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.setupCamera() }
                    else { self?.showToast("Camera permission required") }
                }
            }
        default:
            showToast("Camera permission required")
        }
    }

    private func setupCamera() {
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            self.session.inputs.forEach { self.session.removeInput($0) }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: self.cameraPosition),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.showToast("Camera unavailable") }
                return
            }
            self.session.addInput(input)
            self.computeFallbackFocal(device: device)

            // Portrait display aspect (height/width). The active format's
            // dimensions are landscape (width >= height); rotated to the portrait
            // connection, the on-screen height/width ratio is width/height.
            let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            if dims.width > 0 && dims.height > 0 {
                let aspect = CGFloat(dims.width) / CGFloat(dims.height)
                DispatchQueue.main.async {
                    self.videoPortraitAspect = aspect
                    self.view.setNeedsLayout()
                }
            }

            if self.session.outputs.isEmpty {
                self.videoOutput.videoSettings =
                    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.captureQueue)
                if self.session.canAddOutput(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                }
            }

            if let conn = self.videoOutput.connection(with: .video) {
                if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
                if conn.isCameraIntrinsicMatrixDeliverySupported {
                    conn.isCameraIntrinsicMatrixDeliveryEnabled = true
                }
                conn.isVideoMirrored = (self.cameraPosition == .front) && conn.isVideoMirroringSupported
            }

            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    /// Horizontal FOV → focal length in pixels, used when the camera doesn't deliver
    /// an intrinsic matrix. The portrait image height equals the sensor's landscape
    /// width, so the *horizontal* FOV is the right one for the vertical pixel span.
    private func computeFallbackFocal(device: AVCaptureDevice) {
        let hfovDeg = device.activeFormat.videoFieldOfView   // degrees, horizontal
        if hfovDeg > 0 {
            let hfovRad = Float(hfovDeg) * .pi / 180
            // imageHeight (portrait) is filled in per-frame; store the angular term.
            // focalPx = (imageHeightPortrait) / (2 * tan(hfov/2)); applied lazily.
            fallbackFocalPx = 1 / (2 * tan(hfovRad / 2))   // multiply by portrait height
        } else {
            fallbackFocalPx = 0
        }
    }

    private func effectiveFocalPx() -> Float {
        if focalLengthPx > 0 { return focalLengthPx }
        if fallbackFocalPx > 0 { return fallbackFocalPx * Float(lastImageHeight) }
        // last-ditch constant: ~26mm-equiv phone lens on a typical 1080-tall frame
        return Float(lastImageHeight) * 1.2
    }

    private func fullReset() {
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            self.appState = .lightCheck
            self.confirmationCount = 0
            self.capturedPhotos.removeAll()
            self.capturedScores.removeAll()
            self.nextCaptureEarliestAtMs = 0
            self.lastFrameImage = nil
            self.successCount = 0
            self.distanceIsOk = false
            self.poseLandmarker = nil
            self.landmarkSmoother.reset()
            self.legEstimator.reset()
            self.yoloDetector = YoloDetector()
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async {
                self.tvCaptureStatus.isHidden = true
                self.flashOverlay.isHidden = true
                self.flashOverlay.alpha = 0
                self.overlayView.updateLandmarks([], imgWidth: 1, imgHeight: 1)
                self.overlayView.setHeightGuide(.hidden)
                self.overlayView.updateRosaAngles(nil)
                self.updatePanel(lightOk: nil)
            }
        }
    }

    // =========================================================================
    // Pose landmarker
    // =========================================================================

    private func initializePoseLandmarker() {
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task") else {
            NSLog("pose_landmarker_full.task not found in bundle")
            return
        }
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .liveStream
        options.numPoses = 1
        options.poseLandmarkerLiveStreamDelegate = self
        do {
            poseLandmarker = try PoseLandmarker(options: options)
        } catch {
            NSLog("Failed to create PoseLandmarker: \(error)")
        }
    }

    // =========================================================================
    // Frame analysis  (runs on captureQueue via the delegate)
    // =========================================================================

    fileprivate func analyze(sampleBuffer: CMSampleBuffer) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        readIntrinsics(from: sampleBuffer)

        switch appState {
        case .lightCheck: runLightCheckPhase(pb)
        case .detecting: runDetectionPhase(pb)
        case .pose: runPosePhase(pb)
        }
    }

    private func readIntrinsics(from sampleBuffer: CMSampleBuffer) {
        guard let raw = CMGetAttachment(sampleBuffer,
                                        key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                                        attachmentModeOut: nil) as? Data,
              raw.count >= MemoryLayout<matrix_float3x3>.size else { return }
        // Copy into an aligned value — `Data`'s storage isn't guaranteed to meet
        // matrix_float3x3's 16-byte alignment, so a direct `load(as:)` can trap.
        var m = matrix_float3x3()
        _ = withUnsafeMutableBytes(of: &m) { raw.copyBytes(to: $0, count: MemoryLayout<matrix_float3x3>.size) }
        // Column-major: columns.0 = (fx, 0, 0). The intrinsics describe the
        // landscape sensor; fx is the focal length along the axis that becomes the
        // portrait image's vertical, which is exactly what the distance math wants.
        focalLengthPx = m.columns.0.x
    }

    // -------------------------------------------------------------------------
    // Phase 1: Light check
    // -------------------------------------------------------------------------

    private func runLightCheckPhase(_ pb: CVPixelBuffer) {
        let luminance = computeLuminance(pb)
        if luminance < MIN_LUMINANCE {
            DispatchQueue.main.async {
                self.updatePanel(lightOk: false, message: "Room is too dark — turn on more lights")
            }
        } else if luminance > MAX_LUMINANCE {
            DispatchQueue.main.async {
                self.updatePanel(lightOk: false, message: "Too bright — reduce glare or step back")
            }
        } else {
            appState = .detecting
            DispatchQueue.main.async { self.updatePanel(lightOk: true) }
        }
    }

    // Average a strided sample of luma over the BGRA buffer — analogue of the
    // Android Y-plane average, every 20th pixel.
    private func computeLuminance(_ pb: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return 0.5 }
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        let width = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)
        let rowStride = CVPixelBufferGetBytesPerRow(pb)
        let step = 20
        var sum: Double = 0
        var count = 0
        var row = 0
        while row < height {
            var col = 0
            while col < width {
                let p = row * rowStride + col * 4
                let b = Double(ptr[p + 0]), g = Double(ptr[p + 1]), r = Double(ptr[p + 2])
                sum += 0.299 * r + 0.587 * g + 0.114 * b
                count += 1
                col += step
            }
            row += step
        }
        return count == 0 ? 0.5 : (sum / Double(count)) / 255.0
    }

    // -------------------------------------------------------------------------
    // Phase 2: YOLO detection
    // -------------------------------------------------------------------------

    private func runDetectionPhase(_ pb: CVPixelBuffer) {
        guard let result = yoloDetector?.detect(pixelBuffer: pb) else { return }

        if result.personDetected && result.monitorDetected {
            confirmationCount += 1
            if confirmationCount >= REQUIRED_CONFIRMATIONS {
                DispatchQueue.main.async {
                    self.updatePanel(lightOk: true, personDetected: true, monitorDetected: true,
                                     confirmCount: self.REQUIRED_CONFIRMATIONS, message: "Loading…")
                }
                initializePoseLandmarker()
                appState = .pose
                yoloDetector = nil
                DispatchQueue.main.async {
                    // Entering pose phase: keep the condition list visible but
                    // clear the detection-only progress bar and message.
                    self.confirmProgress.isHidden = true
                    self.tvStatusMessage.isHidden = true
                }
            } else {
                let c = confirmationCount
                DispatchQueue.main.async {
                    self.updatePanel(lightOk: true, personDetected: true, monitorDetected: true,
                                     confirmCount: c, message: "Hold still…")
                }
            }
        } else {
            confirmationCount = 0
            let p = result.personDetected, m = result.monitorDetected
            DispatchQueue.main.async {
                self.updatePanel(lightOk: true, personDetected: p, monitorDetected: m, confirmCount: 0)
            }
        }
    }

    // -------------------------------------------------------------------------
    // Phase 3: Pose detection
    // -------------------------------------------------------------------------

    private func runPosePhase(_ pb: CVPixelBuffer) {
        // The buffer is already upright (portrait connection) and front-mirrored if
        // needed, so no rotation/flip is required here — unlike the Android path.
        guard let cg = ciContext.createCGImage(CIImage(cvPixelBuffer: pb),
                                               from: CGRect(x: 0, y: 0,
                                                            width: CVPixelBufferGetWidth(pb),
                                                            height: CVPixelBufferGetHeight(pb))) else { return }
        let image = UIImage(cgImage: cg)
        lastImageWidth = cg.width
        lastImageHeight = cg.height
        lastFrameImage = image

        guard let landmarker = poseLandmarker, let mpImage = try? MPImage(uiImage: image) else { return }
        poseTimestampMs += 33
        do {
            try landmarker.detectAsync(image: mpImage, timestampInMilliseconds: poseTimestampMs)
        } catch {
            NSLog("detectAsync failed: \(error)")
        }
    }

    // Funnelled from the MediaPipe callback onto captureQueue.
    private func handlePoseResult(_ result: PoseLandmarkerResult?) {
        let currentState = appState
        let w = lastImageWidth
        let h = lastImageHeight
        let tSec = CACurrentMediaTime()

        let rawLandmarks: [RawLandmark]
        if let pose = result?.landmarks.first {
            rawLandmarks = pose.map { RawLandmark(x: $0.x, y: $0.y, visibility: $0.visibility?.floatValue) }
        } else {
            rawLandmarks = []
        }

        let sm: [LandmarkPoint]?
        if rawLandmarks.isEmpty {
            landmarkSmoother.reset()
            sm = nil
        } else {
            sm = landmarkSmoother.smooth(rawLandmarks, timestampSec: tSec)
        }

        let sideOk = sm != nil && currentState == .pose && checkSideView(sm!)
        sideIsOk = sideOk

        let smoothed: [LandmarkPoint]
        if let sm = sm {
            smoothed = sideOk ? legEstimator.estimate(raw: rawLandmarks, smoothed: sm) : sm
        } else {
            smoothed = []
        }

        // ── Continuous side view + height guide ───────────────────────────────
        if currentState == .pose {
            let guideState: PoseOverlayView.HeightGuideState
            if tiltIsOk && rotationIsOk {
                let shoulderY = smoothed.count >= 13 ? (smoothed[11].y + smoothed[12].y) / 2 : -1
                heightIsOk = shoulderY >= 0.43 && shoulderY <= 0.57
                if shoulderY < 0 { guideState = .hidden }
                else if shoulderY > 0.57 { guideState = .tooHigh }
                else if shoulderY < 0.43 { guideState = .tooLow }
                else { guideState = .ok }
            } else {
                heightIsOk = false
                guideState = .hidden
            }
            DispatchQueue.main.async {
                self.tvSideViewStatus.textColor = sideOk ? self.colorDetected : self.colorNotDetected
                self.tvSideViewStatus.text = sideOk ? "● Side  OK" : "● Side  Adjust angle"
                self.overlayView.setHeightGuide(guideState)
            }
        }

        // ── Multi-shot capture sequence ───────────────────────────────────────
        let allOk = sideOk && tiltIsOk && rotationIsOk && heightIsOk && distanceIsOk
        let capturing = currentState == .pose && capturedPhotos.count < TOTAL_SHOTS_NEEDED
        if capturing { DispatchQueue.main.async { self.updateCaptureCue(allOk: allOk) } }

        if capturing && allOk {
            let nowMs = tSec * 1000
            successCount += 1
            if successCount >= SUCCESS_FRAMES_NEEDED && nowMs >= nextCaptureEarliestAtMs {
                successCount = 0
                if let frame = lastFrameImage {
                    let captured = smoothed
                    let blurred = FaceBlurrer.blurFace(frame, landmarks: captured)
                    let angles = RosaAnglesCalculator.compute(captured)
                    let photo = bakeSkeletonOntoPhoto(blurred, landmarks: captured, angles: angles)
                    capturedPhotos.append(photo)
                    capturedScores.append(angles != nil ? RosaScorer.score(angles!, mods: workstationModifiers) : nil)
                    nextCaptureEarliestAtMs = nowMs + CAPTURE_COOLDOWN_MS
                    let shotNumber = capturedPhotos.count
                    DispatchQueue.main.async {
                        self.triggerCaptureFlash()
                        self.updateCaptureCue(allOk: true)
                    }
                    if shotNumber >= TOTAL_SHOTS_NEEDED {
                        let photos = capturedPhotos
                        let scores = capturedScores
                        pauseCameraPipeline()
                        DispatchQueue.main.async {
                            self.finishWithCapturedPhotos(photos, scores: scores)
                        }
                    }
                }
            }
        } else if capturing {
            successCount = 0
        }

        // ── Distance ──────────────────────────────────────────────────────────
        let distanceM: Float?
        if currentState == .pose && smoothed.count >= 25 {
            let hipMidY = (smoothed[23].y + smoothed[24].y) / 2
            distanceM = DistanceEstimator.estimate(noseY: smoothed[0].y, hipMidY: hipMidY,
                                                    imageHeightPx: h, focalLengthPx: effectiveFocalPx())
        } else {
            distanceM = nil
        }

        let rosaAngles = (currentState == .pose && smoothed.count >= 29)
            ? RosaAnglesCalculator.compute(smoothed) : nil

        distanceIsOk = distanceM != nil && distanceM! >= 1.7 && distanceM! <= 2.1

        let capturedSnapshot = smoothed
        DispatchQueue.main.async {
            self.overlayView.updateLandmarks(capturedSnapshot, imgWidth: w, imgHeight: h)
            self.overlayView.updateRosaAngles(rosaAngles)
            if let d = distanceM {
                let dOk = d >= 1.7 && d <= 2.1
                let hint = d < 1.7 ? "  ·  Move back" : (d > 2.1 ? "  ·  Move closer" : "")
                self.tvDistanceStatus.text = String(format: "● Distance  %.2fm%@", d, hint)
                self.tvDistanceStatus.textColor = dOk ? self.colorDetected : self.colorNotDetected
            } else {
                self.tvDistanceStatus.text = "● Distance  --"
                self.tvDistanceStatus.textColor = self.colorNeutral
            }
        }
    }

    private func pauseCameraPipeline() {
        session.stopRunning()
        poseLandmarker = nil
    }

    // =========================================================================
    // Side view check
    // =========================================================================

    private func checkSideView(_ smoothed: [LandmarkPoint]) -> Bool {
        if smoothed.count < 25 { return false }
        let lHip = smoothed[23], rHip = smoothed[24]
        let lShoulder = smoothed[11], rShoulder = smoothed[12]
        let torsoH = abs((lShoulder.y + rShoulder.y) / 2 - (lHip.y + rHip.y) / 2)
        if torsoH < 0.01 { return false }
        return abs(lHip.x - rHip.x) / torsoH < SIDE_VIEW_THRESHOLD
    }

    // =========================================================================
    // Tilt
    // =========================================================================

    private func handleTilt(tiltAngle: Double, rollAngle: Double, pitchAngle: Double) {
        let tOk = TiltMonitor.isTiltAcceptable(tiltAngle)
        let rOk = TiltMonitor.isRollAcceptable(rollAngle)
        captureQueue.async {
            self.tiltIsOk = tOk
            self.rotationIsOk = rOk
        }
        levelView.update(roll: rollAngle, pitch: pitchAngle)
        tvTiltStatus.textColor = tOk ? colorDetected : colorNotDetected
        tvTiltStatus.text = tOk ? String(format: "● Tilt  %.1f°", tiltAngle)
                                : String(format: "● Tilt  %.1f°  ·  Hold phone upright", tiltAngle)
        tvRotationStatus.textColor = rOk ? colorDetected : colorNotDetected
        tvRotationStatus.text = rOk ? "● Rotation  OK"
                                    : String(format: "● Rotation  %.1f°  ·  Level the phone", abs(rollAngle))
    }

    // =========================================================================
    // Capture: baking + finishing
    // =========================================================================

    private func bakeSkeletonOntoPhoto(_ photo: UIImage,
                                       landmarks: [LandmarkPoint],
                                       angles: RosaAnglesCalculator.Angles?) -> UIImage {
        guard let cg = photo.cgImage else { return photo }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let bakeScale = w / SKELETON_REFERENCE_WIDTH

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        return renderer.image { rctx in
            let ctx = rctx.cgContext
            photo.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
            PoseRenderer.drawScene(in: ctx, landmarks: landmarks, angles: angles,
                                   sx: { CGFloat($0) * w }, sy: { CGFloat($0) * h }, scale: bakeScale)
        }
    }

    private func finishWithCapturedPhotos(_ photos: [UIImage], scores: [RosaScorer.Result?]) {
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("posture_photos")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var paths: [String] = []
        for (i, photo) in photos.enumerated() {
            let path = (dir as NSString).appendingPathComponent("photo_\(i + 1).jpg")
            if let data = photo.jpegData(compressionQuality: 0.92) {
                try? data.write(to: URL(fileURLWithPath: path))
                paths.append(path)
            }
        }
        let scoreMaps: [[String: Any]] = scores.map { $0?.toMap() ?? [:] }
        let result: [String: Any] = ["photo_paths": paths, "rosa_scores": scoreMaps]
        finish(with: result)
    }

    private func finish(with result: [String: Any]?) {
        let completion = onComplete
        onComplete = nil
        dismiss(animated: true) { completion?(result) }
    }

    // =========================================================================
    // Capture cues
    // =========================================================================

    private func triggerCaptureFlash() {
        flashOverlay.isHidden = false
        flashOverlay.alpha = 1
        UIView.animate(withDuration: 0.35, animations: { self.flashOverlay.alpha = 0 },
                       completion: { _ in self.flashOverlay.isHidden = true })
    }

    private func updateCaptureCue(allOk: Bool) {
        let done = capturedPhotos.count
        if done == 0 && !allOk { tvCaptureStatus.isHidden = true; return }
        tvCaptureStatus.isHidden = false
        let nowMs = CACurrentMediaTime() * 1000
        if done >= TOTAL_SHOTS_NEEDED {
            tvCaptureStatus.text = "✓ All \(TOTAL_SHOTS_NEEDED) photos captured"
        } else if nowMs < nextCaptureEarliestAtMs {
            tvCaptureStatus.text = "✓ Photo \(done) of \(TOTAL_SHOTS_NEEDED) captured — hold your position"
        } else if allOk {
            tvCaptureStatus.text = "Hold steady — capturing photo \(done + 1) of \(TOTAL_SHOTS_NEEDED)…"
        } else {
            tvCaptureStatus.text = "Get into position for photo \(done + 1) of \(TOTAL_SHOTS_NEEDED)"
        }
    }

    // =========================================================================
    // UI construction
    // =========================================================================

    private func buildUI() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        overlayView = PoseOverlayView(frame: view.bounds)
        view.addSubview(overlayView)

        // Level indicator, centered on the preview (positioned in layout).
        view.addSubview(levelView)

        flashOverlay.frame = view.bounds
        flashOverlay.backgroundColor = .white
        flashOverlay.alpha = 0
        flashOverlay.isHidden = true
        flashOverlay.isUserInteractionEnabled = false
        view.addSubview(flashOverlay)

        tvCaptureStatus.font = .boldSystemFont(ofSize: 14)
        tvCaptureStatus.textColor = .white
        tvCaptureStatus.textAlignment = .center
        tvCaptureStatus.numberOfLines = 0
        tvCaptureStatus.backgroundColor = UIColor(white: 0.1, alpha: 0.8)
        tvCaptureStatus.layer.cornerRadius = 6
        tvCaptureStatus.clipsToBounds = true
        tvCaptureStatus.isHidden = true
        tvCaptureStatus.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tvCaptureStatus)

        buildStatusStack()

        let switchImage = UIImage(named: "ic_switch_camera")?.withRenderingMode(.alwaysTemplate)
        let switchBtn = makeCircleIconButton(image: switchImage, action: #selector(onSwitchCamera))
        let closeBtn = makeButton("✕", action: #selector(onClose))
        view.addSubview(switchBtn)
        view.addSubview(closeBtn)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            // All status conditions sit at the bottom-left in a single column (the
            // camera preview is anchored to the top). 16pt from the leading edge
            // mirrors the switch-camera button's 16pt from the trailing edge.
            statusStack.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            statusStack.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -48),

            tvCaptureStatus.bottomAnchor.constraint(equalTo: statusStack.topAnchor, constant: -8),
            tvCaptureStatus.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            tvCaptureStatus.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),

            // 66 = previewTopGap (48) + 18, so the control sits 18pt below the
            // top edge of the camera preview.
            switchBtn.topAnchor.constraint(equalTo: g.topAnchor, constant: 66),
            switchBtn.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            closeBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            closeBtn.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -8),
        ])
    }

    /// Builds the single bottom column listing every status condition, in order:
    /// Light, Person, Monitor, Rotation, Tilt, Distance, Side — followed by the
    /// confirmation progress bar and the general status message.
    private func buildStatusStack() {
        tvLightStatus.text = "● Light"
        tvPersonStatus.text = "● Person"
        tvMonitorStatus.text = "● Monitor"
        tvRotationStatus.text = "● Rotation  --"
        tvTiltStatus.text = "● Tilt  --°"
        tvDistanceStatus.text = "● Distance  --"
        tvSideViewStatus.text = "● Side  --"

        let conditions: [UILabel] = [tvLightStatus, tvPersonStatus, tvMonitorStatus,
                                     tvRotationStatus, tvTiltStatus,
                                     tvDistanceStatus, tvSideViewStatus]
        for label in conditions { styleStatusChip(label) }

        confirmProgress.progressTintColor = colorDetected
        confirmProgress.trackTintColor = UIColor(white: 1, alpha: 0.2)
        confirmProgress.progress = 0
        confirmProgress.isHidden = true
        confirmProgress.widthAnchor.constraint(equalToConstant: 160).isActive = true

        tvStatusMessage.font = .systemFont(ofSize: 12)
        tvStatusMessage.textColor = UIColor(white: 1, alpha: 0.8)
        tvStatusMessage.textAlignment = .center
        tvStatusMessage.numberOfLines = 0
        tvStatusMessage.isHidden = true

        var arranged = [UIView]()
        arranged.append(contentsOf: conditions)
        arranged.append(confirmProgress)
        arranged.append(tvStatusMessage)
        statusStack = UIStackView(arrangedSubviews: arranged)
        statusStack.axis = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 6
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusStack)
    }

    private func styleStatusChip(_ label: UILabel) {
        label.font = .systemFont(ofSize: 13)
        label.textColor = colorNeutral
        label.textAlignment = .center
        label.backgroundColor = UIColor(white: 0, alpha: 0.67)
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        // padding via attributed insets is fiddly; a little width slack is enough here
        label.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func makeButton(_ title: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15)
        b.backgroundColor = UIColor(white: 0, alpha: 0.5)
        b.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        b.layer.cornerRadius = 6
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    /// A 48pt semi-transparent white circle holding a (template) icon image.
    private func makeCircleIconButton(image: UIImage?, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(image, for: .normal)
        b.tintColor = .white
        b.imageView?.contentMode = .scaleAspectFit
        b.contentEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        b.backgroundColor = UIColor(white: 1, alpha: 0.25)
        b.layer.cornerRadius = 24
        b.clipsToBounds = true
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 48).isActive = true
        b.heightAnchor.constraint(equalToConstant: 48).isActive = true
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    /// Mirrors the Android `updatePanel` indicator logic.
    private func updatePanel(lightOk: Bool?,
                             personDetected: Bool = false,
                             monitorDetected: Bool = false,
                             confirmCount: Int = 0,
                             message: String? = nil) {
        switch lightOk {
        case nil: tvLightStatus.textColor = colorNeutral
        case .some(true): tvLightStatus.textColor = colorDetected
        case .some(false): tvLightStatus.textColor = colorNotDetected
        }

        let yoloActive = (lightOk == true)
        tvPersonStatus.textColor = !yoloActive ? colorNeutral : (personDetected ? colorDetected : colorNotDetected)
        tvMonitorStatus.textColor = !yoloActive ? colorNeutral : (monitorDetected ? colorDetected : colorNotDetected)

        let showProgress = yoloActive && personDetected && monitorDetected && confirmCount > 0
        confirmProgress.isHidden = !showProgress
        confirmProgress.progress = Float(confirmCount) / Float(REQUIRED_CONFIRMATIONS)

        if let message = message {
            tvStatusMessage.text = message
            tvStatusMessage.isHidden = false
        } else {
            tvStatusMessage.isHidden = true
        }
    }

    private func showToast(_ text: String) {
        tvStatusMessage.text = text
        tvStatusMessage.isHidden = false
    }

    // MARK: - Button actions

    @objc private func onSwitchCamera() {
        cameraPosition = (cameraPosition == .back) ? .front : .back
        fullReset()
        setupCamera()
    }

    @objc private func onClose() { finish(with: nil) }
}

// =========================================================================
// Camera + MediaPipe delegates
// =========================================================================

extension PoseDetectionViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        analyze(sampleBuffer: sampleBuffer)   // already on captureQueue
    }
}

extension PoseDetectionViewController: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(_ poseLandmarker: PoseLandmarker,
                        didFinishDetection result: PoseLandmarkerResult?,
                        timestampInMilliseconds: Int,
                        error: Error?) {
        if let error = error { NSLog("pose detection error: \(error)"); return }
        captureQueue.async { [weak self] in
            self?.handlePoseResult(result)
        }
    }
}

// =========================================================================
// Level / horizon indicator
// =========================================================================

/// Camera level indicator (like the Pixel camera's "Level"). A fixed pair of
/// side ticks plus a centre line that rotates with the phone's roll and shifts
/// vertically with its forward/back pitch. Everything turns green when the phone
/// is held upright and level (within `TiltMonitor`'s acceptable ranges).
final class CameraLevelView: UIView {

    private var roll: CGFloat = 0    // degrees, 0 = level
    private var pitch: CGFloat = 0   // degrees, 0 = upright

    // Match TiltMonitor's acceptable ranges.
    private let rollTolerance: CGFloat = 15
    private let pitchTolerance: CGFloat = 5

    // Flip these if the motion feels reversed on device.
    private let rollSign: CGFloat = -1
    private let pitchSign: CGFloat = -1     // forward tilt → line moves up

    private let pxPerDegree: CGFloat = 0.6  // small, proportional travel
    private let maxOffset: CGFloat = 18
    private let centerHalf: CGFloat = 36   // half-length of the wide centre / moving line
    private let sideGap: CGFloat = 14      // gap between the centre line and each side tick
    private let sideLen: CGFloat = 14      // length of the short side ticks
    private let lineWidth: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(roll: Double, pitch: Double) {
        self.roll = CGFloat(roll)
        self.pitch = CGFloat(pitch)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let cx = bounds.midX, cy = bounds.midY

        let aligned = abs(roll) <= rollTolerance && abs(pitch) <= pitchTolerance
        let color: UIColor = aligned
            ? UIColor(red: 0x43 / 255.0, green: 0xA0 / 255.0, blue: 0x47 / 255.0, alpha: 1)
            : UIColor(white: 1, alpha: 0.95)

        ctx.setLineCap(.round)
        ctx.setShadow(offset: .zero, blur: 3, color: UIColor(white: 0, alpha: 0.6).cgColor)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)

        // Fixed reference: a wide centre line plus two shorter side ticks (3 lines,
        // all horizontal and centred).
        ctx.move(to: CGPoint(x: cx - centerHalf, y: cy))
        ctx.addLine(to: CGPoint(x: cx + centerHalf, y: cy))
        let tickInnerL = cx - centerHalf - sideGap
        let tickInnerR = cx + centerHalf + sideGap
        ctx.move(to: CGPoint(x: tickInnerL - sideLen, y: cy))
        ctx.addLine(to: CGPoint(x: tickInnerL, y: cy))
        ctx.move(to: CGPoint(x: tickInnerR, y: cy))
        ctx.addLine(to: CGPoint(x: tickInnerR + sideLen, y: cy))
        ctx.strokePath()

        // Moving line: same width as the centre line, shifted vertically by pitch
        // and rotated by roll. Overlaps the centre line when the phone is level.
        let dy = max(-maxOffset, min(maxOffset, pitchSign * pitch * pxPerDegree))
        // Deadzone: no rotation while roll is within the acceptable range, then
        // rotate smoothly past it (so there's no jump at the threshold).
        let effRoll: CGFloat = abs(roll) <= rollTolerance
            ? 0 : roll - (roll < 0 ? -rollTolerance : rollTolerance)
        let angle = rollSign * effRoll * .pi / 180
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy + dy)
        ctx.rotate(by: angle)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.move(to: CGPoint(x: -centerHalf, y: 0))
        ctx.addLine(to: CGPoint(x: centerHalf, y: 0))
        ctx.strokePath()
        ctx.restoreGState()
    }
}
