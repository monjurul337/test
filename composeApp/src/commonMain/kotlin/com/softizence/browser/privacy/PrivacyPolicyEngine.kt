package com.softizence.browser.privacy

import com.softizence.browser.core.model.FingerprintProfile
import kotlinx.serialization.Serializable

/** User-visible privacy switches. Everything here is enforced in the engine, not just the UI. */
@Serializable
data class PrivacySettings(
    val maskFingerprint: Boolean = true,
    val blockWebRtc: Boolean = true,
    val blockThirdPartyCookies: Boolean = true,
    val stripTrackingParams: Boolean = true,
    val forceHttps: Boolean = true,
    val doNotTrack: Boolean = true,
    val spoofTimezoneFromExit: Boolean = true,
    val blockTrackerHosts: Boolean = true,
)

/** Request-time privacy decisions shared by both engines. */
class PrivacyPolicyEngine(
    @Volatile var settings: PrivacySettings = PrivacySettings(),
    @Volatile var fingerprint: FingerprintProfile = FingerprintProfile.Default,
) {
    private val trackingParams = setOf(
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "gclid", "gbraid", "wbraid", "dclid", "fbclid", "msclkid", "twclid", "igshid",
        "mc_eid", "mc_cid", "yclid", "_openstat", "vero_id", "oly_enc_id", "ref_src",
    )

    private val trackerHosts = setOf(
        "doubleclick.net", "googlesyndication.com", "google-analytics.com",
        "googletagmanager.com", "scorecardresearch.com", "adservice.google.com",
        "connect.facebook.net", "analytics.tiktok.com", "hotjar.com", "fullstory.com",
        "segment.io", "mixpanel.com", "branch.io", "adnxs.com", "criteo.com",
    )

    fun rewrite(url: String): String {
        var result = url
        if (settings.forceHttps && result.startsWith("http://")) {
            result = "https://" + result.removePrefix("http://")
        }
        if (settings.stripTrackingParams && '?' in result) {
            val base = result.substringBefore('?')
            val fragment = result.substringAfter('#', "")
            val query = result.substringAfter('?').substringBefore('#')
            val kept = query.split('&')
                .filter { it.isNotBlank() && it.substringBefore('=').lowercase() !in trackingParams }
            result = buildString {
                append(base)
                if (kept.isNotEmpty()) append('?').append(kept.joinToString("&"))
                if (fragment.isNotEmpty()) append('#').append(fragment)
            }
        }
        return result
    }

    fun shouldBlock(url: String): Boolean {
        if (!settings.blockTrackerHosts) return false
        val host = url.substringAfter("://", url).substringBefore('/').substringBefore(':').lowercase()
        return trackerHosts.any { host == it || host.endsWith(".$it") }
    }

    fun requestHeaders(): Map<String, String> = buildMap {
        if (settings.maskFingerprint) {
            put("User-Agent", fingerprint.userAgent)
            put("Accept-Language", fingerprint.acceptLanguage)
            put("Sec-CH-UA", "\"Chromium\";v=\"131\", \"Google Chrome\";v=\"131\", \"Not_A Brand\";v=\"24\"")
            put("Sec-CH-UA-Mobile", if (fingerprint.maxTouchPoints > 0) "?1" else "?0")
        }
        if (settings.doNotTrack) {
            put("DNT", "1")
            put("Sec-GPC", "1")
        }
    }

    fun documentStartScript(): String? =
        if (settings.maskFingerprint) {
            StealthScripts.documentStart(fingerprint.copy(blockWebRtc = settings.blockWebRtc))
        } else null
}
