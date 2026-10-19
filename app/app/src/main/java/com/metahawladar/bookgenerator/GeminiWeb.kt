package com.metahawladar.bookgenerator

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.random.Random

class GeminiWebException(message: String, val expired: Boolean = false) : RuntimeException(message)

/** User-owned credentials, held in RAM only. Never include this object in logs. */
class GeminiWebSession private constructor(private val cookies: List<JSONObject>) {
    val count: Int get() = cookies.size

    fun cookieHeader(): String {
        val now = System.currentTimeMillis() / 1000
        return cookies.filter { cookie ->
            val expiry = cookie.optDouble("expires", cookie.optDouble("expirationDate", -1.0))
            cookie.optString("path", "/") == "/" && (expiry <= 0 || expiry > now)
        }.distinctBy { it.optString("name") }
            .joinToString("; ") { "${it.optString("name")}=${it.optString("value")}" }
    }

    companion object {
        private val domains = setOf("google.com", ".google.com", "gemini.google.com", ".gemini.google.com")
        fun parse(raw: String): GeminiWebSession {
            val root = try { JSONTokener(raw.trim()).nextValue() }
            catch (_: Exception) { throw GeminiWebException("Invalid session JSON. Export your own signed-in Gemini cookies.") }
            fun find(value: Any?): JSONArray? {
                if (value is JSONArray && value.length() > 0 && value.optJSONObject(0)?.has("name") == true) return value
                if (value is JSONObject) {
                    value.optJSONArray("cookies")?.let { return it }
                    for (key in value.keys()) {
                        val child = value.opt(key)
                        if (child is JSONArray && child.length() > 0 && child.optJSONObject(0)?.has("name") == true) return child
                        if (child is JSONObject) child.optJSONArray("cookies")?.let { return it }
                    }
                }
                return null
            }
            val array = find(root) ?: throw GeminiWebException("No cookies found. Use storageState or a cookie-export JSON array.")
            val valid = (0 until array.length()).mapNotNull { array.optJSONObject(it) }.filter {
                val domain = it.optString("domain", ".google.com").lowercase()
                val name = it.optString("name")
                val value = it.optString("value")
                domain in domains && name.isNotBlank() && value.isNotBlank() &&
                    !Regex("[;=\\r\\n]").containsMatchIn(name) && !Regex("[;\\r\\n]").containsMatchIn(value)
            }
            if (valid.none { it.optString("name") in setOf("__Secure-1PSID", "__Secure-3PSID") }) {
                throw GeminiWebException("Missing Gemini authentication cookies. Export your own signed-in session.")
            }
            return GeminiWebSession(valid)
        }
        fun countCookies(raw: String): Int = try { parse(raw).count } catch (_: Exception) { 0 }
    }
}

/** Native port of the supplied Dart StreamGenerate client. No API-key fallback. */
class GeminiWeb(raw: String) : LlmClient {
    private val session = GeminiWebSession.parse(raw)
    private var token: String? = null
    private var build: String? = null
    private var reqId = Random.nextInt(100000, 900000)
    private var lastRaw = ""

    private fun encode(s: String): String = URLEncoder.encode(s, "UTF-8")

    private fun request(url: String, form: String? = null): String {
        val target = URL(url)
        require(target.protocol == "https" && target.host == "gemini.google.com")
        val conn = target.openConnection() as HttpURLConnection
        try {
            conn.instanceFollowRedirects = false // Never forward credentials to redirects.
            conn.connectTimeout = 45000
            conn.readTimeout = 120000
            conn.setRequestProperty("User-Agent", USER_AGENT)
            conn.setRequestProperty("Cookie", session.cookieHeader())
            conn.setRequestProperty("Origin", "https://gemini.google.com")
            conn.setRequestProperty("Referer", "https://gemini.google.com/")
            conn.setRequestProperty("X-Same-Domain", "1")
            conn.setRequestProperty("Accept-Language", "en-US,en;q=0.9")
            if (form != null) {
                conn.requestMethod = "POST"
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded;charset=UTF-8")
                conn.outputStream.use { it.write(form.toByteArray(Charsets.UTF_8)) }
            }
            val code = conn.responseCode
            if (code in 300..399 || code == 401 || code == 403) {
                throw GeminiWebException("Gemini session rejected or signed out. Re-export fresh cookies.", true)
            }
            if (code == 429) throw GeminiWebException("Gemini account rate limit. Wait before retrying.")
            if (code != 200) throw GeminiWebException("Gemini web HTTP $code.")
            return conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        } finally { conn.disconnect() }
    }

    private fun init() {
        val html = request("https://gemini.google.com/app")
        token = Regex("\"SNlM0e\":\"(.*?)\"").find(html)?.groupValues?.get(1)
        build = Regex("\"cfb2h\":\"(.*?)\"").find(html)?.groupValues?.get(1)
        if (token.isNullOrBlank()) throw GeminiWebException(
            "No Gemini auth token found. Session may be expired, or the web protocol changed. Re-export fresh cookies.", true)
        if (build.isNullOrBlank()) throw GeminiWebException("Gemini web build token missing; protocol may have changed.")
    }

    private fun send(prompt: String): String {
        if (token == null) init()
        lastRaw = ""
        // Each call starts a fresh chat; the book pipeline supplies its own running summary.
        val inner = JSONArray().put(JSONArray().put(prompt)).put(JSONObject.NULL)
            .put(JSONArray().put(JSONObject.NULL).put(JSONObject.NULL).put(JSONObject.NULL)).toString()
        val freq = JSONArray().put(JSONObject.NULL).put(inner).toString()
        val url = "https://gemini.google.com/_/BardChatUi/data/assistant.lamda.BardFrontendService/StreamGenerate" +
            "?bl=${encode(build!!)}&_reqid=$reqId&rt=c"
        reqId += 100000
        lastRaw = request(url, "f.req=${encode(freq)}&at=${encode(token!!)}")
        return parseStream(lastRaw)
    }

    private fun parseStream(raw: String): String {
        var best = ""
        raw.lineSequence().map { it.trim() }.filter { it.startsWith("[") }.forEach { line ->
            val chunk = try { JSONArray(line) } catch (_: Exception) { return@forEach }
            for (i in 0 until chunk.length()) {
                val entry = chunk.optJSONArray(i) ?: continue
                if (entry.optString(0) != "wrb.fr") continue
                val payload = try { JSONArray(entry.optString(2)) } catch (_: Exception) { continue }
                val text = payload.optJSONArray(4)?.optJSONArray(0)?.optJSONArray(1)?.optString(0).orEmpty()
                if (text.trim().length > best.trim().length) best = text
            }
        }
        if (best.isBlank()) throw GeminiWebException("Gemini returned no readable answer. Session or web protocol may have changed.")
        return best.trim()
    }

    override suspend fun generate(
        prompt: String, system: String?, temperature: Double, maxTokens: Int,
        asJson: Boolean, thinking: Int, retries: Int, log: ((String) -> Unit)?,
    ): String = withContext(Dispatchers.IO) {
        val combined = listOfNotNull(
            system?.takeIf { it.isNotBlank() }?.let { "Instructions: $it" },
            if (asJson) "Reply with raw JSON only, no markdown fences or prose." else null,
            prompt,
        ).joinToString("\n\n")
        var last: GeminiWebException? = null
        val attempts = retries.coerceIn(1, 3)
        for (attempt in 0 until attempts) {
            try { return@withContext send(combined) }
            catch (e: CancellationException) { throw e }
            catch (e: GeminiWebException) {
                last = e
                if (e.expired) { token = null; throw e }
            } catch (_: Exception) { last = GeminiWebException("Gemini web connection failed. Check your connection and session.") }
            if (attempt < attempts - 1) delay(3000L * (attempt + 1))
        }
        throw last ?: GeminiWebException("Gemini web request failed.")
    }

    override suspend fun generateJson(
        prompt: String, system: String?, temperature: Double, maxTokens: Int,
        thinking: Int, log: ((String) -> Unit)?,
    ): JSONObject {
        val raw = generate(prompt, system, temperature, maxTokens, true, thinking, 3, log)
        try { return JSONObject(raw) } catch (_: Exception) { /* Strip a markdown wrapper, if present. */ }
        val first = raw.indexOf('{')
        val last = raw.lastIndexOf('}')
        if (first >= 0 && last > first) {
            try { return JSONObject(raw.substring(first, last + 1)) } catch (_: Exception) { }
        }
        throw GeminiWebException("Gemini web did not return a valid JSON object.")
    }

    suspend fun generateImage(prompt: String): ByteArray = withContext(Dispatchers.IO) {
        try { send(prompt) } catch (e: GeminiWebException) {
            if (e.expired || lastRaw.isBlank()) throw e // Image-only replies may have no prose.
        }
        val raw = lastRaw.replace("\\/", "/").replace("\\u003d", "=").replace("\\u0026", "&")
        val link = Regex("https://lh3\\.googleusercontent\\.com/[^\"\\s\\\\]+").find(raw)?.value
            ?: throw GeminiWebException("Gemini returned no downloadable artwork. Try again or select geometric cover.")
        val url = URL(link)
        if (url.protocol != "https" || url.host != "lh3.googleusercontent.com" ||
            url.userInfo != null || (url.port != -1 && url.port != 443)) throw GeminiWebException("Unexpected artwork host.")
        val conn = url.openConnection() as HttpURLConnection
        try {
            conn.instanceFollowRedirects = false
            conn.connectTimeout = 45000
            conn.readTimeout = 60000
            conn.setRequestProperty("User-Agent", USER_AGENT) // Never attach Google account cookies to artwork requests.
            if (conn.responseCode != 200 || conn.contentType?.startsWith("image/") != true) {
                throw GeminiWebException("Artwork download failed or was not an image.")
            }
            val out = ByteArrayOutputStream()
            conn.inputStream.use { input ->
                val buffer = ByteArray(8192)
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    if (out.size() + n > 20 * 1024 * 1024) throw GeminiWebException("Artwork exceeds 20 MB.")
                    out.write(buffer, 0, n)
                }
            }
            out.toByteArray()
        } finally { conn.disconnect() }
    }

    companion object {
        private const val USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    }
}
