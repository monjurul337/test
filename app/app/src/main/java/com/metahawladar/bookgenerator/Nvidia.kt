package com.metahawladar.bookgenerator

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * Thin client for build.nvidia.com, which speaks the OpenAI chat format.
 *
 * Shares the rotating [KeyPool] with the Gemini client, so a pile of
 * `nvapi-...` keys can be pasted and the load spread across them.
 */
class Nvidia(apiKey: String, private val model: String = MODELS[0]) : LlmClient {

    private val pool = KeyPool(apiKey)

    companion object {
        /**
         * The model pool. A strong generalist first, the big reasoner for hard
         * plots, the fast one for drafts.
         */
        val MODELS = listOf(
            "z-ai/glm-5.2",
            "nvidia/nemotron-3-super-120b-a12b",
            "nvidia/nemotron-3-ultra-550b-a55b",
            "nvidia/nemotron-3.5-lightning-30b-a3b",
        )

        /** Nemotron exposes an explicit thinking switch in its chat template. */
        fun supportsThinking(model: String): Boolean = model.startsWith("nvidia/")

        private const val URL_CHAT = "https://integrate.api.nvidia.com/v1/chat/completions"
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
        if (pool.isEmpty) throw GeminiException("No NVIDIA API key. Add one in Settings.")

        val messages = JSONArray()
        if (!system.isNullOrBlank()) {
            messages.put(JSONObject().put("role", "system").put("content", system))
        }
        val userText = if (asJson) {
            "$prompt\n\nReturn one JSON object and nothing else. " +
                "No markdown fences, no commentary."
        } else {
            prompt
        }
        messages.put(JSONObject().put("role", "user").put("content", userText))

        val body = JSONObject()
            .put("model", model)
            .put("messages", messages)
            .put("temperature", temperature)
            .put("top_p", 0.95)
            .put("max_tokens", maxTokens)
            .put("stream", false)
        if (supportsThinking(model)) {
            body.put("chat_template_kwargs", JSONObject().put("thinking", thinking > 0))
        }
        val payload = body.toString().toByteArray(Charsets.UTF_8)
        var lastError = "unknown error"

        val tries = if (pool.size > 1) retries * 2 else retries
        for (attempt in 0 until tries) {
            var conn: HttpURLConnection? = null
            val key = pool.next()
            try {
                conn = (URL(URL_CHAT).openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 60_000
                    readTimeout = 300_000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Accept", "application/json")
                    setRequestProperty("Authorization", "Bearer $key")
                }
                conn.outputStream.use { it.write(payload) }

                val code = conn.responseCode
                val stream = if (code in 200..299) conn.inputStream else conn.errorStream
                val text = stream?.let {
                    BufferedReader(InputStreamReader(it, Charsets.UTF_8)).use { r -> r.readText() }
                } ?: ""

                if (code !in 200..299) {
                    lastError = "HTTP $code: ${text.take(300)}"
                    val dead = code == 401 || code == 403
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
                val choices = root.optJSONArray("choices")
                    ?: throw GeminiException("Model returned nothing: ${text.take(300)}")
                if (choices.length() == 0) {
                    throw GeminiException("Model returned nothing.")
                }
                val first = choices.getJSONObject(0)
                val result = first.optJSONObject("message")
                    ?.optString("content", "")
                    ?.trim()
                    .orEmpty()
                if (result.isEmpty()) {
                    lastError = "Empty response (finish_reason=${first.optString("finish_reason")})"
                    if (attempt < tries - 1) {
                        log?.invoke("   $lastError, retrying")
                        delay(5_000)
                        continue
                    }
                    throw GeminiException(lastError)
                }
                return@withContext stripThinking(result)
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
        val raw = stripFences(
            generate(
                prompt = prompt,
                system = system,
                temperature = temperature,
                maxTokens = maxTokens,
                asJson = true,
                thinking = thinking,
                log = log,
            )
        )
        return try {
            JSONObject(raw)
        } catch (e: Exception) {
            val s = raw.indexOf('{')
            val t = raw.lastIndexOf('}')
            if (s >= 0 && t > s) {
                JSONObject(raw.substring(s, t + 1))
            } else {
                throw GeminiException("Model did not return valid JSON.")
            }
        }
    }

    /** Reasoning models sometimes prepend a <think> block. Drop it. */
    private fun stripThinking(s: String): String {
        val end = s.indexOf("</think>")
        return if (end < 0) s else s.substring(end + 8).trim()
    }

    private fun stripFences(s: String): String {
        var t = s.trim()
        if (t.startsWith("```")) {
            val nl = t.indexOf('\n')
            if (nl > 0) t = t.substring(nl + 1)
            if (t.endsWith("```")) t = t.dropLast(3)
        }
        return t.trim()
    }
}
