package com.softizence.browser.browser

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebChromeClient
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.softizence.browser.core.model.TabState
import com.softizence.browser.privacy.PrivacyPolicyEngine
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream
import java.util.concurrent.atomic.AtomicLong

/**
 * Android engine built on WebView.
 *
 * Privacy is enforced at three layers, because any one of them alone is bypassable:
 *  1. `DOCUMENT_START_SCRIPT` injects the stealth bundle before any page script runs.
 *  2. `shouldInterceptRequest` applies tracker blocking + extension DNR rules and
 *     rewrites headers (UA client hints, DNT).
 *  3. `WebSettings.userAgentString` keeps the network-level UA consistent with the JS one.
 */
@SuppressLint("SetJavaScriptEnabled")
class WebViewBrowserEngine(private val context: Context) : BrowserEngine {

    private val _tabs = MutableStateFlow<List<TabState>>(emptyList())
    override val tabs: StateFlow<List<TabState>> = _tabs.asStateFlow()

    private val _activeTabId = MutableStateFlow<String?>(null)
    override val activeTabId: StateFlow<String?> = _activeTabId.asStateFlow()

    private val views = mutableMapOf<String, WebView>()
    private val counter = AtomicLong(0)
    private lateinit var privacy: PrivacyPolicyEngine

    /** Called by the Android host so extension DNR rules can veto a request. */
    var requestBlocker: ((String) -> Boolean)? = null

    override suspend fun initialize(privacy: PrivacyPolicyEngine) {
        this.privacy = privacy
        WebView.setWebContentsDebuggingEnabled(false)
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(
            WebView(context).also { it.destroy() },
            !privacy.settings.blockThirdPartyCookies,
        )
    }

    internal fun viewFor(tabId: String): WebView = views.getOrPut(tabId) { createWebView(tabId) }

    private fun createWebView(tabId: String): WebView = WebView(context).apply {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            loadWithOverviewMode = true
            useWideViewPort = true
            mediaPlaybackRequiresUserGesture = true
            allowFileAccess = false
            allowContentAccess = false
            setSupportMultipleWindows(true)
            userAgentString = privacy.fingerprint.userAgent
            // Safe Browsing on, but no personalised ad identifiers.
            if (WebViewFeature.isFeatureSupported(WebViewFeature.SAFE_BROWSING_ENABLE)) {
                WebSettingsCompat.setSafeBrowsingEnabled(this, true)
            }
        }

        // Layer 1: stealth bundle before any page script.
        privacy.documentStartScript()?.let { script ->
            if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                WebViewCompat.addDocumentStartJavaScript(this, script, setOf("*"))
            }
        }

        webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                update(tabId) { it.copy(url = url, isLoading = true, progress = 0.05f) }
                // Fallback for devices without DOCUMENT_START_SCRIPT support.
                if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                    privacy.documentStartScript()?.let { view.evaluateJavascript(it, null) }
                }
            }

            override fun onPageFinished(view: WebView, url: String) {
                update(tabId) {
                    it.copy(
                        url = url,
                        title = view.title.orEmpty().ifBlank { it.title },
                        isLoading = false,
                        progress = 1f,
                        canGoBack = view.canGoBack(),
                        canGoForward = view.canGoForward(),
                    )
                }
            }

            // Layer 2: block before the socket is opened.
            override fun shouldInterceptRequest(
                view: WebView,
                request: WebResourceRequest,
            ): WebResourceResponse? {
                val url = request.url.toString()
                if (privacy.shouldBlock(url) || requestBlocker?.invoke(url) == true) {
                    return WebResourceResponse("text/plain", "utf-8", ByteArrayInputStream(ByteArray(0)))
                }
                return null
            }

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val url = request.url.toString()
                val rewritten = privacy.rewrite(url)
                if (rewritten != url) {
                    view.loadUrl(rewritten, privacy.requestHeaders())
                    return true
                }
                return false
            }
        }

        webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) {
                update(tabId) { it.copy(progress = newProgress / 100f, isLoading = newProgress < 100) }
            }

            override fun onReceivedTitle(view: WebView, title: String) {
                update(tabId) { it.copy(title = title) }
            }
        }
    }

    override fun openTab(url: String, profileId: String, incognito: Boolean): String {
        val id = "tab-${counter.incrementAndGet()}"
        _tabs.value += TabState(id = id, url = url, profileId = profileId, isIncognito = incognito)
        _activeTabId.value = id
        if (url != "softizence://home") navigate(id, url)
        return id
    }

    override fun closeTab(tabId: String) {
        views.remove(tabId)?.apply { stopLoading(); destroy() }
        _tabs.value = _tabs.value.filterNot { it.id == tabId }
        if (_activeTabId.value == tabId) _activeTabId.value = _tabs.value.lastOrNull()?.id
    }

    override fun selectTab(tabId: String) { _activeTabId.value = tabId }

    override fun reorderTab(fromIndex: Int, toIndex: Int) {
        val list = _tabs.value.toMutableList()
        if (fromIndex !in list.indices || toIndex !in list.indices) return
        list.add(toIndex, list.removeAt(fromIndex))
        _tabs.value = list
    }

    override fun navigate(tabId: String, url: String) {
        update(tabId) { it.copy(url = url, isLoading = true) }
        if (url == "softizence://home") return
        viewFor(tabId).loadUrl(url, privacy.requestHeaders())
    }

    override fun goBack(tabId: String) = viewFor(tabId).goBack()
    override fun goForward(tabId: String) = viewFor(tabId).goForward()
    override fun reload(tabId: String, bypassCache: Boolean) {
        val view = viewFor(tabId)
        if (bypassCache) view.clearCache(false)
        view.reload()
    }
    override fun stopLoading(tabId: String) = viewFor(tabId).stopLoading()

    override suspend fun evaluateJavaScript(tabId: String, script: String): String? =
        withContext(Dispatchers.Main) {
            val result = CompletableDeferred<String?>()
            viewFor(tabId).evaluateJavascript(script) { result.complete(it) }
            result.await()
        }

    override suspend fun clearProfileData(profileId: String) = withContext(Dispatchers.Main) {
        CookieManager.getInstance().removeAllCookies(null)
        CookieManager.getInstance().flush()
        WebStorage.getInstance().deleteAllData()
    }

    override suspend fun persistSession() = withContext(Dispatchers.Main) {
        CookieManager.getInstance().flush()
    }

    override fun dispose() {
        views.values.forEach { it.destroy() }
        views.clear()
    }

    private fun update(tabId: String, block: (TabState) -> TabState) {
        _tabs.value = _tabs.value.map { if (it.id == tabId) block(it) else it }
    }
}

@Composable
actual fun WebSurface(engine: BrowserEngine, tabId: String, modifier: Modifier) {
    val android = engine as WebViewBrowserEngine
    AndroidView(
        factory = { android.viewFor(tabId) },
        modifier = modifier,
        update = { },
    )
}
