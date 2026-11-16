package com.example.learn_ota

import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "learn_ota/app_restart")
            .setMethodCallHandler { call, result ->
                if (call.method == "restart") {
                    result.success(null)
                    // Give the reply time to reach Dart, then cold-restart.
                    Handler(Looper.getMainLooper()).postDelayed({ restartApp() }, 300)
                } else {
                    result.notImplemented()
                }
            }
    }

    /// Kills the process and relaunches the app, so flutter_patcher loads
    /// the newly installed patch on this "cold start".
    private fun restartApp() {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return
        startActivity(Intent.makeRestartActivityTask(launch.component))
        Runtime.getRuntime().exit(0)
    }
}
