package com.ooplab.exercises_fitfuel

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.util.AttributeSet
import android.view.View
import kotlin.math.*

class PoseOverlayView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    enum class HeightGuideState { HIDDEN, TOO_HIGH, TOO_LOW, OK }

    private val TARGET_GUIDE_Y = 0.45f

    private val dotPaint = Paint().apply {
        color = Color.GREEN; style = Paint.Style.FILL; isAntiAlias = true
    }
    private val linePaint = Paint().apply {
        color = Color.WHITE; style = Paint.Style.STROKE; strokeWidth = 6f; isAntiAlias = true
    }
    private val estimatedDotPaint = Paint().apply {
        color = Color.argb(160, 0, 220, 0); style = Paint.Style.FILL; isAntiAlias = true
    }
    private val estimatedLinePaint = Paint().apply {
        color = Color.WHITE; style = Paint.Style.STROKE; strokeWidth = 4f; isAntiAlias = true
        pathEffect = DashPathEffect(floatArrayOf(14f, 9f), 0f)
    }
    private val guideLinePaint = Paint().apply {
        style = Paint.Style.STROKE; strokeWidth = 3f; isAntiAlias = true
        pathEffect = DashPathEffect(floatArrayOf(22f, 13f), 0f)
    }
    private val guideTickPaint  = Paint().apply { style = Paint.Style.STROKE; strokeWidth = 5f; isAntiAlias = true }
    private val guideLabelPaint = Paint().apply { textSize = 42f; isAntiAlias = true; typeface = Typeface.DEFAULT_BOLD }

    // ROSA angle arc paints — instance fields so no allocation per frame
    private val arcPaint = Paint().apply {
        color = Color.parseColor("#FF5722"); style = Paint.Style.STROKE; strokeWidth = 4f; isAntiAlias = true
    }
    private val vertRefPaint = Paint().apply {
        color = Color.argb(200, 255, 87, 34); style = Paint.Style.STROKE; strokeWidth = 3f; isAntiAlias = true
        pathEffect = DashPathEffect(floatArrayOf(12f, 8f), 0f)
    }
    private val angleLabelPaint = Paint().apply {
        color = Color.parseColor("#FF5722"); textSize = 36f; isAntiAlias = true
        typeface = Typeface.DEFAULT_BOLD; textAlign = Paint.Align.CENTER
    }

    private var landmarks: List<LandmarkPoint> = emptyList()
    private var imageWidth: Int = 1
    private var imageHeight: Int = 1
    private var heightGuideState = HeightGuideState.HIDDEN
    private var rosaAngles: RosaAnglesCalculator.Angles? = null
    // Landmark indices to omit from both connections and dots. Empty for the side
    // shots (full skeleton); set during the front phase to mirror the captured
    // photo (face/ears, wrist/palm and legs dropped).
    private var excludedIndices: Set<Int> = emptySet()

    fun updateLandmarks(newLandmarks: List<LandmarkPoint>, imgWidth: Int, imgHeight: Int) {
        landmarks = newLandmarks
        imageWidth = imgWidth
        imageHeight = imgHeight
        postInvalidate()
    }

    fun setExcludedIndices(indices: Set<Int>) {
        if (excludedIndices == indices) return
        excludedIndices = indices
        postInvalidate()
    }

    fun updateRosaAngles(angles: RosaAnglesCalculator.Angles?) {
        rosaAngles = angles
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

        val scale   = minOf(width.toFloat() / imageWidth, height.toFloat() / imageHeight)
        val offsetX = (width  - imageWidth  * scale) / 2f
        val offsetY = (height - imageHeight * scale) / 2f

        fun sx(x: Float) = x * imageWidth  * scale + offsetX
        fun sy(y: Float) = y * imageHeight * scale + offsetY

        // ── Height guide line ──────────────────────────────────────────────────
        if (heightGuideState != HeightGuideState.HIDDEN) {
            val lineY = sy(TARGET_GUIDE_Y)
            val baseColor = if (heightGuideState == HeightGuideState.OK) Color.GREEN else Color.RED
            guideLinePaint.color = Color.argb(200, Color.red(baseColor), Color.green(baseColor), Color.blue(baseColor))
            canvas.drawLine(0f, lineY, width.toFloat(), lineY, guideLinePaint)
            guideTickPaint.color = baseColor
            val cx = width / 2f
            canvas.drawLine(cx - 40f, lineY - 18f, cx - 40f, lineY + 18f, guideTickPaint)
            canvas.drawLine(cx + 40f, lineY - 18f, cx + 40f, lineY + 18f, guideTickPaint)
            canvas.drawLine(cx - 40f, lineY, cx - 14f, lineY, guideTickPaint)
            canvas.drawLine(cx + 14f, lineY, cx + 40f, lineY, guideTickPaint)
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
            if (start in excludedIndices || end in excludedIndices) continue
            if (start < landmarks.size && end < landmarks.size) {
                val s = landmarks[start]; val e = landmarks[end]
                val paint = if (s.estimated || e.estimated) estimatedLinePaint else linePaint
                canvas.drawLine(sx(s.x), sy(s.y), sx(e.x), sy(e.y), paint)
            }
        }

        // ── Landmark dots ──────────────────────────────────────────────────────
        for ((i, lm) in landmarks.withIndex()) {
            if (i in excludedIndices) continue
            if (lm.estimated) canvas.drawCircle(sx(lm.x), sy(lm.y), 5f, estimatedDotPaint)
            else              canvas.drawCircle(sx(lm.x), sy(lm.y), 7f, dotPaint)
        }

        // ── ROSA angle arcs ────────────────────────────────────────────────────
        val ra = rosaAngles
        if (ra != null && landmarks.size >= 29) {
            drawAngles(canvas, landmarks, ra, ::sx, ::sy, arcPaint, vertRefPaint, angleLabelPaint)
        }
    }

    companion object {
        val POSE_CONNECTIONS = listOf(
            0 to 1, 1 to 2, 2 to 3, 3 to 7,
            0 to 4, 4 to 5, 5 to 6, 6 to 8,
            9 to 10,
            7 to 11, 8 to 12,
            11 to 12,
            11 to 13, 13 to 15, 15 to 17, 17 to 19, 19 to 15, 15 to 21,
            12 to 14, 14 to 16, 16 to 18, 18 to 20, 20 to 16, 16 to 22,
            11 to 23, 12 to 24, 23 to 24,
            23 to 25, 25 to 27, 27 to 29, 29 to 31, 31 to 27,
            24 to 26, 26 to 28, 28 to 30, 30 to 32, 32 to 28
        )

        /** MediaPipe's canonical 21-point hand skeleton: thumb, four fingers, palm. */
        val HAND_CONNECTIONS = listOf(
            0 to 1, 1 to 2, 2 to 3, 3 to 4,        // thumb
            0 to 5, 5 to 6, 6 to 7, 7 to 8,        // index
            5 to 9, 9 to 10, 10 to 11, 11 to 12,   // middle
            9 to 13, 13 to 14, 14 to 15, 15 to 16, // ring
            13 to 17, 17 to 18, 18 to 19, 19 to 20,// pinky
            0 to 17,                                // palm base
        )

        /** Draws the detected hands and the elbow→wrist connector. Shared by the live
         *  overlay and bakeSkeletonOntoPhoto so both look identical. Uses the same
         *  [linePaint]/[dotPaint] as the body skeleton so the hand reads as a
         *  continuation of the arm. [poseLandmarks] supplies the elbows (13/14);
         *  each hand's wrist (point 0) is joined to its nearest elbow. */
        fun drawHands(
            canvas: Canvas,
            hands: List<List<LandmarkPoint>>,
            poseLandmarks: List<LandmarkPoint>,
            sx: (Float) -> Float,
            sy: (Float) -> Float,
            linePaint: Paint,
            dotPaint: Paint,
            dotRadius: Float,
        ) {
            val elbows = listOfNotNull(poseLandmarks.getOrNull(13), poseLandmarks.getOrNull(14))
            for (hand in hands) {
                val h0 = hand.getOrNull(0)
                if (h0 != null && elbows.isNotEmpty()) {
                    // Nearest elbow by squared pixel distance (comparable, no sqrt).
                    val nearest = elbows.minByOrNull {
                        val dx = sx(it.x) - sx(h0.x); val dy = sy(it.y) - sy(h0.y)
                        dx * dx + dy * dy
                    }!!
                    canvas.drawLine(sx(nearest.x), sy(nearest.y), sx(h0.x), sy(h0.y), linePaint)
                }
                for ((start, end) in HAND_CONNECTIONS) {
                    if (start < hand.size && end < hand.size) {
                        canvas.drawLine(sx(hand[start].x), sy(hand[start].y),
                                        sx(hand[end].x), sy(hand[end].y), linePaint)
                    }
                }
                for (lm in hand) canvas.drawCircle(sx(lm.x), sy(lm.y), dotRadius, dotPaint)
            }
        }

        /** Draws the three ROSA angle arcs onto [canvas]. Called from both the live
         *  overlay (onDraw) and bakeSkeletonOntoPhoto, so both views look identical. */
        fun drawAngles(
            canvas: Canvas,
            landmarks: List<LandmarkPoint>,
            angles: RosaAnglesCalculator.Angles,
            sx: (Float) -> Float,
            sy: (Float) -> Float,
            arcPaint: Paint,
            vertRefPaint: Paint,
            labelPaint: Paint,
        ) {
            if (landmarks.size < 29) return
            val left = angles.isLeftSide

            val ear      = landmarks[if (left) 7 else 8]
            val shoulder = landmarks[if (left) 11 else 12]
            val elbow    = landmarks[if (left) 13 else 14]
            val wrist    = landmarks[if (left) 15 else 16]
            val hip      = landmarks[if (left) 23 else 24]
            val knee     = landmarks[if (left) 25 else 26]
            val ankle    = landmarks[if (left) 27 else 28]

            val shSx = sx(shoulder.x); val shSy = sy(shoulder.y)
            val hipSx = sx(hip.x);     val hipSy = sy(hip.y)

            // Arc radius proportional to torso height — scales with person's distance
            val torsoLen = hypot((shSx - hipSx).toDouble(), (shSy - hipSy).toDouble()).toFloat()
            val r = torsoLen * 0.22f

            // Knee angle — hip → knee ← ankle
            drawArc(canvas, sx(hip.x), sy(hip.y), sx(knee.x), sy(knee.y),
                sx(ankle.x), sy(ankle.y), "${"%.0f".format(angles.kneeAngle)}°", r, arcPaint, labelPaint)

            // Trunk angle — shoulder → hip ← vertical reference line
            val vRefSy = sy(hip.y - 0.18f)
            canvas.drawLine(hipSx, hipSy, hipSx, vRefSy, vertRefPaint)
            drawArc(canvas, shSx, shSy, hipSx, hipSy, hipSx, vRefSy,
                "${"%.0f".format(angles.trunkAngle)}°", r, arcPaint, labelPaint)

            // Neck angle — ear → shoulder ← vertical reference line
            val neckVRefSy = sy(shoulder.y - 0.14f)
            canvas.drawLine(shSx, shSy, shSx, neckVRefSy, vertRefPaint)
            drawArc(canvas, sx(ear.x), sy(ear.y), shSx, shSy, shSx, neckVRefSy,
                "${"%.0f".format(angles.neckAngle)}°", r * 0.75f, arcPaint, labelPaint)

            // Elbow angle — shoulder → elbow ← wrist
            drawArc(canvas, shSx, shSy, sx(elbow.x), sy(elbow.y),
                sx(wrist.x), sy(wrist.y), "${"%.0f".format(angles.elbowAngle)}°", r, arcPaint, labelPaint)
        }

        private fun drawArc(
            canvas: Canvas,
            p1x: Float, p1y: Float,
            vx: Float,  vy: Float,
            p2x: Float, p2y: Float,
            text: String,
            radius: Float,
            arcPaint: Paint,
            labelPaint: Paint,
        ) {
            val v1x = p1x - vx; val v1y = p1y - vy
            val v2x = p2x - vx; val v2y = p2y - vy
            val m1 = sqrt((v1x * v1x + v1y * v1y).toDouble()).toFloat()
            val m2 = sqrt((v2x * v2x + v2y * v2y).toDouble()).toFloat()
            if (m1 < 1f || m2 < 1f) return

            val startAngle = Math.toDegrees(atan2(v1y.toDouble(), v1x.toDouble())).toFloat()
            val cross      = v1x * v2y - v1y * v2x
            val dot        = v1x * v2x + v1y * v2y
            val sweepAngle = Math.toDegrees(atan2(cross.toDouble(), dot.toDouble())).toFloat()

            val rect = RectF(vx - radius, vy - radius, vx + radius, vy + radius)

            // Black outline pass — makes arc visible on both white and black backgrounds
            val outlineArcPaint = Paint(arcPaint).apply {
                color = Color.BLACK; strokeWidth = arcPaint.strokeWidth + 4f
            }
            canvas.drawArc(rect, startAngle, sweepAngle, false, outlineArcPaint)
            canvas.drawArc(rect, startAngle, sweepAngle, false, arcPaint)

            val bisectorRad = Math.toRadians((startAngle + sweepAngle / 2f).toDouble())
            val textDist = radius + labelPaint.textSize * 0.6f
            val textX = vx + (textDist * cos(bisectorRad)).toFloat()
            val textY = vy + (textDist * sin(bisectorRad)).toFloat() + labelPaint.textSize / 3f

            // Black outline pass for text
            val outlineLabelPaint = Paint(labelPaint).apply {
                color = Color.BLACK; style = Paint.Style.STROKE; strokeWidth = labelPaint.textSize * 0.22f
            }
            canvas.drawText(text, textX, textY, outlineLabelPaint)
            canvas.drawText(text, textX, textY, labelPaint)
        }
    }
}
