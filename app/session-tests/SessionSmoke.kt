package com.metahawladar.bookgenerator

import org.json.JSONArray
import org.json.JSONObject

fun main() {
    val cookies = JSONArray()
        .put(JSONObject().put("name", "__Secure-1PSID").put("value", "dummy-only").put("domain", ".google.com"))
        .put(JSONObject().put("name", "badHost").put("value", "excluded").put("domain", "notgoogle.com"))
        .put(JSONObject().put("name", "expired").put("value", "excluded").put("domain", ".google.com").put("expires", 1))
        .put(JSONObject().put("name", "badPath").put("value", "excluded").put("domain", ".google.com").put("path", "/other"))
        .put(JSONObject().put("name", "injected").put("value", "bad\r\nCookie: nope").put("domain", ".google.com"))
    for (input in listOf(cookies, JSONObject().put("cookies", cookies), JSONObject().put("session", cookies), JSONObject().put("nested", JSONObject().put("cookies", cookies)))) {
        check(GeminiWebSession.parse(input.toString()).cookieHeader() == "__Secure-1PSID=dummy-only")
    }
    for (input in listOf("", "{}", "[]", "not json")) {
        check(runCatching { GeminiWebSession.parse(input) }.isFailure)
    }
    check(Providers.client(Providers.GEMINI, cookies.toString(), "ignored") is GeminiWeb)
    check(Providers.fixModel(Providers.GEMINI, "gemini-flash-latest") == "gemini-web (cookie)")
    val client = GeminiWeb(cookies.toString())
    val method = client.javaClass.getDeclaredMethod("parseStream", String::class.java).apply { isAccessible = true }
    val payload = JSONArray().put(JSONObject.NULL).put(JSONObject.NULL).put(JSONObject.NULL).put(JSONObject.NULL)
        .put(JSONArray().put(JSONArray().put("candidate").put(JSONArray().put("A complete answer."))))
    val stream = ")]}'\n123\n" + JSONArray().put(JSONArray().put("wrb.fr").put(JSONObject.NULL).put(payload.toString())).toString()
    check(method.invoke(client, stream) == "A complete answer.")
    check(runCatching { method.invoke(client, "[[\"metadata-only\"]]") }.isFailure)
    check(ImageGen.modelsFor(Providers.GEMINI) == listOf("off", "gemini-web-image"))
    println("PASS: Kotlin session formats, cookie scope/expiry/injection filtering, invalid input, provider routing and model migration. No live request made.")
}
