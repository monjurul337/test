package com.sotizence.playbooks.browser.model

import android.webkit.WebView

data class TabItem(
    val id: String = "tab_" + System.currentTimeMillis() + "_" + (100..999).random(),
    var title: String = "New Tab",
    var url: String = "file:///android_asset/home/home.html",
    var webView: WebView? = null,
    var isLoading: Boolean = false,
    var canGoBack: Boolean = false,
    var canGoForward: Boolean = false,
    var profileId: String = "default"
)
