package com.example.bath_royale

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bath_royale/technical_context")
            .setMethodCallHandler { call, result ->
                if (call.method == "versions") {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    result.success(mapOf(
                        "app_version" to (info.versionName ?: "desconhecida"),
                        "semantic_version" to (info.versionName?.substringBefore("-") ?: "desconhecida"),
                        "build_channel" to (if (packageName.endsWith(".development")) "development" else "alpha"),
                        "version_code" to (if (Build.VERSION.SDK_INT >= 28) info.longVersionCode.toString() else @Suppress("DEPRECATION") info.versionCode.toString()),
                        "platform_version" to "Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})"
                    ))
                } else {
                    result.notImplemented()
                }
            }
    }
}
