package com.softizence.browser.net

import com.softizence.browser.core.model.TunnelStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Shared orchestration layer sitting on top of the platform [TunnelController].
 *
 * Owns the config library, the "exclusively tunnelled" rule and the direct-connection
 * fallback, so both platforms behave identically:
 *
 *   configs.isEmpty()            -> DIRECT  (browsing allowed, badge says "Direct")
 *   configs present, none active -> DIRECT  (user chose not to connect)
 *   config active & up           -> TUNNEL  (all traffic through wg, public IP shown)
 *   config active & down + KS on -> BLOCKED (browsing paused, no leak)
 */
class TunnelManager(
    private val controller: TunnelController,
    private val store: WireGuardConfigStore,
    private val ipResolver: PublicIpResolver,
    private val scope: CoroutineScope,
) {
    private val _configs = MutableStateFlow<List<WireGuardConfig>>(emptyList())
    val configs: StateFlow<List<WireGuardConfig>> = _configs.asStateFlow()

    private val _policy = MutableStateFlow(TunnelPolicy())
    val policy: StateFlow<TunnelPolicy> = _policy.asStateFlow()

    private val _importErrors = MutableStateFlow<List<String>>(emptyList())
    val importErrors: StateFlow<List<String>> = _importErrors.asStateFlow()

    val state: StateFlow<com.softizence.browser.core.model.TunnelState> get() = controller.state

    /** The single source of truth the browser layer consults before issuing a request. */
    val networkMode: StateFlow<NetworkMode> =
        combine(controller.state, _configs, _policy) { st, cfgs, pol ->
            when {
                st.statusEnum == TunnelStatus.Connected -> NetworkMode.Tunnelled
                cfgs.isEmpty() -> NetworkMode.Direct
                st.activeConfigId == null -> NetworkMode.Direct
                pol.killSwitch -> NetworkMode.Blocked
                else -> NetworkMode.Direct
            }
        }.stateInEagerly(scope, NetworkMode.Direct)

    suspend fun loadLibrary() {
        val (ok, failed) = store.loadAll()
        _configs.value = ok
        _importErrors.value = failed
    }

    /** Import one or many `.conf` files that the user dropped in / picked. */
    suspend fun import(files: List<ImportedFile>): ImportReport {
        val added = mutableListOf<WireGuardConfig>()
        val errors = mutableListOf<String>()
        files.forEach { file ->
            WireGuardConfigParser.parseOrNull(file.name, file.text)
                .onSuccess { cfg ->
                    if (!cfg.isFullTunnel) {
                        errors += "${file.name}: AllowedIPs is not 0.0.0.0/0 - this would leak traffic outside the tunnel."
                        return@onSuccess
                    }
                    store.save(cfg)
                    added += cfg
                }
                .onFailure { errors += "${file.name}: ${it.message}" }
        }
        if (added.isNotEmpty()) loadLibrary()
        _importErrors.value = errors
        return ImportReport(added.map { it.name }, errors)
    }

    suspend fun remove(configId: String) {
        if (controller.state.value.activeConfigId == configId) controller.disconnect()
        store.delete(configId)
        loadLibrary()
    }

    suspend fun activate(configId: String) {
        val cfg = _configs.value.firstOrNull { it.id == configId } ?: return
        if (!controller.ensurePermission()) return
        controller.connect(cfg, _policy.value)
        scope.launch { watch() }
    }

    suspend fun deactivate() = controller.disconnect()

    fun updatePolicy(block: (TunnelPolicy) -> TunnelPolicy) {
        _policy.value = block(_policy.value)
    }

    /** Polls handshake + public IP so the UI can prove where traffic is actually exiting. */
    private suspend fun watch() {
        while (scope.isActive && controller.state.value.statusEnum != TunnelStatus.Off) {
            controller.refreshStatistics()
            ipResolver.resolve()
            delay(POLL_MS)
        }
    }

    private companion object { const val POLL_MS = 5_000L }
}

enum class NetworkMode {
    /** No configs, or user opted out - requests go out on the physical interface. */
    Direct,
    /** Everything is exiting through WireGuard. */
    Tunnelled,
    /** Kill switch engaged: the tunnel is expected but down. Nothing may be sent. */
    Blocked,
}

data class ImportedFile(val name: String, val text: String)
data class ImportReport(val imported: List<String>, val errors: List<String>)

/** Persistence for the `.conf` library (encrypted at rest on both platforms). */
interface WireGuardConfigStore {
    suspend fun loadAll(): Pair<List<WireGuardConfig>, List<String>>
    suspend fun save(config: WireGuardConfig)
    suspend fun delete(configId: String)
}

/** Reports the public IP as seen *from inside the current network path*. */
interface PublicIpResolver {
    val current: StateFlow<String?>
    suspend fun resolve(): String?
}

// Small helper so the file doesn't depend on kotlinx-coroutines' experimental stateIn overloads.
private fun <T> kotlinx.coroutines.flow.Flow<T>.stateInEagerly(
    scope: CoroutineScope,
    initial: T,
): StateFlow<T> {
    val flow = MutableStateFlow(initial)
    scope.launch { collect { flow.value = it } }
    return flow.asStateFlow()
}
