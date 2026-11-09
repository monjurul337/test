package com.geminihd.studio

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Kotlin Android host (user requirement: Flutter + Kotlin).
//
// Two browser channels:
//  * "browser" — the Image Search screen's intent channel: its
//    browsing runs in a dedicated external browser process (Chrome
//    first, then Firefox, then the system default).
//  * "gecko" — the Gemini sign-in: a built-in Firefox engine
//    (GeckoView, see GeckoBridge) whose profile keeps the Google
//    session and hands its cookies back to the app after sign-in.
//    A separate browser's cookies are unreadable to any app, so the
//    sign-in could not hand the session over any other way.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.geminihd.studio/browser"
        ).setMethodCallHandler { call, result ->
            if (call.method == "openExternal") {
                val url = call.argument<String>("url") ?: ""
                result.success(openExternal(url))
            } else {
                result.notImplemented()
            }
        }

        val geckoChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.geminihd.studio/gecko"
        )
        GeckoBridge.channel = geckoChannel
        geckoChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "signIn" -> GeckoBridge.signIn(
                        this, call.argument<String>("url"), result)
                    "refresh" -> GeckoBridge.refresh(this, result)
                    "cookies" -> GeckoBridge.readCookies(this) {
                        result.success(it)
                    }
                    "browserOpen" -> {
                        GeckoBridge.browserOpen(
                            this, call.argument<String>("url"))
                        result.success(true)
                    }
                    "browserClose" -> {
                        GeckoBridge.browserClose()
                        result.success(true)
                    }
                    "browserBasket" -> {
                        GeckoBridge.browserBasket(call.arguments as String)
                        result.success(true)
                    }
                    "browserStatus" -> {
                        GeckoBridge.browserStatus(call.arguments as String)
                        result.success(true)
                    }
                    "browserToast" -> {
                        GeckoBridge.browserToast(call.arguments as String)
                        result.success(true)
                    }
                    "browserFetch" -> GeckoBridge.browserFetch(
                        this, call.arguments as String) {
                        result.success(it)
                    }
                    "browserCapture" -> GeckoBridge.browserCapture(
                        call.arguments as String) {
                        result.success(it)
                    }
                    "browserIsOpen" ->
                        result.success(GeckoBridge.hasBrowserSession())
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                result.error("gecko", e.toString(), null)
            }
        }
    }

    private fun openExternal(url: String): Boolean {
        if (url.isEmpty()) return false
        val uri = Uri.parse(url)
        for (pkg in listOf("com.android.chrome", "org.mozilla.firefox")) {
            try {
                startActivity(Intent(Intent.ACTION_VIEW, uri).apply {
                    setPackage(pkg)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
                return true
            } catch (e: Exception) {
                // Browser not installed — try the next one.
            }
        }
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
            true
        } catch (e: Exception) {
            false
        }
    }
}
