package com.softizence.browser.extensions

import com.softizence.browser.core.model.ExtensionInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import java.io.File

/**
 * Full MV3 hosting on Chromium.
 *
 * We do not reimplement the extension runtime - that would be both enormous and wrong.
 * Instead we validate each unpacked folder, then hand Chromium a `--load-extension`
 * switch listing every enabled one, so service workers, `chrome.*` APIs,
 * declarativeNetRequest and popups all run natively.
 *
 * Because the switch is read at CEF start-up, enabling/disabling an extension schedules
 * a restart of the CEF host rather than pretending it took effect immediately.
 */
class DesktopExtensionHost(
    private val rootDir: String,
    private val extraSearchPaths: List<String> = emptyList(),
) : ExtensionHost {

    private val _extensions = MutableStateFlow<List<ExtensionInfo>>(emptyList())
    override val extensions: StateFlow<List<ExtensionInfo>> = _extensions.asStateFlow()

    override val capabilities = ExtensionCapabilities.FullChromium

    private val _restartRequired = MutableStateFlow(false)
    val restartRequired: StateFlow<Boolean> = _restartRequired.asStateFlow()

    private val manifests = mutableMapOf<String, Mv3Manifest>()

    override suspend fun refresh() = withContext(Dispatchers.IO) {
        val roots = (listOf(rootDir) + extraSearchPaths).map(::File)
        roots.forEach { if (!it.exists()) it.mkdirs() }

        _extensions.value = roots
            .flatMap { it.listFiles { f: File -> f.isDirectory }.orEmpty().toList() }
            .mapNotNull { dir -> inspect(dir).getOrNull() }
            .distinctBy { it.id }
            .sortedBy { it.name.lowercase() }
    }

    override suspend fun load(folderPath: String): Result<ExtensionInfo> = withContext(Dispatchers.IO) {
        val source = File(folderPath)
        inspect(source).mapCatching { info ->
            // Copy into the managed dir so the extension survives the source folder moving.
            val target = File(rootDir, info.id)
            if (source.absolutePath != target.absolutePath) {
                target.deleteRecursively()
                source.copyRecursively(target, overwrite = true)
            }
            val managed = info.copy(installPath = target.absolutePath)
            _extensions.value = _extensions.value.filterNot { it.id == managed.id } + managed
            _restartRequired.value = true
            managed
        }
    }

    private fun inspect(dir: File): Result<ExtensionInfo> = runCatching {
        val manifestFile = File(dir, "manifest.json")
        require(manifestFile.exists()) { "No manifest.json in ${dir.name}" }

        val manifest = ManifestReader.read(manifestFile.readText()).getOrThrow()
        val id = dir.name
        manifests[id] = manifest

        // Resolve __MSG_*__ placeholders so the UI shows the real name.
        val messages = File(dir, "_locales/en/messages.json").takeIf { it.exists() }
            ?.let { ManifestReader.messagesOf(it.readText()) }

        ExtensionInfo(
            id = id,
            name = ManifestReader.localize(manifest.name, messages),
            version = manifest.version,
            manifestVersion = manifest.manifestVersion,
            description = ManifestReader.localize(manifest.description, messages),
            installPath = dir.absolutePath,
            permissions = manifest.permissions,
            hostPermissions = manifest.hostPermissions,
            hasServiceWorker = manifest.background?.serviceWorker != null,
            hasPopup = manifest.action?.defaultPopup != null,
            iconPath = manifest.bestIcon()?.let { File(dir, it).absolutePath },
        )
    }

    override suspend fun setEnabled(extensionId: String, enabled: Boolean) {
        _extensions.value = _extensions.value.map {
            if (it.id == extensionId) it.copy(enabled = enabled) else it
        }
        _restartRequired.value = true
    }

    override suspend fun remove(extensionId: String) = withContext(Dispatchers.IO) {
        _extensions.value.firstOrNull { it.id == extensionId }?.let { File(it.installPath).deleteRecursively() }
        manifests.remove(extensionId)
        _restartRequired.value = true
        refresh()
    }

    /**
     * Chromium handles content-script matching itself, so this is only used for
     * diagnostics and for the "what will run on this page" UI.
     */
    override suspend fun contentScriptsFor(url: String, runAt: String): List<InjectedScript> =
        _extensions.value.filter { it.enabled }.flatMap { ext ->
            manifests[ext.id]?.contentScripts
                ?.filter { it.runAt == runAt && it.matches.anyMatches(url) && !it.excludeMatches.anyMatches(url) }
                ?.map { InjectedScript(ext.id, it.js.joinToString(", "), it.allFrames) }
                .orEmpty()
        }

    /** Chromium's own DNR engine does the real blocking; this is the UI-side preview. */
    override suspend fun isBlocked(url: String): Boolean = false

    /** The `--load-extension=` switch (plus the flag that permits unpacked loading). */
    fun loadExtensionSwitch(): List<String> {
        val enabled = _extensions.value.filter { it.enabled && it.loadError == null }
        if (enabled.isEmpty()) return emptyList()
        return listOf(
            "--load-extension=" + enabled.joinToString(File.pathSeparator) { it.installPath },
            "--disable-extensions-except=" + enabled.joinToString(File.pathSeparator) { it.installPath },
            "--allow-legacy-extension-manifests",
        )
    }

    /** Called after the UI restarts CEF so the badge clears. */
    fun acknowledgeRestart() { _restartRequired.value = false }
}
