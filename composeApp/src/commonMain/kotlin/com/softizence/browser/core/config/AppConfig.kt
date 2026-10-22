package com.softizence.browser.core.config

import com.softizence.browser.net.TunnelPolicy
import com.softizence.browser.privacy.PrivacySettings
import kotlinx.serialization.Serializable

/**
 * Single, versioned configuration document (`<configDir>/config.json`).
 *
 * Everything the product can be tuned with lives here so the app stays extensible without
 * recompiling: search engines, start page, privacy defaults, tunnel policy, feature flags
 * and per-profile identities. Unknown keys are preserved-by-default on read so a newer
 * build's settings survive a downgrade.
 */
@Serializable
data class AppConfig(
    val schemaVersion: Int = CURRENT_SCHEMA,
    val appearance: Appearance = Appearance(),
    val search: Search = Search(),
    val privacy: PrivacySettings = PrivacySettings(),
    val tunnel: TunnelConfig = TunnelConfig(),
    val extensions: ExtensionConfig = ExtensionConfig(),
    val profiles: List<ProfileConfig> = listOf(ProfileConfig()),
    val featureFlags: Map<String, Boolean> = defaultFlags,
) {
    @Serializable
    data class Appearance(
        /** "obsidian" (dark, default) or "porcelain" (light). */
        val theme: String = "obsidian",
        val accent: String = "brass",
        val cornerRadiusDp: Int = 18,
        val tabStrip: String = "rail",          // rail | top | hidden
        val glassBlur: Boolean = true,
        val reduceMotion: Boolean = false,
        val fontScale: Float = 1.0f,
    )

    @Serializable
    data class Search(
        val defaultEngineId: String = "ddg",
        val engines: List<Engine> = listOf(
            Engine("ddg", "DuckDuckGo", "https://duckduckgo.com/?q=%s", "https://duckduckgo.com/ac/?q=%s&type=list"),
            Engine("startpage", "Startpage", "https://www.startpage.com/sp/search?query=%s", null),
            Engine("brave", "Brave", "https://search.brave.com/search?q=%s", null),
            Engine("google", "Google", "https://www.google.com/search?q=%s", null),
        ),
        val suggestionsEnabled: Boolean = false,  // off by default: suggestions leak keystrokes
    ) {
        @Serializable
        data class Engine(val id: String, val name: String, val urlTemplate: String, val suggestTemplate: String?)

        fun resolve(query: String): String {
            val engine = engines.firstOrNull { it.id == defaultEngineId } ?: engines.first()
            return engine.urlTemplate.replace("%s", query.encodeQuery())
        }
    }

    @Serializable
    data class TunnelConfig(
        val killSwitch: Boolean = true,
        val tunnelDns: Boolean = true,
        val autoReconnect: Boolean = true,
        val autoConnectConfigId: String? = null,
        val showPublicIpBadge: Boolean = true,
        val ipCheckEndpoints: List<String> = listOf(
            "https://api.ipify.org?format=json",
            "https://ifconfig.co/json",
            "https://ipinfo.io/json",
        ),
        val splitTunnelExclusions: List<String> = emptyList(),
    ) {
        fun toPolicy() = TunnelPolicy(killSwitch, tunnelDns, autoReconnect, splitTunnelExclusions)
    }

    @Serializable
    data class ExtensionConfig(
        val enabled: Boolean = true,
        /** Extra folders scanned for unpacked MV3 extensions, besides the managed dir. */
        val extraSearchPaths: List<String> = emptyList(),
        val disabledIds: List<String> = emptyList(),
        val allowFileAccess: Boolean = false,
    )

    @Serializable
    data class ProfileConfig(
        val id: String = "default",
        val name: String = "Personal",
        val colorTag: Long = 0xFFC9A227,
        val fingerprintSeed: Long = 0x50F7_12E4L,
        val persistCookies: Boolean = true,
        val pinnedTunnelId: String? = null,
        val startupUrls: List<String> = emptyList(),
    )

    companion object {
        const val CURRENT_SCHEMA = 1

        val defaultFlags = mapOf(
            "ui.commandPalette" to true,
            "ui.readerMode" to true,
            "ui.splitView" to true,
            "net.quicDisabled" to true,      // QUIC can bypass some userspace tunnels
            "ext.mv3ServiceWorkers" to true,
            "privacy.perProfileFingerprint" to true,
        )

        val Default = AppConfig()
    }
}

/** Minimal percent-encoding so the module stays free of platform URL classes. */
internal fun String.encodeQuery(): String = buildString {
    this@encodeQuery.encodeToByteArray().forEach { byte ->
        val c = byte.toInt().toChar()
        when {
            c.isLetterOrDigit() || c in "-_.~" -> append(c)
            c == ' ' -> append('+')
            else -> append('%').append(((byte.toInt() and 0xFF).toString(16)).padStart(2, '0').uppercase())
        }
    }
}
