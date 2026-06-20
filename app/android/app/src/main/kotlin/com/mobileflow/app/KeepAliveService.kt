package com.mobileflow.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.app.NotificationCompat

/**
 * Foreground Service that keeps the Flutter isolate and WebSocket alive
 * when the app is in the background.
 *
 * Key features:
 *   - PARTIAL_WAKE_LOCK: prevents CPU sleep (auto-renews, no timeout)
 *   - WIFI_LOCK: prevents WiFi from being turned off in sleep mode
 *   - Notification action button: "Disconnect" to stop service from tray
 *   - Chronometer: shows elapsed connection time
 *   - Proper monochrome small icon (not mipmap)
 *   - Brand color for notification accent
 *   - START_STICKY with null-intent recovery
 *
 * Notification states:
 *   - Connected (idle):  "已连接 · 编程助手运行中" + chronometer
 *   - AI streaming:      "✨ AI 正在回复..." + text preview
 *   - Completed:         "✅ 回复完成"  (auto-reverts to idle)
 */
class KeepAliveService : Service() {

    companion object {
        const val CHANNEL_ID = "mobileflow_keepalive"
        const val NOTIFICATION_ID = 1001

        const val ACTION_UPDATE = "com.mobileflow.app.UPDATE_NOTIFICATION"
        const val ACTION_DISCONNECT = "com.mobileflow.app.DISCONNECT"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_TICKER = "ticker"
        const val EXTRA_STREAMING = "streaming"

        /** Brand color (MobileFlow blue) for notification accent. */
        private const val BRAND_COLOR = 0xFF2196F3.toInt()

        /** Start the service with an initial notification. */
        fun start(context: Context, title: String, text: String) {
            val intent = Intent(context, KeepAliveService::class.java).apply {
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /** Update the notification content without restarting the service. */
        fun update(context: Context, title: String, text: String, ticker: String? = null) {
            val intent = Intent(context, KeepAliveService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
                putExtra(EXTRA_STREAMING, true)
                if (ticker != null) putExtra(EXTRA_TICKER, ticker)
            }
            context.startService(intent)
        }

        /** Stop the service and remove the notification. */
        fun stop(context: Context) {
            context.stopService(Intent(context, KeepAliveService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var connectionStartTime: Long = 0L
    private var isStreaming: Boolean = false

    /** Receiver for the "Disconnect" action button in the notification. */
    private val disconnectReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            stopSelf()
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                disconnectReceiver,
                IntentFilter(ACTION_DISCONNECT),
                RECEIVER_NOT_EXPORTED
            )
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(disconnectReceiver, IntentFilter(ACTION_DISCONNECT))
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // START_STICKY: system may restart us with null intent after kill
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "MobileFlow"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "已连接"
        val ticker = intent?.getStringExtra(EXTRA_TICKER)
        isStreaming = intent?.getBooleanExtra(EXTRA_STREAMING, false) ?: false

        if (intent?.action == ACTION_UPDATE) {
            updateNotification(title, text, ticker)
        } else {
            // Initial start or restart after kill — promote to foreground
            connectionStartTime = SystemClock.elapsedRealtime()
            val notification = buildNotification(title, text, ticker)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            acquireWakeLock()
            acquireWifiLock()
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        releaseWakeLock()
        releaseWifiLock()
        try { unregisterReceiver(disconnectReceiver) } catch (_: Exception) {}
        super.onDestroy()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(NOTIFICATION_ID)
    }

    // ── Wake Lock (CPU) ──

    private fun acquireWakeLock() {
        if (wakeLock != null) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "MobileFlow::KeepAlive"
        ).apply {
            // No timeout — held until service is stopped.
            // Service lifecycle (stop on disconnect) is the release mechanism.
            acquire()
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    // ── WiFi Lock ──

    private fun acquireWifiLock() {
        if (wifiLock != null) return
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        wifiLock = wm.createWifiLock(
            WifiManager.WIFI_MODE_FULL_HIGH_PERF,
            "MobileFlow::WifiKeepAlive"
        ).apply {
            acquire()
        }
    }

    private fun releaseWifiLock() {
        wifiLock?.let { if (it.isHeld) it.release() }
        wifiLock = null
    }

    // ── Notification ──

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "MobileFlow 连接保活",
                NotificationManager.IMPORTANCE_LOW  // No sound, no popup
            ).apply {
                description = "保持与桌面 Agent 的连接"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String, text: String, ticker: String?): Notification {
        // Tap notification → open the app
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // "Disconnect" action button
        val disconnectIntent = PendingIntent.getBroadcast(
            this, 1,
            Intent(ACTION_DISCONNECT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_notification)
            .setColor(BRAND_COLOR)
            .setColorized(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(contentIntent)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .addAction(
                R.drawable.ic_stat_notification,
                "断开连接",
                disconnectIntent
            )

        // Show elapsed time when connected (not during streaming)
        if (!isStreaming && connectionStartTime > 0) {
            builder.setUsesChronometer(true)
            builder.setWhen(System.currentTimeMillis() -
                (SystemClock.elapsedRealtime() - connectionStartTime))
        }

        if (ticker != null) builder.setTicker(ticker)

        return builder.build()
    }

    private fun updateNotification(title: String, text: String, ticker: String?) {
        val notification = buildNotification(title, text, ticker)
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, notification)
    }
}
