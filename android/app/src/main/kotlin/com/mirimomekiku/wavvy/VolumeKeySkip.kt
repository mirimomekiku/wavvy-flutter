package com.mirimomekiku.wavvy

import android.app.Activity
import android.content.Context
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import android.view.ViewConfiguration
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Hold volume up for the next song and volume down for the previous one.
 *
 * Android only gives an app the volume keys while its window has focus, so this
 * works only while Wavvy is on screen. When it is off (the default) every key
 * event goes straight to the system, untouched.
 *
 * With it on, a key press is held back: released before the long-press time it
 * changes the music volume here, as the system would have; held longer it asks
 * Dart to skip once and the release does nothing.
 */
class VolumeKeySkip(private val activity: Activity) {
    companion object {
        private const val TAG = "Wavvy"
        const val CHANNEL = "com.mirimomekiku.wavvy/volume_keys"
    }

    private var channel: MethodChannel? = null
    private val handler = Handler(Looper.getMainLooper())

    @Volatile
    private var enabled = false

    // The key being held (0 for none) and whether it already skipped.
    private var heldKey = 0
    private var skipped = false
    private var pendingSkip: Runnable? = null

    fun register(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL)
        this.channel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    enabled = call.argument<Boolean>("enabled") ?: false
                    if (!enabled) cancelHold()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Returns true when the event was handled here; false lets the system have it. */
    fun onKeyEvent(event: KeyEvent): Boolean {
        try {
            val code = event.keyCode
            if (code != KeyEvent.KEYCODE_VOLUME_UP && code != KeyEvent.KEYCODE_VOLUME_DOWN) return false
            if (!enabled) return false

            when (event.action) {
                KeyEvent.ACTION_DOWN -> {
                    // Auto-repeats of a key already being held are swallowed.
                    if (event.repeatCount == 0 || heldKey != code) startHold(code)
                    return true
                }
                KeyEvent.ACTION_UP -> {
                    // An UP whose DOWN this class never saw (the setting was
                    // turned on mid-press) is left to the system.
                    if (heldKey != code) return false
                    val wasSkip = skipped
                    cancelHold()
                    if (!wasSkip) adjustVolume(code)
                    return true
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Volume key handling failed", e)
        }
        return false
    }

    private fun startHold(code: Int) {
        cancelHold()
        heldKey = code
        skipped = false
        val skip = Runnable {
            pendingSkip = null
            // Only skip while the key is still down and the app is in front.
            if (heldKey != code || !activity.hasWindowFocus()) return@Runnable
            skipped = true
            try {
                channel?.invokeMethod(
                    "skip",
                    if (code == KeyEvent.KEYCODE_VOLUME_UP) "next" else "previous",
                )
            } catch (e: Exception) {
                Log.w(TAG, "Could not send the volume key skip", e)
            }
        }
        pendingSkip = skip
        handler.postDelayed(skip, ViewConfiguration.getLongPressTimeout().toLong())
    }

    private fun cancelHold() {
        pendingSkip?.let { handler.removeCallbacks(it) }
        pendingSkip = null
        heldKey = 0
        skipped = false
    }

    private fun adjustVolume(code: Int) {
        try {
            val audio = activity.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            audio.adjustStreamVolume(
                AudioManager.STREAM_MUSIC,
                if (code == KeyEvent.KEYCODE_VOLUME_UP) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                AudioManager.FLAG_SHOW_UI,
            )
        } catch (e: Exception) {
            // Do Not Disturb policy can refuse volume changes.
            Log.w(TAG, "Could not change the volume", e)
        }
    }
}
