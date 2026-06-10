package com.ooplab.exercises_fitfuel

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL      = "posture_detection"
        const val REQUEST_CODE = 1001
    }

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startDetection" -> {
                        pendingResult = result
                        val answers = call.arguments as? Map<*, *>
                        val intent = Intent(this, PoseDetectionActivity::class.java)
                        if (answers != null) {
                            intent.putExtra(
                                PoseDetectionActivity.EXTRA_WORKSTATION_ANSWERS,
                                org.json.JSONObject(answers).toString()
                            )
                        }
                        startActivityForResult(intent, REQUEST_CODE)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Required for activity result on older APIs")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val paths      = data.getStringArrayListExtra(PoseDetectionActivity.EXTRA_PHOTO_PATHS)
                val scoresJson = data.getStringExtra(PoseDetectionActivity.EXTRA_ROSA_SCORES)
                val scores = if (!scoresJson.isNullOrEmpty()) {
                    val arr = org.json.JSONArray(scoresJson)
                    (0 until arr.length()).map { i ->
                        val obj = arr.getJSONObject(i)
                        hashMapOf<String, Any>(
                            "final_score"               to obj.optInt("finalScore", 0),
                            "risk_level"                to obj.optString("riskLevel", "Unknown"),
                            "chair_score"               to obj.optInt("chairScore", 0),
                            "peripheral_score"          to obj.optInt("peripheralScore", 0),
                            "monitor_area_score"        to obj.optInt("monitorAreaScore", 0),
                            "mouse_keyboard_area_score" to obj.optInt("mouseKeyboardAreaScore", 0),
                            "seat_height_score" to obj.optInt("seatHeightScore", 0),
                            "backrest_score"    to obj.optInt("backrestScore", 0),
                            "armrest_score"     to obj.optInt("armrestScore", 0),
                            "monitor_score"     to obj.optInt("monitorScore", 0),
                            "keyboard_score"    to obj.optInt("keyboardScore", 0),
                            "mouse_score"       to obj.optInt("mouseScore", 0),
                        )
                    }
                } else emptyList<Map<String, Any>>()
                pendingResult?.success(hashMapOf(
                    "photo_paths"  to (paths ?: arrayListOf<String>()),
                    "rosa_scores"  to scores,
                ))
            } else {
                pendingResult?.success(null)
            }
            pendingResult = null
        }
    }
}
