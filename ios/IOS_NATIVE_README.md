# iOS native posture-detection engine

This folder now contains a Swift port of the Android Kotlin engine
(`android/app/src/main/java/com/ooplab/exercises_fitfuel/`). It implements the same
`posture_detection` `MethodChannel` (`startDetection`) so the existing Flutter UI
(`lib/`) drives iOS unchanged.

The two ML models are **cross-platform** and reused as-is:

| Model file | Android (asset) | iOS (bundle resource) | Runtime |
|---|---|---|---|
| `pose_landmarker_full.task` | MediaPipe Tasks Vision | `MediaPipeTasksVision` pod | pose landmarks |
| `yolov8n_float16.tflite` | TensorFlow Lite | TFLite C API (via `MediaPipeTasksVision`) | person/monitor detect |

## What was added

```
ios/Runner/PostureEngine/
  LandmarkPoint.swift            ← LandmarkPoint + RawLandmark
  OneEuroFilter.swift            ← port of OneEuroFilter.kt
  LandmarkSmoother.swift         ← port of LandmarkSmoother.kt
  LegEstimator.swift             ← port of LegEstimator.kt
  RosaAnglesCalculator.swift     ← port of RosaAnglesCalculator.kt
  RosaScorer.swift               ← port of RosaScorer.kt (lookup tables + checklist)
  DistanceEstimator.swift        ← port of DistanceEstimator.kt (uses camera intrinsics)
  TiltMonitor.swift              ← port of TiltMonitor.kt (CoreMotion accelerometer)
  YoloDetector.swift             ← port of YoloDetector.kt (TensorFlow Lite C API)
  TFLiteCAPI.h                   ← TFLite C API declarations for YoloDetector
  FaceBlurrer.swift              ← port of FaceBlurrer.kt (CoreGraphics pixelation)
  PoseOverlayView.swift          ← port of PoseOverlayView.kt (UIView + PoseRenderer)
  PoseDetectionViewController.swift ← port of PoseDetectionActivity.kt (AVFoundation + state machine)
ios/Runner/Models/
  pose_landmarker_full.task      ← copied from android assets
  yolov8n_float16.tflite         ← copied from android assets
ios/Runner/AppDelegate.swift     ← registers the posture_detection MethodChannel
ios/Runner/Runner-Bridging-Header.h ← imports PostureEngine/TFLiteCAPI.h
ios/Runner/Info.plist            ← + NSCameraUsageDescription, NSMotionUsageDescription
ios/Podfile                      ← adds MediaPipeTasksVision
```

## One-time setup (must run on macOS with Xcode)

Everything below requires a Mac — iOS apps cannot be compiled on Windows. The code
itself is complete; these are the project-wiring steps Xcode needs.

1. **Get Flutter's iOS scaffolding generated** (creates `Flutter/Generated.xcconfig`):
   ```bash
   flutter pub get
   flutter precache --ios
   ```

2. **Install pods**:
   ```bash
   cd ios
   pod install      # reads the Podfile added here
   ```

3. **Open the *workspace*** (not the project):
   ```bash
   open ios/Runner.xcworkspace
   ```

4. **Add the new Swift files to the Runner target.** In Xcode:
   - Right-click the `Runner` group → *Add Files to "Runner"…*
   - Select the `PostureEngine` folder → check **Copy items if needed = off**
     (they're already in place), **Add to target: Runner**.
   - Confirm each `.swift` shows the `Runner` target membership (File Inspector →
     Target Membership).

5. **Add the models as bundle resources.** Add `Runner/Models/pose_landmarker_full.task`
   and `Runner/Models/yolov8n_float16.tflite` the same way, making sure they land in
   **Target → Build Phases → Copy Bundle Resources**. (The Swift code loads them via
   `Bundle.main.path(forResource:ofType:)`, so they must be in the app bundle root —
   the `Models` folder is just for organising on disk; do **not** add it as a *folder
   reference* (blue), use a *group* (yellow) so the files are copied flat.)

6. Build & run on a **physical device** (the camera + CoreMotion need real hardware).

## How it maps to the Android side

- `AppDelegate.swift` plays the role of the Android `MainActivity` method-channel
  handler: on `startDetection` it builds `WorkstationModifiers` from the questionnaire
  answers, presents `PoseDetectionViewController`, and returns
  `{"photo_paths": [...], "rosa_scores": [...]}` (snake_case, identical keys) — or
  `nil` if cancelled. `RosaScore.fromMap` on the Dart side parses it unchanged.
- `PoseDetectionViewController` is the `PoseDetectionActivity`: the
  light-check → YOLO → pose state machine, the 3-shot guided capture, face blur,
  baked skeleton + ROSA angle arcs, and the same status panel / tilt-rotation-
  distance-side cues.
- All detection state lives on a single serial `captureQueue`; the camera delegate,
  MediaPipe live-stream callback and tilt callback all funnel onto it (the iOS analogue
  of Android's single-thread `cameraExecutor` + `@Volatile`/`AtomicInteger`).

## Platform differences worth knowing

- **Orientation**: the capture connection is set to `.portrait`, so frames arrive
  upright. That removes all the YUV rotation math the Android `YoloDetector` and
  `analyzeImage` need — iOS samples the upright BGRA `CVPixelBuffer` directly and
  passes MediaPipe an `.up` image.
- **Distance**: iOS doesn't expose the physical sensor size that Android's Camera2
  `SENSOR_INFO_PHYSICAL_SIZE` gives. Instead the capture connection delivers the
  **camera intrinsic matrix** per frame, whose `fx` term *is* the focal length in
  pixels — fed straight into `DistanceEstimator.estimate(focalLengthPx:)`. If
  intrinsics are unavailable it falls back to the format's horizontal field of view.
- **Front camera** is horizontally mirrored via `isVideoMirrored` (natural selfie
  behaviour); the back camera (the default) matches Android exactly.
- **GPU**: the Android build tries a TFLite GPU delegate first. This port runs YOLO on
  CPU (4 threads) for simplicity.
- **TensorFlow Lite runtime**: `YoloDetector` calls the TensorFlow Lite C API
  directly (declared in `PostureEngine/TFLiteCAPI.h`, imported via
  `Runner-Bridging-Header.h`) instead of depending on the `TensorFlowLiteSwift`
  pod. `MediaPipeTasksVision`'s `MediaPipeTasksCommon` dependency already
  statically links a full copy of this C API to run
  `pose_landmarker_full.task`; adding `TensorFlowLiteSwift` would link a second
  copy of the same ~48 C API symbols and fail with duplicate-symbol linker
  errors. Do not add `TensorFlowLiteSwift`/`TensorFlowLiteC` back to the Podfile
  without addressing that.

## If the MediaPipe pod version errors out

`MediaPipeTasksVision` is pinned to `~> 0.10.21` (CocoaPods uses its own `0.10.x`
versioning, not the `0.20230731`-style Android Maven version). If CocoaPods can't
resolve `0.10.21`, change the Podfile line to another available version
(`pod 'MediaPipeTasksVision'` with no constraint installs the latest) — the Swift API
used here (`PoseLandmarker`, `PoseLandmarkerOptions`, `.liveStream`,
`poseLandmarkerLiveStreamDelegate`, `detectAsync(image:timestampInMilliseconds:)`)
has been stable across 0.10.x releases.
