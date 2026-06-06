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
                        startActivityForResult(
                            Intent(this, PoseDetectionActivity::class.java),
                            REQUEST_CODE
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Required for activity result on older APIs")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE) {
            pendingResult?.success(resultCode == Activity.RESULT_OK)
            pendingResult = null
        }
    }
}
