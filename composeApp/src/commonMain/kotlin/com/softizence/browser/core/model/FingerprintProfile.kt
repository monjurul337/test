package com.softizence.browser.core.model

import kotlinx.serialization.Serializable
import kotlin.random.Random

/**
 * A deterministic, *coherent* fake device identity.
 *
 * Randomising each surface independently is the classic anti-detect mistake: a Windows
 * user-agent with a Metal GPU string and an Asia/Dhaka timezone behind a Swiss exit IP is
 * more unique, not less. We therefore pick ONE consistent persona from a seed and derive
 * every surface from it, and we keep it stable per [BrowsingProfile] so a site that sees
 * you twice sees the same device twice.
 */
@Serializable
data class FingerprintProfile(
    val seed: Long,
    val userAgent: String,
    val platform: String,
    val vendor: String,
    val acceptLanguage: String,
    val languages: List<String>,
    val timezone: String,
    val screenWidth: Int,
    val screenHeight: Int,
    val colorDepth: Int,
    val devicePixelRatio: Double,
    val hardwareConcurrency: Int,
    val deviceMemoryGb: Int,
    val webglVendor: String,
    val webglRenderer: String,
    val canvasNoise: Double,
    val audioNoise: Double,
    val maxTouchPoints: Int,
    val blockWebRtc: Boolean = true,
) {
    companion object {
        private data class Persona(
            val ua: String, val platform: String, val vendor: String,
            val glVendor: String, val glRenderer: String,
            val w: Int, val h: Int, val dpr: Double, val cores: Int, val mem: Int, val touch: Int,
        )

        private val personas = listOf(
            Persona(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
                "Win32", "Google Inc.", "Google Inc. (NVIDIA)",
                "ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 Direct3D11 vs_5_0 ps_5_0, D3D11)",
                1920, 1080, 1.0, 8, 16, 0,
            ),
            Persona(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
                "Win32", "Google Inc.", "Google Inc. (Intel)",
                "ANGLE (Intel, Intel(R) UHD Graphics 620 Direct3D11 vs_5_0 ps_5_0, D3D11)",
                1536, 864, 1.25, 4, 8, 0,
            ),
            Persona(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
                "MacIntel", "Google Inc.", "Google Inc. (Apple)",
                "ANGLE (Apple, ANGLE Metal Renderer: Apple M2, Unspecified Version)",
                1512, 982, 2.0, 8, 16, 0,
            ),
            Persona(
                "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
                "Linux x86_64", "Google Inc.", "Google Inc. (AMD)",
                "ANGLE (AMD, AMD Radeon RX 6600 (radeonsi), OpenGL 4.6)",
                1920, 1080, 1.0, 12, 16, 0,
            ),
            Persona(
                "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36",
                "Linux armv8l", "Google Inc.", "Qualcomm",
                "Adreno (TM) 740", 412, 915, 2.625, 8, 8, 5,
            ),
        )

        /** Timezone must agree with the exit country, so the tunnel reports it back in. */
        fun forSeed(seed: Long, timezone: String = "UTC", locale: String = "en-US"): FingerprintProfile {
            val rnd = Random(seed)
            val p = personas[(seed.hashCode().toUInt() % personas.size.toUInt()).toInt()]
            return FingerprintProfile(
                seed = seed,
                userAgent = p.ua,
                platform = p.platform,
                vendor = p.vendor,
                acceptLanguage = "$locale,${locale.substringBefore('-')};q=0.9",
                languages = listOf(locale, locale.substringBefore('-')),
                timezone = timezone,
                screenWidth = p.w,
                screenHeight = p.h,
                colorDepth = 24,
                devicePixelRatio = p.dpr,
                hardwareConcurrency = p.cores,
                deviceMemoryGb = p.mem,
                webglVendor = p.glVendor,
                webglRenderer = p.glRenderer,
                // Sub-perceptual, deterministic jitter: breaks hash-equality without
                // looking like a scrambler (which is itself a detectable signal).
                canvasNoise = rnd.nextDouble(0.0001, 0.0009),
                audioNoise = rnd.nextDouble(0.00001, 0.00009),
                maxTouchPoints = p.touch,
            )
        }

        val Default = forSeed(0x50F7_12E4L)
    }
}
