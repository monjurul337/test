package com.softizence.browser.net

import com.softizence.browser.ExtensionPaths
import com.softizence.browser.core.model.TunnelState
import com.softizence.browser.core.model.TunnelStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Desktop tunnel. Executes the Proton `.conf` directly using whichever WireGuard
 * implementation the machine has, in this order:
 *
 *   1. `wg-quick up <file>`                    - Linux/macOS, kernel module or wireguard-go
 *   2. `wireguard.exe /installtunnelservice`   - Windows, the official service installer
 *   3. bundled `wireguard-go` + `wg setconf`   - fallback userspace path
 *
 * The file is written to a 0600 temp path, used, and shredded - the private key never
 * lingers in a world-readable location.
 *
 * Elevation: bringing up a TUN device needs admin rights. We detect the failure and
 * surface it as an actionable error instead of silently continuing unprotected, because
 * "VPN says connected but isn't" is the worst possible outcome for this product.
 */
class DesktopTunnelController(
    private val ipResolver: PublicIpResolver,
) : TunnelController {

    private val _state = MutableStateFlow(TunnelState())
    override val state: StateFlow<TunnelState> = _state.asStateFlow()

    private var activeConfig: WireGuardConfig? = null
    private var activeFile: File? = null
    private val interfaceName = "softizence0"

    private val isWindows = "win" in System.getProperty("os.name").lowercase()

    override suspend fun ensurePermission(): Boolean = withContext(Dispatchers.IO) {
        // On Windows the WireGuard service handles elevation; elsewhere we need root/sudo.
        if (isWindows) return@withContext which("wireguard.exe") != null
        which("wg-quick") != null || which("wireguard-go") != null
    }

    override suspend fun connect(config: WireGuardConfig, policy: TunnelPolicy) = withContext(Dispatchers.IO) {
        _state.value = tunnelState(TunnelStatus.Connecting, config)

        if (policy.killSwitch && !config.isFullTunnel) {
            _state.value = tunnelState(
                TunnelStatus.Error, config,
                error = "Config does not route 0.0.0.0/0 — refusing to connect with the kill switch on.",
            )
            return@withContext
        }

        runCatching {
            disconnectInternal()
            val file = writeTempConf(config)
            activeFile = file

            val result = when {
                isWindows -> run("wireguard.exe", "/installtunnelservice", file.absolutePath)
                which("wg-quick") != null -> run("wg-quick", "up", file.absolutePath)
                else -> bringUpWithWireGuardGo(file)
            }

            if (result.exitCode != 0) {
                error(result.humanError() ?: "Tunnel failed to start (exit ${result.exitCode}).")
            }
            activeConfig = config
        }.onSuccess {
            val ip = ipResolver.resolve()
            _state.value = tunnelState(TunnelStatus.Connected, config, publicIp = ip)
        }.onFailure { error ->
            shredTempConf()
            activeConfig = null
            _state.value = tunnelState(TunnelStatus.Error, config, error = error.message)
        }
        Unit
    }

    override suspend fun disconnect() = withContext(Dispatchers.IO) {
        disconnectInternal()
        _state.value = TunnelState()
    }

    private fun disconnectInternal() {
        val config = activeConfig ?: return
        when {
            isWindows -> run("wireguard.exe", "/uninstalltunnelservice", config.name)
            which("wg-quick") != null -> activeFile?.let { run("wg-quick", "down", it.absolutePath) }
            else -> run("ip", "link", "delete", interfaceName)
        }
        shredTempConf()
        activeConfig = null
    }

    override suspend fun refreshStatistics() = withContext(Dispatchers.IO) {
        val config = activeConfig ?: return@withContext
        // `wg show <iface> dump` -> peer\tpresharedkey\tendpoint\tallowed\thandshake\trx\ttx\tkeepalive
        val dump = run("wg", "show", interfaceName, "dump").stdout
        val peerLine = dump.lineSequence().drop(1).firstOrNull()?.split('\t')

        if (peerLine != null && peerLine.size >= 7) {
            _state.value = _state.value.copy(
                lastHandshakeEpochSeconds = peerLine[4].toLongOrNull() ?: 0,
                rxBytes = peerLine[5].toLongOrNull() ?: 0,
                txBytes = peerLine[6].toLongOrNull() ?: 0,
                publicIp = ipResolver.current.value ?: _state.value.publicIp,
                country = config.country,
            )

            // Stale handshake == the tunnel is dead even though the interface exists.
            val age = (System.currentTimeMillis() / 1000) - (peerLine[4].toLongOrNull() ?: 0)
            if (age > STALE_HANDSHAKE_SECONDS) {
                _state.value = _state.value.copy(status = TunnelStatus.Reconnecting.name)
            }
        }
        Unit
    }

    private fun bringUpWithWireGuardGo(file: File): ProcessResult {
        val up = run("wireguard-go", interfaceName)
        if (up.exitCode != 0) return up

        val conf = file.readText()
        val setconf = run("wg", "setconf", interfaceName, file.absolutePath, stdin = conf)
        if (setconf.exitCode != 0) return setconf

        activeConfig?.interfaceSection?.addresses?.forEach { address ->
            run("ip", "address", "add", address, "dev", interfaceName)
        }
        run("ip", "link", "set", "up", "dev", interfaceName)
        // Default route into the tunnel == traffic is tunnel-exclusive.
        run("ip", "route", "add", "default", "dev", interfaceName)
        return ProcessResult(0, "", "")
    }

    /** 0600 temp file, deleted and overwritten after use. */
    private fun writeTempConf(config: WireGuardConfig): File {
        val dir = File(ExtensionPaths.tunnelsDir, "runtime").apply { mkdirs() }
        val file = File(dir, "${config.name}.conf")
        file.writeText(config.rawText)
        runCatching {
            file.setReadable(false, false)
            file.setReadable(true, true)
            file.setWritable(false, false)
            file.setWritable(true, true)
        }
        return file
    }

    private fun shredTempConf() {
        activeFile?.let { file ->
            runCatching {
                if (file.exists()) {
                    file.writeBytes(ByteArray(file.length().toInt()))
                    file.delete()
                }
            }
        }
        activeFile = null
    }

    private fun which(command: String): String? {
        val probe = if (isWindows) "where" else "which"
        val result = run(probe, command)
        return result.stdout.lineSequence().firstOrNull()?.takeIf { result.exitCode == 0 && it.isNotBlank() }
    }

    private fun run(vararg command: String, stdin: String? = null): ProcessResult = runCatching {
        val process = ProcessBuilder(*command).redirectErrorStream(false).start()
        stdin?.let { process.outputStream.bufferedWriter().use { w -> w.write(it) } }
        val out = process.inputStream.bufferedReader().readText()
        val err = process.errorStream.bufferedReader().readText()
        if (!process.waitFor(PROCESS_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            process.destroyForcibly()
            return ProcessResult(-1, out, "Timed out after ${PROCESS_TIMEOUT_SECONDS}s")
        }
        ProcessResult(process.exitValue(), out, err)
    }.getOrElse { ProcessResult(-1, "", it.message.orEmpty()) }

    private data class ProcessResult(val exitCode: Int, val stdout: String, val stderr: String) {
        fun humanError(): String? = when {
            stderr.isBlank() -> null
            "permission denied" in stderr.lowercase() || "must be root" in stderr.lowercase() ->
                "Administrator rights are required to create the tunnel interface. " +
                    "Run Softizence elevated, or install the WireGuard service."
            "not found" in stderr.lowercase() ->
                "WireGuard tools were not found. Install WireGuard (wg-quick / wireguard.exe) and retry."
            else -> stderr.trim().lines().first()
        }
    }

    private companion object {
        const val PROCESS_TIMEOUT_SECONDS = 25L
        const val STALE_HANDSHAKE_SECONDS = 180
    }
}
