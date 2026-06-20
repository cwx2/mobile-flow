package com.mobileflow.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Foreground Service that keeps the Flutter isolate alive when the app
 * is in the background. Displays a persistent notification whose content
 * can be dynamically updated from Dart via MethodChannel.
 *
 * Holds a PARTIAL_WAKE_LOCK to prevent CPU sleep, ensuring that Dart
 * timers (heartbeat pings) continue to fire in background. The wake lock
 * auto-releases after 30 minutes as a safety net against battery drain.
 *
 * Notification states:
 *   - Connected (idle):  "MobileFlow · 已连接"
 *   - AI streaming:      "✨ AI 正在回复..." + scrolling text preview
 *   - Completed:         "✅ 回复完成"  (auto-reverts to idle after 3s)
 */
class KeepAliveService : Service() {

    companion object {
        const val CHANNEL_ID = "mobileflow_keepalive"
        const val NOTIFICATION_ID = 1001

        const val ACTION_UPDATE = "com.mobileflow.app.UPDATE_NOTIFICATION"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_TICKER = "ticker"

        /** Maximum wake lock hold time (30 minutes). Safety net to prevent
         *  indefinite battery drain if the service is never stopped. */
        private const val WAKE_LOCK_TIMEOUT_MS = 30L * 60 * 1000

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

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "MobileFlow"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "已连接"
        val ticker = intent?.getStringExtra(EXTRA_TICKER)

        if (intent?.action == ACTION_UPDATE) {
            // Just update the notification, service is already running
            updateNotification(title, text, ticker)
        } else {
            // Initial start — promote to foreground
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
            // Acquire partial wake lock to prevent CPU sleep.
            // This ensures Dart isolate timers (heartbeat) keep firing
            // even when the screen is off or the app is in background.
            acquireWakeLock()
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(NOTIFICATION_ID)
    }

    private fun acquireWakeLock() {
        if (wakeLock != null) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "MobileFlow::KeepAlive"
        ).apply {
            // Timeout prevents indefinite hold if service isn't stopped
            acquire(WAKE_LOCK_TIMEOUT_MS)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

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
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(pendingIntent)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .apply { if (ticker != null) setTicker(ticker) }
            .build()
    }

    private fun updateNotification(title: String, text: String, ticker: String?) {
        val notification = buildNotification(title, text, ticker)
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, notification)
    }
}
