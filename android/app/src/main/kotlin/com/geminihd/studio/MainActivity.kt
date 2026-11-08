package com.geminihd.studio

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Kotlin Android host (user requirement: Flutter + Kotlin).
// The Gemini login WebView, cookie manager and all platform plugins
// are provided by flutter_inappwebview's Kotlin Android implementation.
//
// This activity also hosts the dedicated "browser intent" channel:
// opening a URL in a SEPARATE real Chrome window (the user's own
// Chrome profile and session), falling back to the default browser
// when Chrome is not installed. Chrome owns its window and session
// state; the app's built-in browser is left untouched.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.geminihd.studio/browser"
        ).setMethodCallHandler { call, result ->
            if (call.method == "openInChrome") {
                val url = call.argument<String>("url") ?: ""
                result.success(openInChrome(url))
            } else {
                result.notImplemented()
            }
        }
    }

    private fun openInChrome(url: String): Boolean {
        if (url.isEmpty()) return false
        val uri = Uri.parse(url)
        val chromeIntent = Intent(Intent.ACTION_VIEW, uri).apply {
            setPackage("com.android.chrome")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(chromeIntent)
            true
        } catch (e: Exception) {
            try {
                startActivity(
                    Intent(Intent.ACTION_VIEW, uri).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                )
                true
            } catch (e2: Exception) {
                false
            }
        }
    }
}
