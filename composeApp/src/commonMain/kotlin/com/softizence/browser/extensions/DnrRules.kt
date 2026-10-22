package com.softizence.browser.extensions

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Minimal declarativeNetRequest support: we honour `urlFilter` + `action.type == "block"`,
 * which covers the overwhelming majority of real content-blocker rulesets.
 */
@Serializable
data class DnrRule(
    val id: Int = 0,
    val priority: Int = 1,
    val action: Action = Action(),
    val condition: Condition = Condition(),
) {
    @Serializable data class Action(val type: String = "block")
    @Serializable
    data class Condition(
        val urlFilter: String = "",
        val resourceTypes: List<String> = emptyList(),
        val domains: List<String> = emptyList(),
        val excludedDomains: List<String> = emptyList(),
    )
}

object DnrRules {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    fun parse(text: String): List<DnrRule> =
        runCatching { json.decodeFromString<List<DnrRule>>(text) }.getOrDefault(emptyList())

    fun urlFiltersOf(text: String): List<String> =
        parse(text).filter { it.action.type == "block" }
            .map { it.condition.urlFilter }
            .filter { it.isNotBlank() }

    /**
     * Chrome urlFilter syntax: `||host^` anchors a domain, `|` anchors start/end,
     * `*` is a wildcard, `^` is a separator character.
     */
    fun matches(filter: String, url: String): Boolean {
        var f = filter
        if (f.startsWith("||")) {
            val host = f.removePrefix("||").substringBefore('^').substringBefore('/').substringBefore('*')
            val urlHost = url.substringAfter("://", url).substringBefore('/').substringBefore(':')
            return urlHost == host || urlHost.endsWith(".$host")
        }
        if (f.startsWith("|")) f = f.removePrefix("|")
        if (f.endsWith("|")) f = f.removeSuffix("|")
        val normalized = f.replace('^', '*')
        return MatchPattern.globMatches(if ('*' in normalized) normalized else "*$normalized*", url)
    }
}
