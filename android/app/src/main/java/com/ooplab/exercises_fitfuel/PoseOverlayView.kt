package com.ooplab.exercises_fitfuel

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Typeface
import android.util.AttributeSet
import android.view.View

class PoseOverlayView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    enum class HeightGuideState { HIDDEN, TOO_HIGH, TOO_LOW, OK }

    // Target normalized y in landmark space where the shoulder should land.
    // At this y the guide line and the shoulder dot will overlap visually.
    private val TARGET_GUIDE_Y = 0.45f

    private val dotPaint = Paint().apply {
        color = Color.GREEN
        style = Paint.Style.FILL
        isAntiAlias = true
    }
    private val linePaint = Paint().apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 6f
        isAntiAlias = true
    }
    private val estimatedDotPaint = Paint().apply {
        color = Color.argb(160, 0, 220, 0)
        style = Paint.Style.FILL
        isAntiAlias = true
    }
    private val estimatedLinePaint = Paint().apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 4f
        isAntiAlias = true
        pathEffect = DashPathEffect(floatArrayOf(14f, 9f), 0f)
    }

    // Guide line — dashed, spans full screen width
    private val guideLinePaint = Paint().apply {
        style = Paint.Style.STROKE
        strokeWidth = 3f
        isAntiAlias = true
        pathEffect = DashPathEffect(floatArrayOf(22f, 13f), 0f)
    }
    // Small bracket ticks at the midpoint of the line
    private val guideTickPaint = Paint().apply {
        style = Paint.Style.STROKE
        strokeWidth = 5f
        isAntiAlias = true
    }
    private val guideLabelPaint = Paint().apply {
        textSize = 42f
        isAntiAlias = true
        typeface = Typeface.DEFAULT_BOLD
    }

    private var landmarks: List<LandmarkPoint> = emptyList()
    private var imageWidth: Int = 1
    private var imageHeight: Int = 1
    private var heightGuideState = HeightGuideState.HIDDEN

    companion object {
        val POSE_CONNECTIONS = listOf(
            // Face
            0 to 1, 1 to 2, 2 to 3, 3 to 7,
            0 to 4, 4 to 5, 5 to 6, 6 to 8,
            9 to 10,
            // Shoulders
            11 to 12,
            // Left arm
            11 to 13, 13 to 15, 15 to 17, 17 to 19, 19 to 15, 15 to 21,
            // Right arm
            12 to 14, 14 to 16, 16 to 18, 18 to 20, 20 to 16, 16 to 22,
            // Torso
            11 to 23, 12 to 24, 23 to 24,
            // Left leg
            23 to 25, 25 to 27, 27 to 29, 29 to 31, 31 to 27,
            // Right leg
            24 to 26, 26 to 28, 28 to 30, 30 to 32, 32 to 28
        )
    }

    fun updateLandmarks(newLandmarks: List<LandmarkPoint>, imgWidth: Int, imgHeight: Int) {
        landmarks = newLandmarks
        imageWidth = imgWidth
        imageHeight = imgHeight
        postInvalidate()
    }

    fun setHeightGuide(state: HeightGuideState) {
        if (heightGuideState == state) return
        heightGuideState = state
        postInvalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (imageWidth <= 1) return

        // Letterbox fit — scale the full frame down to fit within the view while
        // preserving aspect ratio (mirrors PreviewView's fitCenter), with bars on
        // the sides. Keeps the skeleton aligned with the now-uncropped live preview.
        val scale   = minOf(width.toFloat() / imageWidth, height.toFloat() / imageHeight)
        val offsetX = (width  - imageWidth  * scale) / 2f
        val offsetY = (height - imageHeight * scale) / 2f

        fun sx(x: Float) = x * imageWidth  * scale + offsetX
        fun sy(y: Float) = y * imageHeight * scale + offsetY

        // ── Height guide line (drawn behind the skeleton) ──────────────────────
        if (heightGuideState != HeightGuideState.HIDDEN) {
            val lineY = sy(TARGET_GUIDE_Y)
            val baseColor = if (heightGuideState == HeightGuideState.OK)
                Color.GREEN else Color.RED

            guideLinePaint.color = Color.argb(200,
                Color.red(baseColor), Color.green(baseColor), Color.blue(baseColor))
            canvas.drawLine(0f, lineY, width.toFloat(), lineY, guideLinePaint)

            // Bracket ticks at center — acts as a visual target crosshair
            guideTickPaint.color = baseColor
            val cx = width / 2f
            canvas.drawLine(cx - 40f, lineY - 18f, cx - 40f, lineY + 18f, guideTickPaint)
            canvas.drawLine(cx + 40f, lineY - 18f, cx + 40f, lineY + 18f, guideTickPaint)
            canvas.drawLine(cx - 40f, lineY, cx - 14f, lineY, guideTickPaint)
            canvas.drawLine(cx + 14f, lineY, cx + 40f, lineY, guideTickPaint)

            // Directional label to the right of center
            val label = when (heightGuideState) {
                HeightGuideState.TOO_HIGH -> "▼  Lower phone"
                HeightGuideState.TOO_LOW  -> "▲  Raise phone"
                HeightGuideState.OK       -> "✓  Height OK"
                HeightGuideState.HIDDEN   -> ""
            }
            guideLabelPaint.color = baseColor
            canvas.drawText(label, cx + 56f, lineY - 12f, guideLabelPaint)
        }

        if (landmarks.isEmpty()) return

        // ── Skeleton connections ───────────────────────────────────────────────
        for ((start, end) in POSE_CONNECTIONS) {
            if (start < landmarks.size && end < landmarks.size) {
                val s = landmarks[start]
                val e = landmarks[end]
                val paint = if (s.estimated || e.estimated) estimatedLinePaint else linePaint
                canvas.drawLine(sx(s.x), sy(s.y), sx(e.x), sy(e.y), paint)
            }
        }

        // ── Landmark dots ──────────────────────────────────────────────────────
        for (lm in landmarks) {
            if (lm.estimated) {
                canvas.drawCircle(sx(lm.x), sy(lm.y), 9f, estimatedDotPaint)
            } else {
                canvas.drawCircle(sx(lm.x), sy(lm.y), 12f, dotPaint)
            }
        }
    }
}
