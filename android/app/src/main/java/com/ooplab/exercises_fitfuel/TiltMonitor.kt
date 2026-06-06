package com.ooplab.exercises_fitfuel

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.*

class TiltMonitor(
    context: Context,
    private val onAnglesChanged: (tiltAngle: Double, rollAngle: Double) -> Unit,
) : SensorEventListener {

    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accelerometer =
        sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

    private var fx = 0f; private var fy = 0f; private var fz = 0f
    private var initialized = false

    fun start() {
        sensorManager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_UI)
    }

    fun stop() = sensorManager.unregisterListener(this)

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
        val x = event.values[0]; val y = event.values[1]; val z = event.values[2]

        if (!initialized) {
            fx = x; fy = y; fz = z; initialized = true
        } else {
            fx += ALPHA * (x - fx)
            fy += ALPHA * (y - fy)
            fz += ALPHA * (z - fz)
        }

        // Inclination from horizontal: 0° = lying flat, 90° = perfectly upright portrait
        val tilt = atan2(fy.toDouble(), sqrt((fx * fx + fz * fz).toDouble())) * (180.0 / PI)

        // Lateral roll derived directly from the accelerometer.
        // When upright, fy ≈ g and fx ≈ 0; tilting the phone left/right shifts fx.
        // atan2(fx, fy) gives the signed roll angle with no gimbal-lock — unlike
        // SensorManager.getOrientation() which breaks near ±90° pitch (our exact case).
        val roll = atan2(fx.toDouble(), fy.toDouble()) * (180.0 / PI)

        onAnglesChanged(tilt, roll)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    companion object {
        private const val ALPHA = 0.1f
        const val MIN_TILT = 85.0
        const val MAX_TILT = 95.0
        const val MAX_ROLL = 15.0
        fun isTiltAcceptable(angle: Double) = angle in MIN_TILT..MAX_TILT
        fun isRollAcceptable(roll: Double) = abs(roll) <= MAX_ROLL
    }
}
