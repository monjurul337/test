package com.softizence.browser.net

import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Asks a neutral echo endpoint what IP it sees. Because the socket is created *after*
 * the tunnel is up, the answer is the exit IP - which is exactly the proof the UI shows.
 *
 * Endpoints are tried in order; the first that answers wins. All are plain-text/JSON and
 * none of them is the VPN vendor, so the result is independent verification.
 */
class KtorPublicIpResolver(
    private val client: HttpClient,
    private val endpoints: List<String> = listOf(
        "https://api.ipify.org?format=json",
        "https://ifconfig.co/json",
        "https://ipinfo.io/json",
    ),
) : PublicIpResolver {

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    private val _current = MutableStateFlow<String?>(null)
    override val current: StateFlow<String?> = _current.asStateFlow()

    private val _country = MutableStateFlow<String?>(null)
    val country: StateFlow<String?> = _country.asStateFlow()

    override suspend fun resolve(): String? {
        for (url in endpoints) {
            val body = withTimeoutOrNull(TIMEOUT_MS) {
                runCatching { client.get(url).bodyAsText() }.getOrNull()
            } ?: continue

            val obj = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull() ?: continue
            val ip = listOf("ip", "query", "address")
                .firstNotNullOfOrNull { obj[it]?.jsonPrimitive?.contentOrNullSafe() }
                ?: continue

            _current.value = ip
            _country.value = listOf("country", "country_code", "countryCode")
                .firstNotNullOfOrNull { obj[it]?.jsonPrimitive?.contentOrNullSafe() }
            return ip
        }
        return null
    }

    fun invalidate() {
        _current.value = null
        _country.value = null
    }

    private fun kotlinx.serialization.json.JsonPrimitive.contentOrNullSafe(): String? =
        runCatching { content }.getOrNull()?.takeIf { it.isNotBlank() && it != "null" }

    private companion object { const val TIMEOUT_MS = 6_000L }
}
