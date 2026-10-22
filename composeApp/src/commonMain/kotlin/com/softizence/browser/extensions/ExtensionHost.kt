package com.softizence.browser.extensions

import com.softizence.browser.core.model.ExtensionInfo
import kotlinx.coroutines.flow.StateFlow

/**
 * Loads unpacked MV3 extensions.
 *
 * Desktop (CEF/Chromium) is the fully-featured implementation: Chromium itself owns the
 * service worker, `chrome.*` APIs and declarativeNetRequest, and we only point it at the
 * unpacked folders via `--load-extension`, plus a request-router for `chrome-extension://`.
 *
 * Android's WebView has no extension runtime at all. Rather than pretend, the Android actual
 * supports the *content-script and DNR subset* by compiling each manifest into injected
 * scripts and URL-blocking rules - and reports anything it cannot honour in
 * [ExtensionInfo.loadError] so the UI can be honest about it.
 */
interface ExtensionHost {
    val extensions: StateFlow<List<ExtensionInfo>>

    /** Capability advertised to the UI so it can grey out unsupported controls. */
    val capabilities: ExtensionCapabilities

    /** Scans [ExtensionPaths.extensionsDir] and loads every unpacked extension found. */
    suspend fun refresh()

    /** Loads a single unpacked folder (a directory containing manifest.json). */
    suspend fun load(folderPath: String): Result<ExtensionInfo>

    suspend fun setEnabled(extensionId: String, enabled: Boolean)

    suspend fun remove(extensionId: String)

    /** Content scripts that must be injected into [url] at [runAt]. */
    suspend fun contentScriptsFor(url: String, runAt: String): List<InjectedScript>

    /** True when a request to [url] is blocked by an enabled DNR ruleset. */
    suspend fun isBlocked(url: String): Boolean
}

data class ExtensionCapabilities(
    val serviceWorkers: Boolean,
    val declarativeNetRequest: Boolean,
    val contentScripts: Boolean,
    val popups: Boolean,
    val chromeApis: Boolean,
) {
    companion object {
        val FullChromium = ExtensionCapabilities(true, true, true, true, true)
        val WebViewSubset = ExtensionCapabilities(false, true, true, false, false)
    }
}

data class InjectedScript(
    val extensionId: String,
    val source: String,
    val allFrames: Boolean,
)
