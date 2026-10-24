package com.sotizence.playbooks.browser.model

data class Bookmark(
    val id: String = System.currentTimeMillis().toString(),
    val title: String,
    val url: String,
    val timestamp: Long = System.currentTimeMillis()
)
