package com.softizence.browser.browser

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.awt.SwingPanel
import com.softizence.browser.ExtensionPaths
import com.softizence.browser.core.model.TabState
import com.softizence.browser.extensions.DesktopExtensionHost
import com.softizence.browser.privacy.PrivacyPolicyEngine
import dev.datlag.kcef.KCEF
import dev.datlag.kcef.KCEFBrowser
import dev.datlag.kcef.KCEFClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import org.cef.browser.CefBrowser
import org.cef.browser.CefFrame
import org.cef.handler.CefDisplayHandlerAdapter
import org.cef.handler.CefLoadHandlerAdapter
import org.cef.handler.CefRequestHandlerAdapter
import org.cef.handler.CefResourceRequestHandler
import org.cef.handler.CefResourceRequestHandlerAdapter
import org.cef.misc.BoolRef
import org.cef.network.CefRequest
import java.io.File
import java.util.concurrent.atomic.AtomicLong

/**
 * Desktop engine: real Chromium through JCEF/KCEF.
 *
 * This is where MV3 hosting is genuine - Chromium owns the extension runtime, so we pass
 * `--load-extension` with every enabled unpacked folder and let the browser run the
 * service workers, `chrome.*` APIs and declarativeNetRequest itself.
 *
 * Privacy hooks:
 *  - Command-line switches disable the detectable automation surface, QUIC (which can
 *    slip past a userspace tunnel) and WebRTC's real-IP exposure.
 *  - A per-tab request handler applies URL rewriting, tracker blocking and header masking.
 *  - The stealth bundle is registered as a document-start script on every frame.
 */
class CefBrowserEngine : BrowserEngine {

    private val _tabs = MutableStateFlow<List<TabState>>(emptyList())
    override val tabs: StateFlow<List<TabState>> = _tabs.asStateFlow()

    private val _activeTabId = MutableStateFlow<String?>(null)
    override val activeTabId: StateFlow<String?> = _activeTabId.asStateFlow()

    private val browsers = mutableMapOf<String, KCEFBrowser>()
    private val counter = AtomicLong(0)

    private lateinit var client: KCEFClient
    private lateinit var privacy: PrivacyPolicyEngine

    /** Injected so Chromium is launched with the user's enabled extensions. */
    var extensionHost: DesktopExtensionHost? = null

    override suspend fun initialize(privacy: PrivacyPolicyEngine) {
        this.privacy = privacy
        val extensionArgs = extensionHost?.loadExtensionSwitch().orEmpty()

        withContext(Dispatchers.IO) {
            KCEF.init(
                builder = {
                    installDir(File(ExtensionPaths.cefDir, "bundle"))
                    settings {
                        cachePath = File(ExtensionPaths.profilesDir, "default/cef").apply { mkdirs() }.absolutePath
                        // A persistent cache path is what keeps logins alive across restarts.
                        persistSessionCookies = true
                        windowlessRenderingEnabled = false
                        userAgent = privacy.fingerprint.userAgent
                        locale = privacy.fingerprint.languages.first()
                        logSeverity = org.cef.CefSettings.LogSeverity.LOGSEVERITY_ERROR
                    }
                    addArgs(
                        *buildList {
                            add("--disable-blink-features=AutomationControlled")
                            add("--disable-features=Translate,MediaRouter,OptimizationHints")
                            add("--no-default-browser-check")
                            add("--no-first-run")
                            add("--disable-quic")                       // keep everything on TCP/UDP wg can see
                            add("--force-webrtc-ip-handling-policy=disable_non_proxied_udp")
                            add("--enable-features=NetworkServiceInProcess")
                            add("--lang=${privacy.fingerprint.languages.first()}")
                            addAll(extensionArgs)
                        }.toTypedArray(),
                    )
                },
                onError = { it?.printStackTrace() },
            )
            client = KCEF.newClientBlocking()
            installHandlers()
        }
    }

    private fun installHandlers() {
        client.addDisplayHandler(object : CefDisplayHandlerAdapter() {
            override fun onAddressChange(browser: CefBrowser, frame: CefFrame?, url: String) {
                tabIdOf(browser)?.let { id -> update(id) { it.copy(url = url) } }
            }

            override fun onTitleChange(browser: CefBrowser, title: String?) {
                tabIdOf(browser)?.let { id -> update(id) { it.copy(title = title.orEmpty()) } }
            }
        })

        client.addLoadHandler(object : CefLoadHandlerAdapter() {
            override fun onLoadingStateChange(
                browser: CefBrowser,
                isLoading: Boolean,
                canGoBack: Boolean,
                canGoForward: Boolean,
            ) {
                tabIdOf(browser)?.let { id ->
                    update(id) {
                        it.copy(
                            isLoading = isLoading,
                            progress = if (isLoading) 0.4f else 1f,
                            canGoBack = canGoBack,
                            canGoForward = canGoForward,
                        )
                    }
                }
            }

            override fun onLoadStart(browser: CefBrowser, frame: CefFrame?, type: CefRequest.TransitionType?) {
                // Document-start stealth injection, per frame.
                privacy.documentStartScript()?.let { script ->
                    frame?.executeJavaScript(script, frame.url, 0)
                }
            }
        })

        client.addRequestHandler(object : CefRequestHandlerAdapter() {
            override fun getResourceRequestHandler(
                browser: CefBrowser?,
                frame: CefFrame?,
                request: CefRequest?,
                isNavigation: Boolean,
                isDownload: Boolean,
                requestInitiator: String?,
                disableDefaultHandling: BoolRef?,
            ): CefResourceRequestHandler = object : CefResourceRequestHandlerAdapter() {
                override fun onBeforeResourceLoad(
                    browser: CefBrowser?,
                    frame: CefFrame?,
                    request: CefRequest?,
                ): Boolean {
                    val url = request?.url ?: return false
                    if (privacy.shouldBlock(url)) return true     // true == cancel
                    privacy.requestHeaders().forEach { (k, v) -> request.setHeaderByName(k, v, true) }
                    val rewritten = privacy.rewrite(url)
                    if (rewritten != url) request.url = rewritten
                    return false
                }
            }
        })
    }

    internal fun browserFor(tabId: String): KCEFBrowser = browsers.getValue(tabId)

    override fun openTab(url: String, profileId: String, incognito: Boolean): String {
        val id = "tab-${counter.incrementAndGet()}"
        val target = if (url == "softizence://home") "about:blank" else url
        browsers[id] = client.createBrowser(
            url = target,
            rendering = KCEFBrowser.Rendering.DEFAULT,
            isTransparent = false,
        )
        _tabs.value += TabState(id = id, url = url, profileId = profileId, isIncognito = incognito)
        _activeTabId.value = id
        return id
    }

    override fun closeTab(tabId: String) {
        browsers.remove(tabId)?.close(true)
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
        browsers[tabId]?.loadURL(url)
    }

    override fun goBack(tabId: String) { browsers[tabId]?.goBack() }
    override fun goForward(tabId: String) { browsers[tabId]?.goForward() }
    override fun reload(tabId: String, bypassCache: Boolean) {
        browsers[tabId]?.let { if (bypassCache) it.reloadIgnoreCache() else it.reload() }
    }
    override fun stopLoading(tabId: String) { browsers[tabId]?.stopLoad() }

    override suspend fun evaluateJavaScript(tabId: String, script: String): String? {
        browsers[tabId]?.evaluateJavaScript(script) { }
        return null
    }

    override suspend fun clearProfileData(profileId: String) = withContext(Dispatchers.IO) {
        File(ExtensionPaths.profilesDir, profileId).deleteRecursively()
        Unit
    }

    override suspend fun persistSession() = withContext(Dispatchers.IO) {
        // CEF flushes its cookie store on dispose; force it now so a crash cannot lose logins.
        runCatching { org.cef.network.CefCookieManager.getGlobalManager().flushStore(null) }
        Unit
    }

    override fun dispose() {
        browsers.values.forEach { runCatching { it.close(true) } }
        browsers.clear()
        runCatching { client.dispose() }
        runCatching { KCEF.disposeBlocking() }
    }

    private fun tabIdOf(browser: CefBrowser): String? =
        browsers.entries.firstOrNull { it.value.cefBrowser === browser || it.value === browser }?.key

    private fun update(tabId: String, block: (TabState) -> TabState) {
        _tabs.value = _tabs.value.map { if (it.id == tabId) block(it) else it }
    }
}

@Composable
actual fun WebSurface(engine: BrowserEngine, tabId: String, modifier: Modifier) {
    val cef = engine as CefBrowserEngine
    SwingPanel(
        modifier = modifier,
        factory = { cef.browserFor(tabId).uiComponent },
    )
}
