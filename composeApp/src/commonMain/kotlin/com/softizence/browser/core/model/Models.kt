package com.softizence.browser.core.model

import kotlinx.serialization.Serializable

/** A single browser tab. [id] is stable for the lifetime of the session. */
@Serializable
data class TabState(
    val id: String,
    val title: String = "New tab",
    val url: String = "softizence://home",
    val favicon: String? = null,
    val isLoading: Boolean = false,
    val progress: Float = 0f,
    val canGoBack: Boolean = false,
    val canGoForward: Boolean = false,
    /** Cookie/storage partition. Each identity gets its own jar -> persistent, isolated logins. */
    val profileId: String = "default",
    val isPinned: Boolean = false,
    val isIncognito: Boolean = false,
)

/** A named, persisted browsing identity: its own cookie jar, storage and fingerprint. */
@Serializable
data class BrowsingProfile(
    val id: String,
    val name: String,
    val colorTag: Long = 0xFFC9A227,
    val fingerprintSeed: Long,
    val persistCookies: Boolean = true,
    val tunnelId: String? = null,
)

enum class TunnelStatus { Off, Connecting, Connected, Reconnecting, Error }

@Serializable
data class TunnelState(
    val status: String = TunnelStatus.Off.name,
    val activeConfigId: String? = null,
    val activeConfigName: String? = null,
    val publicIp: String? = null,
    val country: String? = null,
    val rxBytes: Long = 0,
    val txBytes: Long = 0,
    val lastHandshakeEpochSeconds: Long = 0,
    val errorMessage: String? = null,
) {
    val statusEnum: TunnelStatus get() = runCatching { TunnelStatus.valueOf(status) }.getOrDefault(TunnelStatus.Off)
    val isUp: Boolean get() = statusEnum == TunnelStatus.Connected
}

@Serializable
data class ExtensionInfo(
    val id: String,
    val name: String,
    val version: String,
    val manifestVersion: Int,
    val description: String = "",
    val installPath: String,
    val enabled: Boolean = true,
    val permissions: List<String> = emptyList(),
    val hostPermissions: List<String> = emptyList(),
    val hasServiceWorker: Boolean = false,
    val hasPopup: Boolean = false,
    val iconPath: String? = null,
    val loadError: String? = null,
)
