package com.pcassistant.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * Foreground service for Bridge mode: polls the Firebase Realtime Database
 * wake node every 5 seconds and fires a Wake-on-LAN magic packet when the
 * controller has requested a wake. Runs on an old always-on phone at home.
 */
class WolBridgeService : Service() {

    @Volatile private var running = false
    private var worker: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification("Bridge running - waiting for a wake request"))
        if (!running) {
            running = true
            worker = Thread { pollLoop() }.apply { isDaemon = true; start() }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        worker?.interrupt()
        super.onDestroy()
    }

    private fun pollLoop() {
        while (running) {
            try { pollOnce() } catch (e: Exception) { /* keep polling */ }
            try { Thread.sleep(5000) } catch (e: InterruptedException) { break }
        }
    }

    private fun pollOnce() {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val db = prefs.getString("databaseUrl", "")?.trimEnd('/') ?: ""
        val code = prefs.getString("pairingCode", "") ?: ""
        if (db.isEmpty() || code.isEmpty()) return
        val wakeUrl = "$db/pcassistant/$code/wake.json"
        val text = httpGet(wakeUrl) ?: return
        if (text == "null") return
        val json = JSONObject(text)
        if (!json.optBoolean("requested", false)) return
        val mac = json.optString("mac", prefs.getString("pcMac", "") ?: "")
        val broadcast = json.optString("broadcast", prefs.getString("broadcastIp", "192.168.1.255") ?: "192.168.1.255")
        val ok = WakeOnLan.send(mac, broadcast)
        // Clear the flag so the packet is sent once per request.
        val clear = JSONObject()
        clear.put("requested", false)
        clear.put("mac", mac)
        clear.put("broadcast", broadcast)
        clear.put("lastWakeOk", ok)
        clear.put("ts", System.currentTimeMillis())
        httpPut(wakeUrl, clear.toString())
        updateNotification(if (ok) "Wake packet sent to $mac" else "Wake FAILED - check MAC address")
    }

    private fun httpGet(urlStr: String): String? {
        val conn = URL(urlStr).openConnection() as HttpURLConnection
        conn.requestMethod = "GET"
        conn.connectTimeout = 8000
        conn.readTimeout = 8000
        return try {
            if (conn.responseCode in 200..299) conn.inputStream.bufferedReader().readText() else null
        } finally { conn.disconnect() }
    }

    private fun httpPut(urlStr: String, body: String) {
        val conn = URL(urlStr).openConnection() as HttpURLConnection
        conn.requestMethod = "PUT"
        conn.doOutput = true
        conn.setRequestProperty("Content-Type", "application/json")
        conn.connectTimeout = 8000
        conn.readTimeout = 8000
        try {
            OutputStreamWriter(conn.outputStream).use { it.write(body) }
            conn.responseCode
        } finally { conn.disconnect() }
    }

    private fun buildNotification(text: String): Notification {
        val channelId = "wol_bridge"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(
                NotificationChannel(channelId, "PC Bridge", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        return builder
            .setContentTitle("PC Assistant Bridge")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }

    companion object {
        const val PREFS = "pc_assistant_bridge"
        const val NOTIFICATION_ID = 4201
    }
}
