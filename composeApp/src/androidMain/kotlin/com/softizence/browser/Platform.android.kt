package com.softizence.browser

import android.annotation.SuppressLint
import android.content.Context
import com.softizence.browser.browser.BrowserEngine
import com.softizence.browser.browser.WebViewBrowserEngine

/** Process-wide application context, set once in [SoftizenceApplication]. */
@SuppressLint("StaticFieldLeak")
object AppContextHolder {
    lateinit var context: Context
        internal set
}

actual object ExtensionPaths {
    private val base get() = AppContextHolder.context.filesDir.absolutePath
    actual val extensionsDir: String get() = "$base/extensions"
    actual val tunnelsDir: String get() = "$base/tunnels"
    actual val profilesDir: String get() = "$base/profiles"
    actual val configDir: String get() = "$base/config"
}

actual fun platformName(): String = "Android ${android.os.Build.VERSION.RELEASE}"

actual fun createBrowserEngine(): BrowserEngine = WebViewBrowserEngine(AppContextHolder.context)
