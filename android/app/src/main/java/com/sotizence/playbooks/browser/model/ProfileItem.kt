package com.sotizence.playbooks.browser.model

data class ProfileItem(
    val id: String = "default",
    val name: String = "Default Profile",
    val color: String = "#6366F1",
    val proxyEnabled: Boolean = false,
    val proxyHost: String = "127.0.0.1",
    val proxyPort: Int = 10808,
    val proxyType: String = "SOCKS5" // SOCKS5 or HTTP
)
