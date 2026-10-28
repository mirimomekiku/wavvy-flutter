package com.mirimomekiku.wavvy

import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.Intent
import android.content.IntentSender
import android.media.MediaScannerConnection
import android.media.audiofx.BassBoost
import android.media.audiofx.PresetReverb
import android.media.audiofx.Virtualizer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.MediaStore
import android.util.Log
import com.mirimomekiku.wavvy.widget.WavvyWidgetProvider
import com.mirimomekiku.wavvy.ytdlp.YtDlpPlugin
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    companion object {
        private const val TAG = "Wavvy"
        private const val EFFECTS_CHANNEL = "com.mirimomekiku.wavvy/audio_effects"
        private const val APP_CHANNEL = "com.mirimomekiku.wavvy/app"
        private const val WIDGET_CHANNEL = "com.mirimomekiku.wavvy/widget"
        private const val MEDIA_CHANNEL = "com.mirimomekiku.wavvy/media_store"
        private const val REQUEST_MEDIA = 4101

        // Effects belong to the player's audio session, which the playback
        // service keeps after this Activity is gone (swiped from recents), so
        // they live with the process. initEffects replaces them when the
        // session changes.
        private var bassBoost: BassBoost? = null
        private var virtualizer: Virtualizer? = null
        private var presetReverb: PresetReverb? = null
    }

    // A MediaStore request is waiting on the system consent dialog.
    private var pendingResult: MethodChannel.Result? = null
    private var pendingDelete: Uri? = null

    // Spectrum for the visualizer page; released with the Activity.
    private var visualizerBridge: VisualizerBridge? = null

    override fun onDestroy() {
        visualizerBridge?.release()
        visualizerBridge = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        visualizerBridge?.release()
        visualizerBridge = VisualizerBridge.register(this, flutterEngine.dartExecutor.binaryMessenger)
        // The downloader exists only in the full flavor; the Play flavor's
        // version of this call does nothing.
        YtDlpPlugin.register(this, flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, EFFECTS_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "initEffects" -> {
                        val sessionId = call.argument<Int>("sessionId") ?: 0
                        if (sessionId <= 0) {
                            result.error("bad_session", "Invalid audio session $sessionId", null)
                        } else {
                            result.success(initAudioEffects(sessionId))
                        }
                    }
                    "setBassBoost" -> {
                        setBassBoostStrength(call.argument<Int>("strength") ?: 0)
                        result.success(null)
                    }
                    "setVirtualizer" -> {
                        setVirtualizerStrength(call.argument<Int>("strength") ?: 0)
                        result.success(null)
                    }
                    "setReverb" -> {
                        setReverbPreset(call.argument<String>("preset") ?: "None")
                        result.success(null)
                    }
                    "releaseEffects" -> {
                        releaseAudioEffects()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: IllegalArgumentException) {
                result.error("bad_argument", e.message, null)
            } catch (e: RuntimeException) {
                // IllegalStateException and UnsupportedOperationException from
                // the audio framework land here.
                Log.w(TAG, "Audio effect call ${call.method} failed", e)
                result.error("effect_unavailable", e.message, null)
            }
        }

        MethodChannel(messenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    WavvyWidgetProvider.save(
                        applicationContext,
                        call.argument<String>("title") ?: "Wavvy",
                        call.argument<String>("artist") ?: "",
                        call.argument<Boolean>("playing") ?: false,
                        call.argument<ByteArray>("art"),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, APP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "restart" -> restartApp(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, MEDIA_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "scanFile") {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.notImplemented()
                } else {
                    // Refresh MediaStore so edited tags show up in the library.
                    MediaScannerConnection.scanFile(this, arrayOf(path), null) { _, _ ->
                        Handler(Looper.getMainLooper()).post { result.success(null) }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "deleteAudios") {
                val ids = call.argument<List<Number>>("ids")?.map { it.toLong() }
                if (ids.isNullOrEmpty()) {
                    result.error("bad_argument", "No songs to delete", null)
                } else {
                    deleteAudios(ids, result)
                }
                return@setMethodCallHandler
            }
            val id = call.argument<Number>("id")?.toLong()
            if (id == null) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            when (call.method) {
                "deleteAudio" -> deleteAudio(audioUri(id), result)
                "requestWriteAccess" -> requestWriteAccess(audioUri(id), result)
                else -> result.notImplemented()
            }
        }
    }

    // ------------------------------------------------------------ Restart

    /** Relaunches the app in a fresh process (used by the startup-failure screen). */
    private fun restartApp(result: MethodChannel.Result) {
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        }
        if (intent == null) {
            result.error("no_launcher", "Launch intent not found", null)
            return
        }
        result.success(null)
        finishAffinity()
        startActivity(intent)
        // Give the new task a moment to start, then drop this process so the
        // relaunch begins with clean native state.
        Handler(Looper.getMainLooper()).postDelayed({
            Process.killProcess(Process.myPid())
        }, 200)
    }

    // -------------------------------------------------------- MediaStore

    private fun audioUri(id: Long): Uri =
        ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)

    private fun launchConsent(sender: IntentSender, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "Another storage request is in progress", null)
            return
        }
        pendingResult = result
        try {
            startIntentSenderForResult(sender, REQUEST_MEDIA, null, 0, 0, 0)
        } catch (e: IntentSender.SendIntentException) {
            pendingResult = null
            pendingDelete = null
            result.error("launch_failed", e.message, null)
        }
    }

    /**
     * Deletes one audio file. Android 11+ asks the user through the system
     * delete dialog; Android 10 asks only when the file belongs to another app.
     * Completes with true when the file is gone.
     */
    private fun deleteAudio(uri: Uri, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            pendingDelete = null
            val request = MediaStore.createDeleteRequest(contentResolver, listOf(uri))
            launchConsent(request.intentSender, result)
            return
        }
        try {
            result.success(contentResolver.delete(uri, null, null) > 0)
        } catch (e: SecurityException) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && e is RecoverableSecurityException) {
                pendingDelete = uri
                launchConsent(e.userAction.actionIntent.intentSender, result)
            } else {
                result.error("denied", e.message, null)
            }
        }
    }

    /**
     * Deletes several audio files. Android 11+ asks once for all of them and
     * completes with true or false; older versions delete what they can and
     * complete with the ids that are gone (a file that needs its own consent
     * on Android 10 is left for the user to delete on its own).
     */
    private fun deleteAudios(ids: List<Long>, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            pendingDelete = null
            val request = MediaStore.createDeleteRequest(contentResolver, ids.map { audioUri(it) })
            launchConsent(request.intentSender, result)
            return
        }
        val deleted = ArrayList<Long>()
        for (id in ids) {
            try {
                if (contentResolver.delete(audioUri(id), null, null) > 0) deleted.add(id)
            } catch (e: SecurityException) {
                Log.w(TAG, "Could not delete audio $id", e)
            }
        }
        result.success(deleted)
    }

    /**
     * Makes [uri] writable for this app (needed before editing tags). Completes
     * with true when write access is available.
     */
    private fun requestWriteAccess(uri: Uri, result: MethodChannel.Result) {
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> {
                pendingDelete = null
                val request = MediaStore.createWriteRequest(contentResolver, listOf(uri))
                launchConsent(request.intentSender, result)
            }
            Build.VERSION.SDK_INT == Build.VERSION_CODES.Q -> {
                try {
                    contentResolver.openOutputStream(uri, "wa")?.close()
                    result.success(true)
                } catch (e: RecoverableSecurityException) {
                    pendingDelete = null
                    launchConsent(e.userAction.actionIntent.intentSender, result)
                } catch (e: Exception) {
                    result.error("denied", e.message, null)
                }
            }
            // Before scoped storage the storage permission already covers it.
            else -> result.success(true)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_MEDIA) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingResult
        val retry = pendingDelete
        pendingResult = null
        pendingDelete = null
        if (result == null) return
        if (resultCode != RESULT_OK) {
            result.success(false)
            return
        }
        if (retry != null) {
            // Android 10: the user approved this file, now repeat the delete.
            try {
                result.success(contentResolver.delete(retry, null, null) > 0)
            } catch (e: Exception) {
                result.error("denied", e.message, null)
            }
        } else {
            result.success(true)
        }
    }

    // ----------------------------------------------------------- Effects

    /**
     * Creates the effects for [sessionId], disabled, and reports what this
     * device supports. A missing effect never blocks the others.
     */
    private fun initAudioEffects(sessionId: Int): Map<String, Boolean> {
        releaseAudioEffects()

        bassBoost = create("BassBoost") { BassBoost(0, sessionId).also { it.enabled = false } }
        virtualizer = create("Virtualizer") { Virtualizer(0, sessionId).also { it.enabled = false } }
        presetReverb = create("PresetReverb") { PresetReverb(0, sessionId).also { it.enabled = false } }

        return mapOf(
            "bassBoost" to (bassBoost != null),
            "virtualizer" to (virtualizer != null),
            "reverb" to (presetReverb != null),
        )
    }

    private fun <T> create(name: String, factory: () -> T): T? = try {
        factory()
    } catch (e: Exception) {
        Log.w(TAG, "$name is not available on this device", e)
        null
    }

    private fun setBassBoostStrength(strength: Int) {
        val effect = bassBoost ?: throw IllegalStateException("Bass boost is not available on this device")
        val value = strength.coerceIn(0, 1000)
        if (value > 0) {
            if (effect.strengthSupported) effect.setStrength(value.toShort())
            effect.enabled = true
        } else {
            effect.enabled = false
        }
    }

    private fun setVirtualizerStrength(strength: Int) {
        val effect = virtualizer ?: throw IllegalStateException("Virtualizer is not available on this device")
        val value = strength.coerceIn(0, 1000)
        if (value > 0) {
            if (effect.strengthSupported) effect.setStrength(value.toShort())
            effect.enabled = true
        } else {
            effect.enabled = false
        }
    }

    private fun setReverbPreset(presetName: String) {
        val effect = presetReverb ?: throw IllegalStateException("Reverb is not available on this device")
        if (presetName == "None") {
            effect.enabled = false
            return
        }
        effect.preset = when (presetName) {
            "SmallRoom" -> PresetReverb.PRESET_SMALLROOM
            "MediumRoom" -> PresetReverb.PRESET_MEDIUMROOM
            "LargeRoom" -> PresetReverb.PRESET_LARGEROOM
            "MediumHall" -> PresetReverb.PRESET_MEDIUMHALL
            "LargeHall" -> PresetReverb.PRESET_LARGEHALL
            "Plate" -> PresetReverb.PRESET_PLATE
            else -> throw IllegalArgumentException("Unknown reverb preset $presetName")
        }
        effect.enabled = true
    }

    private fun releaseAudioEffects() {
        bassBoost?.release()
        bassBoost = null
        virtualizer?.release()
        virtualizer = null
        presetReverb?.release()
        presetReverb = null
    }
}
