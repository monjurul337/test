package com.sotizence.playbooks.browser

import android.annotation.SuppressLint
import android.app.Activity
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
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.widget.doAfterTextChanged
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.sotizence.playbooks.browser.databinding.ActivityMainBinding
import com.sotizence.playbooks.browser.model.Bookmark

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var bookmarkManager: BookmarkManager

    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    private var isDesktopMode = false
    private var defaultUserAgent: String = ""
    private val desktopUserAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

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

        initWebView()
        initTopBar()
        initBottomNav()
        initBackPress()

        // Load Home Page initially
        loadUrl(homeUrl)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun initWebView() {
        val webView = binding.webView
        val settings = webView.settings

        defaultUserAgent = settings.userAgentString

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

        // Enable Cookies
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        // WebApp interface for Home screen navigation
        webView.addJavascriptInterface(WebAppInterface { url ->
            runOnUiThread { loadUrl(url) }
        }, "Android")

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val url = request?.url?.toString() ?: return false
                if (url.startsWith("http://") || url.startsWith("https://") || url.startsWith("file://")) {
                    return false
                }
                return try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    startActivity(intent)
                    true
                } catch (e: Exception) {
                    true
                }
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                binding.progressBar.visibility = View.VISIBLE
                binding.btnReload.setImageResource(R.drawable.ic_close)
                updateUrlDisplay(url)

                // Inject early intercept for Play Books Partner Center
                if (url != null && url.contains("play.google.com/books/publish")) {
                    injectScriptFromAsset(view, "extension/early-intercept.js")
                }
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                binding.progressBar.visibility = View.GONE
                binding.swipeRefresh.isRefreshing = false
                binding.btnReload.setImageResource(R.drawable.ic_refresh)
                updateUrlDisplay(url)
                updateNavButtons()
                updateBookmarkStar(url)

                // Inject Play Books Auto Uploader Extension v9.26 scripts
                if (url != null && url.contains("play.google.com/books/publish")) {
                    injectScriptFromAsset(view, "extension/jszip.min.js")
                    injectScriptFromAsset(view, "extension/content.js")
                }
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                super.onProgressChanged(view, newProgress)
                binding.progressBar.progress = newProgress
                if (newProgress >= 100) {
                    binding.progressBar.visibility = View.GONE
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

        binding.swipeRefresh.setOnRefreshListener {
            val current = webView.url
            if (current != null && current != homeUrl) {
                webView.reload()
            } else {
                binding.swipeRefresh.isRefreshing = false
            }
        }
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

    private fun initTopBar() {
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
            binding.btnClear.visibility = if (binding.etUrl.hasFocus() && !s.isNullOrEmpty()) View.VISIBLE else View.GONE
        }

        binding.etUrl.setOnFocusChangeListener { _, hasFocus ->
            if (hasFocus) {
                val current = binding.webView.url
                if (current != null && current != homeUrl) {
                    binding.etUrl.setText(current)
                    binding.etUrl.selectAll()
                }
                binding.btnClear.visibility = if (binding.etUrl.text.isNotEmpty()) View.VISIBLE else View.GONE
            } else {
                binding.btnClear.visibility = View.GONE
                updateUrlDisplay(binding.webView.url)
            }
        }

        binding.btnClear.setOnClickListener {
            binding.etUrl.setText("")
        }

        binding.btnReload.setOnClickListener {
            val current = binding.webView.url
            if (binding.progressBar.visibility == View.VISIBLE) {
                binding.webView.stopLoading()
                binding.progressBar.visibility = View.GONE
                binding.btnReload.setImageResource(R.drawable.ic_refresh)
            } else {
                if (current == null || current == homeUrl) {
                    loadUrl(homeUrl)
                } else {
                    binding.webView.reload()
                }
            }
        }

        binding.btnStar.setOnClickListener {
            val url = binding.webView.url
            val title = binding.webView.title ?: ""
            if (url != null && url != homeUrl) {
                val added = bookmarkManager.toggleBookmark(url, title)
                updateBookmarkStar(url)
                val msg = if (added) "Bookmarked page ⭐" else "Bookmark removed"
                Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun initBottomNav() {
        binding.navBack.setOnClickListener {
            if (binding.webView.canGoBack()) {
                binding.webView.goBack()
            } else {
                loadUrl(homeUrl)
            }
        }

        binding.navForward.setOnClickListener {
            if (binding.webView.canGoForward()) {
                binding.webView.goForward()
            }
        }

        binding.navHome.setOnClickListener {
            loadUrl(homeUrl)
        }

        binding.navDesktop.setOnClickListener {
            toggleDesktopMode()
        }

        binding.navBookmarks.setOnClickListener {
            showBookmarksDialog()
        }

        binding.navMenu.setOnClickListener {
            showSettingsDialog()
        }
    }

    private fun initBackPress() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (binding.webView.canGoBack()) {
                    binding.webView.goBack()
                } else {
                    val current = binding.webView.url
                    if (current != null && current != homeUrl) {
                        loadUrl(homeUrl)
                    } else {
                        finish()
                    }
                }
            }
        })
    }

    private fun loadFromInput(input: String) {
        val trimmed = input.trim()
        val url = when {
            trimmed.startsWith("http://", ignoreCase = true) || trimmed.startsWith("https://", ignoreCase = true) || trimmed.startsWith("file://", ignoreCase = true) -> trimmed
            trimmed.contains(".") && !trimmed.contains(" ") -> "https://$trimmed"
            else -> "https://www.google.com/search?q=" + Uri.encode(trimmed)
        }
        loadUrl(url)
    }

    fun loadUrl(url: String) {
        binding.webView.loadUrl(url)
        updateBookmarkStar(url)
    }

    private fun toggleDesktopMode() {
        isDesktopMode = !isDesktopMode
        val settings = binding.webView.settings
        if (isDesktopMode) {
            settings.userAgentString = desktopUserAgent
            settings.useWideViewPort = true
            settings.loadWithOverviewMode = true
            binding.navDesktop.setColorFilter(ContextCompat.getColor(this, R.color.primary_accent))
            Toast.makeText(this, "Desktop Site Enabled", Toast.LENGTH_SHORT).show()
        } else {
            settings.userAgentString = defaultUserAgent
            binding.navDesktop.setColorFilter(ContextCompat.getColor(this, R.color.text_primary))
            Toast.makeText(this, "Mobile Site Enabled", Toast.LENGTH_SHORT).show()
        }
        binding.webView.reload()
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
        val canBack = binding.webView.canGoBack()
        val canForward = binding.webView.canGoForward()
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
                val v = LayoutInflater.from(parent.context).inflate(R.layout.item_bookmark, parent, false)
                return BookmarkViewHolder(v)
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
                    bookmarkManager.removeBookmark(bm.id)
                    list.removeAt(holder.bindingAdapterPosition)
                    notifyItemRemoved(holder.bindingAdapterPosition)
                    tvEmpty.visibility = if (list.isEmpty()) View.VISIBLE else View.GONE
                    rv.visibility = if (list.isEmpty()) View.GONE else View.VISIBLE
                    updateBookmarkStar(binding.webView.url)
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

    private fun showSettingsDialog() {
        val dialog = BottomSheetDialog(this)
        val dialogView = layoutInflater.inflate(R.layout.dialog_settings, null)
        dialog.setContentView(dialogView)

        dialogView.findViewById<View>(R.id.btnQuickPartnerCenter).setOnClickListener {
            dialog.dismiss()
            loadUrl("https://play.google.com/books/publish/u/0/")
        }

        dialogView.findViewById<View>(R.id.btnClearData).setOnClickListener {
            dialog.dismiss()
            binding.webView.clearCache(true)
            binding.webView.clearHistory()
            CookieManager.getInstance().removeAllCookies(null)
            Toast.makeText(this, "Cache and cookies cleared", Toast.LENGTH_SHORT).show()
            loadUrl(homeUrl)
        }

        dialog.show()
    }

    private fun hideKeyboard() {
        val imm = getSystemService(Activity.INPUT_METHOD_SERVICE) as? InputMethodManager
        imm?.hideSoftInputFromWindow(binding.etUrl.windowToken, 0)
    }
}
