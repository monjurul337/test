package com.softizence.browser.ui

import com.softizence.browser.browser.BrowserEngine
import com.softizence.browser.core.config.AppConfig
import com.softizence.browser.core.config.ConfigStore
import com.softizence.browser.core.model.FingerprintProfile
import com.softizence.browser.core.model.TabState
import com.softizence.browser.extensions.ExtensionHost
import com.softizence.browser.net.ImportedFile
import com.softizence.browser.net.NetworkMode
import com.softizence.browser.net.TunnelManager
import com.softizence.browser.privacy.PrivacyPolicyEngine
import com.softizence.browser.session.SessionVault
import com.softizence.browser.session.WorkspaceSnapshot
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class SidePanel { None, Tunnels, Extensions, Settings }

/**
 * Single place where browsing, privacy, extensions and the tunnel meet.
 *
 * Key invariant: **navigation is gated on [NetworkMode]**. When the kill switch is armed
 * and the tunnel is down we refuse to navigate instead of quietly falling back to the
 * physical interface - that fallback is what leaks a user's real IP in most VPN browsers.
 */
class BrowserViewModel(
    val engine: BrowserEngine,
    val tunnels: TunnelManager,
    val extensions: ExtensionHost,
    private val configStore: ConfigStore,
    private val vault: SessionVault,
    private val privacy: PrivacyPolicyEngine,
    private val scope: CoroutineScope,
) {
    val config: StateFlow<AppConfig> = configStore.config
    val tabs: StateFlow<List<TabState>> get() = engine.tabs
    val activeTabId: StateFlow<String?> get() = engine.activeTabId
    val networkMode: StateFlow<NetworkMode> get() = tunnels.networkMode
    val tunnelState get() = tunnels.state

    private val _panel = MutableStateFlow(SidePanel.None)
    val panel: StateFlow<SidePanel> = _panel.asStateFlow()

    /** Native file/folder pickers supplied by the platform host (Activity / Window). */
    var onPickConfigs: (() -> Unit)? = null
    var onPickExtensionFolder: (() -> Unit)? = null

    private val _notice = MutableStateFlow<String?>(null)
    val notice: StateFlow<String?> = _notice.asStateFlow()

    fun start() = scope.launch {
        val cfg = configStore.load()
        privacy.settings = cfg.privacy
        applyFingerprint(cfg.profiles.first().fingerprintSeed)

        engine.initialize(privacy)
        if (cfg.extensions.enabled) extensions.refresh()
        tunnels.loadLibrary()
        tunnels.updatePolicy { cfg.tunnel.toPolicy() }

        cfg.tunnel.autoConnectConfigId?.let { tunnels.activate(it) }

        val restored = vault.loadWorkspace()
        if (restored != null && restored.tabs.isNotEmpty()) {
            restored.tabs.forEach { engine.openTab(it.url, it.profileId, it.isIncognito) }
        } else {
            engine.openTab("softizence://home")
        }
    }

    // ---------------------------------------------------------------- navigation

    fun navigate(input: String, tabId: String? = activeTabId.value) {
        val target = tabId ?: engine.openTab()
        val url = privacy.rewrite(input)

        when (networkMode.value) {
            NetworkMode.Blocked -> {
                _notice.value = "Blocked: the kill switch is on and the tunnel is down. " +
                    "Reconnect a tunnel, or turn the kill switch off in Tunnels."
                _panel.value = SidePanel.Tunnels
                return
            }
            NetworkMode.Direct, NetworkMode.Tunnelled -> Unit
        }

        if (privacy.shouldBlock(url)) {
            _notice.value = "Tracker request blocked."
            return
        }
        scope.launch {
            if (extensions.isBlocked(url)) {
                _notice.value = "Blocked by an extension rule."
                return@launch
            }
            engine.navigate(target, url)
        }
    }

    fun searchUrl(query: String): String = config.value.search.resolve(query)

    fun newTab(incognito: Boolean = false) {
        engine.openTab(incognito = incognito, profileId = if (incognito) "incognito" else "default")
    }

    fun closeTab(id: String) = engine.closeTab(id)
    fun selectTab(id: String) = engine.selectTab(id)
    fun back() = activeTabId.value?.let(engine::goBack)
    fun forward() = activeTabId.value?.let(engine::goForward)
    fun reload() = activeTabId.value?.let { engine.reload(it) }

    // ---------------------------------------------------------------- tunnel

    fun importConfigs(files: List<ImportedFile>) = scope.launch {
        val report = tunnels.import(files)
        _notice.value = when {
            report.errors.isNotEmpty() -> report.errors.first()
            report.imported.isNotEmpty() -> "Imported ${report.imported.size} tunnel(s)."
            else -> null
        }
    }

    fun activateTunnel(id: String) = scope.launch {
        tunnels.activate(id)
        // Keep the spoofed timezone consistent with the new exit country.
        if (config.value.privacy.spoofTimezoneFromExit) {
            tunnels.configs.value.firstOrNull { it.id == id }?.country?.let { applyTimezoneFor(it) }
        }
    }

    fun deactivateTunnel() = scope.launch { tunnels.deactivate() }

    fun removeTunnel(id: String) = scope.launch { tunnels.remove(id) }

    fun setKillSwitch(enabled: Boolean) {
        tunnels.updatePolicy { it.copy(killSwitch = enabled) }
        configStore.update { it.copy(tunnel = it.tunnel.copy(killSwitch = enabled)) }
    }

    // ---------------------------------------------------------------- extensions

    fun loadExtension(folder: String) = scope.launch {
        extensions.load(folder)
            .onSuccess { _notice.value = "Loaded ${it.name} ${it.version}." }
            .onFailure { _notice.value = "Could not load extension: ${it.message}" }
    }

    fun toggleExtension(id: String, enabled: Boolean) = scope.launch {
        extensions.setEnabled(id, enabled)
    }

    // ---------------------------------------------------------------- settings

    fun updatePrivacy(block: (com.softizence.browser.privacy.PrivacySettings) -> com.softizence.browser.privacy.PrivacySettings) {
        configStore.update { cfg -> cfg.copy(privacy = block(cfg.privacy)).also { privacy.settings = it.privacy } }
    }

    fun updateAppearance(block: (AppConfig.Appearance) -> AppConfig.Appearance) {
        configStore.update { it.copy(appearance = block(it.appearance)) }
    }

    fun openPanel(panel: SidePanel) {
        _panel.value = if (_panel.value == panel) SidePanel.None else panel
    }

    fun dismissNotice() { _notice.value = null }

    fun persist() = scope.launch {
        engine.persistSession()
        vault.saveWorkspace(
            WorkspaceSnapshot(
                tabs = tabs.value.filterNot { it.isIncognito },
                activeTabId = activeTabId.value,
                activeTunnelId = tunnelState.value.activeConfigId,
            ),
        )
        configStore.save()
    }

    private fun applyFingerprint(seed: Long) {
        privacy.fingerprint = FingerprintProfile.forSeed(seed, timezone = privacy.fingerprint.timezone)
    }

    private fun applyTimezoneFor(countryCode: String) {
        val tz = countryTimezones[countryCode.uppercase()] ?: return
        privacy.fingerprint = privacy.fingerprint.copy(timezone = tz)
    }

    private companion object {
        /** Minimal map; a tunnel in CH that reports Asia/Dhaka is a dead giveaway. */
        val countryTimezones = mapOf(
            "US" to "America/New_York", "CA" to "America/Toronto", "GB" to "Europe/London",
            "DE" to "Europe/Berlin", "FR" to "Europe/Paris", "NL" to "Europe/Amsterdam",
            "CH" to "Europe/Zurich", "SE" to "Europe/Stockholm", "ES" to "Europe/Madrid",
            "IT" to "Europe/Rome", "JP" to "Asia/Tokyo", "SG" to "Asia/Singapore",
            "IN" to "Asia/Kolkata", "AU" to "Australia/Sydney", "BR" to "America/Sao_Paulo",
            "IS" to "Atlantic/Reykjavik", "NO" to "Europe/Oslo", "PL" to "Europe/Warsaw",
        )
    }
}
