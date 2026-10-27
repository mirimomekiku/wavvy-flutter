package com.mirimomekiku.wavvy.ytdlp

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.ConnectivityManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Runs yt-dlp for the app: sets the engine up, looks media up, downloads it and
 * publishes the result to the music library. Downloads run one at a time in a
 * foreground service; lookups can run alongside a download.
 *
 * Results of finished downloads are also kept in preferences until Dart
 * acknowledges them, so a download that ends while the UI is gone is not lost.
 */
class YtDlpRunner private constructor(private val app: Context) {
    companion object {
        private const val PREFS = "wavvy_ytdlp"
        private const val KEY_READY = "engine_ready"
        private const val KEY_RESULTS = "results"

        @Volatile
        private var instance: YtDlpRunner? = null

        fun get(context: Context): YtDlpRunner =
            instance ?: synchronized(this) {
                instance ?: YtDlpRunner(context).also { instance = it }
            }
    }

    private val main = Handler(Looper.getMainLooper())
    private val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val lookups = Executors.newCachedThreadPool()
    private val downloads = Executors.newSingleThreadExecutor()
    private val active = AtomicInteger(0)
    private val canceled = java.util.Collections.synchronizedSet(mutableSetOf<String>())
    private val activeIds = java.util.Collections.synchronizedSet(mutableSetOf<String>())

    @Volatile
    private var events: EventChannel.EventSink? = null

    @Volatile
    private var initialized = false

    fun attach(sink: EventChannel.EventSink?) {
        events = sink
    }

    private fun emit(event: Map<String, Any?>) {
        main.post { events?.success(event) }
    }

    @Synchronized
    private fun ensureInit() {
        if (initialized) return
        YoutubeDL.getInstance().init(app)
        initialized = true
    }

    // ------------------------------------------------------------- Dispatch

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "install", "update" -> work(result) { installOrUpdate() }
            "resolve" -> work(result) { resolve(call.argument<String>("url")!!) }
            "search" -> work(result) {
                search(call.argument<String>("query")!!, call.argument<Int>("count") ?: 15)
            }
            "download" -> {
                download(call)
                result.success(null)
            }
            "cancel" -> {
                val id = call.argument<String>("id")!!
                canceled.add(id)
                YoutubeDL.getInstance().destroyProcessById(id)
                result.success(null)
            }
            "publish" -> work(result) { publish(call) }
            "pending" -> result.success(pending())
            "ack" -> {
                ack(call.argument<String>("id")!!)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Runs [block] off the main thread and answers the call with its value or error. */
    private fun work(result: MethodChannel.Result, block: () -> Any?) {
        lookups.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("ytdlp_failed", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    // --------------------------------------------------------------- Engine

    private fun status(): Map<String, Any?> = mapOf(
        "state" to if (prefs.getBoolean(KEY_READY, false)) "ready" else "missing",
        "version" to prefs.getString("version", null),
    )

    /**
     * Sets up the engine, then fetches the newest yt-dlp from its releases. The
     * app counts as set up only after that download, so it never runs the older
     * copy that comes with the library.
     */
    private fun installOrUpdate(): Map<String, Any?> {
        emit(mapOf("type" to "engine", "phase" to "starting"))
        ensureInit()
        emit(mapOf("type" to "engine", "phase" to "downloading"))
        YoutubeDL.getInstance().updateYoutubeDL(app, YoutubeDL.UpdateChannel.STABLE)
        val version = YoutubeDL.getInstance().version(app)
        prefs.edit().putBoolean(KEY_READY, true).putString("version", version).apply()
        emit(mapOf("type" to "engine", "phase" to "ready", "version" to version))
        return status()
    }

    // -------------------------------------------------------------- Lookups

    private fun baseRequest(url: String): YoutubeDLRequest = YoutubeDLRequest(url).apply {
        addOption("--ignore-config")
        addOption("--no-warnings")
        addOption("--socket-timeout", "20")
    }

    /** One video as yt-dlp's JSON. */
    private fun resolve(url: String): String {
        ensureInit()
        val request = baseRequest(url).apply {
            addOption("--dump-single-json")
            addOption("--no-playlist")
        }
        return YoutubeDL.getInstance().execute(request).out
    }

    /** A YouTube search as yt-dlp's JSON (a playlist of flat entries). */
    private fun search(query: String, count: Int): String {
        ensureInit()
        val request = baseRequest("ytsearch$count:$query").apply {
            addOption("--dump-single-json")
            addOption("--flat-playlist")
        }
        return YoutubeDL.getInstance().execute(request).out
    }

    // ------------------------------------------------------------ Downloads

    private fun isMetered(): Boolean {
        val manager = app.getSystemService(ConnectivityManager::class.java)
        return manager.isActiveNetworkMetered
    }

    private fun download(call: MethodCall) {
        val id = call.argument<String>("id")!!
        val url = call.argument<String>("url")!!
        val videoId = call.argument<String>("videoId")!!
        val dir = File(call.argument<String>("dir")!!)
        val wifiOnly = call.argument<Boolean>("wifiOnly") ?: false
        val title = call.argument<String>("title") ?: "Download"

        activeIds.add(id)
        if (active.getAndIncrement() == 0) {
            ContextCompat.startForegroundService(app, Intent(app, YtDlpService::class.java))
        }
        downloads.execute {
            try {
                if (wifiOnly && isMetered()) {
                    finish(id, "failed", error = "Waiting for Wi-Fi: this download is set to Wi-Fi only.")
                    return@execute
                }
                if (canceled.remove(id)) {
                    finish(id, "canceled")
                    return@execute
                }
                ensureInit()
                dir.mkdirs()
                val request = baseRequest(url).apply {
                    addOption("--no-playlist")
                    addOption("-f", "bestaudio[ext=m4a]/bestaudio/best")
                    addOption("-o", "${dir.absolutePath}/$videoId.%(ext)s")
                    addOption("--no-mtime")
                    addOption("--newline")
                    addOption("--retries", "5")
                    addOption("--concurrent-fragments", "4")
                }
                emit(mapOf("type" to "task", "id" to id, "status" to "running", "progress" to 0))
                YoutubeDL.getInstance().execute(request, id) { progress, _, _ ->
                    val percent = progress.toInt().coerceIn(0, 100)
                    YtDlpService.update(app, title, percent)
                    emit(mapOf("type" to "task", "id" to id, "status" to "running", "progress" to percent))
                }
                val file = findOutput(dir, videoId)
                if (file == null) {
                    finish(id, "failed", error = "yt-dlp finished but no audio file was found.")
                } else {
                    finish(id, "complete", path = file.absolutePath)
                }
            } catch (e: Exception) {
                if (canceled.remove(id)) {
                    finish(id, "canceled")
                } else {
                    finish(id, "failed", error = e.message ?: e.javaClass.simpleName)
                }
            } finally {
                activeIds.remove(id)
                if (active.decrementAndGet() == 0) {
                    app.stopService(Intent(app, YtDlpService::class.java))
                }
            }
        }
    }

    /** The finished audio file for [videoId], ignoring yt-dlp's temporary files. */
    private fun findOutput(dir: File, videoId: String): File? =
        dir.listFiles { f ->
            f.name.startsWith("$videoId.") &&
                !f.name.endsWith(".part") &&
                !f.name.endsWith(".ytdl") &&
                !f.name.endsWith(".json")
        }?.maxByOrNull { it.length() }

    private fun finish(id: String, status: String, path: String? = null, error: String? = null) {
        val event = mapOf(
            "type" to "task",
            "id" to id,
            "status" to status,
            "progress" to if (status == "complete") 100 else 0,
            "path" to path,
            "error" to error,
        )
        // Kept until acknowledged, in case the UI is not listening right now.
        synchronized(prefs) {
            val all = JSONObject(prefs.getString(KEY_RESULTS, "{}")!!)
            all.put(id, JSONObject(event.filterValues { it != null }))
            prefs.edit().putString(KEY_RESULTS, all.toString()).apply()
        }
        emit(event)
    }

    /** Results of finished downloads not yet acknowledged, and the ids still running. */
    private fun pending(): Map<String, Any?> = mapOf(
        "results" to results(),
        "active" to activeIds.toList(),
    )

    private fun results(): List<Map<String, Any?>> = synchronized(prefs) {
        val all = JSONObject(prefs.getString(KEY_RESULTS, "{}")!!)
        all.keys().asSequence().map { key ->
            val o = all.getJSONObject(key)
            mapOf(
                "type" to "task",
                "id" to key,
                "status" to o.optString("status"),
                "progress" to o.optInt("progress"),
                "path" to o.optString("path").ifEmpty { null },
                "error" to o.optString("error").ifEmpty { null },
            )
        }.toList()
    }

    private fun ack(id: String) = synchronized(prefs) {
        val all = JSONObject(prefs.getString(KEY_RESULTS, "{}")!!)
        all.remove(id)
        prefs.edit().putString(KEY_RESULTS, all.toString()).apply()
    }

    // -------------------------------------------------------------- Publish

    private fun mimeFor(name: String): String = when (name.substringAfterLast('.').lowercase()) {
        "m4a", "mp4" -> "audio/mp4"
        "mp3" -> "audio/mpeg"
        "opus", "ogg" -> "audio/ogg"
        "webm" -> "audio/webm"
        "flac" -> "audio/flac"
        else -> "audio/mpeg"
    }

    /**
     * Copies a finished file into the music library (Music/Wavvy) and deletes the
     * staged copy. Returns the content URI (Android 10+) or the file path.
     */
    private fun publish(call: MethodCall): String {
        val source = File(call.argument<String>("path")!!)
        val displayName = call.argument<String>("displayName")!!
        val mime = mimeFor(displayName)

        val published: String
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = app.contentResolver
            val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Audio.Media.MIME_TYPE, mime)
                put(MediaStore.Audio.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/Wavvy")
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }
            val uri = resolver.insert(collection, values)
                ?: throw IllegalStateException("Could not create the file in your music library")
            try {
                resolver.openOutputStream(uri, "w")!!.use { out ->
                    source.inputStream().use { it.copyTo(out) }
                }
                values.clear()
                values.put(MediaStore.Audio.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
            published = uri.toString()
        } else {
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), "Wavvy")
            dir.mkdirs()
            val target = File(dir, displayName)
            source.copyTo(target, overwrite = true)
            MediaScannerConnection.scanFile(app, arrayOf(target.absolutePath), arrayOf(mime), null)
            published = target.absolutePath
        }
        source.delete()
        return published
    }
}
