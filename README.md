# Posture Detector — ROSA Workstation Assessment

A hybrid Flutter + native-Android app that walks an office worker through a
**ROSA (Rapid Office Strain Assessment)** evaluation. The user answers a short
questionnaire about their workstation (Flutter), then a native Android camera
pipeline detects a seated side-on pose, captures three photos, computes joint
angles with MediaPipe, scores them against the ROSA Tables A/B/C/D/E, and
hands everything back to Flutter for review.

```
Flutter (lib/)                         Native Android (android/.../exercises_fitfuel/)
─────────────────────────────          ──────────────────────────────────────────────
StartScreen
   │
   ▼
WorkstationQuestionnaire  ──answers──▶  MethodChannel "posture_detection"
   │                                       │ "startDetection"
   │                                       ▼
   │                                    PoseDetectionActivity
   │                                       │ (light → YOLO → pose state machine)
   │                                       │ captures 3 photos + RosaScorer.Result
   │                                       ▼
ReviewScreen  ◀──photos + scores──────  MainActivity.onActivityResult
   │
   ▼
SuccessScreen
```

---

## 1. High-level flow

1. **`StartScreen`** — entry screen with a "Start" button.
2. **`WorkstationQuestionnaire`** — a multi-section form covering everything
   the camera *can't* see (adjustability of chair/armrests/monitor, glare,
   phone usage, desk duration, etc.). Produces a `WorkstationAnswers` object.
3. `WorkstationAnswers.toMap()` is sent over the `posture_detection`
   `MethodChannel` as the `startDetection` call argument.
4. **`MainActivity.kt`** receives the call, serialises the answers map to a
   JSON string, and launches **`PoseDetectionActivity`** with it as an intent
   extra (`EXTRA_WORKSTATION_ANSWERS`).
5. **`PoseDetectionActivity`** runs a 3-phase camera state machine
   (light check → person/monitor detection → pose capture). Once a good
   side-on seated pose is held steady, it captures **3 photos**, computing a
   ROSA score for each from the live pose landmarks + the questionnaire
   answers.
6. The activity finishes with `RESULT_OK`, returning photo file paths and a
   JSON array of ROSA score maps.
7. `MainActivity.onActivityResult` converts the JSON back into a
   `Map<String, Any>` (snake_case keys) and resolves the pending Flutter
   `MethodChannel.Result`.
8. **`StartScreen`** receives `photo_paths` + `rosa_scores`, parses the latter
   into `RosaScore` objects, and pushes **`ReviewScreen`**.
9. **`ReviewScreen`** shows each captured photo (with the skeleton/angle
   overlay baked in) plus a breakdown of ROSA sub-scores. Tapping a photo
   opens **`GalleryImageViewer`** (full-screen pinch-zoom gallery).
10. "Continue" → **`SuccessScreen`** → "Start Again" returns to `StartScreen`.

---

## 2. Flutter layer (`lib/`)

### `main.dart`
App entry point. A `MaterialApp` (Material 3, blue seed color) whose home is
`StartScreen`.

### `start_screen.dart`
- Holds the `MethodChannel('posture_detection')`.
- `_onStart()`:
  1. Pushes `WorkstationQuestionnaire` and awaits a `WorkstationAnswers`
     result (returns early if the user backs out).
  2. Calls `_channel.invokeMethod('startDetection', answers.toMap())` —
     this blocks (shows a spinner) until the native activity finishes.
  3. Parses the result map: `photo_paths` (List<String>) and `rosa_scores`
     (List → `RosaScore.fromMap`).
  4. Pushes `ReviewScreen` with both lists.

### `workstation_answers.dart`
Plain data model + enums for the manual ROSA checklist:
- `SeatDepthFit { ok, tooLong, tooShort }`
- `PhoneUsage { none, headsetOrOneHand, reachFar }`
- `DeskDuration { short, medium, long }`
- `WorkstationAnswers` — one boolean/enum per ROSA checklist item (chair,
  armrests, backrest, monitor, phone, mouse, keyboard, duration).
- `toMap()` converts to the **snake_case JSON contract** consumed by Kotlin's
  `RosaScorer.WorkstationModifiers.fromMap()`:
  - Booleans pass through as-is.
  - `seatDepthFit` → `seat_depth_score` (1 = OK, 2 = too long/short).
  - `phoneUsage` → `phone_score` (0/1/2).
  - `deskDuration` → `duration_modifier` (-1/0/+1).

### `workstation_questionnaire.dart`
A `ListView` form with three sections (Chair / Monitor & Telephone / Mouse &
Keyboard) plus a "Daily Duration" segmented control. `_BoolQuestion` is a
`SwitchListTile` wrapper; `_SectionHeader` is a styled section title. On
"Continue" it pops the screen with a populated `WorkstationAnswers`.

Note the inversions: the UI asks positive questions ("Chair height is
adjustable") but `WorkstationAnswers` stores the ROSA-style *negative*
modifier (`chairHeightNonAdjustable: !_chairHeightAdjustable`).

### `rosa_score.dart`
`RosaScore` — immutable model mirroring `RosaScorer.Result.toMap()` from the
Kotlin side (snake_case fields): `final_score`, `risk_level`, `chair_score`,
`peripheral_score`, `monitor_area_score`, `mouse_keyboard_area_score`,
`seat_height_score`, `backrest_score`, `armrest_score`, `monitor_score`,
`keyboard_score`, `mouse_score`. `fromMap`/`toMap` round-trip this; missing
keys default to `11` (an out-of-range "invalid" sentinel since valid ROSA
scores are 0–10).

### `review_screen.dart`
- `ReviewScreen` — scrollable list of `_PhotoScoreCard`, one per captured
  photo, then a "Continue" button → `SuccessScreen`.
- `_PhotoScoreCard`:
  - Shows the photo (tap → full-screen `GalleryImageViewer` synced to that
    index) with a colored "X / 10" badge (top-right) and "Photo N" label
    (top-left).
  - A colored header bar showing `ROSA Score: X / 10` and the risk-level
    chip (Low / Medium / High / Very High Risk).
  - Three `_SectionRow`s: **Chair** (sub-chips Seat/Back/Arms),
    **Monitor** (sub-chip Neck), **Keyboard / Mouse** (sub-chips
    Keys/Mouse). Each row shows a colored badge for its **area score**
    (`chair_score`, `monitor_area_score`, `mouse_keyboard_area_score`) plus
    chips for the underlying camera-derived sub-scores.
- `_riskColor(finalScore)` — green ≤2, amber ≤4, orange ≤6, red >6.
- `_subScoreColor(s)` — green ≤1, amber ≤2, red >2 (used for both the area
  badges and the individual chips, via `sectionColorFn`/`chipColorFn`).

### `image_viewer.dart`
Generic full-screen `PhotoViewGallery` wrapper (`GalleryImageViewer`) with
pinch-zoom, page swiping, and an optional "N / total" counter overlay. Used by
`ReviewScreen` for tapping through the captured photos.

### `success_screen.dart`
Simple "All Set!" confirmation screen with a button that pops back to
`StartScreen` (`pushReplacement`).

---

## 3. Native Android layer (`android/app/src/main/java/com/ooplab/exercises_fitfuel/`)

> Package/namespace: `com.ooplab.exercises_fitfuel`. (There's also a stale
> `com.example.posture_detector.MainActivity` left over from `flutter create`
> under `main/kotlin/` — it's unused; the manifest's `applicationId` is still
> `com.example.posture_detector` but `.MainActivity` resolves to the
> `exercises_fitfuel` namespace package.)

### `MainActivity.kt`
The Flutter↔native bridge.
- Registers a `MethodChannel("posture_detection")` handler for
  `"startDetection"`.
- On call: stores the Flutter `MethodChannel.Result` as `pendingResult`,
  converts the answers `Map` to a `JSONObject` string, and starts
  `PoseDetectionActivity` via `startActivityForResult` with that JSON as
  `EXTRA_WORKSTATION_ANSWERS`.
- `onActivityResult`: reads `EXTRA_PHOTO_PATHS` (string array) and
  `EXTRA_ROSA_SCORES` (JSON array string). For each score object, builds a
  snake_case `HashMap<String, Any>` (the `RosaScore.fromMap` contract) and
  resolves `pendingResult.success(...)` with `{photo_paths, rosa_scores}`. On
  cancel/failure, resolves with `null`.

### `PoseDetectionActivity.kt`
The core camera/ML pipeline. A single `AppCompatActivity` driving a 3-state
machine via `appState: AppState { LIGHT_CHECK, DETECTING, POSE }`.

**Setup (`onCreate`)**
- Parses `EXTRA_WORKSTATION_ANSWERS` JSON → `RosaScorer.WorkstationModifiers`
  (defaults if absent).
- Wires up views (preview, overlay, status panel, indicator rows).
- Starts `TiltMonitor` (accelerometer-based phone tilt/roll).
- Spins up a single-thread `cameraExecutor` and loads `YoloDetector` on it.
- "Switch camera" / "Reset" buttons call `fullReset()` (clears all
  state/captures and re-arms the pipeline).

**Phase 1 — `LIGHT_CHECK`** (`runLightCheckPhase`)
- Computes average luma over a sparse pixel grid (`computeLuminance`,
  step = 20px).
- If `luminance < 0.25` → "Room is too dark"; `> 0.85` → "Too bright";
  otherwise advances to `DETECTING`.

**Phase 2 — `DETECTING`** (`runDetectionPhase`)
- Runs `YoloDetector.detect()` (YOLOv8n TFLite) on each frame.
- Looks for **person** (class 0) AND a **monitor** (TV class 62 or laptop
  class 63).
- Requires `REQUIRED_CONFIRMATIONS = 4` consecutive frames with both
  detected before advancing — resets the counter if either drops out.
- On success: initializes the MediaPipe `PoseLandmarker`
  (`initializePoseLandmarker`), switches to `POSE`, disposes the YOLO
  detector (no longer needed), and fades out the detection panel.

**Phase 3 — `POSE`** (`runPosePhase` + `PoseLandmarker` result listener)
- Converts each YUV frame to an upright RGB `Bitmap` (rotation + front-camera
  mirroring) and feeds it to `poseLandmarker.detectAsync` (LIVE_STREAM mode).
- In the async result callback, for the first detected person:
  1. **Smoothing** — `LandmarkSmoother` (One-Euro filter per x/y per
     landmark) reduces jitter.
  2. **Side-view check** (`checkSideView`) — uses hip-spread / torso-height
     ratio (< `SIDE_VIEW_THRESHOLD = 0.35`) to confirm the camera is roughly
     side-on (~within 30°). Only computed once `appState == POSE`.
  3. **Leg estimation** — if side-view is OK, `LegEstimator.estimate()`
     reconstructs occluded knee/ankle/heel/foot landmarks for a seated
     side profile (see §5).
  4. **Height guide** — when `tiltIsOk && rotationIsOk`, checks the
     shoulder midpoint Y is within `0.43..0.57` of frame height; drives
     `PoseOverlayView`'s on-screen "raise/lower phone" guide line.
  5. **Distance estimate** — `DistanceEstimator.estimate()` from
     nose→hip pixel height + camera focal length/sensor size (Camera2
     characteristics read once at bind time); accepted range `1.7–2.1 m`.
  6. **ROSA angles** — `RosaAnglesCalculator.compute(smoothed)` produces
     knee/trunk/elbow/neck angles, shrug gap, wrist extension, mouse reach,
     etc. Drawn live via `PoseOverlayView.updateRosaAngles`.
  7. **Multi-shot capture** — when **all** of
     `sideOk && tiltIsOk && rotationIsOk && heightIsOk && distanceIsOk` hold
     for `SUCCESS_FRAMES_NEEDED = 20` consecutive frames *and* the
     `CAPTURE_COOLDOWN_MS = 2000` cooldown since the last shot has elapsed:
     - Face-blurs the frame (`FaceBlurrer`), bakes the skeleton + angle arcs
       onto it (`bakeSkeletonOntoPhoto`), and scores it
       (`RosaScorer.score(angles, workstationModifiers)`).
     - Stores the bitmap + score; flashes the screen
       (`triggerCaptureFlash`); updates the capture-progress caption
       (`updateCaptureCue`).
     - After `TOTAL_SHOTS_NEEDED = 3` photos, pauses the camera
       (`pauseCameraPipeline`) and finishes the activity
       (`finishWithCapturedPhotos`), writing JPEGs to
       `cacheDir/posture_photos/photo_N.jpg` and serialising scores to a JSON
       array via `EXTRA_ROSA_SCORES`.
     - If `angles.lowerBodyConfidence == LOW` (knee landmark itself was
       reconstructed), logs a `Log.d("RosaScorer", ...)` note that the
       seat-height score is a best-effort guess — diagnostic only, not
       surfaced in the UI.

**Status panel** (`updatePanel`) drives the colored indicator rows
(light/person/monitor + confirmation progress bar + status message) for
phases 1–2; tilt/rotation/side/distance indicators are updated directly from
their respective callbacks during phase 3.

### `YoloDetector.kt`
Wraps a TFLite `yolov8n_float16.tflite` model (320×320 input, 80 COCO
classes, 2100 candidates).
- `buildInputTensor` does YUV420→RGB conversion *and* rotation/resize to
  320×320 in one pass (handles 0/90/180/270° rotation from the camera).
- `parseAndNms` filters by per-class confidence (`0.45` general,
  `0.30` for TV/laptop — monitors are smaller/harder to detect) then
  per-class NMS (`IOU > 0.45` suppressed).
- `detect()` returns `YoloResult(personDetected, monitorDetected, ...)` —
  person = class 0, monitor = class 62 (TV) or 63 (laptop).
- Tries GPU delegate first, falls back to 4-thread CPU.

### `LandmarkSmoother.kt` / `OneEuroFilter.kt`
- `LandmarkPoint(x, y, estimated: Boolean = false)` — the common point type
  used everywhere downstream of smoothing. `estimated = true` marks
  landmarks reconstructed by `LegEstimator` (occluded knee/ankle/etc.),
  rendered as dashed lines / translucent dots.
- `LandmarkSmoother` runs one `OneEuroFilter` per axis per of the 33
  MediaPipe landmarks (`minCutoff = 0.5`, `beta = 0.5` as configured in
  `PoseDetectionActivity`).
- `OneEuroFilter` — standard One-Euro adaptive low-pass filter: more
  smoothing when the signal is near-static, less lag during fast motion
  (cutoff = `minCutoff + beta * |dx̂/dt|`).

### `LegEstimator.kt`
Stateful reconstructor for hidden lower-body landmarks of a **seated, side-on**
subject (knee/ankle/heel/foot are frequently occluded by the desk).
- **Standing guard** — if either knee is high-confidence
  (`visibility ≥ HIGH_CONFIDENCE = 0.65`) and clearly below the hip
  (drop > 50% of torso length), the person is standing; landmarks pass
  through untouched.
- **Facing direction** — a rolling 20-frame vote
  (`updateFacingVote`/`lockedFacingSign`) on which side of the shoulder
  midpoint the nose sits, locked once ≥70% of recent frames agree (prevents
  frame-to-frame flips).
- **Per-leg reconstruction** (independently for left/right, each anchored to
  its own hip):
  - If the raw knee landmark is high-confidence, use it as-is.
  - Otherwise, place the knee at
    `hip + facingSign * (torsoLen * THIGH_RATIO=0.90)` horizontally and
    `hip.y + torsoLen * SEATED_THIGH_DROP=0.08` vertically, marked
    `estimated = true`.
  - If the ankle isn't high-confidence, place it directly below the (real or
    estimated) knee at `kneeY + torsoLen * SHIN_RATIO=0.90`, also
    `estimated = true`.
  - Heel/foot-index landmarks collapse onto the ankle position when not
    high-confidence (avoids stray lines).

### `RosaAnglesCalculator.kt`
Computes the geometric inputs to ROSA scoring from one frame's 33 landmarks.
- Picks the **near (visible) side** by comparing nose→ear distances (the
  near ear is farther from the nose in 2D in a side view).
- **`kneeAngle`** (seat height) — see §5 for the full occlusion-aware logic.
  Also produces `lowerBodyConfidence: HIGH | LOW`.
- **`trunkAngle`** — angle of the shoulder→hip line from vertical
  (backrest score).
- **`elbowAngle`** — shoulder→elbow→wrist angle (informational/overlay).
- **`neckAngle`** — ear→shoulder line angle from vertical, plus a
  **`neckState`** classifier (`NEUTRAL`, `FORWARD_HEAD`, `MILD_FLEXION`,
  `SEVERE_FLEXION`, `HEAD_BACK`) derived from `noseAboveEar`,
  `earShoulderVert`, `neckFlexY`, `earForward` thresholds — this drives the
  monitor/neck ROSA sub-score.
- **`shrugGap`** = `ear.y - shoulder.y` (armrest score: shoulder hiked
  toward ear).
- **`wristExtension`** = `elbow.y - wrist.y` (keyboard score).
- **`mouseReach`** = `|wrist.x - shoulder.x|` (mouse score).
- `angleBetween(p1, vertex, p2)` — generic 2D angle helper via dot product.

### `RosaScorer.kt`
Pure scoring object implementing the ROSA Tables A/B/C lookups (Cornell /
Sonne 2012 methodology). See **§4** for the full scoring breakdown.

### `PoseOverlayView.kt`
Custom `View` drawn over the camera preview:
- Skeleton (33-point MediaPipe connections, `POSE_CONNECTIONS`), with dashed
  translucent lines/dots for `estimated` landmarks.
- Height-guide line (`HeightGuideState`: HIDDEN/TOO_HIGH/TOO_LOW/OK) with
  "raise/lower phone" labels, target at `y = 0.45`.
- ROSA angle arcs (`drawAngles`/`drawArc`, shared with the photo-baking code
  in `PoseDetectionActivity` so the live overlay and the saved photo look
  identical): knee angle (hip-knee-ankle), trunk angle (shoulder-hip vs.
  vertical), neck angle (ear-shoulder vs. vertical), elbow angle
  (shoulder-elbow-wrist). Each arc has a black outline pass for visibility on
  any background.

### `FaceBlurrer.kt`
Pixelates the face region of a captured photo before it's saved/baked:
- Center = nose landmark; radius = nose↔(farther ear) distance ×
  `RADIUS_MARGIN = 1.25` (or `6%` of image height if no ear is usable).
- Downscales the region by `DOWNSCALE_FACTOR = 12` then scales back up
  (mosaic/pixelation effect), drawn back over the original.

### `DistanceEstimator.kt`
Estimates camera-to-subject distance from the nose→hip-midpoint pixel span:
```
focal_length_px = (focalMm / sensorHeightMm) × imageHeightPx
real_torso_cm   = personHeightCm(170) × TORSO_RATIO(0.37)
distance_cm     = (real_torso_cm × focal_length_px) / pixelHeight
```
Returns `null` if the pixel height is degenerate (< 20px) or optics data is
invalid.

### `TiltMonitor.kt`
Accelerometer-based phone orientation:
- Low-pass filters raw accelerometer values (`ALPHA = 0.1`).
- `tilt` = inclination from horizontal (90° = perfectly upright portrait);
  acceptable range `85–95°`.
- `roll` = lateral tilt via `atan2(fx, fy)` (avoids gimbal lock near ±90°
  pitch); acceptable `|roll| ≤ 15°`.

---

## 4. ROSA scoring (`RosaScorer.kt`)

ROSA combines a **camera-derived base score (1–3)** for each body
region with **manual checklist modifiers** (+1/+2 for non-adjustable
furniture, glare, awkward postures, etc.) into an **area score**, which is
then run through one of three lookup tables.

### Section A — Chair → `chairScore`
| Camera-derived base | Manual modifiers added |
|---|---|
| `seatHeightScore` (1–3, from `kneeAngle`) | `chairHeightNonAdjustable`, `insufficientUnderDeskSpace` → **chairHeightArea** |
| `mods.seatDepthScore` (1 or 2) | `seatPanNonAdjustable` → **panDepthArea** |
| `armrestScore` (1–2, from `shrugGap`) | `armrestNonAdjustable`, `armrestHardDamaged`, `armrestTooWide` → **armrestArea** |
| `backrestScore` (1–2, from `trunkAngle`) | `backrestNonAdjustable`, `workSurfaceTooHigh` → **backSupportArea** |

```
seatCombined = clamp(chairHeightArea + panDepthArea, 2, 8)   // Table A row
armsCombined = clamp(armrestArea + backSupportArea, 2, 9)     // Table A col
chairScore   = clamp(TableA[seatCombined][armsCombined] + durationModifier, 1, 10)
```

`seatHeightScore` thresholds (from `kneeAngle`):
`< 80° → 2` (chair too low), `> 130° → 3` (legs extended/feet off floor),
`> 100° → 2` (chair too high), else `1` (neutral).

`backrestScore`: `trunkAngle > 28° → 2`, else `1`.
`armrestScore`: `shrugGap > -0.06 → 2` (shoulder hiked), else `1`.

### Section B — Monitor & Telephone → `sectB` (= `monitorAreaScore`)
- `monitorScore` (1–3) from `neckState`: `NEUTRAL → 1`,
  `MILD_FLEXION`/`FORWARD_HEAD → 2`, `SEVERE_FLEXION`/`HEAD_BACK → 3`.
- `monitorArea = monitorScore + monitorNonAdjustable + neckTwistOver30 +
  monitorTooFar + screenGlare + noDocumentHolder` (each `+1`).
- `phoneArea = mods.phoneScore (0/1/2) + phoneCradleNeckShoulder(+2) +
  noHandsFreeOption(+1)`.
```
sectB = TableB[clamp(phoneArea + duration, 0, 6)][clamp(monitorArea + duration, 0, 7)]
```

### Section C — Mouse & Keyboard → `sectC` (= `mouseKeyboardAreaScore`)
- `keyboardScore` (1–3) from `wristExtension`: `> 0.07 → 3`, `> 0.03 → 2`,
  else `1`.
- `keyboardArea = keyboardScore + keyboardDeviation + keyboardTooHigh +
  reachingOverhead + keyboardPlatformNonAdjustable` (each `+1`).
- `mouseScore` (1–2) from `mouseReach`: `> 0.18 → 2`, else `1`.
- `mouseArea = mouseScore + mouseKeyboardDifferentSurfaces(+2) +
  mousePinchGrip(+1) + mousePalmrest(+1) + mouseNonAdjustable(+1)`.
```
sectC = TableC[clamp(mouseArea + duration, 0, 7)][clamp(keyboardArea + duration, 0, 7)]
```

### Combine (Tables D/E — both "max wins")
```
peripheralScore = clamp(max(sectB, sectC), 1, 9)
finalScore      = clamp(max(chairScore, peripheralScore), 1, 10)

riskLevel = finalScore <= 2 ? "Low Risk"
          : finalScore <= 4 ? "Medium Risk"
          : finalScore <= 6 ? "High Risk"
          : "Very High Risk"
```

`tlu(table, row, col)` clamps `row`/`col` to each table's actual key range
before lookup, so out-of-range sums never crash.

`durationModifier` (from `DeskDuration`: short = -1, medium = 0, long = +1)
is added into every Table B/C row/col input, and added directly onto
`chairScore` for Table A.

### `Result` (returned to Flutter)
`finalScore, riskLevel, chairScore, peripheralScore, monitorAreaScore,
mouseKeyboardAreaScore, seatHeightScore, backrestScore, armrestScore,
monitorScore, keyboardScore, mouseScore, lowerBodyConfidence`. The last field
(`HIGH`/`LOW`) is diagnostic-only — not currently surfaced in the Flutter UI.

---

## 5. Occlusion-aware seat-height scoring

When seated at a desk, the knee and/or ankle landmarks are frequently hidden.
`RosaAnglesCalculator.compute()` handles three cases for `kneeAngle`:

1. **Knee itself estimated** (`knee.estimated == true`, reconstructed by
   `LegEstimator`) → use the **hip-knee gap proxy** (below) and mark
   `lowerBodyConfidence = LOW`.
2. **Only the ankle is estimated** (knee is real, ankle is a fabricated
   straight-down point) → `angleBetween(hip, knee, ankle)` would be distorted
   by the fake ankle, so use the **gap proxy** instead, with
   `lowerBodyConfidence = HIGH` (the knee position itself is trustworthy).
3. **Both real** → compute `angleBetween(hip, knee, ankle)` normally. If the
   result is implausibly straight (`> 160°`, essentially impossible while
   seated), fall back to the gap proxy with `LOW` confidence — likely a
   pose-estimation glitch.

**Gap proxy** — based on the vertical hip→knee gap
(`gap = knee.y - hip.y`, normalized image coordinates):
```
gap < -0.02   → 70°   (knee raised above hip)
gap > 0.15    → 115°  (knee well below hip → seatHeightScore = 2, chair too high)
otherwise     → 92°   (knee level with hip → seatHeightScore = 1, neutral)
```
These three buckets are chosen to land on the correct side of the
`seatHeightScore` thresholds (`<80`, `>100`, `>130`) used downstream.

When `lowerBodyConfidence == LOW`, `PoseDetectionActivity` logs a
`Log.d("RosaScorer", ...)` note per captured shot — informational only, no
UI/score change. (See `oclusionlogic.docx` for the original full spec this
was scoped down from — the interactive re-take/Q&A flow it describes was not
implemented.)

---

## 6. MethodChannel data contract

**Flutter → Native** (`startDetection` argument — `WorkstationAnswers.toMap()`):
snake_case keys, e.g. `chair_height_non_adjustable: bool`,
`seat_depth_score: int (1|2)`, `phone_score: int (0-2)`,
`duration_modifier: int (-1|0|1)`, etc. — see
`RosaScorer.WorkstationModifiers.fromMap()` for the full key list.

**Native → Flutter** (`startDetection` result):
```jsonc
{
  "photo_paths": ["/.../photo_1.jpg", "/.../photo_2.jpg", "/.../photo_3.jpg"],
  "rosa_scores": [
    {
      "final_score": 5, "risk_level": "High Risk",
      "chair_score": 4, "peripheral_score": 5,
      "monitor_area_score": 3, "mouse_keyboard_area_score": 5,
      "seat_height_score": 1, "backrest_score": 2, "armrest_score": 1,
      "monitor_score": 1, "keyboard_score": 2, "mouse_score": 1
    }
    // ...one per photo, or {} if angles couldn't be computed
  ]
}
```
A `null` result means the user backed out of `PoseDetectionActivity` without
completing capture.

---

## 7. Other notes

- **Models**: `pose_landmarker_full.task` (MediaPipe, 33-point body pose) and
  `yolov8n_float16.tflite` (COCO, used only for person+monitor presence
  gating before pose tracking starts) live in
  `android/app/src/main/assets/`.
- **Photo storage**: captured JPEGs (skeleton + angle arcs baked in, face
  pixelated) are written to `cacheDir/posture_photos/photo_N.jpg` — cleared
  naturally by Android's cache management, not explicitly by the app.
- **Reset/retry**: the "Reset" and "switch camera" buttons in
  `PoseDetectionActivity` call `fullReset()`, which clears all captured
  photos/scores, resets smoothing/leg-estimation state, and restarts from
  `LIGHT_CHECK`.
- **`ROSA_CALCULATION.md`** — a plain-language (non-code) walkthrough of the
  same Measure → Rate → Combine → Interpret pipeline described in §4–5,
  written for a non-technical reader.
- **`ROSA forms.pdf`** — the original ROSA checklist/reference tables this
  implementation is based on.
- **`oclusionlogic.docx`** — the original "strict enterprise occlusion logic"
  spec; only a scoped-down subset (the gap proxy + confidence flag in §5) was
  implemented.

---

## 8. Project structure

```
lib/                                   Flutter UI
├── main.dart                          App entry point (MaterialApp → StartScreen)
├── start_screen.dart                  "Start" button; owns the MethodChannel call
├── workstation_questionnaire.dart     Pre-camera ROSA checklist form
├── workstation_answers.dart           Answer model + enums + toMap()
├── review_screen.dart                 Photo + score breakdown cards
├── rosa_score.dart                    RosaScore model (fromMap/toMap)
├── image_viewer.dart                  Full-screen pinch-zoom photo gallery
└── success_screen.dart                "All Set!" confirmation

android/app/src/main/
├── AndroidManifest.xml                CAMERA permission, activity declarations
├── assets/
│   ├── pose_landmarker_full.task      MediaPipe pose model
│   └── yolov8n_float16.tflite         YOLOv8n COCO detector
├── res/layout/activity_main.xml       PoseDetectionActivity's layout (see below)
├── kotlin/com/example/posture_detector/MainActivity.kt   unused flutter-create boilerplate
└── java/com/ooplab/exercises_fitfuel/ All app/ML logic (this is the real package)
    ├── MainActivity.kt                MethodChannel bridge
    ├── PoseDetectionActivity.kt       Camera state machine + capture pipeline
    ├── YoloDetector.kt                YOLOv8n person/monitor detection
    ├── LandmarkSmoother.kt            One-Euro smoothing of MediaPipe landmarks
    ├── OneEuroFilter.kt               Generic adaptive low-pass filter
    ├── LegEstimator.kt                Reconstructs occluded seated leg landmarks
    ├── RosaAnglesCalculator.kt        Pose → joint angles + neck state
    ├── RosaScorer.kt                  ROSA Tables A/B/C scoring
    ├── PoseOverlayView.kt             Skeleton/angle/height-guide overlay view
    ├── FaceBlurrer.kt                 Pixelates face region in captured photos
    ├── DistanceEstimator.kt           Camera-to-subject distance estimate
    └── TiltMonitor.kt                 Accelerometer tilt/roll monitor

ROSA_CALCULATION.md                    Plain-language ROSA methodology walkthrough
ROSA forms.pdf                         Original ROSA reference tables/checklist
oclusionlogic.docx                     Reference spec for occlusion handling (§5)
```

### `activity_main.xml` (PoseDetectionActivity's layout)
A `ConstraintLayout` containing: `previewCam` (camera preview),
`poseOverlay` (`PoseOverlayView`), four always/conditionally-visible status
chips stacked top-center (`tvTiltStatus`, `tvRotationStatus`,
`tvDistanceStatus`, `tvSideViewStatus`), `tvCaptureStatus` (multi-shot
progress caption), the `detectionPanel` (light/person/monitor status block
with `confirmProgress` bar and `tvStatusMessage`, shown during
LIGHT_CHECK/DETECTING), `btnSwitchCamera` / `btnReset` buttons (top
corners), and `flashOverlay` (full-screen white flash on capture).

---

## 9. Tech stack, build & run

- **Flutter** SDK `^3.10.4`, Material 3. Dart deps: `photo_view ^0.15.0`,
  `cupertino_icons ^1.0.8` (no backend/network dependencies — everything is
  on-device).
- **Android**: `minSdk 30`, `targetSdk 35`, Java/Kotlin 11.
  Key deps: `androidx.camera:*:1.3.4`,
  `com.google.mediapipe:tasks-vision:0.20230731`,
  `org.tensorflow:tensorflow-lite(-gpu):2.14.0`.
- **`noCompress += listOf("tflite", "task")`** in `build.gradle.kts` is
  required — MediaPipe/TFLite open their model files via
  `AssetFileDescriptor`, which needs the asset stored uncompressed in the
  APK. Without this, release builds crash at runtime when loading the
  models (debug `flutter run` deploys assets separately and isn't affected).
- **Permissions**: `android.permission.CAMERA` only (declared in
  `AndroidManifest.xml`, requested at runtime in
  `PoseDetectionActivity.requestCameraPermission`).
- **Run**: `flutter pub get` then `flutter run` (debug) or
  `flutter build apk --release`. Release builds currently sign with the
  debug keystore (see the `TODO` in `android/app/build.gradle.kts`).

---

## 10. Known quirks

- `test/widget_test.dart` is unmodified `flutter create` boilerplate — it
  references a `MyApp`/counter demo that doesn't exist in this app (the real
  entry widget is `App` in `main.dart`, with no counter). It will fail if
  run and isn't representative of the app.
- `applicationId` is still `com.example.posture_detector` (from the original
  `flutter create`), while the actual namespace and all real source live
  under `com.ooplab.exercises_fitfuel` — see the note in §3.
