package com.softizence.browser.extensions

/**
 * Chrome match-pattern matcher, e.g. a scheme wildcard, a `*.` host wildcard and a
 * trailing path wildcard.
 * Used for content-script targeting and host-permission checks on both platforms.
 */
class MatchPattern private constructor(
    private val scheme: String,
    private val host: String,
    private val path: String,
    private val matchesAllUrls: Boolean,
) {
    fun matches(url: String): Boolean {
        if (matchesAllUrls) return url.startsWith("http://") || url.startsWith("https://")
        val urlScheme = url.substringBefore("://", "").lowercase()
        if (urlScheme.isEmpty()) return false
        if (scheme != "*" && scheme != urlScheme) return false
        if (scheme == "*" && urlScheme !in setOf("http", "https")) return false

        val rest = url.substringAfter("://")
        val urlHost = rest.substringBefore('/').substringBefore('?').substringBefore(':').lowercase()
        val urlPath = "/" + rest.substringAfter('/', "")

        val hostOk = when {
            host == "*" -> true
            host.startsWith("*.") -> {
                val base = host.removePrefix("*.")
                urlHost == base || urlHost.endsWith(".$base")
            }
            else -> urlHost == host
        }
        if (!hostOk) return false
        return globMatches(path, urlPath)
    }

    companion object {
        fun parse(pattern: String): MatchPattern? {
            if (pattern == "<all_urls>") return MatchPattern("*", "*", "/*", matchesAllUrls = true)
            val scheme = pattern.substringBefore("://", "").lowercase().ifEmpty { return null }
            val rest = pattern.substringAfter("://")
            val host = rest.substringBefore('/').lowercase()
            val path = "/" + rest.substringAfter('/', "")
            if (host.isEmpty()) return null
            return MatchPattern(scheme, host, path, matchesAllUrls = false)
        }

        /** Simple star-glob - the only wildcard Chrome allows in the path component. */
        internal fun globMatches(glob: String, value: String): Boolean {
            if (glob == "*" || glob == "/*") return true
            val parts = glob.split('*')
            var index = 0
            parts.forEachIndexed { i, part ->
                if (part.isEmpty()) return@forEachIndexed
                val found = value.indexOf(part, index)
                if (found < 0) return false
                if (i == 0 && found != 0) return false
                index = found + part.length
            }
            return glob.endsWith("*") || index == value.length
        }
    }
}

fun List<String>.anyMatches(url: String): Boolean =
    asSequence().mapNotNull(MatchPattern::parse).any { it.matches(url) }
