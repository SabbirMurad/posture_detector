package com.ooplab.exercises_fitfuel

import android.app.Activity
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.*
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.Image
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class PoseDetectionActivity : AppCompatActivity() {

    companion object {
        /** Activity-result extra: ArrayList<String> of absolute paths to the captured JPEGs. */
        const val EXTRA_PHOTO_PATHS  = "photo_paths"
        /** Activity-result extra: JSON array string of ROSA score maps, one per photo. */
        const val EXTRA_ROSA_SCORES  = "rosa_scores"
    }

    private enum class AppState { LIGHT_CHECK, DETECTING, POSE }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------
    private lateinit var previewView: PreviewView
    private lateinit var poseOverlayView: PoseOverlayView
    private lateinit var detectionPanel: LinearLayout
    private lateinit var tvCaptureStatus: TextView
    private lateinit var flashOverlay: View
    private lateinit var tvLightStatus: TextView
    private lateinit var tvPersonStatus: TextView
    private lateinit var tvMonitorStatus: TextView
    private lateinit var confirmProgress: ProgressBar
    private lateinit var tvStatusMessage: TextView
    private lateinit var tvTiltStatus: TextView
    private lateinit var tvRotationStatus: TextView
    private lateinit var tvDistanceStatus: TextView
    private lateinit var tvSideViewStatus: TextView

    // -------------------------------------------------------------------------
    // Tilt
    // -------------------------------------------------------------------------
    private lateinit var tiltMonitor: TiltMonitor

    // -------------------------------------------------------------------------
    // ML
    // -------------------------------------------------------------------------
    private lateinit var cameraExecutor: ExecutorService
    @Volatile private var poseLandmarker: PoseLandmarker? = null
    private var yoloDetector: YoloDetector? = null

    // -------------------------------------------------------------------------
    // Camera
    // -------------------------------------------------------------------------
    private var cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
    @Volatile private var cameraProvider: ProcessCameraProvider? = null
    @Volatile private var lastImageWidth: Int  = 1
    @Volatile private var lastImageHeight: Int = 1

    // Camera2 optics — read once per camera bind, used for distance estimation
    @Volatile private var focalLengthMm: Float  = 4.25f  // sensible fallback
    @Volatile private var sensorWidthMm: Float  = 6.4f   // landscape sensor width
    @Volatile private var sensorHeightMm: Float = 4.8f   // landscape sensor height
    private var frameCounter = 0
    private val processEveryNFrames = 1

    // -------------------------------------------------------------------------
    // Smoother + leg estimator
    // -------------------------------------------------------------------------
    private val landmarkSmoother = LandmarkSmoother(minCutoff = 0.5f, beta = 0.5f)
    private val legEstimator     = LegEstimator()

    // -------------------------------------------------------------------------
    // State machine  (only written on cameraExecutor thread except resets)
    // -------------------------------------------------------------------------
    @Volatile private var appState = AppState.LIGHT_CHECK
    private var confirmationCount = 0
    private val REQUIRED_CONFIRMATIONS = 4

    // ── Multi-shot capture sequence ───────────────────────────────────────────
    // Once conditions are met, captures TOTAL_SHOTS_NEEDED photos, each at least
    // CAPTURE_COOLDOWN_MS apart and only while every condition is currently OK.
    private val capturedPhotos = mutableListOf<Bitmap>()
    private val capturedScores = mutableListOf<RosaScorer.Result?>()
    private val TOTAL_SHOTS_NEEDED = 3
    private val CAPTURE_COOLDOWN_MS = 2000L

    // Reference width the baked-in skeleton's stroke widths / dot radii are tuned
    // against (see bakeSkeletonOntoPhoto). Using a fixed constant — instead of the
    // capturing device's screen size — makes the skeleton's proportions relative
    // to the photo a fixed, intrinsic property of the image itself: the same photo
    // resolution always bakes the same skeleton, regardless of which phone took
    // it or what screen it's later viewed on. That matters because these photos
    // get sent to Flutter and on to the server for storage, where they must look
    // consistent no matter where they came from or where they're displayed.
    private val SKELETON_REFERENCE_WIDTH = 1080f
    @Volatile private var nextCaptureEarliestAtMs = 0L

    // Hip spread / torso height ratio threshold for side-view detection.
    // Accepts camera within ~30° of true side view; unaffected by torso lean.
    private val SIDE_VIEW_THRESHOLD = 0.35f

    // ── All-green success detection ───────────────────────────────────────────
    // Shows confirmation overlay when every condition holds for ~1.5 s (~45 frames)
    @Volatile private var tiltIsOk         = false
    @Volatile private var rotationIsOk     = false
    @Volatile private var sideIsOk         = false
    @Volatile private var heightIsOk       = false
    @Volatile private var distanceIsOk     = false
    @Volatile private var lastFrameBitmap: Bitmap? = null
    private val successCount           = java.util.concurrent.atomic.AtomicInteger(0)
    private val SUCCESS_FRAMES_NEEDED  = 20

    // Light thresholds (same as live_guidence project)
    private val MIN_LUMINANCE = 0.25
    private val MAX_LUMINANCE = 0.85

    // -------------------------------------------------------------------------
    // Colors
    // -------------------------------------------------------------------------
    private val COLOR_DETECTED     = Color.parseColor("#43A047") // green
    private val COLOR_NOT_DETECTED = Color.parseColor("#E53935") // red
    private val COLOR_NEUTRAL      = Color.parseColor("#9E9E9E") // grey

    // =========================================================================
    // Lifecycle
    // =========================================================================

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        setupEdgeToEdge()

        previewView      = findViewById(R.id.previewCam)
        poseOverlayView  = findViewById(R.id.poseOverlay)
        detectionPanel   = findViewById(R.id.detectionPanel)
        tvLightStatus    = findViewById(R.id.tvLightStatus)
        tvPersonStatus   = findViewById(R.id.tvPersonStatus)
        tvMonitorStatus  = findViewById(R.id.tvMonitorStatus)
        confirmProgress  = findViewById(R.id.confirmProgress)
        tvStatusMessage  = findViewById(R.id.tvStatusMessage)
        tvTiltStatus          = findViewById(R.id.tvTiltStatus)
        tvRotationStatus      = findViewById(R.id.tvRotationStatus)
        tvDistanceStatus      = findViewById(R.id.tvDistanceStatus)
        tvSideViewStatus      = findViewById(R.id.tvSideViewStatus)
        tvCaptureStatus         = findViewById(R.id.tvCaptureStatus)
        flashOverlay            = findViewById(R.id.flashOverlay)

        tiltMonitor = TiltMonitor(this) { tiltAngle, rollAngle ->
            val tOk = TiltMonitor.isTiltAcceptable(tiltAngle)
            val rOk = TiltMonitor.isRollAcceptable(rollAngle)
            tiltIsOk     = tOk
            rotationIsOk = rOk

            val tiltStr = "%.1f".format(tiltAngle)
            tvTiltStatus.setTextColor(if (tOk) COLOR_DETECTED else COLOR_NOT_DETECTED)
            tvTiltStatus.text = if (tOk) "● Tilt  $tiltStr°"
                                else     "● Tilt  $tiltStr°  ·  Hold phone upright"

            val rollStr = "%.1f".format(kotlin.math.abs(rollAngle))
            tvRotationStatus.setTextColor(if (rOk) COLOR_DETECTED else COLOR_NOT_DETECTED)
            tvRotationStatus.text = if (rOk) "● Rotation  OK"
                                    else     "● Rotation  $rollStr°  ·  Level the phone"
        }

        cameraExecutor = Executors.newSingleThreadExecutor()
        // Load YOLO model on the executor thread so it's ready for the first frame
        cameraExecutor.execute { yoloDetector = YoloDetector(this) }

        // Show initial panel state (all neutral, checking light)
        updatePanel(lightOk = null)

        findViewById<Button>(R.id.btnSwitchCamera).setOnClickListener {
            cameraSelector = if (cameraSelector == CameraSelector.DEFAULT_BACK_CAMERA)
                CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
            fullReset()
            setupCamera()
        }

        findViewById<Button>(R.id.btnReset).setOnClickListener {
            fullReset()
        }

        requestCameraPermission()
    }

    private fun fullReset() {
        appState = AppState.LIGHT_CHECK
        confirmationCount = 0
        capturedPhotos.clear()
        capturedScores.clear()
        nextCaptureEarliestAtMs = 0L
        lastFrameBitmap = null
        successCount.set(0)
        distanceIsOk = false
        poseLandmarker?.close()
        poseLandmarker = null
        landmarkSmoother.reset()
        legEstimator.reset()
        cameraExecutor.execute {
            yoloDetector?.dispose()
            yoloDetector = YoloDetector(this)
        }
        runOnUiThread {
            tvCaptureStatus.visibility = View.GONE
            flashOverlay.visibility = View.GONE
            flashOverlay.alpha = 0f
            poseOverlayView.updateLandmarks(emptyList(), 1, 1)
            poseOverlayView.setHeightGuide(PoseOverlayView.HeightGuideState.HIDDEN)
            updatePanel(lightOk = null)
            poseOverlayView.updateRosaAngles(null)
        }
    }

    // =========================================================================
    // Pose landmarker — created only after detection confirms both targets
    // =========================================================================

    private fun initializePoseLandmarker() {
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(
                    BaseOptions.builder().setModelAssetPath("pose_landmarker_full.task").build()
                )
                .setRunningMode(RunningMode.LIVE_STREAM)
                .setResultListener { result, _ ->
                val currentState = appState
                val landmarks = result.landmarks()
                val w = lastImageWidth
                val h = lastImageHeight
                val tSec = android.os.SystemClock.elapsedRealtime() / 1000.0
                val sm = if (landmarks.isNotEmpty()) {
                    landmarkSmoother.smooth(landmarks[0], tSec)
                } else {
                    landmarkSmoother.reset(); null
                }

                // Check side view on the raw-smoothed landmarks (before estimation)
                val sideOk = sm != null &&
                             currentState == AppState.POSE &&
                             checkSideView(sm)
                sideIsOk = sideOk

                // Only apply leg estimation in a confirmed seated side view —
                // prevents bogus leg lines when the person faces the camera
                val smoothed = when {
                    sm == null -> emptyList()
                    sideOk     -> legEstimator.estimate(landmarks[0], sm)
                    else       -> sm
                }

                // ── Continuous side view + height guide ───────────────────────
                if (currentState == AppState.POSE) {
                    // Height guide is only meaningful when the phone is held upright (tilt OK).
                    // A tilted phone skews the shoulder y position, producing false readings.
                    val guideState: PoseOverlayView.HeightGuideState
                    if (tiltIsOk && rotationIsOk) {
                        val shoulderY = if (smoothed.size >= 13) (smoothed[11].y + smoothed[12].y) / 2f else -1f
                        val hOk = shoulderY in 0.43f..0.57f
                        heightIsOk = hOk
                        guideState = when {
                            shoulderY < 0f    -> PoseOverlayView.HeightGuideState.HIDDEN
                            shoulderY > 0.57f -> PoseOverlayView.HeightGuideState.TOO_HIGH
                            shoulderY < 0.43f -> PoseOverlayView.HeightGuideState.TOO_LOW
                            else              -> PoseOverlayView.HeightGuideState.OK
                        }
                    } else {
                        heightIsOk = false
                        guideState = PoseOverlayView.HeightGuideState.HIDDEN
                    }
                    runOnUiThread {
                        tvSideViewStatus.setTextColor(if (sideOk) COLOR_DETECTED else COLOR_NOT_DETECTED)
                        tvSideViewStatus.text = if (sideOk) "● Side  OK" else "● Side  Adjust angle"
                        poseOverlayView.setHeightGuide(guideState)
                    }
                }

                // ── Multi-shot capture sequence ───────────────────────────────
                // Captures TOTAL_SHOTS_NEEDED photos: each requires every condition
                // to hold steady for SUCCESS_FRAMES_NEEDED frames AND at least
                // CAPTURE_COOLDOWN_MS to have passed since the previous shot. If
                // conditions drop, the steady-frame count simply resets and we wait
                // for them to come back — the cooldown clock keeps running regardless.
                val allOk     = sideOk && tiltIsOk && rotationIsOk && heightIsOk && distanceIsOk
                val capturing = currentState == AppState.POSE && capturedPhotos.size < TOTAL_SHOTS_NEEDED
                if (capturing) runOnUiThread { updateCaptureCue(allOk) }

                if (capturing && allOk) {
                    val now = android.os.SystemClock.elapsedRealtime()
                    if (successCount.incrementAndGet() >= SUCCESS_FRAMES_NEEDED && now >= nextCaptureEarliestAtMs) {
                        successCount.set(0)
                        val captured  = smoothed.toList()
                        val frameCopy = lastFrameBitmap?.copy(Bitmap.Config.ARGB_8888, true)
                        if (frameCopy != null) {
                            val blurred  = FaceBlurrer.blurFace(frameCopy, captured)
                            val angles   = RosaAnglesCalculator.compute(captured)
                            val photo    = bakeSkeletonOntoPhoto(blurred, captured, angles)
                            capturedPhotos.add(photo)
                            capturedScores.add(if (angles != null) RosaScorer.score(angles) else null)
                            nextCaptureEarliestAtMs = now + CAPTURE_COOLDOWN_MS
                            val shotNumber = capturedPhotos.size
                            runOnUiThread {
                                triggerCaptureFlash()
                                updateCaptureCue(allOk = true)
                                if (shotNumber >= TOTAL_SHOTS_NEEDED) {
                                    pauseCameraPipeline()
                                    finishWithCapturedPhotos(capturedPhotos.toList(), capturedScores.toList())
                                }
                            }
                        }
                    }
                } else if (capturing) {
                    successCount.set(0)
                }

                // ── Distance (POSE only) ──────────────────────────────────────
                val distanceM = if (currentState == AppState.POSE && smoothed.size >= 25) {
                    val hipMidY = (smoothed[23].y + smoothed[24].y) / 2f
                    val sensorDimForY = if (h > w) sensorWidthMm else sensorHeightMm
                    DistanceEstimator.estimate(
                        noseY          = smoothed[0].y,
                        hipMidY        = hipMidY,
                        imageHeightPx  = h,
                        focalMm        = focalLengthMm,
                        sensorHeightMm = sensorDimForY,
                    )
                } else null

                val rosaAngles = if (currentState == AppState.POSE && smoothed.size >= 29)
                    RosaAnglesCalculator.compute(smoothed) else null

                distanceIsOk = distanceM != null && distanceM in 1.7f..2.1f

                runOnUiThread {
                    poseOverlayView.updateLandmarks(smoothed, w, h)
                    poseOverlayView.updateRosaAngles(rosaAngles)
                    if (distanceM != null) {
                        val dOk = distanceM in 1.7f..2.1f
                        val hint = when {
                            distanceM < 1.7f -> "  ·  Move back"
                            distanceM > 2.1f -> "  ·  Move closer"
                            else             -> ""
                        }
                        tvDistanceStatus.text = "● Distance  ${"%.2f".format(distanceM)}m$hint"
                        tvDistanceStatus.setTextColor(if (dOk) COLOR_DETECTED else COLOR_NOT_DETECTED)
                    } else {
                        distanceIsOk = false
                        tvDistanceStatus.text = "● Distance  --"
                        tvDistanceStatus.setTextColor(COLOR_NEUTRAL)
                    }
                }
            }.build()

        poseLandmarker = PoseLandmarker.createFromOptions(this, options)
    }

    // =========================================================================
    // Camera
    // =========================================================================

    private val cameraPermissionLauncher: ActivityResultLauncher<String> =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) setupCamera()
            else Toast.makeText(this, "Camera permission required", Toast.LENGTH_SHORT).show()
        }

    private fun requestCameraPermission() {
        if (hasCameraPermission()) setupCamera()
        else cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
    }

    private fun hasCameraPermission() =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    private fun readCameraCharacteristics() {
        try {
            val mgr = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val facing = if (cameraSelector == CameraSelector.DEFAULT_BACK_CAMERA)
                CameraCharacteristics.LENS_FACING_BACK else CameraCharacteristics.LENS_FACING_FRONT
            val id = mgr.cameraIdList.firstOrNull { cid ->
                mgr.getCameraCharacteristics(cid).get(CameraCharacteristics.LENS_FACING) == facing
            } ?: return
            val chars = mgr.getCameraCharacteristics(id)
            chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                ?.firstOrNull()?.let { focalLengthMm = it }
            chars.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)?.let { sz ->
                // SizeF is always landscape (width > height) regardless of phone orientation
                sensorWidthMm  = sz.width
                sensorHeightMm = sz.height
            }
            Log.d("CameraChars", "focal=${focalLengthMm}mm  sensor=${sensorWidthMm}×${sensorHeightMm}mm")
        } catch (e: Exception) {
            Log.w("CameraChars", "Could not read characteristics: ${e.message}")
        }
    }

    private fun setupCamera() {
        readCameraCharacteristics()
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            val provider = future.get()
            cameraProvider = provider
            val preview  = Preview.Builder().build().apply { setSurfaceProvider(previewView.surfaceProvider) }
            val analyzer = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build().apply { setAnalyzer(cameraExecutor, ::analyzeImage) }
            try {
                provider.unbindAll()
                provider.bindToLifecycle(this, cameraSelector, preview, analyzer)
            } catch (e: Exception) {
                Log.e("CameraSetup", "Bind failed", e)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    /**
     * Stops the camera feed and closes the pose landmarker once all shots are
     * captured — there's nothing left to detect while the photo review screen
     * is up, so keep it from burning CPU/battery in the background.
     *
     * unbindAll() must run on the main thread (camera lifecycle). The landmarker
     * close is posted onto cameraExecutor — the same single-thread executor that
     * calls detectAsync — so it's serialized after any in-flight frame analysis
     * instead of racing with it (closing while detectAsync is in flight crashes
     * MediaPipe; this also avoids closing it from inside its own result callback).
     */
    private fun pauseCameraPipeline() {
        cameraProvider?.unbindAll()
        cameraExecutor.execute {
            poseLandmarker?.close()
            poseLandmarker = null
        }
    }

    // =========================================================================
    // Frame analysis
    // =========================================================================

    @OptIn(ExperimentalGetImage::class)
    private fun analyzeImage(imageProxy: ImageProxy) {
        if (++frameCounter % processEveryNFrames != 0) { imageProxy.close(); return }

        val mediaImage = imageProxy.image
        if (mediaImage == null || imageProxy.format != ImageFormat.YUV_420_888) {
            Log.e("AnalyzeImage", "Unsupported format"); imageProxy.close(); return
        }

        when (appState) {
            AppState.LIGHT_CHECK -> runLightCheckPhase(mediaImage, imageProxy)
            AppState.DETECTING   -> runDetectionPhase(mediaImage, imageProxy)
            AppState.POSE        -> runPosePhase(mediaImage, imageProxy)
        }
    }

    // -------------------------------------------------------------------------
    // Phase 1: Light check
    // -------------------------------------------------------------------------

    private fun runLightCheckPhase(mediaImage: Image, imageProxy: ImageProxy) {
        val luminance = computeLuminance(mediaImage)
        when {
            luminance < MIN_LUMINANCE -> runOnUiThread {
                updatePanel(lightOk = false, message = "Room is too dark — turn on more lights")
            }
            luminance > MAX_LUMINANCE -> runOnUiThread {
                updatePanel(lightOk = false, message = "Too bright — reduce glare or step back")
            }
            else -> {
                // Light is good — start YOLO detection
                appState = AppState.DETECTING
                runOnUiThread { updatePanel(lightOk = true) }
            }
        }
        imageProxy.close()
    }

    // Average the Y (luma) plane, sampling every 20th pixel — same algorithm as live_guidence
    private fun computeLuminance(image: Image): Double {
        val yPlane    = image.planes[0]
        val yBuf      = yPlane.buffer
        val rowStride = yPlane.rowStride
        val width     = image.width
        val height    = image.height
        val step      = 20
        var sum   = 0L
        var count = 0
        var row = 0
        while (row < height) {
            var col = 0
            while (col < width) {
                sum += yBuf.get(row * rowStride + col).toInt() and 0xFF
                count++
                col += step
            }
            row += step
        }
        return if (count == 0) 0.5 else (sum.toDouble() / count) / 255.0
    }

    // -------------------------------------------------------------------------
    // Phase 2: YOLO detection
    // -------------------------------------------------------------------------

    private fun runDetectionPhase(mediaImage: Image, imageProxy: ImageProxy) {
        val result = yoloDetector?.detect(mediaImage, imageProxy.imageInfo.rotationDegrees)
            ?: run { imageProxy.close(); return }

        if (result.personDetected && result.monitorDetected) {
            confirmationCount++

            if (confirmationCount >= REQUIRED_CONFIRMATIONS) {
                runOnUiThread {
                    updatePanel(
                        lightOk         = true,
                        personDetected  = true,
                        monitorDetected = true,
                        confirmCount    = REQUIRED_CONFIRMATIONS,
                        message         = "Loading…"
                    )
                }
                initializePoseLandmarker()
                appState = AppState.POSE
                yoloDetector?.dispose()
                yoloDetector = null
                runOnUiThread {
                    detectionPanel.animate()
                        .alpha(0f).setDuration(500)
                        .withEndAction {
                            detectionPanel.visibility = View.GONE
                            detectionPanel.alpha = 1f
                        }.start()
                }
            } else {
                runOnUiThread {
                    updatePanel(
                        lightOk         = true,
                        personDetected  = true,
                        monitorDetected = true,
                        confirmCount    = confirmationCount,
                        message         = "Hold still…"
                    )
                }
            }
        } else {
            confirmationCount = 0
            runOnUiThread {
                updatePanel(
                    lightOk         = true,
                    personDetected  = result.personDetected,
                    monitorDetected = result.monitorDetected,
                    confirmCount    = 0
                )
            }
        }
        imageProxy.close()
    }

    // -------------------------------------------------------------------------
    // Phase 3: Pose detection
    // -------------------------------------------------------------------------

    private fun runPosePhase(mediaImage: Image, imageProxy: ImageProxy) {
        val bitmap = yuvToRgb(mediaImage, imageProxy)
        val matrix = Matrix().apply {
            postRotate(imageProxy.imageInfo.rotationDegrees.toFloat())
            if (cameraSelector == CameraSelector.DEFAULT_FRONT_CAMERA)
                postScale(-1f, 1f, bitmap.width.toFloat(), bitmap.height.toFloat())
        }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        lastImageWidth  = rotated.width
        lastImageHeight = rotated.height
        lastFrameBitmap = rotated
        poseLandmarker?.detectAsync(BitmapImageBuilder(rotated).build(), imageProxy.imageInfo.timestamp)
        imageProxy.close()
    }

    // =========================================================================
    // Side view check
    // =========================================================================

    /**
     * Returns true when the camera is at a side-on angle to the subject.
     *
     * Uses only hip spread relative to torso height. Hips stay planted in the
     * chair regardless of how much the person leans forward — making this
     * signal stable for typical seated office postures.
     *
     * Shoulder spread is intentionally excluded: when someone leans over a desk
     * MediaPipe shifts the shoulder landmarks, causing false "not side-on" reads.
     * Ears are intentionally excluded: the far ear can be occluded by hair or
     * head angle even when the camera is not truly side-on.
     *
     * Geometry: hipSpread ≈ hipWidth × cos(angleFromFrontal) / torsoHeight.
     * With typical proportions (hip width ≈ 70 % of torso height) a threshold
     * of 0.35 accepts angles within ~30° of true side view.
     */
    private fun checkSideView(smoothed: List<LandmarkPoint>): Boolean {
        if (smoothed.size < 25) return false
        val lHip = smoothed[23]; val rHip = smoothed[24]
        val lShoulder = smoothed[11]; val rShoulder = smoothed[12]
        val torsoH = kotlin.math.abs(
            (lShoulder.y + rShoulder.y) / 2f - (lHip.y + rHip.y) / 2f
        )
        if (torsoH < 0.01f) return false
        return kotlin.math.abs(lHip.x - rHip.x) / torsoH < SIDE_VIEW_THRESHOLD
    }

    // =========================================================================
    // Panel UI helper
    // =========================================================================

    /**
     * Single method that drives all panel indicator states.
     *
     * lightOk  = null  → neutral grey (not yet checked)
     * lightOk  = false → red  (out of range, message shown)
     * lightOk  = true  → green (passed, locked)
     *
     * During LIGHT_CHECK: pass lightOk only; person/monitor stay neutral.
     * During DETECTING:   pass lightOk=true + person/monitorDetected + confirmCount.
     */
    private fun updatePanel(
        lightOk: Boolean?,
        personDetected: Boolean  = false,
        monitorDetected: Boolean = false,
        confirmCount: Int        = 0,
        message: String?         = null,
    ) {
        detectionPanel.visibility = View.VISIBLE

        // Light
        tvLightStatus.setTextColor(when (lightOk) {
            null  -> COLOR_NEUTRAL
            true  -> COLOR_DETECTED
            false -> COLOR_NOT_DETECTED
        })

        // Person / monitor — grey until light passes
        val yoloActive = lightOk == true
        tvPersonStatus.setTextColor(when {
            !yoloActive    -> COLOR_NEUTRAL
            personDetected -> COLOR_DETECTED
            else           -> COLOR_NOT_DETECTED
        })
        tvMonitorStatus.setTextColor(when {
            !yoloActive     -> COLOR_NEUTRAL
            monitorDetected -> COLOR_DETECTED
            else            -> COLOR_NOT_DETECTED
        })

        // Progress bar
        val showProgress = yoloActive && personDetected && monitorDetected && confirmCount > 0
        confirmProgress.visibility = if (showProgress) View.VISIBLE else View.INVISIBLE
        confirmProgress.progress   = confirmCount

        // Status message
        if (message != null) {
            tvStatusMessage.text       = message
            tvStatusMessage.visibility = View.VISIBLE
        } else {
            tvStatusMessage.visibility = View.GONE
        }
    }

    // =========================================================================
    // YUV → Bitmap
    // =========================================================================

    private fun yuvToRgb(image: Image, imageProxy: ImageProxy): Bitmap {
        val yBuffer = image.planes[0].buffer
        val uBuffer = image.planes[1].buffer
        val vBuffer = image.planes[2].buffer
        val ySize = yBuffer.remaining()
        val uSize = uBuffer.remaining()
        val vSize = vBuffer.remaining()
        val nv21 = ByteArray(ySize + uSize + vSize)
        yBuffer.get(nv21, 0, ySize)
        vBuffer.get(nv21, ySize, vSize)
        uBuffer.get(nv21, ySize + vSize, uSize)
        val yuvImage = YuvImage(nv21, ImageFormat.NV21, imageProxy.width, imageProxy.height, null)
        val out = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, imageProxy.width, imageProxy.height), 100, out)
        return BitmapFactory.decodeByteArray(out.toByteArray(), 0, out.size())
    }

    /**
     * Writes the captured photos (skeleton already baked in) to the cache dir as JPEGs,
     * serialises the ROSA scores to JSON, and hands both back to MainActivity via the
     * activity result for Flutter to render on the review screen.
     */
    private fun finishWithCapturedPhotos(photos: List<Bitmap>, scores: List<RosaScorer.Result?>) {
        val dir = File(cacheDir, "posture_photos").apply { mkdirs() }
        val paths = ArrayList<String>(photos.size)
        photos.forEachIndexed { i, bitmap ->
            val file = File(dir, "photo_${i + 1}.jpg")
            FileOutputStream(file).use { out -> bitmap.compress(Bitmap.CompressFormat.JPEG, 92, out) }
            paths.add(file.absolutePath)
        }
        val scoresJson = org.json.JSONArray().also { arr ->
            scores.forEach { r ->
                arr.put(if (r != null) org.json.JSONObject(r.toMap()) else org.json.JSONObject())
            }
        }.toString()
        setResult(Activity.RESULT_OK, Intent()
            .putStringArrayListExtra(EXTRA_PHOTO_PATHS, paths)
            .putExtra(EXTRA_ROSA_SCORES, scoresJson))
        finish()
    }

    // =========================================================================
    // Capture sequence — visual cues + skeleton baking
    // =========================================================================

    /** Draws the pose skeleton and ROSA angle arcs onto the photo so each still image is self-contained. */
    private fun bakeSkeletonOntoPhoto(
        photo: Bitmap,
        landmarks: List<LandmarkPoint>,
        angles: RosaAnglesCalculator.Angles?,
    ): Bitmap {
        val canvas = Canvas(photo)
        val w = photo.width.toFloat()
        val h = photo.height.toFloat()

        // The line/dot sizes below are tuned to look right at SKELETON_REFERENCE_WIDTH.
        // Scaling by (photo width / reference width) makes the skeleton's size a
        // fixed proportion of the photo's own resolution — a property "baked in"
        // and intrinsic to the image, not dependent on the capturing device's
        // screen size. That keeps the result identical across devices and stable
        // if the camera's capture resolution ever changes.
        val bakeScale = w / SKELETON_REFERENCE_WIDTH

        val linePaint = Paint().apply {
            color = Color.WHITE; style = Paint.Style.STROKE; strokeWidth = 6f * bakeScale; isAntiAlias = true
        }
        val estimatedLinePaint = Paint().apply {
            color = Color.WHITE; style = Paint.Style.STROKE; strokeWidth = 4f * bakeScale; isAntiAlias = true
            pathEffect = DashPathEffect(floatArrayOf(14f * bakeScale, 9f * bakeScale), 0f)
        }
        val dotPaint = Paint().apply { color = Color.GREEN; style = Paint.Style.FILL; isAntiAlias = true }
        val estimatedDotPaint = Paint().apply {
            color = Color.argb(160, 0, 220, 0); style = Paint.Style.FILL; isAntiAlias = true
        }

        for ((start, end) in PoseOverlayView.POSE_CONNECTIONS) {
            if (start < landmarks.size && end < landmarks.size) {
                val s = landmarks[start]
                val e = landmarks[end]
                val paint = if (s.estimated || e.estimated) estimatedLinePaint else linePaint
                canvas.drawLine(s.x * w, s.y * h, e.x * w, e.y * h, paint)
            }
        }
        for (lm in landmarks) {
            val paint = if (lm.estimated) estimatedDotPaint else dotPaint
            val radius = (if (lm.estimated) 5f else 7f) * bakeScale
            canvas.drawCircle(lm.x * w, lm.y * h, radius, paint)
        }

        if (angles != null) {
            val arcPaint = Paint().apply {
                color = Color.parseColor("#FF5722"); style = Paint.Style.STROKE
                strokeWidth = 4f * bakeScale; isAntiAlias = true
            }
            val vertRefPaint = Paint().apply {
                color = Color.argb(200, 255, 87, 34); style = Paint.Style.STROKE
                strokeWidth = 3f * bakeScale; isAntiAlias = true
                pathEffect = DashPathEffect(floatArrayOf(12f * bakeScale, 8f * bakeScale), 0f)
            }
            val labelPaint = Paint().apply {
                color = Color.parseColor("#FF5722"); textSize = 36f * bakeScale; isAntiAlias = true
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                textAlign = Paint.Align.CENTER
            }
            PoseOverlayView.drawAngles(canvas, landmarks, angles, { x -> x * w }, { y -> y * h },
                arcPaint, vertRefPaint, labelPaint)
        }

        return photo
    }

    /** Camera-shutter flash — brief white flash so the phone holder feels each shot register. */
    private fun triggerCaptureFlash() {
        flashOverlay.visibility = View.VISIBLE
        flashOverlay.alpha = 1f
        flashOverlay.animate().alpha(0f).setDuration(350)
            .withEndAction { flashOverlay.visibility = View.GONE }
            .start()
    }

    /** Drives tvCaptureStatus through the multi-shot sequence so the phone holder always
     *  knows: how many shots are done, whether to hold steady, or to adjust position. */
    private fun updateCaptureCue(allOk: Boolean) {
        val done = capturedPhotos.size
        if (done == 0 && !allOk) {
            tvCaptureStatus.visibility = View.GONE
            return
        }
        tvCaptureStatus.visibility = View.VISIBLE
        tvCaptureStatus.text = when {
            done >= TOTAL_SHOTS_NEEDED ->
                "✓ All $TOTAL_SHOTS_NEEDED photos captured"
            android.os.SystemClock.elapsedRealtime() < nextCaptureEarliestAtMs ->
                "✓ Photo $done of $TOTAL_SHOTS_NEEDED captured — hold your position"
            allOk ->
                "Hold steady — capturing photo ${done + 1} of $TOTAL_SHOTS_NEEDED…"
            else ->
                "Get into position for photo ${done + 1} of $TOTAL_SHOTS_NEEDED"
        }
    }

    private fun setupEdgeToEdge() {
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.main)) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
    }

    override fun onResume() {
        super.onResume()
        tiltMonitor.start()
    }

    override fun onPause() {
        super.onPause()
        tiltMonitor.stop()
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraExecutor.shutdown()
        poseLandmarker?.close()
        yoloDetector?.dispose()
    }
}
