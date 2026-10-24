package com.sotizence.playbooks.browser

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.sotizence.playbooks.browser.model.ProfileItem

class ProfileManager(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("sotizence_profiles_prefs", Context.MODE_PRIVATE)
    private val gson = Gson()
    private val keyProfiles = "profiles_list"
    private val keyActiveProfile = "active_profile_id"

    fun getProfiles(): MutableList<ProfileItem> {
        val json = prefs.getString(keyProfiles, null)
        if (json.isNullOrBlank()) {
            val defaultList = mutableListOf(
                ProfileItem("default", "Default Profile", "#6366F1"),
                ProfileItem("work", "Work Profile", "#06B6D4")
            )
            saveProfiles(defaultList)
            return defaultList
        }
        val type = object : TypeToken<MutableList<ProfileItem>>() {}.type
        return try {
            gson.fromJson(json, type) ?: mutableListOf()
        } catch (e: Exception) {
            mutableListOf(ProfileItem("default", "Default Profile", "#6366F1"))
        }
    }

    fun getActiveProfile(): ProfileItem {
        val id = prefs.getString(keyActiveProfile, "default") ?: "default"
        return getProfiles().find { it.id == id } ?: getProfiles().firstOrNull() ?: ProfileItem()
    }

    fun setActiveProfile(id: String) {
        prefs.edit().putString(keyActiveProfile, id).apply()
    }

    fun addProfile(name: String, color: String): ProfileItem {
        val id = "profile_" + System.currentTimeMillis()
        val item = ProfileItem(id, name, color)
        val list = getProfiles()
        list.add(item)
        saveProfiles(list)
        return item
    }

    fun deleteProfile(id: String) {
        if (id == "default") return // Do not delete default
        val list = getProfiles()
        list.removeAll { it.id == id }
        saveProfiles(list)
        if (getActiveProfile().id == id) {
            setActiveProfile("default")
        }
    }

    private fun saveProfiles(list: List<ProfileItem>) {
        prefs.edit().putString(keyProfiles, gson.toJson(list)).apply()
    }
}
