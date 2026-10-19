package com.metahawladar.bookgenerator

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.regex.Pattern

/** Thrown for every Gemini-web problem. [expired] = "re-export the cookies". */
class GeminiWebException(
    message: String,
    val expired: Boolean = false,
) : RuntimeException(message)

/**
 * Gemini Web (cookie session) client - talks to gemini.google.com with the
 * cookies the user exported from their own browser, hitting the same
 * BardFrontendService/StreamGenerate endpoint the web app itself calls.
 * Used when API keys run out of quota. Text and cover artwork both flow
 * through the session; the drawn procedural cover is the last resort.
 */
class GeminiWeb(private val sessionJson: String) : LlmClient {

    companion object {
        const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

        val KEY_COOKIES = listOf(
            "SID", "SSID", "APISID", "SAPISID",
            "__Secure-1PSID", "__Secure-3PSID",
        )
        private val FALLBACK_BL = "boq_assistant-bard-web-server_20240625.13_p0"

        /** Generated artwork is hosted on the CDN the web app serves from. */
        val ART_URLS = Regex("""https://lh3\.googleusercontent\.com/[^"\s\\]+""")

        /** Cheap cookie count for UI helpers; 0 when [raw] is not a session. */
        fun cookieCount(raw: String): Int =
            try {
                Session.parse(raw).cookies.size
            } catch (_: Exception) {
                0
            }
    }

    private var client: Client? = null

    private fun cli(): Client = client ?: Client(Session.parse(sessionJson)).also { client = it }

    /** Asks the web session to draw [prompt] and returns the artwork bytes. */
    suspend fun generateImage(prompt: String, log: ((String) -> Unit)? = null): ByteArray =
        withContext(Dispatchers.IO) {
            try {
                cli().generateImage(prompt, log = log)
            } catch (e: Exception) {
                close()
                throw e
            }
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
        val head = buildList {
            if (!system.isNullOrBlank()) add("Instructions: ${system.trim()}")
            if (asJson) {
                add(
                    "Reply with raw JSON only - no markdown fences, no prose " +
                        "around it, starting with the first brace."
                )
            }
        }
        try {
            val full = if (head.isEmpty()) prompt else head.joinToString("\n\n") + "\n\n" + prompt
            cli().ask(full).trim()
        } catch (e: Exception) {
            client?.close()
            client = null
            throw e
        }
    }

    override suspend fun generateJson(
        prompt: String,
        system: String?,
        temperature: Double,
        maxTokens: Int,
        thinking: Int,
        log: ((String) -> Unit)?,
    ): JSONObject = withContext(Dispatchers.IO) {
        val raw = generate(
            prompt, system, temperature, maxTokens,
            asJson = true, thinking = thinking, log = log,
        )
        try {
            JSONObject(raw)
        } catch (_: Exception) {
            val s = raw.indexOf('{')
            val e = raw.lastIndexOf('}')
            if (s in 0 until e) JSONObject(raw.substring(s, e + 1))
            else throw GeminiWebException("Gemini web did not return valid JSON.")
        }
    }

    /** Handshake + tiny prompt, for the Settings test button. */
    suspend fun test(): TestResult = cli().test()

    fun close() {
        client?.close()
        client = null
    }

    /** One normalized cookie (Playwright storageState shape). */
    data class Cookie(
        val name: String,
        val value: String,
        val domain: String,
        val path: String,
        val expires: Int,
    ) {
        val isGoogle: Boolean get() = domain.contains("google.com")
    }

    /** A parsed + normalized Gemini web session. */
    data class Session(val cookies: List<Cookie>, val format: String) {

        val googleCookies: List<Cookie> get() = cookies.filter { it.isGoogle }

        val authCookies: List<String>
            get() = KEY_COOKIES.filter { name ->
                cookies.any { it.name == name && it.value.isNotBlank() }
            }

        /** Cookie header for gemini.google.com - exactly what the browser sends. */
        val cookieHeader: String
            get() {
                val seen = HashSet<String>()
                return cookies.filter { it.isGoogle && it.name.isNotEmpty() && it.value.isNotEmpty() }
                    .filter { seen.add(it.name) }
                    .joinToString("; ") { "${it.name}=${it.value}" }
            }

        val summary: String
            get() {
                val auth = authCookies
                val authLabel = if (auth.isEmpty()) "NONE - session will fail" else auth.joinToString(", ")
                return "${cookies.size} cookies · ${googleCookies.size} google.com · auth: $authLabel"
            }

        companion object {
            /** `expirationDate` (float) -> `expires` (int, -1 = session). */
            fun normalize(raw: JSONArray): List<Cookie> {
                val out = ArrayList<Cookie>()
                for (i in 0 until raw.length()) {
                    val item = raw.optJSONObject(i) ?: continue
                    val name = item.optString("name").trim()
                    if (name.isEmpty()) continue
                    val value = item.optString("value")

                    var expires = -1
                    var e: Any? = if (item.has("expires")) item.opt("expires") else item.opt("expirationDate")
                    if (e is Number) expires = e.toDouble().toInt()
                    if (e is String) e.toDoubleOrNull()?.let { expires = it.toInt() }

                    var domain = item.optString("domain", "").trim()
                    if (domain.isEmpty()) domain = ".google.com"

                    var path = item.optString("path", "/")
                    if (path.isEmpty()) path = "/"

                    out.add(Cookie(name, value, domain, path, expires))
                }
                return out.groupBy { "${it.name}|${it.domain}|${it.path}" }
                    .values.map { it.last() }
            }

            /**
             * Accepts the same three formats: Playwright storageState
             * {"cookies":[...]}, a raw browser-extension array, or the array
             * nested under a common alternate key.
             */
            fun parse(rawIn: String): Session {
                val text = rawIn.trim()
                if (text.isEmpty()) throw GeminiWebException("Paste your Gemini web session JSON first.")
                var found: JSONArray? = null
                var format = ""
                val parsed = try {
                    JSONObject(text)
                } catch (_: Exception) {
                    try {
                        JSONArray(text)
                    } catch (_: Exception) {
                        throw GeminiWebException(
                            "Gemini session is not valid JSON. Expected either a " +
                                "Playwright storageState {\"cookies\":[...]} or a " +
                                "cookie-editor export array."
                        )
                    }
                }
                if (parsed is JSONObject) {
                    val direct = parsed.optJSONArray("cookies")
                    if (direct != null) {
                        found = direct
                        format = "Playwright storageState"
                    } else {
                        for (k in listOf("cookie", "Cookie", "cookieList", "cookieJar", "session")) {
                            val v = parsed.optJSONArray(k)
                            if (v != null && v.length() > 0) {
                                found = v
                                format = "nested key \"$k\""
                                break
                            }
                        }
                        if (found == null) {
                            val keys = parsed.keys()
                            while (keys.hasNext()) {
                                val v = parsed.opt(keys.next())
                                when (v) {
                                    is JSONObject -> {
                                        val c = v.optJSONArray("cookies")
                                        if (c != null && c.length() > 0) {
                                            found = c
                                            format = "nested storageState"
                                            break
                                        }
                                    }
                                    is JSONArray -> {
                                        if (v.length() > 0 && v.optJSONObject(0)?.has("name") == true) {
                                            found = v
                                            format = "nested cookie array"
                                            break
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else if (parsed is JSONArray && parsed.length() > 0 &&
                    parsed.optJSONObject(0)?.has("name") == true
                ) {
                    found = parsed
                    format = "browser-extension cookie array"
                }
                val cookies = found?.let { normalize(it) } ?: emptyList()
                if (cookies.isEmpty()) {
                    throw GeminiWebException(
                        "No cookies found in the Gemini session JSON. Re-export it " +
                            "from your browser (Playwright storageState or a " +
                            "cookie-editor export)."
                    )
                }
                if (cookies.none { it.isGoogle }) {
                    throw GeminiWebException(
                        "The session has no google.com cookies, so gemini.google.com " +
                            "cannot be restored. Export the cookies while " +
                            "gemini.google.com is open."
                    )
                }
                return Session(cookies, format)
            }
        }
    }

    /** Result of a session self-test. */
    data class TestResult(
        val ok: Boolean,
        val ms: Long,
        val message: String,
        val summary: String,
        val expired: Boolean = false,
    )

    /** Talks to gemini.google.com with a cookie session. */
    class Client(val session: Session) {

        private var at: String? = null // SNlM0e token
        private var bl: String = FALLBACK_BL
        private var cid: String? = null // conversation id
        private var rid: String? = null // response id
        private var rcid: String? = null // chosen candidate id
        private var reqid = 100000 + kotlin.random.Random.nextInt(800000)
        private var lastRaw = "" // last raw reply, scanned for artwork URLs

        val ready: Boolean get() = !at.isNullOrEmpty()

        private fun open(url: String, form: Boolean, readMs: Int): HttpURLConnection =
            (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = if (form) "POST" else "GET"
                connectTimeout = readMs
                readTimeout = readMs
                instanceFollowRedirects = true
                if (form) doOutput = true
                for ((k, v) in headers(form)) setRequestProperty(k, v)
            }

        private fun read(stream: java.io.InputStream): String =
            BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).use { it.readText() }

        private fun headers(form: Boolean): Map<String, String> = buildMap {
            put("User-Agent", USER_AGENT)
            put("Cookie", session.cookieHeader)
            put("Origin", "https://gemini.google.com")
            put("Referer", "https://gemini.google.com/")
            put("X-Same-Domain", "1")
            put("Accept-Language", "en-US,en;q=0.9")
            put("sec-ch-ua", "\"Chromium\";v=\"124\", \"Google Chrome\";v=\"124\", \"Not-A.Brand\";v=\"99\"")
            put("sec-ch-ua-mobile", "?0")
            put("sec-ch-ua-platform", "\"Windows\"")
            put("Sec-Fetch-Site", "same-origin")
            if (form) put("Content-Type", "application/x-www-form-urlencoded;charset=UTF-8")
        }

        private fun looksLoggedOut(url: String, body: String): Boolean {
            val u = url.lowercase()
            if (u.contains("accounts.google.com") || u.contains("servicelogin") ||
                u.contains("/signin") || u.contains("/login")
            ) return true
            val head = body.take(4000)
            return head.contains("ServiceLogin") && !head.contains("SNlM0e")
        }

        /** Loads gemini.google.com/app and picks up SNlM0e + the build id. */
        fun init(timeoutMs: Int = 45_000) {
            var code = 0
            var body = ""
            var finalUrl = ""
            try {
                val conn = open("https://gemini.google.com/app", form = false, readMs = timeoutMs)
                code = conn.responseCode
                finalUrl = conn.url.toString()
                body = read(
                    if (code in 200..299) conn.inputStream else conn.errorStream
                        ?: throw IOException("HTTP $code"),
                )
            } catch (e: java.net.SocketTimeoutException) {
                throw GeminiWebException("gemini.google.com did not respond within ${timeoutMs / 1000}s.")
            } catch (e: IOException) {
                throw GeminiWebException("Could not reach gemini.google.com: ${e.message}")
            }
            if (code == 401 || code == 403) {
                throw GeminiWebException(
                    "Gemini rejected the session (HTTP $code). Re-export fresh cookies.",
                    expired = true,
                )
            }
            if (code >= 400) throw GeminiWebException("gemini.google.com returned HTTP $code.")
            if (looksLoggedOut(finalUrl, body)) {
                throw GeminiWebException(
                    "The Gemini session is signed out (redirected to the Google " +
                        "login page). Re-export fresh cookies while gemini.google.com " +
                        "is open.",
                    expired = true,
                )
            }
            val token = Pattern.compile("\"SNlM0e\":\"(.*?)\"").matcher(body).let { m ->
                if (m.find()) m.group(1) else null
            }
            if (token.isNullOrEmpty()) {
                throw GeminiWebException(
                    "The Gemini session is expired or invalid (no auth token in the " +
                        "page). Re-export fresh cookies.",
                    expired = true,
                )
            }
            at = token
            val pb = Pattern.compile("\"cfb2h\":\"(.*?)\"").matcher(body)
            if (pb.find() && pb.group(1)?.isNotEmpty() == true) bl = pb.group(1)!!
            newChat()
        }

        /** Forget the conversation - the equivalent of opening /app/new. */
        fun newChat() {
            cid = null
            rid = null
            rcid = null
        }

        /**
         * Sends [prompt] and returns Gemini's answer text. When [completeWhen]
         * is given, the reply is only accepted once it matches - a partial
         * reply is retried instead of being parsed.
         */
        fun ask(
            prompt: String,
            completeWhen: Regex? = null,
            timeoutMs: Int = 120_000,
            attempts: Int = 3,
            freshChat: Boolean = true,
        ): String {
            if (!ready) init(timeoutMs)
            var lastErr: Any? = null
            for (i in 0 until attempts) {
                if (freshChat) newChat()
                try {
                    val text = send(prompt, timeoutMs)
                    when {
                        text.isBlank() -> lastErr = "Gemini web returned an empty reply."
                        completeWhen != null && !completeWhen.containsMatchIn(text) ->
                            lastErr = "Gemini web reply was cut off before the closing marker."
                        else -> return text.trim()
                    }
                } catch (e: GeminiWebException) {
                    lastErr = e.message
                    if (e.expired) {
                        at = null // one re-handshake: the token can rotate mid-run
                        if (i == attempts - 1) throw e
                        init(timeoutMs)
                    }
                } catch (e: java.net.SocketTimeoutException) {
                    lastErr = "Gemini web timed out after ${timeoutMs / 1000}s."
                } catch (e: Exception) {
                    lastErr = e.toString()
                }
                if (i < attempts - 1) Thread.sleep(2000L * (i + 1))
            }
            throw GeminiWebException("Gemini web failed after $attempts attempts. Last: $lastErr")
        }

        private fun send(prompt: String, timeoutMs: Int): String {
            val token = at ?: throw GeminiWebException("Gemini web session is not initialized.", expired = true)
            if (token.isEmpty()) throw GeminiWebException("Gemini web session is not initialized.", expired = true)
            lastRaw = ""
            val url = "https://gemini.google.com/_/BardChatUi/data/assistant.lamda." +
                "BardFrontendService/StreamGenerate" +
                "?bl=${URLEncoder.encode(bl, "UTF-8")}&_reqid=$reqid&rt=c"
            val inner = JSONArray()
                .put(JSONArray().put(prompt))
                .put(JSONObject.NULL)
                .put(JSONArray().put(cid).put(rid).put(rcid))
            val freq = JSONArray().put(JSONObject.NULL).put(inner)

            var code = 0
            var body = ""
            try {
                val conn = open(url, form = true, readMs = timeoutMs)
                conn.outputStream.use {
                    it.write(
                        "f.req=${URLEncoder.encode(freq.toString(), "UTF-8")}" +
                            "&at=${URLEncoder.encode(token, "UTF-8")}".toByteArray(Charsets.UTF_8),
                    )
                }
                code = conn.responseCode
                body = read(
                    if (code in 200..299) conn.inputStream else conn.errorStream
                        ?: throw IOException("HTTP $code"),
                )
            } catch (e: java.net.SocketTimeoutException) {
                throw GeminiWebException("Gemini web timed out after ${timeoutMs / 1000}s.")
            }
            reqid += 100000

            if (code == 401 || code == 403) {
                throw GeminiWebException(
                    "Gemini rejected the session (HTTP $code). Re-export fresh cookies.",
                    expired = true,
                )
            }
            if (code == 429) {
                throw GeminiWebException(
                    "Gemini web is rate limiting this account (HTTP 429). " +
                        "Wait a moment and retry.",
                )
            }
            if (code != 200) throw GeminiWebException("Gemini web HTTP $code.")
            lastRaw = body
            return parseStream(body)
        }

        /**
         * Asks the web app for an image and downloads the artwork it draws -
         * the reply carries the picture as a lh3.googleusercontent.com link
         * rather than base64, so the raw reply is scanned and the best image
         * is fetched. Text parsing failures are tolerated - artwork-only
         * replies sometimes confuse the text parser.
         */
        fun generateImage(
            prompt: String,
            timeoutMs: Int = 180_000,
            log: ((String) -> Unit)? = null,
        ): ByteArray {
            if (!ready) init()
            var lastErr = "unknown error"
            for (i in 0 until 3) {
                newChat()
                try {
                    send(prompt, timeoutMs)
                } catch (e: GeminiWebException) {
                    lastErr = e.message ?: "error"
                    if (e.expired) {
                        at = null // one re-handshake: the token can rotate mid-run
                        if (i == 2) throw e
                        init(timeoutMs)
                    }
                } catch (e: java.net.SocketTimeoutException) {
                    lastErr = "Gemini web timed out while generating the artwork."
                    continue
                }
                val raw = lastRaw
                    .replace("\\/", "/")
                    .replace("\\u003d", "=")
                    .replace("\\u0026", "&")
                for (m in ART_URLS.findAll(raw)) {
                    try {
                        val bytes = downloadArtwork(m.value)
                        if (bytes.size > 1024) {
                            log?.invoke("Fetching the cover artwork...")
                            return bytes
                        }
                    } catch (_: Exception) {
                        continue // try the next image in the reply
                    }
                }
                lastErr = "Gemini web returned no artwork in the reply."
                if (i < 2) Thread.sleep(3000)
            }
            throw GeminiWebException("Cover artwork failed after 3 attempts. Last: $lastErr")
        }

        private fun downloadArtwork(url: String): ByteArray {
            val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                setRequestProperty("User-Agent", USER_AGENT)
                connectTimeout = 60_000
                readTimeout = 60_000
            }
            if (conn.responseCode != 200) {
                throw GeminiWebException("Artwork download returned HTTP ${conn.responseCode}.")
            }
            return conn.inputStream.use { it.readBytes() }
        }

        /** Parses the `)]}'`-prefixed chunked batchexecute stream. */
        private fun parseStream(raw: String): String {
            val payloads = ArrayList<String>()
            for (line in raw.lineSequence()) {
                val t = line.trim()
                if (!t.startsWith("[")) continue
                val chunk = runCatching { JSONArray(t) }.getOrNull() ?: continue
                for (i in 0 until chunk.length()) {
                    val entry = chunk.optJSONArray(i) ?: continue
                    if (entry.length() > 2 && entry.optString(0) == "wrb.fr" && !entry.isNull(2)) {
                        val p = entry.optString(2)
                        if (p.isNotEmpty()) payloads.add(p)
                    }
                }
            }

            var best = ""
            for (payload in payloads) {
                val body = runCatching { JSONArray(payload) }.getOrNull() ?: continue
                val text = extractAnswer(body) ?: continue
                if (text.trim().length > best.trim().length) {
                    best = text
                    captureIds(body)
                }
            }

            if (best.isBlank()) {
                if (raw.contains("accounts.google.com") || raw.contains("ServiceLogin")) {
                    throw GeminiWebException(
                        "The Gemini session expired mid-run. Re-export fresh cookies.",
                        expired = true,
                    )
                }
                throw GeminiWebException(
                    "Gemini web returned no readable answer (the page layout or the " +
                        "session may have changed).",
                )
            }
            return best
        }

        private fun extractAnswer(body: JSONArray): String? {
            // Canonical shape: body[4][0][1][0]
            runCatching {
                val cands = body.getJSONArray(4)
                if (cands.length() > 0) {
                    val first = cands.getJSONArray(0)
                    if (first.length() > 1) {
                        val texts = first.getJSONArray(1)
                        if (texts.length() > 0) {
                            val t0 = texts.optString(0)
                            if (t0.isNotBlank()) return t0
                        }
                    }
                }
            }
            // Tolerant fallback: the longest substantial string in the payload.
            var longest = ""
            fun walk(n: Any) {
                when (n) {
                    is String -> if (n.length > longest.length) longest = n
                    is JSONArray -> for (i in 0 until n.length()) walk(n.get(i))
                    is JSONObject -> n.keys().forEachRemaining { walk(n.get(it)) }
                }
            }
            walk(body)
            return if (longest.trim().length >= 20) longest else null
        }

        private fun captureIds(body: JSONArray) {
            runCatching {
                val meta = body.getJSONArray(1)
                if (meta.length() > 1 && !meta.isNull(0) && !meta.isNull(1)) {
                    cid = meta.getString(0)
                    rid = meta.getString(1)
                }
                val cands = body.getJSONArray(4)
                if (cands.length() > 0) {
                    val first = cands.getJSONArray(0)
                    rcid = first.optString(0)
                }
            }
        }

        /** Handshake + one tiny prompt, for the Settings test button. */
        suspend fun test(): TestResult {
            val started = System.currentTimeMillis()
            return try {
                init()
                val reply = ask("Reply with the single word OK.", attempts = 2, timeoutMs = 90_000)
                val ms = System.currentTimeMillis() - started
                val snippet = reply.replace(Regex("\\s+"), " ").trim()
                TestResult(
                    ok = true,
                    ms = ms,
                    message = "Session alive - Gemini replied \"${snippet.take(60)}\"",
                    summary = session.summary,
                )
            } catch (e: GeminiWebException) {
                TestResult(
                    ok = false,
                    ms = System.currentTimeMillis() - started,
                    message = e.message ?: "Session test failed.",
                    summary = session.summary,
                    expired = e.expired,
                )
            } catch (e: Exception) {
                TestResult(
                    ok = false,
                    ms = System.currentTimeMillis() - started,
                    message = "Test failed: $e",
                    summary = session.summary,
                )
            }
        }

        fun close() = Unit
    }
}
