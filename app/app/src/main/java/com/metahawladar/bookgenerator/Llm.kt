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

/** The two back ends the app can write with. */
object Providers {
    const val GEMINI = "gemini"
    const val NVIDIA = "nvidia"

    val ALL = listOf(GEMINI, NVIDIA)

    fun label(p: String): String =
        if (p == NVIDIA) "NVIDIA (build.nvidia.com)" else "Gemini (cookie session)"

    fun keyHome(p: String): String =
        if (p == NVIDIA) "build.nvidia.com" else "gemini.google.com"

    fun models(p: String): List<String> =
        if (p == NVIDIA) Nvidia.MODELS else listOf("gemini-web (cookie)")

    fun defaultModel(p: String): String = models(p)[0]

    /** Keeps a saved model valid when the provider changes. */
    fun fixModel(p: String, model: String): String =
        if (models(p).contains(model)) model else defaultModel(p)

    /** Builds the right client from a blob of pasted keys. */
    fun client(provider: String, keys: String, model: String): LlmClient =
        if (provider == NVIDIA) Nvidia(keys, model) else GeminiWeb(keys)
}
