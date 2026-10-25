package com.visabot.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * BootReceiver - Auto-starts the OTP forwarding service on device boot.
 * Only starts if the user had previously configured and enabled the service.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val prefs = context.getSharedPreferences("visabot_prefs", Context.MODE_PRIVATE)
        val serverUrl = prefs.getString("serverUrl", "") ?: ""
        val pairingCode = prefs.getString("pairingCode", "") ?: ""
        val autoStart = prefs.getBoolean("autoStart", false)

        if (autoStart && serverUrl.isNotEmpty() && pairingCode.isNotEmpty()) {
            val serviceIntent = Intent(context, OtpForwardingService::class.java).apply {
                putExtra("serverUrl", serverUrl)
                putExtra("pairingCode", pairingCode)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        }
    }
}
