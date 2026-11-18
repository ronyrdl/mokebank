package com.example.moke_bank

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class OperationNotifications(private val activity: Activity) {
    private val manager = activity.getSystemService(NotificationManager::class.java)
    private val pending = linkedMapOf<String, String>()

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "moke_bank/notifications").setMethodCallHandler { call, result ->
            if (call.method != "operationCompleted") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val title = call.argument<String>("title")
            val reference = call.argument<String>("reference")
            if (title.isNullOrBlank() || reference.isNullOrBlank()) {
                result.error("INVALID_NOTIFICATION", "Falta el título o la referencia.", null)
                return@setMethodCallHandler
            }

            try {
                notifyOperation(title, reference)
                result.success(null)
            } catch (error: SecurityException) {
                result.error("NOTIFICATION_PERMISSION", "Android bloqueó el aviso.", null)
            }
        }
    }

    private fun notifyOperation(title: String, reference: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            if (pending.isNotEmpty()) {
                pending[reference] = title
                return
            }

            val preferences = activity.getSharedPreferences("moke_notifications", Activity.MODE_PRIVATE)
            if (preferences.getBoolean("permission_requested", false)) return

            pending[reference] = title
            preferences.edit().putBoolean("permission_requested", true).apply()
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
            return
        }

        post(title, reference)
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST) return
        val approved = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        val operations = pending.toMap()
        pending.clear()
        if (approved) operations.forEach { (reference, title) -> post(title, reference) }
    }

    @Suppress("DEPRECATION")
    private fun post(title: String, reference: String) {
        if (!manager.areNotificationsEnabled()) return
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Operaciones de Moke", NotificationManager.IMPORTANCE_DEFAULT)
            )
            Notification.Builder(activity, CHANNEL_ID)
        } else {
            Notification.Builder(activity)
        }

        val openApp = PendingIntent.getActivity(
            activity, 0,
            Intent(activity, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = builder
            .setSmallIcon(R.drawable.ic_moke_notification)
            .setLargeIcon(BitmapFactory.decodeResource(activity.resources, R.mipmap.ic_launcher))
            .setColor(Color.rgb(255, 107, 0))
            .setContentTitle(title)
            .setContentText("Ya puedes consultar el comprobante en Moke Bank.")
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setContentIntent(openApp)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .build()

        manager.notify(reference, 1, notification)
    }

    private companion object {
        const val CHANNEL_ID = "moke_operations"
        const val PERMISSION_REQUEST = 4301
    }
}
