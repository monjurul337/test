package com.sotizence.playbooks.browser

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.sotizence.playbooks.browser.model.Bookmark

class BookmarkManager(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("sotizence_browser_prefs", Context.MODE_PRIVATE)
    private val gson = Gson()
    private val keyBookmarks = "bookmarks_list"

    fun getBookmarks(): MutableList<Bookmark> {
        val json = prefs.getString(keyBookmarks, null) ?: return mutableListOf()
        val type = object : TypeToken<MutableList<Bookmark>>() {}.type
        return try {
            gson.fromJson(json, type) ?: mutableListOf()
        } catch (e: Exception) {
            mutableListOf()
        }
    }

    fun isBookmarked(url: String): Boolean {
        if (url.startsWith("file://") || url.isBlank()) return false
        return getBookmarks().any { it.url.equals(url, ignoreCase = true) }
    }

    fun toggleBookmark(url: String, title: String): Boolean {
        if (url.startsWith("file://") || url.isBlank()) return false
        val list = getBookmarks()
        val existingIndex = list.indexOfFirst { it.url.equals(url, ignoreCase = true) }
        val added: Boolean
        if (existingIndex >= 0) {
            list.removeAt(existingIndex)
            added = false
        } else {
            val displayTitle = if (title.isBlank()) url else title
            list.add(0, Bookmark(title = displayTitle, url = url))
            added = true
        }
        saveBookmarks(list)
        return added
    }

    fun removeBookmark(id: String) {
        val list = getBookmarks()
        list.removeAll { it.id == id }
        saveBookmarks(list)
    }

    private fun saveBookmarks(list: List<Bookmark>) {
        prefs.edit().putString(keyBookmarks, gson.toJson(list)).apply()
    }
}
