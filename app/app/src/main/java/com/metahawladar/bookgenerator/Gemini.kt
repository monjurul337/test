package com.metahawladar.bookgenerator


class GeminiException(message: String) : RuntimeException(message)

/**
 * A rotating pool of Gemini API keys.
 *
 * Paste as many keys as you like - one per line, or separated by commas or
 * spaces. Every request takes the next healthy key, so the free-tier per-key
 * rate limit is shared out instead of stopping the book.
 */
class KeyPool(raw: String) {

    val keys: List<String> = parse(raw)

    private var cursor = 0

    companion object {
        private val cooldown = HashMap<String, Long>()

        /** Splits a blob of pasted text into unique, plausible-looking keys. */
        fun parse(raw: String): List<String> =
            raw.split(Regex("[\\s,;]+"))
                .map { it.trim() }
                .filter { it.length >= 20 }
                .distinct()
    }

    val isEmpty: Boolean get() = keys.isEmpty()
    val size: Int get() = keys.size

    /** Human label for logs: never prints the key itself. */
    fun label(key: String): String = "key ${keys.indexOf(key) + 1}/${keys.size}"

    /** The next key that is not cooling down, else the one that frees up first. */
    @Synchronized
    fun next(): String {
        val now = System.currentTimeMillis()
        for (i in keys.indices) {
            val k = keys[(cursor + i) % keys.size]
            if ((cooldown[k] ?: 0L) < now) {
                cursor = (keys.indexOf(k) + 1) % keys.size
                return k
            }
        }
        return keys.minByOrNull { cooldown[it] ?: 0L } ?: keys.first()
    }

    /** Benches a key that hit a quota or auth error. */
    @Synchronized
    fun rest(key: String, millis: Long) {
        cooldown[key] = System.currentTimeMillis() + millis
    }

    /** Whether at least one other key is ready right now. */
    @Synchronized
    fun hasReadyAlternative(current: String): Boolean {
        val now = System.currentTimeMillis()
        return keys.any { it != current && (cooldown[it] ?: 0L) < now }
    }
}

