package com.sotizence.playbooks.browser

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.webkit.CookieManager
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.widget.doAfterTextChanged
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.button.MaterialButton
import com.google.android.material.switchmaterial.SwitchMaterial
import com.sotizence.playbooks.browser.databinding.ActivityMainBinding
import com.sotizence.playbooks.browser.model.AppSettings
import com.sotizence.playbooks.browser.model.Bookmark
import com.sotizence.playbooks.browser.model.HistoryItem
import com.sotizence.playbooks.browser.model.TabItem

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var bookmarkManager: BookmarkManager
    private lateinit var historyManager: HistoryManager
    private lateinit var settingsManager: SettingsManager
    private lateinit var profileManager: ProfileManager
    private lateinit var proxyManager: ProxyManager

    private val tabs = mutableListOf<TabItem>()
    private var activeTabId: String = ""

    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    private var isDesktopMode = false
    private val desktopUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
    private var defaultMobileUserAgent: String = ""

    private val homeUrl = "file:///android_asset/home/home.html"

    private val fileChooserLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (filePathCallback == null) return@registerForActivityResult
        var results: Array<Uri>? = null
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            val data = result.data
            val clipData = data?.clipData
            if (clipData != null) {
                results = Array(clipData.itemCount) { i -> clipData.getItemAt(i).uri }
            } else if (data?.data != null) {
                results = arrayOf(data.data!!)
            }
        }
        filePathCallback?.onReceiveValue(results)
        filePathCallback = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        bookmarkManager = BookmarkManager(this)
        historyManager = HistoryManager(this)
        settingsManager = SettingsManager(this)
        profileManager = ProfileManager(this)
        proxyManager = ProxyManager(this)

        initTopBar()
        initBottomNav()
        initBackPress()

        // Auto-connect proxy / VPN if enabled
        val settings = settingsManager.getSettings()
        if (settings.isAutoProxyEnabled) {
            applyProxyConnection(true)
        } else {
            updateVpnPillUi(false)
        }

        // Open initial tab
        openNewTab(homeUrl)
    }

    private fun getActiveTab(): TabItem? {
        return tabs.find { it.id == activeTabId } ?: tabs.firstOrNull()
    }

    private fun getActiveWebView(): WebView? {
        return getActiveTab()?.webView
    }

    /* -------------------------------------------------------------
     * TAB MANAGEMENT
     * ------------------------------------------------------------- */

    private fun openNewTab(url: String = homeUrl, profileId: String = "default"): TabItem {
        val tab = TabItem(
            title = if (url == homeUrl) "Homepage" else "New Tab",
            url = url,
            profileId = profileId
        )
        val wv = createConfiguredWebView(tab)
        tab.webView = wv

        tabs.add(tab)
        switchToTab(tab.id)
        updateTabsBadge()

        if (url.isNotEmpty()) {
            wv.loadUrl(url)
        }
        return tab
    }

    private fun switchToTab(tabId: String) {
        val target = tabs.find { it.id == tabId } ?: return
        activeTabId = target.id

        // Swap view inside webContainer
        binding.webContainer.removeAllViews()
        target.webView?.let { wv ->
            if (wv.parent != null) {
                (wv.parent as? ViewGroup)?.removeView(wv)
            }
            binding.webContainer.addView(
                wv,
                ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            )
        }

        updateUrlDisplay(target.url)
        updateNavButtons()
        updateBookmarkStar(target.url)
        updateTabsBadge()
    }

    private fun closeTab(tabId: String) {
        val index = tabs.indexOfFirst { it.id == tabId }
        if (index < 0) return

        val removingTab = tabs[index]
        removingTab.webView?.destroy()
        tabs.removeAt(index)

        if (tabs.isEmpty()) {
            openNewTab(homeUrl)
        } else {
            if (activeTabId == tabId) {
                val nextIndex = if (index >= tabs.size) tabs.size - 1 else index
                switchToTab(tabs[nextIndex].id)
            } else {
                updateTabsBadge()
            }
        }
    }

    private fun closeAllTabs() {
        for (t in tabs) {
            t.webView?.destroy()
        }
        tabs.clear()
        openNewTab(homeUrl)
    }

    private fun updateTabsBadge() {
        binding.tvTabsBadge.text = tabs.size.toString()
    }

    /* -------------------------------------------------------------
     * WEBVIEW INITIALIZATION FOR EACH TAB
     * ------------------------------------------------------------- */

    @SuppressLint("SetJavaScriptEnabled")
    private fun createConfiguredWebView(tab: TabItem): WebView {
        val webView = WebView(this)
        val settings = webView.settings

        if (defaultMobileUserAgent.isEmpty()) {
            defaultMobileUserAgent = settings.userAgentString
        }

        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.databaseEnabled = true
        settings.allowFileAccess = true
        settings.allowContentAccess = true
        settings.setSupportZoom(true)
        settings.builtInZoomControls = true
        settings.displayZoomControls = false
        settings.useWideViewPort = true
        settings.loadWithOverviewMode = true
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE

        // Apply User-Agent
        if (isDesktopMode) {
            settings.userAgentString = desktopUserAgent
        } else {
            settings.userAgentString = defaultMobileUserAgent
        }

        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        webView.addJavascriptInterface(WebAppInterface(this) { url ->
            runOnUiThread {
                getActiveWebView()?.loadUrl(url)
            }
        }, "Android")

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val u = request?.url?.toString() ?: return false
                if (u.startsWith("http://") || u.startsWith("https://") || u.startsWith("file://")) {
                    return false
                }
                return try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(u))
                    startActivity(intent)
                    true
                } catch (e: Exception) {
                    true
                }
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                tab.isLoading = true
                if (tab.id == activeTabId) {
                    binding.progressBar.visibility = View.VISIBLE
                    binding.btnReload.setImageResource(R.drawable.ic_close)
                    updateUrlDisplay(url)
                }

                // Inject early-intercept script for Partner Center
                val appSettings = settingsManager.getSettings()
                if (appSettings.isExtensionEnabled && appSettings.isEarlyInterceptEnabled) {
                    if (url != null && url.contains("play.google.com/books/publish")) {
                        injectScriptFromAsset(view, "extension/early-intercept.js")
                    }
                }
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                tab.isLoading = false
                tab.url = url ?: tab.url
                tab.title = view?.title ?: tab.title
                tab.canGoBack = view?.canGoBack() ?: false
                tab.canGoForward = view?.canGoForward() ?: false

                if (tab.id == activeTabId) {
                    binding.progressBar.visibility = View.GONE
                    binding.swipeRefresh.isRefreshing = false
                    binding.btnReload.setImageResource(R.drawable.ic_refresh)
                    updateUrlDisplay(url)
                    updateNavButtons()
                    updateBookmarkStar(url)
                }

                // Save to history
                if (url != null && !url.startsWith("file://") && !url.contains("home.html")) {
                    historyManager.addHistory(url, view?.title ?: url)
                }

                // Inject Play Books Auto Uploader v9.26 scripts
                val appSettings = settingsManager.getSettings()
                if (appSettings.isExtensionEnabled && url != null && url.contains("play.google.com/books/publish")) {
                    injectScriptFromAsset(view, "extension/extension-bridge.js")
                    injectScriptFromAsset(view, "extension/background.js")
                    injectScriptFromAsset(view, "extension/jszip.min.js")
                    injectScriptFromAsset(view, "extension/content.js")
                    view?.evaluateJavascript("""
                        (function() {
                            try {
                                if (window.pbuBuildPanel) window.pbuBuildPanel();
                                console.log('[PBU Android] Injected extension scripts successfully.');
                            } catch (e) {
                                console.error('[PBU Android] In-page init error: ', e);
                            }
                        })();
                    """.trimIndent(), null)
                }
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onReceivedTitle(view: WebView?, title: String?) {
                super.onReceivedTitle(view, title)
                if (!title.isNullOrBlank()) {
                    tab.title = title
                }
            }

            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                super.onProgressChanged(view, newProgress)
                if (tab.id == activeTabId) {
                    binding.progressBar.progress = newProgress
                    if (newProgress >= 100) {
                        binding.progressBar.visibility = View.GONE
                    }
                }
            }

            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                this@MainActivity.filePathCallback?.onReceiveValue(null)
                this@MainActivity.filePathCallback = filePathCallback

                val intent = fileChooserParams?.createIntent() ?: Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "*/*"
                    addCategory(Intent.CATEGORY_OPENABLE)
                }

                try {
                    fileChooserLauncher.launch(intent)
                } catch (e: Exception) {
                    this@MainActivity.filePathCallback = null
                    return false
                }
                return true
            }
        }

        return webView
    }

    private fun injectScriptFromAsset(view: WebView?, assetPath: String) {
        if (view == null) return
        try {
            val script = assets.open(assetPath).bufferedReader().use { it.readText() }
            view.evaluateJavascript(script, null)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /* -------------------------------------------------------------
     * TOP TOOLBAR CONTROLS
     * ------------------------------------------------------------- */

    private fun initTopBar() {
        binding.btnVpnPill.setOnClickListener {
            showVpnDialog()
        }

        binding.etUrl.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_GO || actionId == EditorInfo.IME_ACTION_DONE) {
                val input = binding.etUrl.text.toString().trim()
                if (input.isNotEmpty()) {
                    loadFromInput(input)
                    hideKeyboard()
                }
                true
            } else {
                false
            }
        }

        binding.etUrl.doAfterTextChanged { s ->
            val hasText = !s.isNullOrEmpty()
            binding.btnClear.visibility = if (binding.etUrl.hasFocus() && hasText) View.VISIBLE else View.GONE
        }

        binding.etUrl.setOnFocusChangeListener { _, hasFocus ->
            val curUrl = getActiveTab()?.url
            val isHome = curUrl == null || curUrl == homeUrl || curUrl.startsWith("file://")
            if (hasFocus) {
                if (!isHome && curUrl != null) {
                    binding.etUrl.setText(curUrl)
                    binding.etUrl.selectAll()
                }
                binding.btnClear.visibility = if (binding.etUrl.text.isNotEmpty()) View.VISIBLE else View.GONE
                binding.btnCopyUrl.visibility = if (!isHome) View.VISIBLE else View.GONE
            } else {
                binding.btnClear.visibility = View.GONE
                binding.btnCopyUrl.visibility = View.GONE
                updateUrlDisplay(curUrl)
            }
        }

        binding.btnCopyUrl.setOnClickListener {
            val u = getActiveTab()?.url
            if (!u.isNullOrBlank() && u != homeUrl) {
                val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clip = ClipData.newPlainText("URL", u)
                clipboard.setPrimaryClip(clip)
                Toast.makeText(this, "URL copied to clipboard", Toast.LENGTH_SHORT).show()
            }
        }

        binding.btnClear.setOnClickListener {
            binding.etUrl.setText("")
        }

        binding.btnReload.setOnClickListener {
            val wv = getActiveWebView()
            val curUrl = wv?.url
            if (binding.progressBar.visibility == View.VISIBLE) {
                wv?.stopLoading()
                binding.progressBar.visibility = View.GONE
                binding.btnReload.setImageResource(R.drawable.ic_refresh)
            } else {
                if (curUrl == null || curUrl == homeUrl) {
                    wv?.loadUrl(homeUrl)
                } else {
                    wv?.reload()
                }
            }
        }

        binding.btnStar.setOnClickListener {
            val wv = getActiveWebView()
            val url = wv?.url
            val title = wv?.title ?: ""
            if (url != null && url != homeUrl && !url.startsWith("file://")) {
                val added = bookmarkManager.toggleBookmark(url, title)
                updateBookmarkStar(url)
                val msg = if (added) "Bookmarked page ⭐" else "Bookmark removed"
                Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
            }
        }

        binding.swipeRefresh.setOnRefreshListener {
            val wv = getActiveWebView()
            val current = wv?.url
            if (current != null && current != homeUrl) {
                wv.reload()
            } else {
                binding.swipeRefresh.isRefreshing = false
            }
        }
    }

    /* -------------------------------------------------------------
     * BOTTOM NAVIGATION BAR
     * ------------------------------------------------------------- */

    private fun initBottomNav() {
        binding.navBack.setOnClickListener {
            val wv = getActiveWebView()
            if (wv != null && wv.canGoBack()) {
                wv.goBack()
            } else {
                getActiveWebView()?.loadUrl(homeUrl)
            }
        }

        binding.navForward.setOnClickListener {
            val wv = getActiveWebView()
            if (wv != null && wv.canGoForward()) {
                wv.goForward()
            }
        }

        binding.navHome.setOnClickListener {
            getActiveWebView()?.loadUrl(homeUrl)
        }

        binding.navDesktop.setOnClickListener {
            toggleDesktopMode()
        }

        binding.navTabs.setOnClickListener {
            showTabsDialog()
        }

        binding.navMenu.setOnClickListener {
            showSettingsDialog()
        }
    }

    private fun initBackPress() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                val wv = getActiveWebView()
                if (wv != null && wv.canGoBack()) {
                    wv.goBack()
                } else {
                    val current = wv?.url
                    if (current != null && current != homeUrl) {
                        wv.loadUrl(homeUrl)
                    } else if (tabs.size > 1) {
                        closeTab(activeTabId)
                    } else {
                        finish()
                    }
                }
            }
        })
    }

    /* -------------------------------------------------------------
     * URL PARSING & LOADING
     * ------------------------------------------------------------- */

    private fun loadFromInput(input: String) {
        val trimmed = input.trim()
        val url = when {
            trimmed.startsWith("http://", ignoreCase = true) ||
            trimmed.startsWith("https://", ignoreCase = true) ||
            trimmed.startsWith("file://", ignoreCase = true) -> trimmed
            trimmed.contains(".") && !trimmed.contains(" ") -> "https://$trimmed"
            else -> settingsManager.getSearchUrl(trimmed)
        }
        loadUrl(url)
    }

    fun loadUrl(url: String) {
        getActiveWebView()?.loadUrl(url)
        updateBookmarkStar(url)
    }

    private fun toggleDesktopMode() {
        isDesktopMode = !isDesktopMode
        for (t in tabs) {
            val settings = t.webView?.settings ?: continue
            if (isDesktopMode) {
                settings.userAgentString = desktopUserAgent
                settings.useWideViewPort = true
                settings.loadWithOverviewMode = true
            } else {
                settings.userAgentString = defaultMobileUserAgent
            }
        }
        if (isDesktopMode) {
            binding.navDesktop.setColorFilter(ContextCompat.getColor(this, R.color.primary_accent))
            Toast.makeText(this, "Desktop Site Enabled", Toast.LENGTH_SHORT).show()
        } else {
            binding.navDesktop.setColorFilter(ContextCompat.getColor(this, R.color.text_primary))
            Toast.makeText(this, "Mobile Site Enabled", Toast.LENGTH_SHORT).show()
        }
        getActiveWebView()?.reload()
    }

    private fun updateUrlDisplay(url: String?) {
        if (binding.etUrl.hasFocus()) return
        if (url == null || url == homeUrl || url.startsWith("file://")) {
            binding.etUrl.setText("")
            binding.etUrl.hint = getString(R.string.search_hint)
            binding.ivSecurity.setImageResource(R.drawable.ic_lock)
            binding.btnStar.visibility = View.GONE
        } else {
            val uri = Uri.parse(url)
            val host = uri.host ?: url
            binding.etUrl.setText(host)
            binding.ivSecurity.setImageResource(if (url.startsWith("https://")) R.drawable.ic_lock else R.drawable.ic_search)
            binding.btnStar.visibility = View.VISIBLE
        }
    }

    private fun updateNavButtons() {
        val wv = getActiveWebView()
        val canBack = wv?.canGoBack() ?: false
        val canForward = wv?.canGoForward() ?: false
        binding.navBack.alpha = if (canBack) 1.0f else 0.4f
        binding.navForward.alpha = if (canForward) 1.0f else 0.4f
    }

    private fun updateBookmarkStar(url: String?) {
        if (url == null || url == homeUrl || url.startsWith("file://")) {
            binding.btnStar.visibility = View.GONE
            return
        }
        binding.btnStar.visibility = View.VISIBLE
        val isBookmarked = bookmarkManager.isBookmarked(url)
        if (isBookmarked) {
            binding.btnStar.setImageResource(R.drawable.ic_bookmark_filled)
            binding.btnStar.setColorFilter(ContextCompat.getColor(this, R.color.primary_accent))
        } else {
            binding.btnStar.setImageResource(R.drawable.ic_bookmark)
            binding.btnStar.setColorFilter(ContextCompat.getColor(this, R.color.text_secondary))
        }
    }

    /* -------------------------------------------------------------
     * VPN & PROXY CONTROLLER
     * ------------------------------------------------------------- */

    private fun applyProxyConnection(enabled: Boolean) {
        val s = settingsManager.getSettings()
        proxyManager.applyProxy(
            enabled = enabled,
            type = s.proxyType,
            host = s.proxyHost,
            port = s.proxyPort
        ) { success, err ->
            runOnUiThread {
                if (success) {
                    s.isAutoProxyEnabled = enabled
                    settingsManager.saveSettings(s)
                    updateVpnPillUi(enabled)
                    val msg = if (enabled) "VPN / SOCKS5 Proxy Connected (${s.proxyHost}:${s.proxyPort})" else "VPN Disconnected"
                    Toast.makeText(this@MainActivity, msg, Toast.LENGTH_SHORT).show()
                } else {
                    updateVpnPillUi(false)
                    Toast.makeText(this@MainActivity, "Proxy Error: ${err ?: "Failed"}", Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private fun updateVpnPillUi(active: Boolean) {
        if (active) {
            binding.btnVpnPill.setBackgroundResource(R.drawable.bg_vpn_pill_on)
            binding.vpnDot.backgroundTintList = ContextCompat.getColorStateList(this, R.color.active_green)
            binding.tvVpnText.text = "VPN Active"
            binding.tvVpnText.setTextColor(ContextCompat.getColor(this, R.color.active_green))
        } else {
            binding.btnVpnPill.setBackgroundResource(R.drawable.bg_vpn_pill_off)
            binding.vpnDot.backgroundTintList = ContextCompat.getColorStateList(this, R.color.text_muted)
            binding.tvVpnText.text = "VPN Off"
            binding.tvVpnText.setTextColor(ContextCompat.getColor(this, R.color.text_muted))
        }
    }

    private fun showVpnDialog() {
        val dialog = BottomSheetDialog(this)
        val v = layoutInflater.inflate(R.layout.dialog_vpn, null)
        dialog.setContentView(v)

        val s = settingsManager.getSettings()
        val isActive = proxyManager.isProxyActive()

        val tvStatus = v.findViewById<TextView>(R.id.tvVpnStatusBadge)
        val btnToggle = v.findViewById<MaterialButton>(R.id.btnToggleVpn)
        val btnTestIp = v.findViewById<MaterialButton>(R.id.btnTestIp)
        val etHost = v.findViewById<EditText>(R.id.etProxyHost)
        val etPort = v.findViewById<EditText>(R.id.etProxyPort)
        val swAuto = v.findViewById<SwitchMaterial>(R.id.swAutoConnect)
        val btnSave = v.findViewById<MaterialButton>(R.id.btnSaveProxy)

        etHost.setText(s.proxyHost)
        etPort.setText(s.proxyPort.toString())
        swAuto.isChecked = s.isAutoProxyEnabled

        fun refreshUi(connected: Boolean) {
            if (connected) {
                tvStatus.text = "CONNECTED"
                tvStatus.setTextColor(ContextCompat.getColor(this, R.color.active_green))
                btnToggle.text = "Disconnect VPN"
                btnToggle.setBackgroundColor(ContextCompat.getColor(this, android.R.color.holo_red_dark))
            } else {
                tvStatus.text = "DISCONNECTED"
                tvStatus.setTextColor(ContextCompat.getColor(this, R.color.text_muted))
                btnToggle.text = "Connect VPN"
                btnToggle.setBackgroundColor(ContextCompat.getColor(this, R.color.primary_accent))
            }
        }

        refreshUi(isActive)

        btnToggle.setOnClickListener {
            val nextState = !proxyManager.isProxyActive()
            applyProxyConnection(nextState)
            refreshUi(nextState)
        }

        btnTestIp.setOnClickListener {
            dialog.dismiss()
            openNewTab("https://browserleaks.com/ip")
        }

        btnSave.setOnClickListener {
            val host = etHost.text.toString().trim()
            val port = etPort.text.toString().trim().toIntOrNull() ?: 10808
            s.proxyHost = host
            s.proxyPort = port
            s.isAutoProxyEnabled = swAuto.isChecked
            settingsManager.saveSettings(s)
            Toast.makeText(this, "Proxy settings saved", Toast.LENGTH_SHORT).show()
            if (proxyManager.isProxyActive()) {
                applyProxyConnection(true)
            }
            dialog.dismiss()
        }

        dialog.show()
    }

    /* -------------------------------------------------------------
     * MULTI-TABS DIALOG
     * ------------------------------------------------------------- */

    private fun showTabsDialog() {
        val dialog = BottomSheetDialog(this)
        val v = layoutInflater.inflate(R.layout.dialog_tabs, null)
        dialog.setContentView(v)

        val tvHeader = v.findViewById<TextView>(R.id.tvTabsHeader)
        val btnCloseAll = v.findViewById<TextView>(R.id.btnCloseAllTabs)
        val btnNew = v.findViewById<View>(R.id.btnNewTab)
        val rv = v.findViewById<RecyclerView>(R.id.rvTabs)

        tvHeader.text = "Tabs (${tabs.size})"

        val adapter = object : RecyclerView.Adapter<TabViewHolder>() {
            override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): TabViewHolder {
                val itemV = LayoutInflater.from(parent.context).inflate(R.layout.item_tab, parent, false)
                return TabViewHolder(itemV)
            }

            override fun onBindViewHolder(holder: TabViewHolder, position: Int) {
                val t = tabs[position]
                holder.tvTitle.text = if (t.url == homeUrl) "Homepage" else t.title
                holder.tvUrl.text = t.url
                holder.tvBadge.visibility = if (t.id == activeTabId) View.VISIBLE else View.GONE

                holder.itemView.setOnClickListener {
                    dialog.dismiss()
                    switchToTab(t.id)
                }

                holder.btnClose.setOnClickListener {
                    val pos = holder.adapterPosition
                    if (pos != RecyclerView.NO_POSITION && pos < tabs.size) {
                        val closedId = tabs[pos].id
                        closeTab(closedId)
                        notifyItemRemoved(pos)
                        tvHeader.text = "Tabs (${tabs.size})"
                        if (tabs.isEmpty()) {
                            dialog.dismiss()
                        }
                    }
                }
            }

            override fun getItemCount(): Int = tabs.size
        }

        rv.layoutManager = LinearLayoutManager(this)
        rv.adapter = adapter

        btnNew.setOnClickListener {
            dialog.dismiss()
            openNewTab(homeUrl)
        }

        btnCloseAll.setOnClickListener {
            dialog.dismiss()
            closeAllTabs()
        }

        dialog.show()
    }

    private class TabViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val tvTitle: TextView = itemView.findViewById(R.id.tvTabTitle)
        val tvUrl: TextView = itemView.findViewById(R.id.tvTabUrl)
        val tvBadge: TextView = itemView.findViewById(R.id.tvActiveBadge)
        val btnClose: ImageView = itemView.findViewById(R.id.btnCloseTab)
    }

    /* -------------------------------------------------------------
     * SETTINGS DIALOG (MATCHING ALL WINDOWS DESKTOP MODULES)
     * ------------------------------------------------------------- */

    private fun showSettingsDialog() {
        val dialog = BottomSheetDialog(this)
        val v = layoutInflater.inflate(R.layout.dialog_settings, null)
        dialog.setContentView(v)

        val s = settingsManager.getSettings()

        // 1. VPN tile
        val tvVpnSub = v.findViewById<TextView>(R.id.tvSettingsVpnSub)
        val tvVpnBadge = v.findViewById<TextView>(R.id.tvSettingsVpnBadge)
        if (proxyManager.isProxyActive()) {
            tvVpnBadge.text = "ON"
            tvVpnBadge.setTextColor(ContextCompat.getColor(this, R.color.active_green))
            tvVpnSub.text = "${s.proxyType} ${s.proxyHost}:${s.proxyPort} · Active"
        } else {
            tvVpnBadge.text = "OFF"
            tvVpnBadge.setTextColor(ContextCompat.getColor(this, R.color.text_muted))
            tvVpnSub.text = "${s.proxyType} ${s.proxyHost}:${s.proxyPort} · Disconnected"
        }
        v.findViewById<View>(R.id.btnSettingVpn).setOnClickListener {
            dialog.dismiss()
            showVpnDialog()
        }

        // 2. Extensions switch
        val swExt = v.findViewById<SwitchMaterial>(R.id.swExtension)
        val tvExtStatus = v.findViewById<TextView>(R.id.tvExtensionStatus)
        swExt.isChecked = s.isExtensionEnabled
        tvExtStatus.text = if (s.isExtensionEnabled) "v9.26 Active on Partner Center" else "Extension Disabled"
        tvExtStatus.setTextColor(ContextCompat.getColor(this, if (s.isExtensionEnabled) R.color.active_green else R.color.text_muted))

        swExt.setOnCheckedChangeListener { _, isChecked ->
            s.isExtensionEnabled = isChecked
            settingsManager.saveSettings(s)
            tvExtStatus.text = if (isChecked) "v9.26 Active on Partner Center" else "Extension Disabled"
            tvExtStatus.setTextColor(ContextCompat.getColor(this, if (isChecked) R.color.active_green else R.color.text_muted))
            Toast.makeText(this, "Extension ${if (isChecked) "Enabled" else "Disabled"}", Toast.LENGTH_SHORT).show()
        }

        v.findViewById<View>(R.id.btnToggleExtensionPanel).setOnClickListener {
            dialog.dismiss()
            val curUrl = getActiveTab()?.url
            if (curUrl != null && curUrl.contains("play.google.com/books/publish")) {
                getActiveWebView()?.evaluateJavascript("window.__pbuTogglePanel ? window.__pbuTogglePanel(true) : null", null)
                Toast.makeText(this, "Opening Auto Uploader panel...", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(this, "Opening Partner Center with Auto Uploader...", Toast.LENGTH_SHORT).show()
                openNewTab("https://play.google.com/books/publish/u/0/")
            }
        }

        // 3. Profiles
        val tvProfile = v.findViewById<TextView>(R.id.tvCurrentProfile)
        tvProfile.text = profileManager.getActiveProfile().name
        v.findViewById<View>(R.id.btnSettingProfiles).setOnClickListener {
            dialog.dismiss()
            showProfilesDialog()
        }

        // 4. Bookmarks
        v.findViewById<View>(R.id.btnSettingBookmarks).setOnClickListener {
            dialog.dismiss()
            showBookmarksDialog()
        }

        // 5. History
        v.findViewById<View>(R.id.btnSettingHistory).setOnClickListener {
            dialog.dismiss()
            showHistoryDialog()
        }

        // 6. Search Engine
        val tvSearch = v.findViewById<TextView>(R.id.tvSearchEngine)
        tvSearch.text = s.searchEngine
        v.findViewById<View>(R.id.btnSettingSearchEngine).setOnClickListener {
            val engines = arrayOf("Google", "DuckDuckGo", "Bing")
            AlertDialog.Builder(this)
                .setTitle("Select Search Engine")
                .setItems(engines) { _, which ->
                    s.searchEngine = engines[which]
                    settingsManager.saveSettings(s)
                    tvSearch.text = s.searchEngine
                    Toast.makeText(this, "Search engine: ${s.searchEngine}", Toast.LENGTH_SHORT).show()
                }
                .show()
        }

        // 7. Quick Partner Center
        v.findViewById<View>(R.id.btnQuickPartnerCenter).setOnClickListener {
            dialog.dismiss()
            openNewTab("https://play.google.com/books/publish/u/0/")
        }

        // 8. Clear Data
        v.findViewById<View>(R.id.btnClearData).setOnClickListener {
            dialog.dismiss()
            showClearDataConfirmation()
        }

        dialog.show()
    }

    /* -------------------------------------------------------------
     * PROFILES DIALOG
     * ------------------------------------------------------------- */

    private fun showProfilesDialog() {
        val list = profileManager.getProfiles()
        val names = list.map { it.name }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle("Select Browser Profile")
            .setItems(names) { _, which ->
                val selected = list[which]
                profileManager.setActiveProfile(selected.id)
                Toast.makeText(this, "Switched to profile: ${selected.name}", Toast.LENGTH_SHORT).show()
            }
            .setPositiveButton("+ New Profile") { _, _ ->
                val input = EditText(this)
                input.hint = "Profile Name (e.g. Work, Studio)"
                AlertDialog.Builder(this)
                    .setTitle("Create Profile")
                    .setView(input)
                    .setPositiveButton("Create") { _, _ ->
                        val name = input.text.toString().trim()
                        if (name.isNotEmpty()) {
                            profileManager.addProfile(name, "#8B5CF6")
                            Toast.makeText(this, "Profile '$name' created", Toast.LENGTH_SHORT).show()
                        }
                    }
                    .setNegativeButton("Cancel", null)
                    .show()
            }
            .show()
    }

    /* -------------------------------------------------------------
     * HISTORY DIALOG
     * ------------------------------------------------------------- */

    private fun showHistoryDialog() {
        val dialog = BottomSheetDialog(this)
        val v = layoutInflater.inflate(R.layout.dialog_history, null)
        dialog.setContentView(v)

        val rv = v.findViewById<RecyclerView>(R.id.rvHistory)
        val tvEmpty = v.findViewById<TextView>(R.id.tvEmptyHistory)
        val btnClearAll = v.findViewById<TextView>(R.id.btnClearAllHistory)

        val list = historyManager.getHistory()
        tvEmpty.visibility = if (list.isEmpty()) View.VISIBLE else View.GONE
        rv.visibility = if (list.isEmpty()) View.GONE else View.VISIBLE

        val adapter = object : RecyclerView.Adapter<HistoryViewHolder>() {
            override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): HistoryViewHolder {
                val itemV = LayoutInflater.from(parent.context).inflate(R.layout.item_history, parent, false)
                return HistoryViewHolder(itemV)
            }

            override fun onBindViewHolder(holder: HistoryViewHolder, position: Int) {
                val h = list[position]
                holder.tvTitle.text = h.title
                holder.tvUrl.text = h.url

                holder.itemView.setOnClickListener {
                    dialog.dismiss()
                    loadUrl(h.url)
                }

                holder.btnDelete.setOnClickListener {
                    val pos = holder.adapterPosition
                    if (pos != RecyclerView.NO_POSITION && pos < list.size) {
                        historyManager.removeHistory(h.id)
                        list.removeAt(pos)
                        notifyItemRemoved(pos)
                        tvEmpty.visibility = if (list.isEmpty()) View.VISIBLE else View.GONE
                        rv.visibility = if (list.isEmpty()) View.GONE else View.VISIBLE
                    }
                }
            }

            override fun getItemCount(): Int = list.size
        }

        rv.layoutManager = LinearLayoutManager(this)
        rv.adapter = adapter

        btnClearAll.setOnClickListener {
            historyManager.clearHistory()
            list.clear()
            adapter.notifyDataSetChanged()
            tvEmpty.visibility = View.VISIBLE
            rv.visibility = View.GONE
            Toast.makeText(this, "History cleared", Toast.LENGTH_SHORT).show()
        }

        dialog.show()
    }

    private class HistoryViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val tvTitle: TextView = itemView.findViewById(R.id.tvHistoryTitle)
        val tvUrl: TextView = itemView.findViewById(R.id.tvHistoryUrl)
        val btnDelete: ImageView = itemView.findViewById(R.id.btnDeleteHistory)
    }

    /* -------------------------------------------------------------
     * BOOKMARKS DIALOG
     * ------------------------------------------------------------- */

    private fun showBookmarksDialog() {
        val dialog = BottomSheetDialog(this)
        val dialogView = layoutInflater.inflate(R.layout.dialog_bookmarks, null)
        dialog.setContentView(dialogView)

        val rv = dialogView.findViewById<RecyclerView>(R.id.rvBookmarks)
        val tvEmpty = dialogView.findViewById<TextView>(R.id.tvEmptyBookmarks)

        val list = bookmarkManager.getBookmarks()
        tvEmpty.visibility = if (list.isEmpty()) View.VISIBLE else View.GONE
        rv.visibility = if (list.isEmpty()) View.GONE else View.VISIBLE

        val adapter = object : RecyclerView.Adapter<BookmarkViewHolder>() {
            override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): BookmarkViewHolder {
                val itemV = LayoutInflater.from(parent.context).inflate(R.layout.item_bookmark, parent, false)
                return BookmarkViewHolder(itemV)
            }

            override fun onBindViewHolder(holder: BookmarkViewHolder, position: Int) {
                val bm = list[position]
                holder.tvTitle.text = bm.title
                holder.tvUrl.text = bm.url

                holder.itemView.setOnClickListener {
                    dialog.dismiss()
                    loadUrl(bm.url)
                }

                holder.btnDelete.setOnClickListener {
                    val pos = holder.adapterPosition
                    if (pos != RecyclerView.NO_POSITION && pos < list.size) {
                        bookmarkManager.removeBookmark(bm.id)
                        list.removeAt(pos)
                        notifyItemRemoved(pos)
                        tvEmpty.visibility = if (list.isEmpty()) View.VISIBLE else View.GONE
                        rv.visibility = if (list.isEmpty()) View.GONE else View.VISIBLE
                        updateBookmarkStar(getActiveWebView()?.url)
                    }
                }
            }

            override fun getItemCount(): Int = list.size
        }

        rv.layoutManager = LinearLayoutManager(this)
        rv.adapter = adapter

        dialog.show()
    }

    private class BookmarkViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val tvTitle: TextView = itemView.findViewById(R.id.tvBookmarkTitle)
        val tvUrl: TextView = itemView.findViewById(R.id.tvBookmarkUrl)
        val btnDelete: ImageView = itemView.findViewById(R.id.btnDeleteBookmark)
    }

    /* -------------------------------------------------------------
     * CLEAR BROWSING DATA
     * ------------------------------------------------------------- */

    private fun showClearDataConfirmation() {
        AlertDialog.Builder(this)
            .setTitle("Clear Browsing Data")
            .setMessage("This will clear cached web files, cookies, and local history.")
            .setPositiveButton("Clear Data") { _, _ ->
                for (t in tabs) {
                    t.webView?.clearCache(true)
                    t.webView?.clearHistory()
                }
                CookieManager.getInstance().removeAllCookies(null)
                historyManager.clearHistory()
                Toast.makeText(this, "Browsing data cleared", Toast.LENGTH_SHORT).show()
                getActiveWebView()?.loadUrl(homeUrl)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun hideKeyboard() {
        val imm = getSystemService(Activity.INPUT_METHOD_SERVICE) as? InputMethodManager
        imm?.hideSoftInputFromWindow(binding.etUrl.windowToken, 0)
    }
}
