package com.visabot.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import okio.ByteString
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * OtpForwardingService - Foreground Service
 *
 * Maintains a persistent WebSocket connection to the backend server.
 * When an OTP is received via SmsReceiver, it forwards it in real-time.
 * Falls back to REST POST if WebSocket is unavailable.
 */
class OtpForwardingService : Service() {

    companion object {
        private const val TAG = "OtpForwardingService"
        const val ACTION_FORWARD_OTP = "com.visabot.app.FORWARD_OTP"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "visabot_service"
        private const val CHANNEL_NAME = "IVAC Visa Bot Service"
        private const val MAX_RECONNECT_ATTEMPTS = 10
    }

    // ─── State ─────────────────────────────────────────────────────────────────
    private var serverUrl = ""
    private var pairingCode = ""
    private var webSocket: WebSocket? = null
    private var isConnected = false
    private var reconnectAttempts = 0
    private val pendingOtps = mutableListOf<Triple<String, String, String>>() // otp, rawMsg, sender

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private lateinit var prefs: android.content.SharedPreferences

    private val okHttpClient by lazy {
        OkHttpClient.Builder()
            .pingInterval(25, TimeUnit.SECONDS)
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .build()
    }

    // ─── Lifecycle ─────────────────────────────────────────────────────────────
    override fun onCreate() {
        super.onCreate()
        prefs = getSharedPreferences("visabot_prefs", MODE_PRIVATE)
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Connecting..."))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_FORWARD_OTP -> {
                val otp = intent.getStringExtra("otp") ?: return START_STICKY
                val rawMsg = intent.getStringExtra("rawMessage") ?: ""
                val sender = intent.getStringExtra("sender") ?: "UNKNOWN"
                Log.i(TAG, "Forward OTP request: $otp")
                forwardOtp(otp, rawMsg, sender)
            }
            else -> {
                // Service started normally — connect WebSocket
                serverUrl = intent?.getStringExtra("serverUrl")
                    ?: prefs.getString("serverUrl", "http://localhost:3000") ?: ""
                pairingCode = intent?.getStringExtra("pairingCode")
                    ?: prefs.getString("pairingCode", "") ?: ""

                // Save for reconnects
                prefs.edit()
                    .putString("serverUrl", serverUrl)
                    .putString("pairingCode", pairingCode)
                    .apply()

                connectWebSocket()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
        webSocket?.close(1000, "Service stopped")
        webSocket = null
        Log.i(TAG, "Service destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ─── WebSocket connection ──────────────────────────────────────────────────
    private fun connectWebSocket() {
        if (serverUrl.isEmpty() || pairingCode.isEmpty()) {
            Log.w(TAG, "No server URL or pairing code configured")
            updateNotification("Not configured. Open the app to set up.")
            return
        }

        val wsUrl = serverUrl.replace(Regex("^http"), "ws") + "/ws"
        Log.i(TAG, "Connecting to: $wsUrl")
        updateNotification("Connecting to server...")

        val request = Request.Builder().url(wsUrl).build()
        webSocket = okHttpClient.newWebSocket(request, object : WebSocketListener() {

            override fun onOpen(ws: WebSocket, response: Response) {
                Log.i(TAG, "WebSocket connected")
                isConnected = true
                reconnectAttempts = 0
                // Authenticate as Android client
                ws.send(JSONObject().apply {
                    put("type", "android_connect")
                    put("pairingCode", pairingCode)
                }.toString())
                updateNotification("Connected | Code: $pairingCode")

                // Flush pending OTPs
                synchronized(pendingOtps) {
                    pendingOtps.forEach { (otp, rawMsg, sender) ->
                        sendOtpViaWs(otp, rawMsg, sender)
                    }
                    pendingOtps.clear()
                }
            }

            override fun onMessage(ws: WebSocket, text: String) {
                Log.d(TAG, "WS message: $text")
                try {
                    val json = JSONObject(text)
                    when (json.optString("type")) {
                        "connected" -> Log.i(TAG, "Android authenticated with session: ${json.optString("sessionId")}")
                        "otp_ack"   -> Log.i(TAG, "OTP acknowledged: ${json.optString("otp")}")
                        "pong"      -> {}
                        "error"     -> Log.e(TAG, "Server error: ${json.optString("error")}")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Message parse error: ${e.message}")
                }
            }

            override fun onMessage(ws: WebSocket, bytes: ByteString) { /* not used */ }

            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "WebSocket failure: ${t.message}")
                isConnected = false
                webSocket = null
                updateNotification("Disconnected. Reconnecting...")
                scheduleReconnect()
            }

            override fun onClosed(ws: WebSocket, code: Int, reason: String) {
                Log.i(TAG, "WebSocket closed: $code $reason")
                isConnected = false
                webSocket = null
                if (code != 1000) { // Not a normal close
                    scheduleReconnect()
                } else {
                    updateNotification("Disconnected")
                }
            }
        })
    }

    private fun scheduleReconnect() {
        if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
            Log.e(TAG, "Max reconnect attempts reached")
            updateNotification("Connection failed. Open app to retry.")
            return
        }
        val delay = minOf(2000L * (1L shl reconnectAttempts), 30000L)
        reconnectAttempts++
        Log.i(TAG, "Reconnecting in ${delay}ms (attempt $reconnectAttempts)")
        serviceScope.launch {
            delay(delay)
            connectWebSocket()
        }
    }

    // ─── OTP forwarding ───────────────────────────────────────────────────────
    private fun forwardOtp(otp: String, rawMessage: String, sender: String) {
        // Show OTP notification
        showOtpNotification(otp, sender)

        if (isConnected && webSocket != null) {
            sendOtpViaWs(otp, rawMessage, sender)
        } else {
            // Buffer for when WS reconnects
            synchronized(pendingOtps) {
                pendingOtps.add(Triple(otp, rawMessage, sender))
            }
            // Also try REST fallback
            serviceScope.launch {
                sendOtpViaRest(otp, rawMessage, sender)
            }
        }
    }

    private fun sendOtpViaWs(otp: String, rawMessage: String, sender: String) {
        val payload = JSONObject().apply {
            put("type", "otp")
            put("otp", otp)
            put("rawMessage", rawMessage)
            put("sender", sender)
        }.toString()
        val success = webSocket?.send(payload) ?: false
        Log.i(TAG, "OTP sent via WebSocket: $otp (success: $success)")
    }

    private suspend fun sendOtpViaRest(otp: String, rawMessage: String, sender: String) {
        try {
            val baseUrl = serverUrl.trimEnd('/')
            val body = JSONObject().apply {
                put("pairingCode", pairingCode)
                put("otp", otp)
                put("rawMessage", rawMessage)
                put("sender", sender)
            }.toString()

            val mediaType = "application/json; charset=utf-8".toMediaTypeOrNull()
            val requestBody = body.toRequestBody(mediaType)
            val request = Request.Builder()
                .url("$baseUrl/api/otp")
                .post(requestBody)
                .build()

            val response = okHttpClient.newCall(request).execute()
            Log.i(TAG, "OTP sent via REST: ${response.code}")
            response.close()
        } catch (e: Exception) {
            Log.e(TAG, "REST fallback failed: ${e.message}")
        }
    }

    // ─── Notifications ────────────────────────────────────────────────────────
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW).apply {
                description = "IVAC Visa Bot OTP forwarding service"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(status: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("IVAC Visa Bot")
            .setContentText(status)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pi)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun updateNotification(status: String) {
        getSystemService(NotificationManager::class.java)
            ?.notify(NOTIFICATION_ID, buildNotification(status))
    }

    private fun showOtpNotification(otp: String, sender: String) {
        val intent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("OTP Forwarded: $otp")
            .setContentText("From: $sender — Sent to Chrome Extension")
            .setSmallIcon(android.R.drawable.ic_menu_send)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID + 1, notification)
    }
}
