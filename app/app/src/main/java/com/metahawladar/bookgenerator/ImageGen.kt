package com.metahawladar.bookgenerator

import android.util.Base64
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
 * Text-to-image for real cover art, so a cover is a painted scene rather than
 * generated geometry.
 *
 * Both providers reuse the same rotating [KeyPool] as the writing models, so
 * your bulk keys cover image generation too.
 */
class ImageGen(
    private val provider: String,
    private val keys: String,
    private val model: String,
) {
    private val pool = KeyPool(if (provider == Providers.NVIDIA) keys else "")

    companion object {
        /** The "no art" choice: fall back to the built-in geometric cover. */
        const val OFF = "off"

        val GEMINI_MODELS = listOf("gemini-web-image")

        val NVIDIA_MODELS = listOf(
            "black-forest-labs/flux.1-schnell",
            "black-forest-labs/flux.1-dev",
            "stabilityai/stable-diffusion-3.5-large",
        )

        fun modelsFor(provider: String): List<String> =
            listOf(OFF) + if (provider == Providers.NVIDIA) NVIDIA_MODELS else GEMINI_MODELS

        /** Keeps a saved choice valid when the provider changes. */
        fun fixModel(provider: String, model: String): String =
            if (modelsFor(provider).contains(model)) model else OFF

        /** Friendly label for the picker. */
        fun label(model: String): String =
            if (model == OFF) "Off - geometric cover" else model
    }

    /** Returns PNG or JPEG bytes, or throws. */
    suspend fun render(prompt: String, log: ((String) -> Unit)? = null): ByteArray {
        if (provider == Providers.GEMINI) return GeminiWeb(keys).generateImage(prompt)
        if (pool.isEmpty) throw GeminiException("No API key for cover art.")
        return nvidia(prompt, log)
    }

    // NVIDIA image API. Gemini artwork uses the cookie session above.

    private suspend fun nvidia(prompt: String, log: ((String) -> Unit)?): ByteArray {
        val sd = model.startsWith("stabilityai")
        val body = if (sd) {
            JSONObject()
                .put("prompt", prompt)
                .put("aspect_ratio", "9:16")
                .put("cfg_scale", 5)
                .put("mode", "text-to-image")
                .put("output_format", "png")
        } else {
            JSONObject()
                .put("prompt", prompt)
                .put("width", 832)
                .put("height", 1216)
                .put("cfg_scale", 3.5)
                .put("steps", if (model.endsWith("schnell")) 4 else 30)
                .put("seed", 0)
        }

        val text = post(
            { "https://ai.api.nvidia.com/v1/genai/$model" },
            body,
            bearer = true,
            log = log,
        )
        val out = JSONObject(text)

        val artifacts = out.optJSONArray("artifacts") ?: JSONArray()
        for (i in 0 until artifacts.length()) {
            val b64 = artifacts.optJSONObject(i)?.optString("base64").orEmpty()
            if (b64.isNotEmpty()) return decode(b64)
        }
        val direct = out.optString("image")
        if (direct.isNotEmpty()) return decode(direct)
        throw GeminiException("The image model returned no picture.")
    }

    // --------------------------------------------------------------- HTTP

    private fun decode(b64: String): ByteArray =
        Base64.decode(b64.substringAfter("base64,"), Base64.DEFAULT)

    private suspend fun post(
        url: (String) -> String,
        body: JSONObject,
        bearer: Boolean,
        log: ((String) -> Unit)?,
    ): String = withContext(Dispatchers.IO) {
        val payload = body.toString().toByteArray(Charsets.UTF_8)
        var lastError = "unknown error"
        val tries = if (pool.size > 1) 6 else 3

        for (attempt in 0 until tries) {
            var conn: HttpURLConnection? = null
            val key = pool.next()
            try {
                conn = (URL(url(key)).openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 60_000
                    readTimeout = 300_000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json; charset=utf-8")
                    setRequestProperty("Accept", "application/json")
                    if (bearer) setRequestProperty("Authorization", "Bearer $key")
                }
                conn.outputStream.use { it.write(payload) }

                val code = conn.responseCode
                val stream = if (code in 200..299) conn.inputStream else conn.errorStream
                val text = stream?.let {
                    BufferedReader(InputStreamReader(it, Charsets.UTF_8)).use { r -> r.readText() }
                } ?: ""
                if (code in 200..299) return@withContext text

                lastError = "HTTP $code: ${text.take(240)}"
                val dead = code == 401 || code == 403 || code == 404
                if ((code == 429 || dead) && pool.size > 1) {
                    pool.rest(key, if (dead) 3_600_000L else 60_000L)
                    if (pool.hasReadyAlternative(key) && attempt < tries - 1) {
                        log?.invoke("   cover art: ${pool.label(key)} refused, next key")
                        continue
                    }
                }
                if (code >= 500 && attempt < tries - 1) {
                    delay(5_000)
                    continue
                }
                throw GeminiException(lastError)
            } catch (e: GeminiException) {
                throw e
            } catch (e: Exception) {
                lastError = e.message ?: e.toString()
                if (attempt == tries - 1) throw GeminiException("Cover art failed: $lastError")
                delay(4_000)
            } finally {
                conn?.disconnect()
            }
        }
        throw GeminiException(lastError)
    }
}
