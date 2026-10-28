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
 *
 * It goes foreground as the first thing in [onStartCommand] (Android gives a
 * service started with startForegroundService only a few seconds to do so), and
 * it is the service itself that stops when there is nothing left to do, so a
 * stop can never overtake the start.
 */
class YtDlpService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
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
            running = true
        } catch (e: Exception) {
            // Android refused (for example a start that is not allowed from the
            // background). Downloads that are queued still run while the app
            // process lives; there is just no notification.
            running = false
            stopSelf(startId)
            return START_NOT_STICKY
        }
        // Everything may have finished between the start request and now.
        if (!YtDlpRunner.get(applicationContext).hasWork()) stopSelf(startId)
        return START_NOT_STICKY
    }

    /**
     * Android 15 limits a dataSync service to about six hours a day and calls
     * this when the time is up; the service must stop soon after, or the app is
     * stopped with an exception. Remaining downloads are marked failed.
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        YtDlpRunner.get(applicationContext).onServiceTimeout()
        stopSelf(startId)
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_ID = "com.mirimomekiku.wavvy.channel.downloads"
        private const val NOTIFICATION_ID = 4102

        /** True from the moment the service is foreground until it is destroyed. */
        @Volatile
        var running = false
            private set

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
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
            // After the service has stopped, a late update would leave a stuck notification.
            if (!running) return
            try {
                ensureChannel(context)
                context.getSystemService(NotificationManager::class.java)
                    ?.notify(NOTIFICATION_ID, build(context, text, percent))
            } catch (e: Exception) {
                // A notification is not worth failing a download for.
            }
        }
    }
}
