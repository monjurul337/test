package com.sotizence.playbooks.browser

import android.webkit.JavascriptInterface

class WebAppInterface(private val onNavigate: (String) -> Unit) {
    @JavascriptInterface
    fun openUrl(url: String) {
        onNavigate(url)
    }
}
