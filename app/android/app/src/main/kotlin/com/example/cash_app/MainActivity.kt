package com.example.cash_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (packageName != "com.example.cash_app.offlineqa") return
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cashflow/offline_qa")
            .setMethodCallHandler { call, result ->
                if (call.method == "cachedFrameRasterized") {
                    reportFullyDrawn()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
