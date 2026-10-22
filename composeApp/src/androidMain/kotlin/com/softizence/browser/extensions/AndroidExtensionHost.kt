package com.softizence.browser.extensions

import com.softizence.browser.core.model.ExtensionInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.io.File

/**
 * MV3 *subset* host for WebView.
 *
 * WebView has no extension runtime, so we compile each manifest down to the two things
 * WebView can actually do: inject content scripts at document start/idle, and block
 * requests via `shouldInterceptRequest`. Anything else (service workers, chrome.* APIs,
 * popups) is reported as unsupported instead of silently ignored.
 */
class AndroidExtensionHost(private val rootDir: String) : ExtensionHost {

    private val _extensions = MutableStateFlow<List<ExtensionInfo>>(emptyList())
    override val extensions: StateFlow<List<ExtensionInfo>> = _extensions.asStateFlow()

    override val capabilities = ExtensionCapabilities.WebViewSubset

    private val manifests = mutableMapOf<String, Mv3Manifest>()
    private val blockPatterns = mutableMapOf<String, List<String>>()

    override suspend fun refresh() = withContext(Dispatchers.IO) {
        val root = File(rootDir)
        if (!root.exists()) root.mkdirs()
        val found = root.listFiles { f: File -> f.isDirectory }.orEmpty()
            .mapNotNull { dir -> loadFolderBlocking(dir).getOrNull() }
        _extensions.value = found
    }

    override suspend fun load(folderPath: String): Result<ExtensionInfo> = withContext(Dispatchers.IO) {
        loadFolderBlocking(File(folderPath)).onSuccess { info ->
            _extensions.value = _extensions.value.filterNot { it.id == info.id } + info
        }
    }

    private fun loadFolderBlocking(dir: File): Result<ExtensionInfo> = runCatching {
        val manifestFile = File(dir, "manifest.json")
        require(manifestFile.exists()) { "No manifest.json in ${dir.name}" }

        val manifest = ManifestReader.read(manifestFile.readText()).getOrThrow()
        val id = dir.name
        manifests[id] = manifest

        blockPatterns[id] = manifest.declarativeNetRequest
            ?.ruleResources
            ?.filter { it.enabled }
            ?.flatMap { res -> DnrRules.urlFiltersOf(File(dir, res.path)) }
            .orEmpty()

        val unsupported = buildList {
            if (manifest.background?.serviceWorker != null) add("background service worker")
            if (manifest.action?.defaultPopup != null) add("action popup")
            if (manifest.permissions.any { it in CHROME_API_PERMISSIONS }) add("chrome.* APIs")
        }

        ExtensionInfo(
            id = id,
            name = manifest.name,
            version = manifest.version,
            manifestVersion = manifest.manifestVersion,
            description = manifest.description,
            installPath = dir.absolutePath,
            permissions = manifest.permissions,
            hostPermissions = manifest.hostPermissions,
            hasServiceWorker = manifest.background?.serviceWorker != null,
            hasPopup = manifest.action?.defaultPopup != null,
            iconPath = manifest.bestIcon()?.let { File(dir, it).absolutePath },
            loadError = unsupported.takeIf { it.isNotEmpty() }
                ?.joinToString(prefix = "Partially loaded — unsupported on Android: ", separator = ", "),
        )
    }

    override suspend fun setEnabled(extensionId: String, enabled: Boolean) {
        _extensions.value = _extensions.value.map {
            if (it.id == extensionId) it.copy(enabled = enabled) else it
        }
    }

    override suspend fun remove(extensionId: String) = withContext(Dispatchers.IO) {
        _extensions.value.firstOrNull { it.id == extensionId }?.let { File(it.installPath).deleteRecursively() }
        manifests.remove(extensionId)
        blockPatterns.remove(extensionId)
        refresh()
    }

    override suspend fun contentScriptsFor(url: String, runAt: String): List<InjectedScript> =
        withContext(Dispatchers.IO) {
            _extensions.value.filter { it.enabled }.flatMap { ext ->
                val manifest = manifests[ext.id] ?: return@flatMap emptyList()
                manifest.contentScripts
                    .filter { it.runAt == runAt }
                    .filter { it.matches.anyMatches(url) && !it.excludeMatches.anyMatches(url) }
                    .map { script ->
                        InjectedScript(
                            extensionId = ext.id,
                            source = script.js.joinToString("\n") { js ->
                                runCatching { File(ext.installPath, js).readText() }.getOrDefault("")
                            },
                            allFrames = script.allFrames,
                        )
                    }
            }
        }

    override suspend fun isBlocked(url: String): Boolean =
        _extensions.value.filter { it.enabled }.any { ext ->
            blockPatterns[ext.id]?.any { pattern -> DnrRules.matches(pattern, url) } == true
        }

    private companion object {
        val CHROME_API_PERMISSIONS = setOf(
            "tabs", "storage", "scripting", "webRequest", "alarms", "cookies", "history", "bookmarks",
        )
    }
}

/** JVM convenience: read a ruleset file straight off disk. */
internal fun DnrRules.urlFiltersOf(file: java.io.File): List<String> =
    runCatching { urlFiltersOf(file.readText()) }.getOrDefault(emptyList())
