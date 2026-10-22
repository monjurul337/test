package com.softizence.browser.extensions

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Chrome Manifest V3 subset that a Chromium-embedding host actually needs. */
@Serializable
data class Mv3Manifest(
    @SerialName("manifest_version") val manifestVersion: Int = 3,
    val name: String = "Unnamed extension",
    val version: String = "0.0.0",
    val description: String = "",
    val permissions: List<String> = emptyList(),
    @SerialName("host_permissions") val hostPermissions: List<String> = emptyList(),
    val background: Background? = null,
    @SerialName("content_scripts") val contentScripts: List<ContentScript> = emptyList(),
    @SerialName("action") val action: Action? = null,
    @SerialName("declarative_net_request") val declarativeNetRequest: Dnr? = null,
    @SerialName("web_accessible_resources") val webAccessibleResources: List<JsonElement> = emptyList(),
    val icons: Map<String, String> = emptyMap(),
) {
    @Serializable
    data class Background(
        @SerialName("service_worker") val serviceWorker: String? = null,
        val type: String? = null,
    )

    @Serializable
    data class ContentScript(
        val matches: List<String> = emptyList(),
        @SerialName("exclude_matches") val excludeMatches: List<String> = emptyList(),
        val js: List<String> = emptyList(),
        val css: List<String> = emptyList(),
        @SerialName("run_at") val runAt: String = "document_idle",
        @SerialName("all_frames") val allFrames: Boolean = false,
    )

    @Serializable
    data class Action(
        @SerialName("default_popup") val defaultPopup: String? = null,
        @SerialName("default_title") val defaultTitle: String? = null,
        @SerialName("default_icon") val defaultIcon: JsonElement? = null,
    )

    @Serializable
    data class Dnr(
        @SerialName("rule_resources") val ruleResources: List<RuleResource> = emptyList(),
    ) {
        @Serializable
        data class RuleResource(
            val id: String,
            val enabled: Boolean = true,
            val path: String,
        )
    }

    fun bestIcon(): String? = icons.entries
        .mapNotNull { (k, v) -> k.toIntOrNull()?.let { it to v } }
        .maxByOrNull { it.first }
        ?.second
}

object ManifestReader {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        allowTrailingComma = true
        coerceInputValues = true
    }

    /**
     * Chrome manifests legally contain `//` comments and localisation placeholders
     * (`__MSG_appName__`). Strip/soften both before strict deserialisation.
     */
    fun read(raw: String): Result<Mv3Manifest> = runCatching {
        val cleaned = raw.lineSequence()
            .filterNot { it.trimStart().startsWith("//") }
            .joinToString("\n")

        val manifest = json.decodeFromString<Mv3Manifest>(cleaned)

        if (manifest.manifestVersion != 3) {
            error("Manifest V${manifest.manifestVersion} is not supported - Softizence hosts MV3 only.")
        }
        manifest
    }

    /** Resolves `__MSG_key__` against `_locales/<locale>/messages.json`. */
    fun localize(value: String, messages: JsonObject?): String {
        if (!value.startsWith("__MSG_") || messages == null) return value
        val key = value.removePrefix("__MSG_").removeSuffix("__")
        return (messages[key] as? JsonObject)
            ?.get("message")
            ?.let { (it as? JsonPrimitive)?.content }
            ?: value
    }

    fun messagesOf(raw: String): JsonObject? =
        runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull()

    fun pretty(element: JsonElement): String = json.encodeToString(JsonElement.serializer(), element)

    fun primitive(obj: JsonObject, key: String): String? =
        runCatching { obj[key]?.jsonPrimitive?.content }.getOrNull()
}
