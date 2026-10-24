package com.sotizence.playbooks.browser

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.JavascriptInterface
import android.widget.Toast

class WebAppInterface(
    private val context: Context? = null,
    private val onNavigate: ((String) -> Unit)? = null
) {
    constructor(onNavigate: (String) -> Unit) : this(context = null, onNavigate = onNavigate)

    @JavascriptInterface
    fun openUrl(url: String) {
        onNavigate?.invoke(url)
    }

    @JavascriptInterface
    fun showToast(message: String) {
        if (context == null) return
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
        }
    }

    @JavascriptInterface
    fun log(tag: String, message: String) {
        Log.d("PlayBooksExtension", "[$tag] $message")
    }
}
