package com.mobileflow.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Main activity with a MethodChannel bridge for the native
 * Foreground Service. Dart calls start/update/stop/requestPermission
 * through the "com.mobileflow.app/keepalive" channel.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.mobileflow.app/keepalive"
        private const val NOTIFICATION_PERMISSION_CODE = 1001
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val title = call.argument<String>("title") ?: "MobileFlow"
                val text = call.argument<String>("text") ?: "已连接"

                when (call.method) {
                    "requestPermission" -> {
                        // Android 13+ requires POST_NOTIFICATIONS runtime permission
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            if (ContextCompat.checkSelfPermission(this,
                                    Manifest.permission.POST_NOTIFICATIONS)
                                == PackageManager.PERMISSION_GRANTED) {
                                result.success(true)
                            } else {
                                pendingPermissionResult = result
                                ActivityCompat.requestPermissions(this,
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    NOTIFICATION_PERMISSION_CODE)
                            }
                        } else {
                            // Pre-Android 13: no runtime permission needed
                            result.success(true)
                        }
                    }
                    "start" -> {
                        KeepAliveService.start(this, title, text)
                        result.success(null)
                    }
                    "update" -> {
                        val ticker = call.argument<String>("ticker")
                        val streaming = call.argument<Boolean>("streaming") ?: false
                        if (streaming) {
                            // During streaming, use the streaming-aware update
                            val intent = Intent(this, KeepAliveService::class.java).apply {
                                action = KeepAliveService.ACTION_UPDATE
                                putExtra(KeepAliveService.EXTRA_TITLE, title)
                                putExtra(KeepAliveService.EXTRA_TEXT, text)
                                putExtra(KeepAliveService.EXTRA_STREAMING, true)
                                if (ticker != null) putExtra(KeepAliveService.EXTRA_TICKER, ticker)
                            }
                            startService(intent)
                        } else {
                            KeepAliveService.update(this, title, text, ticker)
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        KeepAliveService.stop(this)
                        result.success(null)
                    }
                    "openNotificationSettings" -> {
                        val intent = Intent().apply {
                            action = android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS
                            putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_CODE) {
            val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }
}
