package com.sotizence.playbooks.browser

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.sotizence.playbooks.browser.model.AppSettings

class SettingsManager(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("sotizence_settings_prefs", Context.MODE_PRIVATE)
    private val gson = Gson()
    private val keySettings = "app_settings"

    fun getSettings(): AppSettings {
        val json = prefs.getString(keySettings, null) ?: return AppSettings()
        return try {
            gson.fromJson(json, AppSettings::class.java) ?: AppSettings()
        } catch (e: Exception) {
            AppSettings()
        }
    }

    fun saveSettings(settings: AppSettings) {
        prefs.edit().putString(keySettings, gson.toJson(settings)).apply()
    }

    fun getSearchUrl(query: String): String {
        val trimmed = query.trim()
        val engine = getSettings().searchEngine
        val encoded = android.net.Uri.encode(trimmed)
        return when (engine.lowercase()) {
            "duckduckgo" -> "https://duckduckgo.com/?q=$encoded"
            "bing" -> "https://www.bing.com/search?q=$encoded"
            else -> "https://www.google.com/search?q=$encoded"
        }
    }
}
