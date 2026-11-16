package com.mynxsoft.mhmotion

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.StringReader
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val BG_CHANNEL = "com.mynxsoft.mhmotion/background"
    private val WG_CHANNEL = "com.mynxsoft.mhmotion/wireguard"
    private val VPN_REQ_CODE = 4401

    private var wgBackend: GoBackend? = null
    private var wgTunnel: Tunnel? = null
    private var pendingConf: String? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BG_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startKeepAlive" -> {
                    val intent = Intent(this, KeepAliveService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
                    else startService(intent)
                    result.success(true)
                }
                "notifyColabLive" -> {
                    val url = call.argument<String>("url") ?: "Colab Studio is live"
                    val chId = "mh_motion_alerts"
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val ch = NotificationChannel(chId, "Colab Live Alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                            enableVibration(true)
                        }
                        nm.createNotificationChannel(ch)
                    }
                    val pi = PendingIntent.getActivity(
                        this, 1, Intent(this, MainActivity::class.java),
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                    val notif = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, chId) else @Suppress("DEPRECATION") Notification.Builder(this))
                        .setContentTitle("Colab T4 Studio Live!")
                        .setContentText(url)
                        .setSmallIcon(R.mipmap.ic_launcher)
                        .setContentIntent(pi)
                        .setAutoCancel(true)
                        .build()
                    nm.notify(202, notif)
                    result.success(true)
                }
                "requestIgnoreBattery" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            })
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WG_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    val conf = call.argument<String>("config") ?: ""
                    if (conf.isBlank()) {
                        result.error("NO_CONF", "Empty WireGuard config", null)
                        return@setMethodCallHandler
                    }
                    val prep = VpnService.prepare(this)
                    if (prep != null) {
                        pendingConf = conf
                        pendingResult = result
                        startActivityForResult(prep, VPN_REQ_CODE)
                    } else {
                        startWgTunnel(conf, result)
                    }
                }
                "disconnect" -> {
                    thread {
                        try {
                            wgTunnel?.let { wgBackend?.setState(it, Tunnel.State.DOWN, null) }
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("WG_ERR", e.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startWgTunnel(confText: String, result: MethodChannel.Result) {
        thread {
            try {
                if (wgBackend == null) wgBackend = GoBackend(applicationContext)
                if (wgTunnel == null) {
                    wgTunnel = object : Tunnel {
                        override fun getName(): String = "mh_wg0"
                        override fun onStateChange(newState: Tunnel.State) {}
                    }
                }
                val cfg = Config.parse(BufferedReader(StringReader(confText)))
                wgBackend!!.setState(wgTunnel!!, Tunnel.State.UP, cfg)
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("WG_ERR", e.message ?: "WireGuard failed", null) }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQ_CODE) {
            val conf = pendingConf
            val res = pendingResult
            pendingConf = null
            pendingResult = null
            if (resultCode == Activity.RESULT_OK && conf != null && res != null) {
                startWgTunnel(conf, res)
            } else {
                res?.error("VPN_DENIED", "VPN permission denied by user", null)
            }
        }
    }
}
