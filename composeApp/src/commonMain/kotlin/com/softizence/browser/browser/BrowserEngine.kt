package com.softizence.browser.browser

import androidx.compose.runtime.Composable
import com.softizence.browser.core.model.TabState
import com.softizence.browser.privacy.PrivacyPolicyEngine
import kotlinx.coroutines.flow.StateFlow

/**
 * The one abstraction the UI talks to. Android backs it with WebView (+ WebViewAssetLoader /
 * WebViewFeature process isolation), Desktop with CEF/Chromium through KCEF.
 */
interface BrowserEngine {
    val tabs: StateFlow<List<TabState>>
    val activeTabId: StateFlow<String?>

    suspend fun initialize(privacy: PrivacyPolicyEngine)

    fun openTab(url: String = "softizence://home", profileId: String = "default", incognito: Boolean = false): String
    fun closeTab(tabId: String)
    fun selectTab(tabId: String)
    fun reorderTab(fromIndex: Int, toIndex: Int)

    fun navigate(tabId: String, url: String)
    fun goBack(tabId: String)
    fun goForward(tabId: String)
    fun reload(tabId: String, bypassCache: Boolean = false)
    fun stopLoading(tabId: String)

    suspend fun evaluateJavaScript(tabId: String, script: String): String?

    /** Drops every cookie/storage item for a profile without touching the others. */
    suspend fun clearProfileData(profileId: String)

    /** Writes cookie jars + open tabs to disk so logins and the workspace survive a restart. */
    suspend fun persistSession()

    fun dispose()
}

/** Platform-rendered web surface for [tabId]. */
@Composable
expect fun WebSurface(
    engine: BrowserEngine,
    tabId: String,
    modifier: androidx.compose.ui.Modifier,
)
