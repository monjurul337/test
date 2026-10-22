package com.softizence.browser.net

import kotlinx.serialization.Serializable

/**
 * A parsed `wg-quick` configuration file - the exact format Proton VPN hands out
 * from "Downloads -> WireGuard configuration".
 *
 * Proton files look like:
 * ```
 * [Interface]
 * # Key for Softizence
 * # Bouncing = 1
 * # NetShield = 1
 * PrivateKey = qK...=
 * Address = 10.2.0.2/32
 * DNS = 10.2.0.1
 *
 * [Peer]
 * # CH-FR#1
 * PublicKey = AB...=
 * AllowedIPs = 0.0.0.0/0, ::/0
 * Endpoint = 185.159.158.1:51820
 * ```
 */
@Serializable
data class WireGuardConfig(
    val id: String,
    val name: String,
    val interfaceSection: InterfaceSection,
    val peers: List<PeerSection>,
    /** Original file text, byte-identical - handed to wireguard-go / the kernel as-is. */
    val rawText: String,
    val sourcePath: String? = null,
) {
    @Serializable
    data class InterfaceSection(
        val privateKey: String,
        val addresses: List<String>,
        val dns: List<String> = emptyList(),
        val mtu: Int? = null,
        val listenPort: Int? = null,
    )

    @Serializable
    data class PeerSection(
        val publicKey: String,
        val endpoint: String,
        val allowedIps: List<String>,
        val presharedKey: String? = null,
        val persistentKeepalive: Int? = null,
        /** Proton writes the exit node name as a comment above the peer, e.g. `# CH-FR#1`. */
        val label: String? = null,
    ) {
        val endpointHost: String get() = endpoint.substringBeforeLast(':').trim('[', ']')
        val endpointPort: Int get() = endpoint.substringAfterLast(':').toIntOrNull() ?: 51820
    }

    /** True when the peer claims the whole routing table - i.e. full-tunnel, no leaks. */
    val isFullTunnel: Boolean
        get() = peers.any { p -> p.allowedIps.any { it == "0.0.0.0/0" } }

    /** Two-letter country guessed from the Proton peer label (`CH-FR#1` -> `CH`). */
    val country: String?
        get() = peers.firstNotNullOfOrNull { it.label }
            ?.take(2)
            ?.takeIf { it.length == 2 && it.all(Char::isLetter) }
            ?.uppercase()
}

class WireGuardConfigException(message: String) : IllegalArgumentException(message)

/**
 * Tolerant wg-quick parser. Deliberately hand-rolled rather than regex-golfed so that
 * malformed user files produce an actionable message instead of a silent half-tunnel.
 */
object WireGuardConfigParser {

    private const val B64_KEY_LEN = 44

    fun parse(fileName: String, text: String): WireGuardConfig {
        var current: String? = null
        val iface = mutableMapOf<String, String>()
        val peers = mutableListOf<MutableMap<String, String>>()
        var pendingComment: String? = null

        text.lineSequence().forEach { rawLine ->
            val line = rawLine.trim()
            when {
                line.isEmpty() -> Unit

                line.startsWith("#") || line.startsWith(";") -> {
                    // Keep the last comment: Proton uses it as the exit-node label.
                    pendingComment = line.trimStart('#', ';', ' ').takeIf { it.isNotBlank() }
                }

                line.startsWith("[") && line.endsWith("]") -> {
                    current = line.trim('[', ']').lowercase()
                    if (current == "peer") {
                        peers += mutableMapOf<String, String>().also { p ->
                            pendingComment?.let { c -> p["label"] = c }
                        }
                    }
                    pendingComment = null
                }

                "=" in line -> {
                    val key = line.substringBefore('=').trim().lowercase()
                    val value = line.substringAfter('=').trim()
                    when (current) {
                        "interface" -> iface[key] = value
                        "peer" -> peers.lastOrNull()?.put(key, value)
                        else -> throw WireGuardConfigException(
                            "Key \"$key\" appears before any [Interface] or [Peer] section."
                        )
                    }
                }
            }
        }

        val privateKey = iface["privatekey"]
            ?: throw WireGuardConfigException("[Interface] is missing PrivateKey.")
        require(privateKey.isValidWgKey()) {
            throw WireGuardConfigException("[Interface] PrivateKey is not a 44-character base64 key.")
        }

        val addresses = iface["address"].splitList()
        if (addresses.isEmpty()) {
            throw WireGuardConfigException("[Interface] is missing Address (e.g. 10.2.0.2/32).")
        }
        if (peers.isEmpty()) {
            throw WireGuardConfigException("No [Peer] section found - nothing to connect to.")
        }

        val parsedPeers = peers.mapIndexed { index, p ->
            val pub = p["publickey"]
                ?: throw WireGuardConfigException("[Peer] #${index + 1} is missing PublicKey.")
            if (!pub.isValidWgKey()) {
                throw WireGuardConfigException("[Peer] #${index + 1} PublicKey is not a valid base64 key.")
            }
            val endpoint = p["endpoint"]
                ?: throw WireGuardConfigException("[Peer] #${index + 1} is missing Endpoint.")
            if (':' !in endpoint) {
                throw WireGuardConfigException("[Peer] #${index + 1} Endpoint must be host:port.")
            }
            WireGuardConfig.PeerSection(
                publicKey = pub,
                endpoint = endpoint,
                allowedIps = p["allowedips"].splitList().ifEmpty { listOf("0.0.0.0/0", "::/0") },
                presharedKey = p["presharedkey"]?.takeIf { it.isValidWgKey() },
                persistentKeepalive = p["persistentkeepalive"]?.toIntOrNull(),
                label = p["label"],
            )
        }

        return WireGuardConfig(
            id = stableId(fileName, privateKey, parsedPeers.first().endpoint),
            name = fileName.removeSuffix(".conf").ifBlank { parsedPeers.first().label ?: "Tunnel" },
            interfaceSection = WireGuardConfig.InterfaceSection(
                privateKey = privateKey,
                addresses = addresses,
                dns = iface["dns"].splitList(),
                mtu = iface["mtu"]?.toIntOrNull(),
                listenPort = iface["listenport"]?.toIntOrNull(),
            ),
            peers = parsedPeers,
            rawText = text,
        )
    }

    /** Parse without throwing - used when scanning a whole folder of configs. */
    fun parseOrNull(fileName: String, text: String): Result<WireGuardConfig> =
        runCatching { parse(fileName, text) }

    private fun String?.splitList(): List<String> =
        this?.split(',')?.map(String::trim)?.filter(String::isNotEmpty).orEmpty()

    private fun String.isValidWgKey(): Boolean =
        length == B64_KEY_LEN && endsWith("=") && all { it.isLetterOrDigit() || it in "+/=" }

    private fun stableId(vararg parts: String): String {
        var h = -0x340d631b7bdddcdbL // FNV-1a 64 offset basis
        parts.joinToString("|").encodeToByteArray().forEach { b ->
            h = (h xor b.toLong()) * 0x100000001b3L
        }
        return h.toULong().toString(16).padStart(16, '0')
    }
}
