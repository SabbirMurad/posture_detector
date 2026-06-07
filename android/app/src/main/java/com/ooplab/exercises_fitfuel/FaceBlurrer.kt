package com.ooplab.exercises_fitfuel

import android.graphics.Bitmap
import android.graphics.Canvas
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Blurs the face region of a captured photo using pose landmark positions —
 * ported from live_guidence's FaceBlurrer (nose + ear based bounding box with
 * a generous margin), adapted to MediaPipe's 33-point landmark indices
 * (0 = nose, 7 = left ear, 8 = right ear).
 */
object FaceBlurrer {

    private const val NOSE_INDEX      = 0
    private const val LEFT_EAR_INDEX  = 7
    private const val RIGHT_EAR_INDEX = 8

    // Margin around the nose↔ear distance so the face is covered without
    // spilling much into hair/neck/shoulders
    private const val RADIUS_MARGIN = 1.25f
    // Fallback radius when no ear landmark is usable — fraction of image height
    private const val FALLBACK_RADIUS_FRACTION = 0.06f
    // Downscale factor for the pixelation blur — higher = stronger blur
    private const val DOWNSCALE_FACTOR = 12

    /** Blurs the face region of [source] in place using [landmarks]; returns [source]. */
    fun blurFace(source: Bitmap, landmarks: List<LandmarkPoint>): Bitmap {
        if (landmarks.size <= RIGHT_EAR_INDEX) return source

        val w = source.width
        val h = source.height
        val nose = landmarks[NOSE_INDEX]
        val cx = nose.x * w
        val cy = nose.y * h

        // In a side-on view the visible (near) ear sits farther from the nose
        // in 2D than the occluded (far) one — pick whichever is farther.
        val ear = listOf(landmarks[LEFT_EAR_INDEX], landmarks[RIGHT_EAR_INDEX])
            .maxByOrNull { hypot((nose.x - it.x) * w, (nose.y - it.y) * h) }

        val radius = if (ear != null) {
            hypot((nose.x - ear.x) * w, (nose.y - ear.y) * h) * RADIUS_MARGIN
        } else {
            h * FALLBACK_RADIUS_FRACTION
        }
        if (radius < 1f) return source

        val left   = (cx - radius).roundToInt().coerceIn(0, w - 1)
        val top    = (cy - radius).roundToInt().coerceIn(0, h - 1)
        val right  = (cx + radius).roundToInt().coerceIn(0, w - 1)
        val bottom = (cy + radius).roundToInt().coerceIn(0, h - 1)
        val regionW = right - left
        val regionH = bottom - top
        if (regionW <= 0 || regionH <= 0) return source

        val region = Bitmap.createBitmap(source, left, top, regionW, regionH)
        val smallW = max(1, regionW / DOWNSCALE_FACTOR)
        val smallH = max(1, regionH / DOWNSCALE_FACTOR)
        val pixelated = Bitmap.createScaledBitmap(
            Bitmap.createScaledBitmap(region, smallW, smallH, true),
            regionW, regionH, true
        )

        Canvas(source).drawBitmap(pixelated, left.toFloat(), top.toFloat(), null)
        return source
    }
}
