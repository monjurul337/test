package com.sotizence.playbooks.browser.model

data class AppSettings(
    var searchEngine: String = "Google", // Google, DuckDuckGo, Bing
    var homepageUrl: String = "file:///android_asset/home/home.html",
    var userAgentMode: String = "desktop", // desktop, mobile, custom
    var customUserAgent: String = "",
    var isExtensionEnabled: Boolean = true,
    var isEarlyInterceptEnabled: Boolean = true,
    var isAutoProxyEnabled: Boolean = false,
    var proxyType: String = "SOCKS5", // SOCKS5, HTTP
    var proxyHost: String = "127.0.0.1",
    var proxyPort: Int = 10808,
    var wireGuardConfig: String = "",
    var activeProfileId: String = "default"
)
