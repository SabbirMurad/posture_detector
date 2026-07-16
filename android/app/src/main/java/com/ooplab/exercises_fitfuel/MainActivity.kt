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
                val json = data.getStringExtra(PoseDetectionActivity.EXTRA_RESULT)
                // The Activity already emits the final snake_case contract
                // ({ side_captures: [...], front_capture: {...} }); just decode the
                // JSON into plain Map/List so the MethodChannel can serialise it.
                val result = if (!json.isNullOrEmpty()) jsonToMap(org.json.JSONObject(json)) else null
                pendingResult?.success(result)
            } else {
                pendingResult?.success(null)
            }
            pendingResult = null
        }
    }

    // ── JSON → plain Kotlin collections (MethodChannel can't serialise org.json types) ──
    private fun jsonToMap(obj: org.json.JSONObject): Map<String, Any?> {
        val map = HashMap<String, Any?>()
        for (key in obj.keys()) map[key] = unwrap(obj.get(key))
        return map
    }

    private fun jsonToList(arr: org.json.JSONArray): List<Any?> =
        (0 until arr.length()).map { unwrap(arr.get(it)) }

    private fun unwrap(value: Any?): Any? = when (value) {
        is org.json.JSONObject -> jsonToMap(value)
        is org.json.JSONArray  -> jsonToList(value)
        org.json.JSONObject.NULL -> null
        else -> value
    }
}
