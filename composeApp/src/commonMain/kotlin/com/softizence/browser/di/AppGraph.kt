package com.softizence.browser.di

import com.softizence.browser.browser.BrowserEngine
import com.softizence.browser.ExtensionPaths
import com.softizence.browser.createBrowserEngine
import com.softizence.browser.core.config.ConfigStore
import com.softizence.browser.extensions.ExtensionHost
import com.softizence.browser.net.FileWireGuardConfigStore
import com.softizence.browser.net.KtorPublicIpResolver
import com.softizence.browser.net.PublicIpResolver
import com.softizence.browser.net.TunnelController
import com.softizence.browser.net.TunnelManager
import com.softizence.browser.privacy.PrivacyPolicyEngine
import com.softizence.browser.session.SessionVault
import com.softizence.browser.session.createSessionVault
import com.softizence.browser.ui.BrowserViewModel
import io.ktor.client.HttpClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import okio.FileSystem

/**
 * Hand-rolled composition root. No DI framework: the object graph is small, explicit and
 * identical on both platforms, which makes the platform differences easy to audit.
 */
class AppGraph internal constructor(
    val scope: CoroutineScope,
    val fileSystem: FileSystem,
    val httpClient: HttpClient,
    val engine: BrowserEngine,
    val vault: SessionVault,
    val extensionHost: ExtensionHost,
    val tunnelController: TunnelController,
    val ipResolver: PublicIpResolver,
    val configStore: ConfigStore,
    val privacy: PrivacyPolicyEngine,
    val tunnels: TunnelManager,
    val viewModel: BrowserViewModel,
) {
    /** Set by the platform host so the UI can open a native file picker. */
    var onPickConfigs: (() -> Unit)?
        get() = viewModel.onPickConfigs
        set(value) { viewModel.onPickConfigs = value }

    /** Set by the platform host so the UI can open a native folder picker. */
    var onPickExtensionFolder: (() -> Unit)?
        get() = viewModel.onPickExtensionFolder
        set(value) { viewModel.onPickExtensionFolder = value }

    fun shutdown() {
        engine.dispose()
        httpClient.close()
    }

    companion object {
        fun create(): AppGraph {
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            val fs = platformFileSystem()
            val http = createHttpClient()

            val engine = createBrowserEngine()
            val vault = createSessionVault()
            val privacy = PrivacyPolicyEngine()
            val configStore = ConfigStore(fs, ExtensionPaths.configDir)
            val ipResolver = KtorPublicIpResolver(http)
            val controller = createTunnelController(ipResolver)
            val extensionHost = createExtensionHost()

            val tunnelStore = FileWireGuardConfigStore(
                fileSystem = fs,
                directory = ExtensionPaths.tunnelsDir,
                keyProvider = {
                    // Key is generated once and sealed by the platform vault.
                    vault.getSecret(TUNNEL_KEY)?.encodeToByteArray()
                        ?: randomKey().also { vault.putSecret(TUNNEL_KEY, it.decodeToString()) }
                },
            )

            val tunnels = TunnelManager(controller, tunnelStore, ipResolver, scope)

            val viewModel = BrowserViewModel(
                engine = engine,
                tunnels = tunnels,
                extensions = extensionHost,
                configStore = configStore,
                vault = vault,
                privacy = privacy,
                scope = scope,
            )

            return AppGraph(
                scope, fs, http, engine, vault, extensionHost, controller,
                ipResolver, configStore, privacy, tunnels, viewModel,
            )
        }

        private const val TUNNEL_KEY = "tunnel.store.key"

        private fun randomKey(): ByteArray {
            val alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            val random = kotlin.random.Random.Default
            return ByteArray(48) { alphabet[random.nextInt(alphabet.length)].code.toByte() }
        }
    }
}

expect fun platformFileSystem(): FileSystem
expect fun createHttpClient(): HttpClient
expect fun createTunnelController(ipResolver: PublicIpResolver): TunnelController
expect fun createExtensionHost(): ExtensionHost
