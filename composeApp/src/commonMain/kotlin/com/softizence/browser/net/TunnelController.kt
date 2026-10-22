package com.softizence.browser.net

import com.softizence.browser.core.model.TunnelState
import com.softizence.browser.core.model.TunnelStatus
import kotlinx.coroutines.flow.StateFlow

/**
 * Platform tunnel engine.
 *
 * Android  -> [com.softizence.browser.net.AndroidTunnelController] (VpnService + wireguard-go backend)
 * Desktop  -> [com.softizence.browser.net.DesktopTunnelController] (wireguard-go / wg-quick userspace)
 *
 * Contract every implementation must honour:
 *  1. While [state] is Connected, **no** socket may leave the device outside the tunnel.
 *  2. If the tunnel drops and [TunnelPolicy.killSwitch] is on, browsing must be blocked,
 *     not silently downgraded.
 *  3. With zero configs imported, the controller stays Off and the app browses directly.
 */
interface TunnelController {
    val state: StateFlow<TunnelState>

    /** Brings [config] up, tearing down any previous tunnel first. */
    suspend fun connect(config: WireGuardConfig, policy: TunnelPolicy = TunnelPolicy())

    suspend fun disconnect()

    /** Live counters from the WireGuard device (`wg show` equivalent). */
    suspend fun refreshStatistics()

    /** True when the OS granted the VPN/TUN permission (Android consent dialog, Linux CAP_NET_ADMIN...). */
    suspend fun ensurePermission(): Boolean
}

data class TunnelPolicy(
    /** Block all traffic when the tunnel is not up. Requirement: traffic is tunnel-exclusive. */
    val killSwitch: Boolean = true,
    /** Force DNS through the tunnel's resolvers only. */
    val tunnelDns: Boolean = true,
    /** Re-dial automatically when the handshake goes stale. */
    val autoReconnect: Boolean = true,
    /** Apps/hosts explicitly kept outside the tunnel. Empty = nothing bypasses. */
    val splitTunnelExclusions: List<String> = emptyList(),
)

/** Convenience for building states without repeating the enum-to-string dance. */
fun tunnelState(
    status: TunnelStatus,
    config: WireGuardConfig? = null,
    publicIp: String? = null,
    country: String? = null,
    error: String? = null,
    rx: Long = 0,
    tx: Long = 0,
    handshake: Long = 0,
) = TunnelState(
    status = status.name,
    activeConfigId = config?.id,
    activeConfigName = config?.name,
    publicIp = publicIp,
    country = country ?: config?.country,
    rxBytes = rx,
    txBytes = tx,
    lastHandshakeEpochSeconds = handshake,
    errorMessage = error,
)
