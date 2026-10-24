package com.sotizence.playbooks.browser.model

data class HistoryItem(
    val id: String = System.currentTimeMillis().toString(),
    val title: String,
    val url: String,
    val timestamp: Long = System.currentTimeMillis()
)
