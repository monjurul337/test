package com.metahawladar.bookgenerator

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import android.util.Base64
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

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

/** Thin Gemini REST client on top of HttpURLConnection - no HTTP library needed. */
class Gemini(apiKey: String, private val model: String = MODELS[0]) : LlmClient {

    private val pool = KeyPool(apiKey)

    companion object {
        /** Rolling aliases, so the app follows Google's current flash models. */
        val MODELS = listOf("gemini-flash-latest", "gemini-flash-lite-latest")

        /** Google's image generation model, used for cover artwork. */
        const val IMAGE_MODEL = "gemini-2.5-flash-image"

        /** Models that accept generationConfig.thinkingConfig. */
        fun supportsThinking(model: String): Boolean =
            model.startsWith("gemini-2.5") || model in MODELS
        private const val BASE = "https://generativelanguage.googleapis.com/v1beta/models"
        private val RETRYABLE = setOf(429, 500, 502, 503, 504)
    }

    override suspend fun generate(
        prompt: String,
        system: String?,
        temperature: Double,
        maxTokens: Int,
        asJson: Boolean,
        thinking: Int,
        retries: Int,
        log: ((String) -> Unit)?,
    ): String = withContext(Dispatchers.IO) {
        if (pool.isEmpty) throw GeminiException("No Gemini API key. Add one in Settings.")

        val generationConfig = JSONObject()
            .put("temperature", temperature)
            .put("maxOutputTokens", maxTokens)
        if (asJson) generationConfig.put("responseMimeType", "application/json")
        if (supportsThinking(model)) {
            generationConfig.put("thinkingConfig", JSONObject().put("thinkingBudget", thinking))
        }

        val safety = JSONArray()
        for (c in listOf(
            "HARM_CATEGORY_HARASSMENT",
            "HARM_CATEGORY_HATE_SPEECH",
            "HARM_CATEGORY_SEXUALLY_EXPLICIT",
            "HARM_CATEGORY_DANGEROUS_CONTENT",
        )) {
            safety.put(JSONObject().put("category", c).put("threshold", "BLOCK_ONLY_HIGH"))
        }

        val body = JSONObject()
            .put(
                "contents",
                JSONArray().put(
                    JSONObject()
                        .put("role", "user")
                        .put("parts", JSONArray().put(JSONObject().put("text", prompt)))
                )
            )
            .put("generationConfig", generationConfig)
            .put("safetySettings", safety)
        if (system != null) {
            body.put(
                "systemInstruction",
                JSONObject().put("parts", JSONArray().put(JSONObject().put("text", system)))
            )
        }

        val payload = body.toString().toByteArray(Charsets.UTF_8)
        var lastError = "unknown error"

        val tries = if (pool.size > 1) retries * 2 else retries
        for (attempt in 0 until tries) {
            var conn: HttpURLConnection? = null
            val key = pool.next()
            try {
                conn = (URL("$BASE/$model:generateContent?key=$key").openConnection()
                        as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 60_000
                    readTimeout = 300_000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json; charset=utf-8")
                }
                conn.outputStream.use { it.write(payload) }

                val code = conn.responseCode
                val stream = if (code in 200..299) conn.inputStream else conn.errorStream
                val text = stream?.let {
                    BufferedReader(InputStreamReader(it, Charsets.UTF_8)).use { r -> r.readText() }
                } ?: ""

                if (code !in 200..299) {
                    lastError = "HTTP $code: ${text.take(300)}"
                    val dead = code == 400 || code == 403
                    if ((code == 429 || dead) && pool.size > 1) {
                        pool.rest(key, if (dead) 3_600_000L else 60_000L)
                        if (pool.hasReadyAlternative(key) && attempt < tries - 1) {
                            val what = if (dead) "rejected" else "rate limited"
                            log?.invoke("   ${pool.label(key)} $what, switching key")
                            continue
                        }
                    }
                    if (code in RETRYABLE && attempt < tries - 1) {
                        val wait = 4L shl attempt.coerceAtMost(4)
                        log?.invoke("   rate limited ($code), retrying in ${wait}s")
                        delay(wait * 1000)
                        continue
                    }
                    throw GeminiException(lastError)
                }

                val root = JSONObject(text)
                val candidates = root.optJSONArray("candidates")
                    ?: throw GeminiException("Model returned nothing: ${text.take(300)}")
                if (candidates.length() == 0) {
                    throw GeminiException("Model returned nothing (prompt blocked).")
                }
                val candidate = candidates.getJSONObject(0)
                val parts = candidate.optJSONObject("content")?.optJSONArray("parts")
                val sb = StringBuilder()
                if (parts != null) {
                    for (i in 0 until parts.length()) {
                        sb.append(parts.getJSONObject(i).optString("text", ""))
                    }
                }
                val result = sb.toString().trim()
                if (result.isEmpty()) {
                    lastError = "Empty response (finishReason=${candidate.optString("finishReason")})"
                    if (attempt < tries - 1) {
                        log?.invoke("   $lastError, retrying")
                        delay(5_000)
                        continue
                    }
                    throw GeminiException(lastError)
                }
                return@withContext result
            } catch (e: GeminiException) {
                throw e
            } catch (e: Exception) {
                lastError = e.message ?: e.toString()
                if (attempt == tries - 1) throw GeminiException("Network error: $lastError")
                delay((4L shl attempt.coerceAtMost(4)) * 1000)
            } finally {
                conn?.disconnect()
            }
        }
        throw GeminiException(lastError)
    }

    override suspend fun generateJson(
        prompt: String,
        system: String?,
        temperature: Double,
        maxTokens: Int,
        thinking: Int,
        log: ((String) -> Unit)?,
    ): JSONObject {
        val raw = generate(
            prompt, system, temperature, maxTokens,
            asJson = true, thinking = thinking, log = log,
        )
        return try {
            JSONObject(raw)
        } catch (_: Exception) {
            val s = raw.indexOf('{')
            val e = raw.lastIndexOf('}')
            if (s >= 0 && e > s) JSONObject(raw.substring(s, e + 1))
            else throw GeminiException("Model did not return valid JSON.")
        }
    }

    /**
     * Generates one image with the image model and returns its raw bytes.
     *
     * The reply is a generateContent call whose candidate carries an
     * inlineData part instead of text. Aspect ratio 2:3 is the closest
     * standing ratio to a 1600x2560 book cover; the cover renderer crops
     * the rest.
     */
    suspend fun generateImage(
        prompt: String,
        aspectRatio: String = "2:3",
        retries: Int = 3,
        log: ((String) -> Unit)? = null,
    ): ByteArray = withContext(Dispatchers.IO) {
        if (pool.isEmpty) throw GeminiException("No Gemini API key. Add one in Settings.")

        val safety = JSONArray()
        for (c in listOf(
            "HARM_CATEGORY_HARASSMENT",
            "HARM_CATEGORY_HATE_SPEECH",
            "HARM_CATEGORY_SEXUALLY_EXPLICIT",
            "HARM_CATEGORY_DANGEROUS_CONTENT",
        )) {
            safety.put(JSONObject().put("category", c).put("threshold", "BLOCK_ONLY_HIGH"))
        }

        val body = JSONObject()
            .put(
                "contents",
                JSONArray().put(
                    JSONObject()
                        .put("role", "user")
                        .put("parts", JSONArray().put(JSONObject().put("text", prompt)))
                )
            )
            .put(
                "generationConfig",
                JSONObject()
                    .put("responseModalities", JSONArray().put("IMAGE"))
                    .put("imageConfig", JSONObject().put("aspectRatio", aspectRatio)),
            )
            .put("safetySettings", safety)

        val payload = body.toString().toByteArray(Charsets.UTF_8)
        var lastError = "unknown error"

        val tries = if (pool.size > 1) retries * 2 else retries
        for (attempt in 0 until tries) {
            var conn: HttpURLConnection? = null
            val key = pool.next()
            try {
                conn = (URL("$BASE/$IMAGE_MODEL:generateContent?key=$key").openConnection()
                        as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 60_000
                    readTimeout = 300_000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json; charset=utf-8")
                }
                conn.outputStream.use { it.write(payload) }

                val code = conn.responseCode
                val stream = if (code in 200..299) conn.inputStream else conn.errorStream
                val text = stream?.let {
                    BufferedReader(InputStreamReader(it, Charsets.UTF_8)).use { r -> r.readText() }
                } ?: ""

                if (code !in 200..299) {
                    lastError = "HTTP $code: ${text.take(300)}"
                    val dead = code == 400 || code == 403
                    if ((code == 429 || dead) && pool.size > 1) {
                        pool.rest(key, if (dead) 3_600_000L else 60_000L)
                        if (pool.hasReadyAlternative(key) && attempt < tries - 1) {
                            val what = if (dead) "rejected" else "rate limited"
                            log?.invoke("   ${pool.label(key)} $what, switching key")
                            continue
                        }
                    }
                    if (code in RETRYABLE && attempt < tries - 1) {
                        val wait = 4L shl attempt.coerceAtMost(4)
                        log?.invoke("   rate limited ($code), retrying in ${wait}s")
                        delay(wait * 1000)
                        continue
                    }
                    throw GeminiException(lastError)
                }

                val root = JSONObject(text)
                val candidates = root.optJSONArray("candidates")
                    ?: throw GeminiException("Image model returned nothing: ${text.take(300)}")
                if (candidates.length() == 0) {
                    throw GeminiException("Image model returned nothing (prompt blocked).")
                }
                val candidate = candidates.getJSONObject(0)
                val parts = candidate.optJSONObject("content")?.optJSONArray("parts")
                if (parts != null) {
                    for (i in 0 until parts.length()) {
                        val inline = parts.getJSONObject(i).optJSONObject("inlineData")
                            ?: continue
                        val data = inline.optString("data", "")
                        if (data.isNotEmpty()) {
                            return@withContext Base64.decode(data, Base64.DEFAULT)
                        }
                    }
                }
                lastError = "No image in the reply " +
                    "(finishReason=${candidate.optString("finishReason")})"
                if (attempt < tries - 1) {
                    log?.invoke("   $lastError, retrying")
                    delay(5_000)
                    continue
                }
                throw GeminiException(lastError)
            } catch (e: GeminiException) {
                throw e
            } catch (e: Exception) {
                lastError = e.message ?: e.toString()
                if (attempt == tries - 1) throw GeminiException("Network error: $lastError")
                delay((4L shl attempt.coerceAtMost(4)) * 1000)
            } finally {
                conn?.disconnect()
            }
        }
        throw GeminiException(lastError)
    }
}
