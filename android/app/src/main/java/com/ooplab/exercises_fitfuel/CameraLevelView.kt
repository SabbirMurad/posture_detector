package com.ooplab.exercises_fitfuel

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import kotlin.math.abs

/**
 * Camera level indicator (like the Pixel camera's "Level"). A fixed pair of side
 * ticks plus a centre line that rotates with the phone's roll and shifts
 * vertically with its forward/back pitch. Everything turns green when the phone
 * is held upright and level (within [TiltMonitor]'s acceptable ranges).
 *
 * Driven by [update] from the activity's tilt callback.
 */
class CameraLevelView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null,
) : View(context, attrs) {

    private var roll = 0.0   // degrees, 0 = level
    private var pitch = 0.0  // degrees, 0 = upright

    private val rollTolerance = TiltMonitor.MAX_ROLL          // 15°
    private val pitchTolerance = 5.0                          // matches 85–95° tilt

    // Flip these if the motion feels reversed on device.
    private val rollSign = -1.0
    private val pitchSign = -1.0       // forward tilt → line moves up

    private val d = resources.displayMetrics.density
    private val pxPerDegree = 0.6f * d // small, proportional travel
    private val maxOffset = 18f * d
    private val centerHalf = 36f * d   // half-length of the wide centre / moving line
    private val sideGap = 14f * d      // gap between the centre line and each side tick
    private val sideLen = 14f * d      // length of the short side ticks

    private val alignedColor = Color.parseColor("#43A047")
    private val normalColor = Color.WHITE

    private val paint = Paint().apply {
        style = Paint.Style.STROKE
        strokeWidth = 1f * d
        strokeCap = Paint.Cap.ROUND
        isAntiAlias = true
        setShadowLayer(3f * d, 0f, 0f, Color.argb(150, 0, 0, 0))
    }

    init {
        // setShadowLayer needs software rendering.
        setLayerType(LAYER_TYPE_SOFTWARE, null)
    }

    fun update(roll: Double, pitch: Double) {
        this.roll = roll
        this.pitch = pitch
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = width / 2f
        val cy = height / 2f

        val aligned = abs(roll) <= rollTolerance && abs(pitch) <= pitchTolerance
        paint.color = if (aligned) alignedColor else normalColor

        // Fixed reference: a wide centre line plus two shorter side ticks (3 lines,
        // all horizontal and centred).
        canvas.drawLine(cx - centerHalf, cy, cx + centerHalf, cy, paint)
        val tickInnerL = cx - centerHalf - sideGap
        val tickInnerR = cx + centerHalf + sideGap
        canvas.drawLine(tickInnerL - sideLen, cy, tickInnerL, cy, paint)
        canvas.drawLine(tickInnerR, cy, tickInnerR + sideLen, cy, paint)

        // Moving line: same width as the centre line, shifted vertically by pitch
        // and rotated by roll. Overlaps the centre line when the phone is level.
        val offset = (pitchSign * pitch * pxPerDegree).toFloat()
            .coerceIn(-maxOffset, maxOffset)
        // Deadzone: no rotation while roll is within the acceptable range, then
        // rotate smoothly past it (so there's no jump at the threshold).
        val effRoll = if (abs(roll) <= rollTolerance) 0.0
                      else roll - (if (roll < 0) -rollTolerance else rollTolerance)
        val angle = (rollSign * effRoll).toFloat()
        canvas.save()
        canvas.translate(cx, cy + offset)
        canvas.rotate(angle)
        canvas.drawLine(-centerHalf, 0f, centerHalf, 0f, paint)
        canvas.restore()
    }
}
