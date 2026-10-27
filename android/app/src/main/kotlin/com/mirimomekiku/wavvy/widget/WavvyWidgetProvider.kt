package com.mirimomekiku.wavvy.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.view.KeyEvent
import android.widget.RemoteViews
import com.mirimomekiku.wavvy.R
import java.io.File

/**
 * The home-screen widget: the playing song and previous / play-pause / next.
 *
 * What it shows is whatever the app last sent (see [save]), kept in preferences,
 * so it is right after a restart too. The buttons send media-button events to
 * audio_service, which is what the notification and headsets use, so they work
 * with the app in the background.
 */
class WavvyWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, build(context))
    }

    companion object {
        private const val PREFS = "wavvy_widget"
        private const val ART_FILE = "widget_art.jpg"
        private const val MEDIA_RECEIVER = "com.ryanheise.audioservice.MediaButtonReceiver"

        /**
         * Stores what the widget should show and redraws it. [art] is a JPEG, an
         * empty array for "no artwork", or null to keep the current picture.
         */
        fun save(context: Context, title: String, artist: String, playing: Boolean, art: ByteArray?) {
            val file = File(context.filesDir, ART_FILE)
            if (art != null) {
                if (art.isEmpty()) file.delete() else file.writeBytes(art)
            }
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("title", title)
                .putString("artist", artist)
                .putBoolean("playing", playing)
                .apply()
            refreshAll(context)
        }

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, WavvyWidgetProvider::class.java))
            for (id in ids) manager.updateAppWidget(id, build(context))
        }

        private fun mediaButton(context: Context, keyCode: Int): PendingIntent {
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON)
                .setComponent(ComponentName(context, MEDIA_RECEIVER))
                .putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            return PendingIntent.getBroadcast(
                context,
                keyCode,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        private fun build(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.wavvy_widget)

            views.setTextViewText(
                R.id.widget_title,
                prefs.getString("title", null) ?: context.getString(R.string.widget_nothing),
            )
            views.setTextViewText(
                R.id.widget_artist,
                prefs.getString("artist", null) ?: context.getString(R.string.widget_open),
            )

            val art = File(context.filesDir, ART_FILE)
            val bitmap = if (art.exists()) BitmapFactory.decodeFile(art.absolutePath) else null
            if (bitmap != null) {
                views.setImageViewBitmap(R.id.widget_art, bitmap)
            } else {
                views.setImageViewResource(R.id.widget_art, R.drawable.widget_art_placeholder)
            }

            val playing = prefs.getBoolean("playing", false)
            views.setImageViewResource(
                R.id.widget_play,
                if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play,
            )

            views.setOnClickPendingIntent(R.id.widget_prev, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
            views.setOnClickPendingIntent(R.id.widget_play, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
            views.setOnClickPendingIntent(R.id.widget_next, mediaButton(context, KeyEvent.KEYCODE_MEDIA_NEXT))

            // Tapping anywhere else opens the app.
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                val open = PendingIntent.getActivity(
                    context,
                    0,
                    launch,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
                views.setOnClickPendingIntent(R.id.widget_root, open)
                views.setOnClickPendingIntent(R.id.widget_art, open)
            }
            return views
        }
    }
}
