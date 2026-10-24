package com.sotizence.playbooks.browser

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.sotizence.playbooks.browser.model.HistoryItem

class HistoryManager(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("sotizence_history_prefs", Context.MODE_PRIVATE)
    private val gson = Gson()
    private val keyHistory = "history_list"
    private val maxHistorySize = 500

    fun getHistory(): MutableList<HistoryItem> {
        val json = prefs.getString(keyHistory, null) ?: return mutableListOf()
        val type = object : TypeToken<MutableList<HistoryItem>>() {}.type
        return try {
            gson.fromJson(json, type) ?: mutableListOf()
        } catch (e: Exception) {
            mutableListOf()
        }
    }

    fun addHistory(url: String, title: String) {
        if (url.isBlank() || url.startsWith("file://") || url.startsWith("about:")) return
        val list = getHistory()
        // Remove existing duplicate to bring to top
        list.removeAll { it.url.equals(url, ignoreCase = true) }
        val displayTitle = if (title.isBlank()) url else title
        list.add(0, HistoryItem(title = displayTitle, url = url))
        if (list.size > maxHistorySize) {
            list.subList(maxHistorySize, list.size).clear()
        }
        saveHistory(list)
    }

    fun removeHistory(id: String) {
        val list = getHistory()
        list.removeAll { it.id == id }
        saveHistory(list)
    }

    fun clearHistory() {
        prefs.edit().remove(keyHistory).apply()
    }

    private fun saveHistory(list: List<HistoryItem>) {
        prefs.edit().putString(keyHistory, gson.toJson(list)).apply()
    }
}
