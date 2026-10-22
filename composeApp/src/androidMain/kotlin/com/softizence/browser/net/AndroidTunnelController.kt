package com.softizence.browser.net

import android.content.Context
import android.content.Intent
import android.net.VpnService
import com.softizence.browser.core.model.TunnelState
import com.softizence.browser.core.model.TunnelStatus
import com.wireguard.android.backend.Backend
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream

/**
 * Android tunnel: hands the *original* `.conf` text to the official WireGuard
 * `Config.parse`, then brings it up through the Go backend. We never re-serialise the
 * config ourselves - a lossy round-trip is how split-tunnel leaks get introduced.
 */
class AndroidTunnelController(
    private val context: Context,
    private val ipResolver: PublicIpResolver,
) : TunnelController {

    private val backend: Backend by lazy { GoBackend(context) }

    private val _state = MutableStateFlow(TunnelState())
    override val state: StateFlow<TunnelState> = _state.asStateFlow()

    private var activeConfig: WireGuardConfig? = null
    private var permissionRequest: (suspend (Intent) -> Boolean)? = null

    private val tunnel = object : Tunnel {
        override fun getName() = "softizence"
        override fun onStateChange(newState: Tunnel.State) {
            _state.value = _state.value.copy(
                status = when (newState) {
                    Tunnel.State.UP -> TunnelStatus.Connected.name
                    Tunnel.State.DOWN -> TunnelStatus.Off.name
                    else -> TunnelStatus.Connecting.name
                },
            )
        }
    }

    /** Wired from MainActivity so the controller can show the system VPN consent dialog. */
    fun attachPermissionLauncher(launcher: suspend (Intent) -> Boolean) {
        permissionRequest = launcher
        activeInstance = this
    }

    override suspend fun ensurePermission(): Boolean {
        val intent = VpnService.prepare(context) ?: return true   // already granted
        return permissionRequest?.invoke(intent) ?: false
    }

    override suspend fun connect(config: WireGuardConfig, policy: TunnelPolicy) = withContext(Dispatchers.IO) {
        _state.value = tunnelState(TunnelStatus.Connecting, config)
        runCatching {
            // Guard rail: refuse anything that is not a full tunnel.
            if (policy.killSwitch && !config.isFullTunnel) {
                error("Config does not route 0.0.0.0/0 — refusing to connect with the kill switch on.")
            }
            val parsed = Config.parse(ByteArrayInputStream(config.rawText.toByteArray()))
            backend.setState(tunnel, Tunnel.State.UP, parsed)
            activeConfig = config
        }.onSuccess {
            // Resolve the public IP *after* the tunnel is up: it is the proof of routing.
            val ip = ipResolver.resolve()
            _state.value = tunnelState(TunnelStatus.Connected, config, publicIp = ip)
        }.onFailure { error ->
            activeConfig = null
            _state.value = tunnelState(TunnelStatus.Error, config, error = error.message)
        }
        Unit
    }

    override suspend fun disconnect() = withContext(Dispatchers.IO) {
        runCatching { backend.setState(tunnel, Tunnel.State.DOWN, null) }
        activeConfig = null
        _state.value = TunnelState()
        context.stopService(Intent(context, SoftizenceVpnService::class.java))
    }

    override suspend fun refreshStatistics() = withContext(Dispatchers.IO) {
        val config = activeConfig ?: return@withContext
        runCatching {
            val stats = backend.getStatistics(tunnel)
            _state.value = _state.value.copy(
                rxBytes = stats.totalRx(),
                txBytes = stats.totalTx(),
                publicIp = ipResolver.current.value ?: _state.value.publicIp,
                country = config.country,
            )
        }
        Unit
    }

    /** Called when the OS revokes the VPN: never silently fall back to the clear path. */
    fun onRevokedBySystem() {
        _state.value = tunnelState(
            TunnelStatus.Error,
            activeConfig,
            error = "VPN permission was revoked by the system — traffic is blocked.",
        )
        activeConfig = null
    }

    companion object {
        @Volatile
        var activeInstance: AndroidTunnelController? = null
            internal set
    }
}
