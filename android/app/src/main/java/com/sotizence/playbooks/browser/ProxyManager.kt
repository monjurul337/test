package com.sotizence.playbooks.browser

import android.content.Context
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import java.util.concurrent.Executor
import java.util.concurrent.Executors

class ProxyManager(private val context: Context) {
    private val executor: Executor = Executors.newSingleThreadExecutor()
    private var isConnected: Boolean = false

    fun applyProxy(
        enabled: Boolean,
        type: String = "SOCKS5",
        host: String = "127.0.0.1",
        port: Int = 10808,
        onResult: (Boolean, String?) -> Unit
    ) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            isConnected = false
            onResult(false, "Proxy override is not supported by your current Android System WebView.")
            return
        }

        val proxyController = ProxyController.getInstance()

        if (!enabled) {
            try {
                proxyController.clearProxyOverride(executor) {
                    isConnected = false
                    onResult(true, null)
                }
            } catch (e: Exception) {
                isConnected = false
                onResult(true, null)
            }
            return
        }

        try {
            val scheme = if (type.equals("SOCKS5", ignoreCase = true)) "socks" else "http"
            val proxyUrl = "$scheme://$host:$port"
            val config = ProxyConfig.Builder()
                .addProxyRule(proxyUrl)
                .addBypassRule("<local>")
                .build()

            proxyController.setProxyOverride(config, executor) {
                isConnected = true
                onResult(true, null)
            }
        } catch (e: Exception) {
            isConnected = false
            onResult(false, e.message ?: "Failed to set proxy")
        }
    }

    fun isProxyActive(): Boolean = isConnected
}
