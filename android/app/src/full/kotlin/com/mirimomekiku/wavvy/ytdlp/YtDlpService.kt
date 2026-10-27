package com.mirimomekiku.wavvy.ytdlp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Keeps the process alive while downloads run, and shows their progress. Started
 * by [YtDlpRunner] when the first download begins and stopped after the last.
 */
class YtDlpService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel(this)
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            build(this, "Preparing download…", -1),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            },
        )
        return START_NOT_STICKY
    }

    companion object {
        private const val CHANNEL_ID = "com.mirimomekiku.wavvy.channel.downloads"
        private const val NOTIFICATION_ID = 4102

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Downloads", NotificationManager.IMPORTANCE_LOW),
                )
            }
        }

        private fun build(context: Context, text: String, percent: Int): Notification =
            NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle("Wavvy")
                .setContentText(text)
                .setOnlyAlertOnce(true)
                .setOngoing(true)
                .setProgress(100, percent.coerceAtLeast(0), percent < 0)
                .build()

        /** Updates the notification text and progress (a negative percent is indeterminate). */
        fun update(context: Context, text: String, percent: Int) {
            ensureChannel(context)
            context.getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, build(context, text, percent))
        }
    }
}
