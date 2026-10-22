package com.softizence.browser.net

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.VpnService
import android.os.Build
import androidx.core.app.NotificationCompat
import com.wireguard.android.backend.GoBackend

/**
 * The TUN owner. wireguard-go (via [GoBackend]) performs the crypto; this service exists
 * so Android grants us a file descriptor and keeps the process alive.
 *
 * Kill-switch note: `setBlocking(true)` plus an `AllowedIPs = 0.0.0.0/0` route means that
 * when the tunnel is not established the packets have nowhere to go - they are dropped,
 * not re-routed over Wi-Fi. That is the behaviour the product promises.
 */
class SoftizenceVpnService : VpnService() {

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIFICATION_ID, buildNotification())
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onRevoke() {
        // The user (or another VPN app) pulled the rug: tear down rather than leak.
        AndroidTunnelController.activeInstance?.onRevokedBySystem()
        stopSelf()
        super.onRevoke()
    }

    /** Builder pre-configured for a full tunnel with no bypass. */
    fun protectedBuilder(): Builder = Builder()
        .setSession("Softizence")
        .setBlocking(true)
        .allowFamily(android.system.OsConstants.AF_INET)
        .allowFamily(android.system.OsConstants.AF_INET6)

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Tunnel status", NotificationManager.IMPORTANCE_LOW),
                )
            }
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Softizence tunnel")
            .setContentText("All browser traffic is routed through WireGuard")
            .setSmallIcon(com.softizence.browser.R.drawable.ic_tunnel)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    companion object {
        const val CHANNEL_ID = "softizence.tunnel"
        const val NOTIFICATION_ID = 0x5F2

        @Volatile
        var instance: SoftizenceVpnService? = null
            private set
    }
}
