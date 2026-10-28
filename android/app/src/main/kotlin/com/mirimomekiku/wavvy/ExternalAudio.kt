package com.mirimomekiku.wavvy

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * "Open with Wavvy": turns an ACTION_VIEW intent for an audio file into a small
 * map for Dart (uri, title, artist, album, duration, displayName, mediaId).
 *
 * The launch file waits here until Dart asks for it with takePending, so a cold
 * start never races Flutter's start-up; files opened while the app runs are
 * pushed to Dart. Reading the tags happens off the main thread. Nothing here
 * throws: a bad file is ignored.
 */
class ExternalAudio(private val activity: Activity) {
    companion object {
        private const val TAG = "Wavvy"
        const val CHANNEL = "com.mirimomekiku.wavvy/external_audio"

        private val AUDIO_EXTENSIONS = setOf(
            "mp3", "m4a", "aac", "flac", "wav", "ogg", "oga", "opus", "wma", "mka", "amr", "mid", "midi",
        )
    }

    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()

    // Main thread only from here down.
    private var dartReady = false
    private var pending: Map<String, Any?>? = null
    private var waiter: MethodChannel.Result? = null
    private var loading = 0

    fun register(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL)
        this.channel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePending" -> takePending(result)
                else -> result.notImplemented()
            }
        }
    }

    /** The intent the activity was started with. */
    fun handleLaunch(intent: Intent?) = handle(intent)

    /** An intent delivered to the running activity. */
    fun handleNewIntent(intent: Intent?) = handle(intent)

    private fun handle(intent: Intent?) {
        try {
            if (intent == null || intent.action != Intent.ACTION_VIEW || intent.data == null) return
            // Reopened from the recents list: that file was already handled.
            if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
            val snapshot = Intent(intent)
            loading++
            worker.execute {
                val described = try {
                    describe(snapshot)
                } catch (e: Throwable) {
                    Log.w(TAG, "Could not read the opened file", e)
                    null
                }
                main.post { finish(described) }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not handle the opened file", e)
        }
    }

    private fun takePending(result: MethodChannel.Result) {
        dartReady = true
        val ready = pending
        pending = null
        when {
            ready != null -> result.success(ready)
            loading > 0 -> {
                // Still reading the tags: answer when done.
                waiter?.success(null)
                waiter = result
            }
            else -> result.success(null)
        }
    }

    private fun finish(described: Map<String, Any?>?) {
        loading--
        try {
            val w = waiter
            if (w != null && (described != null || loading <= 0)) {
                waiter = null
                w.success(described)
                return
            }
            if (described == null) return
            if (dartReady) {
                channel?.invokeMethod("open", described)
            } else {
                pending = described
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not hand the opened file to Dart", e)
        }
    }

    // ------------------------------------------------------------ Reading

    private fun describe(intent: Intent): Map<String, Any?>? {
        val uri = intent.data ?: return null
        val resolver = activity.contentResolver
        if (!isAudio(intent, uri, resolver)) return null

        var title: String? = null
        var artist: String? = null
        var album: String? = null
        var duration: Long? = null
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(activity, uri)
            title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
            artist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
                ?: retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)
            album = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
            duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
        } catch (e: Exception) {
            // Unreadable tags: Dart falls back to the file name.
            Log.w(TAG, "Could not read tags of $uri", e)
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
                // Nothing to do.
            }
        }

        return mapOf(
            "uri" to uri.toString(),
            "title" to clean(title),
            "artist" to clean(artist),
            "album" to clean(album),
            "duration" to duration,
            "displayName" to displayName(uri, resolver),
            "mediaId" to mediaStoreAudioId(uri),
        )
    }

    private fun clean(text: String?): String? = text?.trim()?.takeIf { it.isNotEmpty() }

    private fun isAudio(intent: Intent, uri: Uri, resolver: ContentResolver): Boolean {
        val type = (intent.type ?: try {
            resolver.getType(uri)
        } catch (e: Exception) {
            null
        })?.lowercase()
        if (type != null) {
            if (type.startsWith("audio/") || type == "application/ogg" || type == "application/x-ogg") return true
            if (type != "application/octet-stream") return false
        }
        // No usable type: judge by the file name.
        val name = displayName(uri, resolver) ?: uri.lastPathSegment ?: return false
        return name.substringAfterLast('.', "").lowercase() in AUDIO_EXTENSIONS
    }

    private fun displayName(uri: Uri, resolver: ContentResolver): String? {
        try {
            if (uri.scheme == ContentResolver.SCHEME_CONTENT) {
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index >= 0) clean(cursor.getString(index))?.let { return it }
                    }
                }
            }
        } catch (e: Exception) {
            // Fall back to the path.
        }
        return clean(uri.lastPathSegment?.substringAfterLast('/'))
    }

    /**
     * The MediaStore audio id of [uri], when it is one (content://media/.../audio/media/123,
     * or a Documents picker URI "audio:123"), so Dart can use the library's copy.
     */
    private fun mediaStoreAudioId(uri: Uri): Long? {
        try {
            if (uri.scheme != ContentResolver.SCHEME_CONTENT) return null
            if (uri.authority == "media") {
                val segments = uri.pathSegments
                if (segments.contains("audio") && !segments.contains("picker")) {
                    return segments.lastOrNull()?.toLongOrNull()
                }
                return null
            }
            if (uri.authority == "com.android.providers.media.documents" && DocumentsContract.isDocumentUri(activity, uri)) {
                val id = DocumentsContract.getDocumentId(uri)
                if (id.startsWith("audio:")) return id.removePrefix("audio:").toLongOrNull()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not resolve a MediaStore id for $uri", e)
        }
        return null
    }
}
