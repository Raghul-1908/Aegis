package com.example.aegis

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val EVENT_CHANNEL = "aegis/notifications"
    private val METHOD_CHANNEL = "aegis/permissions"
    private val REQUEST_POST_NOTIFICATIONS = 1001
    private var permissionResult: MethodChannel.Result? = null

    override fun onDestroy() {
        NotificationListener.eventSink = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_POST_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            permissionResult?.success(granted)
            permissionResult = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    NotificationListener.eventSink = events
                    NotificationListener.onUiAttached()
                }
                override fun onCancel(args: Any?) {
                    NotificationListener.eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "registerBackgroundCallback" -> {
                        val handle = call.argument<Number>("handle")?.toLong()
                        if (handle != null && handle > 0L) {
                            getSharedPreferences("aegis_bg_prefs", MODE_PRIVATE)
                                .edit()
                                .putLong("callback_handle", handle)
                                .apply()
                            NotificationListener.onCallbackRegistered()
                            result.success(null)
                        } else {
                            result.error("INVALID_HANDLE", "Invalid background callback handle", null)
                        }
                    }
                    "openNotificationSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        permissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            REQUEST_POST_NOTIFICATIONS,
                        )
                    }
                    "isNotificationsEnabled" -> {
                        val manager = getSystemService(NotificationManager::class.java)
                        val enabled = manager?.areNotificationsEnabled() == true
                        result.success(enabled)
                    }
                    "isPermissionGranted" -> {
                        val enabled = Settings.Secure.getString(
                            contentResolver, "enabled_notification_listeners"
                        )?.contains(packageName) ?: false
                        result.success(enabled)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}