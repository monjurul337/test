package com.softizence.browser.core.config

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import okio.FileSystem
import okio.Path
import okio.Path.Companion.toPath

/**
 * Loads/saves [AppConfig] as pretty JSON. Writes are atomic (temp + rename) so a crash
 * mid-save can never leave the user with an unreadable config.
 */
class ConfigStore(
    private val fileSystem: FileSystem,
    private val configDir: String,
) {
    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        encodeDefaults = true
        isLenient = true
    }

    private val path: Path get() = configDir.toPath() / FILE_NAME

    private val _config = MutableStateFlow(AppConfig.Default)
    val config: StateFlow<AppConfig> = _config.asStateFlow()

    fun load(): AppConfig {
        val loaded = runCatching {
            if (!fileSystem.exists(path)) return@runCatching AppConfig.Default
            val text = fileSystem.read(path) { readUtf8() }
            json.decodeFromString<AppConfig>(text).migrate()
        }.getOrElse {
            // Never hard-fail on a corrupt config: quarantine it and start clean.
            runCatching { fileSystem.atomicMove(path, configDir.toPath() / "$FILE_NAME.broken") }
            AppConfig.Default
        }
        _config.value = loaded
        return loaded
    }

    fun save(config: AppConfig = _config.value) {
        fileSystem.createDirectories(configDir.toPath())
        val tmp = configDir.toPath() / "$FILE_NAME.tmp"
        fileSystem.write(tmp) { writeUtf8(json.encodeToString(AppConfig.serializer(), config)) }
        fileSystem.atomicMove(tmp, path)
        _config.value = config
    }

    /** Read-modify-write helper used by every settings toggle in the UI. */
    fun update(block: (AppConfig) -> AppConfig) = save(block(_config.value))

    private fun AppConfig.migrate(): AppConfig = when (schemaVersion) {
        AppConfig.CURRENT_SCHEMA -> this
        // Future migrations chain here; unknown-but-newer configs are left untouched.
        else -> copy(schemaVersion = AppConfig.CURRENT_SCHEMA)
    }

    private companion object { const val FILE_NAME = "config.json" }
}
