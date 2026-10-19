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

class GeminiException(message: String) : RuntimeException(message)

/** Thin Gemini REST client on top of HttpURLConnection - no HTTP library needed. */
class Gemini(private val apiKey: String, private val model: String = MODELS[0]) {

    companion object {
        val MODELS = listOf("gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.5-flash-lite")
        private const val BASE = "https://generativelanguage.googleapis.com/v1beta/models"
        private val RETRYABLE = setOf(429, 500, 502, 503, 504)
    }

    suspend fun generate(
        prompt: String,
        system: String? = null,
        temperature: Double = 0.9,
        maxTokens: Int = 8192,
        asJson: Boolean = false,
        thinking: Int = 0,
        retries: Int = 5,
        log: ((String) -> Unit)? = null,
    ): String = withContext(Dispatchers.IO) {
        if (apiKey.isBlank()) throw GeminiException("No Gemini API key. Add one in Settings.")

        val generationConfig = JSONObject()
            .put("temperature", temperature)
            .put("maxOutputTokens", maxTokens)
        if (asJson) generationConfig.put("responseMimeType", "application/json")
        if (model.startsWith("gemini-2.5")) {
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

        for (attempt in 0 until retries) {
            var conn: HttpURLConnection? = null
            try {
                conn = (URL("$BASE/$model:generateContent?key=$apiKey").openConnection()
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
                    if (code in RETRYABLE && attempt < retries - 1) {
                        val wait = 4L shl attempt
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
                    if (attempt < retries - 1) {
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
                if (attempt == retries - 1) throw GeminiException("Network error: $lastError")
                delay((4L shl attempt) * 1000)
            } finally {
                conn?.disconnect()
            }
        }
        throw GeminiException(lastError)
    }

    suspend fun generateJson(
        prompt: String,
        system: String? = null,
        temperature: Double = 0.9,
        maxTokens: Int = 16384,
        thinking: Int = 0,
        log: ((String) -> Unit)? = null,
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
}
