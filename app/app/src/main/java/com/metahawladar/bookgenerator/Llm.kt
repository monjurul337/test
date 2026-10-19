package com.metahawladar.bookgenerator

import org.json.JSONObject

/** What the writer talks to. Both providers expose the same two calls. */
interface LlmClient {
    suspend fun generate(
        prompt: String,
        system: String? = null,
        temperature: Double = 0.9,
        maxTokens: Int = 8192,
        asJson: Boolean = false,
        thinking: Int = 0,
        retries: Int = 5,
        log: ((String) -> Unit)? = null,
    ): String

    suspend fun generateJson(
        prompt: String,
        system: String? = null,
        temperature: Double = 0.9,
        maxTokens: Int = 16384,
        thinking: Int = 0,
        log: ((String) -> Unit)? = null,
    ): JSONObject
}

/** The back ends the app can write with. */
object Providers {
    const val GEMINI = "gemini"
    const val NVIDIA = "nvidia"
    const val WEB = "gemini-web"

    val ALL = listOf(GEMINI, NVIDIA, WEB)

    fun label(p: String): String = when (p) {
        NVIDIA -> "NVIDIA (build.nvidia.com)"
        WEB -> "Gemini Web (cookie session)"
        else -> "Google Gemini"
    }

    fun keyHome(p: String): String = when (p) {
        NVIDIA -> "build.nvidia.com"
        WEB -> "gemini.google.com - export the session JSON"
        else -> "aistudio.google.com/apikey"
    }

    fun models(p: String): List<String> =
        if (p == NVIDIA) Nvidia.MODELS else Gemini.MODELS

    fun defaultModel(p: String): String = models(p)[0]

    /** Keeps a saved model valid when the provider changes. */
    fun fixModel(p: String, model: String): String =
        if (models(p).contains(model)) model else defaultModel(p)

    /** Builds the right client. [keys] is the key blob, or the exported
     *  Gemini web session JSON for the cookie provider. */
    fun client(provider: String, keys: String, model: String): LlmClient = when (provider) {
        NVIDIA -> Nvidia(keys, model)
        WEB -> GeminiWeb(keys)
        else -> Gemini(keys, model)
    }
}
