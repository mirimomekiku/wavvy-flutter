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
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/**
 * Runs yt-dlp for the app: sets the engine up, looks media up, downloads it and
 * publishes the result to the music library. Downloads run one at a time in a
 * foreground service; lookups can run alongside a download.
 *
 * Results of finished downloads are also kept in preferences until Dart
 * acknowledges them, so a download that ends while the UI is gone is not lost.
 *
 * yt-dlp only runs while the installed file has the hash that was verified
 * against the release's published checksum (see [integrityProblem]).
 */
class YtDlpRunner private constructor(private val app: Context) {
    companion object {
        private const val PREFS = "wavvy_ytdlp"
        private const val KEY_RESULTS = "results"
        private const val KEY_SHA = "trusted_sha256"
        private const val KEY_VERSION = "trusted_version"
        private const val KEY_STAGING = "staging_dir"

        /** The preferences file youtubedl-android keeps its installed version in. */
        private const val LIBRARY_PREFS = "youtubedl-android"
        private const val LIBRARY_VERSION_KEY = "dlpVersion"

        /** A lookup (resolve or search) that runs longer than this is killed. */
        private const val LOOKUP_TIMEOUT_SECONDS = 60L

        private const val TIMEOUT_MESSAGE =
            "Android stopped the download service because it ran for too long. Try again later."

        @Volatile
        private var instance: YtDlpRunner? = null

        fun get(context: Context): YtDlpRunner =
            instance ?: synchronized(this) {
                instance ?: YtDlpRunner(context).also { instance = it }
            }
    }

    private val main = Handler(Looper.getMainLooper())
    private val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // Few threads and a short queue: a flood of requests is refused, not queued forever.
    private val lookups = ThreadPoolExecutor(
        4, 4, 30L, TimeUnit.SECONDS, LinkedBlockingQueue<Runnable>(16),
    ).apply { allowCoreThreadTimeOut(true) }
    private val downloads = Executors.newSingleThreadExecutor()
    private val watchdog = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "ytdlp-watchdog").apply { isDaemon = true }
    }

    // Guarded by [gate]: the ids of downloads queued or running, and how many there are.
    private val gate = Any()
    private val activeIds = mutableSetOf<String>()
    private var queued = 0

    // Ids whose download should end as canceled / as failed by the service time limit.
    // Entries only exist while that download is queued or running.
    private val canceled = java.util.Collections.synchronizedSet(mutableSetOf<String>())
    private val timedOut = java.util.Collections.synchronizedSet(mutableSetOf<String>())

    private val lookupSeq = AtomicLong(0)
    private val lookupLock = Any()
    private var currentLookup: String? = null
    private val superseded = java.util.Collections.synchronizedSet(mutableSetOf<String>())
    private val lookupTimedOut = java.util.Collections.synchronizedSet(mutableSetOf<String>())

    private val engineLock = Any()

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
            "status" -> work(result) { status() }
            "install", "update" -> work(result) { installOrUpdate() }
            "trust" -> work(result) {
                trust(call.argument<String>("version")!!, call.argument<String>("sha256")!!)
            }
            "distrust" -> work(result) { distrust() }
            "resolve" -> work(result) { resolve(call.argument<String>("url")!!) }
            "search" -> work(result) {
                search(call.argument<String>("query")!!, call.argument<Int>("count") ?: 15)
            }
            "download" -> {
                try {
                    download(call)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("ytdlp_failed", e.message ?: e.javaClass.simpleName, null)
                }
            }
            "cancel" -> {
                val id = call.argument<String>("id")!!
                // Only a download that is still queued or running can consume the flag;
                // otherwise it would sit there and cancel a later retry with the same id.
                if (synchronized(gate) { activeIds.contains(id) }) {
                    canceled.add(id)
                    YoutubeDL.getInstance().destroyProcessById(id)
                }
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
        try {
            lookups.execute {
                try {
                    val value = block()
                    main.post { result.success(value) }
                } catch (e: Throwable) {
                    main.post { result.error("ytdlp_failed", e.message ?: e.javaClass.simpleName, null) }
                }
            }
        } catch (e: RejectedExecutionException) {
            result.error("ytdlp_failed", "The downloader is busy. Try again in a moment.", null)
        }
    }

    // ------------------------------------------------------------ Integrity

    /** Where youtubedl-android installs the yt-dlp it downloads (its asset named `yt-dlp`). */
    private fun ytdlpFile(): File =
        File(File(File(app.noBackupFilesDir, "youtubedl-android"), "yt-dlp"), "yt-dlp")

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                digest.update(buffer, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    // What was last confirmed: the file's size and time stamp when its hash matched.
    private var checkedLength = -1L
    private var checkedModified = -1L
    private var checkedOk = false

    private fun resetIntegrityCache() {
        synchronized(this) { checkedOk = false }
    }

    /**
     * Null when yt-dlp may run: a hash was verified against the published
     * checksum and the installed file still has it. Otherwise the reason it must
     * not run. The file is fully hashed the first time in a session and again
     * whenever its size or time stamp changes; in between only those two are
     * compared, which is cheap.
     */
    @Synchronized
    private fun integrityProblem(): String? {
        val trusted = prefs.getString(KEY_SHA, null)
            ?: return "The downloader is not set up yet."
        val file = ytdlpFile()
        if (!file.isFile) return "yt-dlp is missing. Set the downloader up again."
        if (checkedOk && file.length() == checkedLength && file.lastModified() == checkedModified) {
            return null
        }
        val actual = try {
            sha256(file)
        } catch (e: Exception) {
            return "yt-dlp could not be read to check it. Set the downloader up again."
        }
        if (actual != trusted) {
            checkedOk = false
            return "yt-dlp changed since it was verified, so it was not run. " +
                "Set the downloader up again."
        }
        checkedLength = file.length()
        checkedModified = file.lastModified()
        checkedOk = true
        return null
    }

    private fun requireTrusted() {
        integrityProblem()?.let { throw IllegalStateException(it) }
    }

    // --------------------------------------------------------------- Engine

    private fun status(): Map<String, Any?> {
        val version = prefs.getString(KEY_VERSION, null)
        if (prefs.getString(KEY_SHA, null) == null) return mapOf("state" to "missing")
        val problem = integrityProblem()
        return if (problem == null) {
            mapOf("state" to "ready", "version" to version)
        } else {
            mapOf("state" to "failed", "version" to version, "message" to problem)
        }
    }

    /**
     * Sets up the engine, then fetches the newest yt-dlp from its releases. The
     * app counts as set up only after that download, so it never runs the older
     * copy that comes with the library, and only once Dart has verified the
     * file's hash against the release's checksum and called [trust].
     *
     * Returns `ready` when the file is the one already verified (nothing new was
     * downloaded), otherwise `unverified` with the version and hash to check.
     */
    private fun installOrUpdate(): Map<String, Any?> = synchronized(engineLock) {
        emit(mapOf("type" to "engine", "phase" to "starting"))
        ensureInit()
        if (integrityProblem() != null) {
            // Not the verified file (first setup, or it changed): download it again
            // even if the library believes it already has the latest version.
            app.getSharedPreferences(LIBRARY_PREFS, Context.MODE_PRIVATE)
                .edit().remove(LIBRARY_VERSION_KEY).apply()
        }
        emit(mapOf("type" to "engine", "phase" to "downloading"))
        YoutubeDL.getInstance().updateYoutubeDL(app, YoutubeDL.UpdateChannel.STABLE)
        resetIntegrityCache()
        val version = YoutubeDL.getInstance().version(app)
            ?: throw IllegalStateException("yt-dlp did not report its version.")
        val file = ytdlpFile()
        if (!file.isFile) throw IllegalStateException("yt-dlp was not installed.")
        val sha = sha256(file)
        if (sha == prefs.getString(KEY_SHA, null) && version == prefs.getString(KEY_VERSION, null)) {
            emit(mapOf("type" to "engine", "phase" to "ready", "version" to version))
            status()
        } else {
            mapOf("state" to "unverified", "version" to version, "sha256" to sha)
        }
    }

    /** Records [version] and [expected] as the verified hash, if the installed file really has that hash. */
    private fun trust(version: String, expected: String): Map<String, Any?> = synchronized(engineLock) {
        val file = ytdlpFile()
        if (!file.isFile) throw IllegalStateException("yt-dlp is missing.")
        val actual = sha256(file)
        if (!actual.equals(expected, ignoreCase = true)) {
            throw IllegalStateException("yt-dlp changed while it was being verified. Try again.")
        }
        prefs.edit().putString(KEY_SHA, actual).putString(KEY_VERSION, version).apply()
        resetIntegrityCache()
        emit(mapOf("type" to "engine", "phase" to "ready", "version" to version))
        status()
    }

    /** Forgets what was verified, so yt-dlp does not run until it is verified again. */
    private fun distrust(): Any? = synchronized(engineLock) {
        prefs.edit().remove(KEY_SHA).remove(KEY_VERSION).apply()
        resetIntegrityCache()
        null
    }

    // -------------------------------------------------------------- Lookups

    private fun baseRequest(url: String): YoutubeDLRequest = YoutubeDLRequest(url).apply {
        addOption("--ignore-config")
        addOption("--no-warnings")
        addOption("--socket-timeout", "20")
    }

    /**
     * Runs a lookup as its own process. Starting one stops the previous one (the
     * user has typed something new), and one that runs too long is stopped too.
     */
    private fun runLookup(request: YoutubeDLRequest): String {
        val pid = "lookup-${lookupSeq.incrementAndGet()}"
        synchronized(lookupLock) {
            currentLookup?.let {
                superseded.add(it)
                YoutubeDL.getInstance().destroyProcessById(it)
            }
            currentLookup = pid
        }
        val timer = watchdog.schedule(
            Runnable {
                lookupTimedOut.add(pid)
                YoutubeDL.getInstance().destroyProcessById(pid)
            },
            LOOKUP_TIMEOUT_SECONDS,
            TimeUnit.SECONDS,
        )
        try {
            return YoutubeDL.getInstance().execute(request, pid).out
        } catch (e: Exception) {
            if (superseded.contains(pid)) throw IllegalStateException("Replaced by a newer lookup.")
            if (lookupTimedOut.contains(pid)) throw IllegalStateException("The lookup timed out.")
            throw e
        } finally {
            timer.cancel(false)
            superseded.remove(pid)
            lookupTimedOut.remove(pid)
            synchronized(lookupLock) {
                if (currentLookup == pid) currentLookup = null
            }
        }
    }

    /** One video as yt-dlp's JSON. */
    private fun resolve(url: String): String {
        requireTrusted()
        ensureInit()
        val request = baseRequest(url).apply {
            addOption("--dump-single-json")
            addOption("--no-playlist")
        }
        return runLookup(request)
    }

    /** A YouTube search as yt-dlp's JSON (a playlist of flat entries). */
    private fun search(query: String, count: Int): String {
        requireTrusted()
        ensureInit()
        val request = baseRequest("ytsearch${count.coerceIn(1, 50)}:$query").apply {
            addOption("--dump-single-json")
            addOption("--flat-playlist")
        }
        return runLookup(request)
    }

    // ------------------------------------------------------------ Downloads

    private fun isMetered(): Boolean {
        val manager = app.getSystemService(ConnectivityManager::class.java) ?: return false
        return manager.isActiveNetworkMetered
    }

    /** Whether any download is queued or running (the service stops itself when none is). */
    fun hasWork(): Boolean = synchronized(gate) { queued > 0 }

    /**
     * Called by the service when Android's time limit for it is up: the downloads
     * that are left are stopped and end as failed with a clear reason.
     */
    fun onServiceTimeout() {
        val ids = synchronized(gate) { activeIds.toList() }
        timedOut.addAll(ids)
        for (id in ids) YoutubeDL.getInstance().destroyProcessById(id)
    }

    /**
     * Counts a download in and starts the service for the first one. If Android
     * does not allow the service to start (Android 12+ in the background), nothing
     * is left counted and the caller gets an error.
     */
    private fun begin(id: String) {
        synchronized(gate) {
            if (activeIds.contains(id)) throw IllegalStateException("This download is already running.")
            if (queued == 0) {
                try {
                    ContextCompat.startForegroundService(app, Intent(app, YtDlpService::class.java))
                } catch (e: Exception) {
                    throw IllegalStateException(
                        "Android did not allow the download to start in the background. " +
                            "Open Wavvy and try again.",
                        e,
                    )
                }
            }
            activeIds.add(id)
            queued++
        }
    }

    /**
     * Counts a download out. The last one stops the service if it is already
     * foreground; if it has not got that far yet it stops itself on seeing there
     * is no work, so a stop never overtakes the start.
     */
    private fun end(id: String) {
        synchronized(gate) {
            activeIds.remove(id)
            queued--
            if (queued <= 0) {
                queued = 0
                if (YtDlpService.running) {
                    try {
                        app.stopService(Intent(app, YtDlpService::class.java))
                    } catch (e: Exception) {
                        // It stops itself when it next starts or times out.
                    }
                }
            }
        }
    }

    /** The staged file name for a task: hex only, whatever the id or the site says. */
    private fun stemFor(id: String): String =
        "wv" + MessageDigest.getInstance("SHA-256").digest(id.toByteArray())
            .joinToString("") { "%02x".format(it) }.take(32)

    private fun download(call: MethodCall) {
        val id = call.argument<String>("id")!!
        val url = call.argument<String>("url")!!
        val dir = File(call.argument<String>("dir")!!)
        val wifiOnly = call.argument<Boolean>("wifiOnly") ?: false
        val title = call.argument<String>("title") ?: "Download"
        val stem = stemFor(id)

        // The cancel and time-out flags only ever exist for an id that is queued or
        // running and are removed when it ends, so none is left for this attempt.
        begin(id)
        try {
            downloads.execute { runDownload(id, url, dir, stem, wifiOnly, title) }
        } catch (e: RejectedExecutionException) {
            end(id)
            throw IllegalStateException("The downloader is shutting down.", e)
        }
    }

    private fun runDownload(
        id: String,
        url: String,
        dir: File,
        stem: String,
        wifiOnly: Boolean,
        title: String,
    ) {
        try {
            if (timedOut.contains(id)) {
                finish(id, "failed", error = TIMEOUT_MESSAGE)
                return
            }
            if (wifiOnly && isMetered()) {
                finish(id, "failed", error = "Waiting for Wi-Fi: this download is set to Wi-Fi only.")
                return
            }
            if (canceled.contains(id)) {
                finish(id, "canceled")
                return
            }
            requireTrusted()
            ensureInit()
            dir.mkdirs()
            prefs.edit().putString(KEY_STAGING, dir.absolutePath).apply()
            // Anything left under this name by an earlier attempt would pass for output.
            deleteStaged(dir, stem)
            val request = baseRequest(url).apply {
                addOption("--no-playlist")
                addOption("-f", "bestaudio[ext=m4a]/bestaudio/best")
                // The folder is a path option and the name is hex plus the extension,
                // so nothing a site supplies (or a '%' in a path) reaches the template.
                addOption("-P", dir.absolutePath)
                addOption("-o", "$stem.%(ext)s")
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
            if (canceled.contains(id)) {
                deleteStaged(dir, stem)
                finish(id, "canceled")
                return
            }
            val file = findOutput(dir, stem)
            if (file == null) {
                deleteStaged(dir, stem)
                finish(id, "failed", error = "yt-dlp finished but no audio file was found.")
            } else {
                // Keep the audio file, drop leftovers (fragments, .ytdl files).
                stagedFiles(dir, stem).filter { it != file }.forEach { it.delete() }
                finish(id, "complete", path = file.absolutePath)
            }
        } catch (e: Throwable) {
            try {
                deleteStaged(dir, stem)
            } catch (ignored: Exception) {
                // Best effort; the startup sweep catches what is left.
            }
            when {
                canceled.contains(id) -> finish(id, "canceled")
                timedOut.contains(id) -> finish(id, "failed", error = TIMEOUT_MESSAGE)
                else -> finish(id, "failed", error = e.message ?: e.javaClass.simpleName)
            }
        } finally {
            canceled.remove(id)
            timedOut.remove(id)
            end(id)
        }
    }

    // ------------------------------------------------------- Staged files

    /**
     * The files in [dir] called `<stem>.*`, only real files whose resolved path is
     * directly inside [dir] (a link or a path that points elsewhere is skipped).
     */
    private fun stagedFiles(dir: File, stem: String): List<File> {
        val root = try {
            dir.canonicalFile
        } catch (e: Exception) {
            return emptyList()
        }
        val candidates = root.listFiles { f -> f.name.startsWith("$stem.") } ?: return emptyList()
        return candidates.filter { f ->
            try {
                f.isFile && f.canonicalFile == File(root, f.name)
            } catch (e: Exception) {
                false
            }
        }
    }

    private fun deleteStaged(dir: File, stem: String) {
        stagedFiles(dir, stem).forEach { it.delete() }
    }

    /** The finished audio file for [stem], ignoring yt-dlp's temporary files. */
    private fun findOutput(dir: File, stem: String): File? =
        stagedFiles(dir, stem).filter { f ->
            !f.name.endsWith(".part") &&
                !f.name.endsWith(".ytdl") &&
                !f.name.endsWith(".json") &&
                !f.name.endsWith(".temp")
        }.maxByOrNull { it.length() }

    // -------------------------------------------------------------- Results

    private fun readResults(): JSONObject = try {
        JSONObject(prefs.getString(KEY_RESULTS, "{}") ?: "{}")
    } catch (e: Exception) {
        JSONObject()
    }

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
            val all = readResults()
            all.put(id, JSONObject(event.filterValues { it != null }))
            prefs.edit().putString(KEY_RESULTS, all.toString()).apply()
        }
        emit(event)
    }

    /** Results of finished downloads not yet acknowledged, and the ids still running. */
    private fun pending(): Map<String, Any?> = mapOf(
        "results" to results(),
        "active" to synchronized(gate) { activeIds.toList() },
    )

    private fun results(): List<Map<String, Any?>> = synchronized(prefs) {
        val all = readResults()
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
        val all = readResults()
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

    /** A plain file name: no folders, no leading dots, never empty. */
    private fun safeName(name: String): String =
        File(name.replace('\\', '/')).name.trimStart('.', ' ').ifEmpty { "download" }

    /**
     * Creates an empty file for [displayName] in [dir], or for "name (1).ext",
     * "name (2).ext" and so on if that name is taken, so two songs with the same
     * name never overwrite each other. Creating is atomic, so it cannot race.
     */
    private fun claimUnique(dir: File, displayName: String): File {
        val base = displayName.substringBeforeLast('.', displayName)
        val ext = if (displayName.contains('.')) "." + displayName.substringAfterLast('.') else ""
        var n = 0
        while (n < 1000) {
            val candidate = File(dir, if (n == 0) displayName else "$base ($n)$ext")
            if (candidate.createNewFile()) return candidate
            n++
        }
        throw IllegalStateException("Could not find a free file name in your music folder")
    }

    /**
     * Copies a finished file into the music library (Music/Wavvy) and deletes the
     * staged copy. Returns the content URI (Android 10+) or the file path. Only a
     * file in the downloader's staging folder is accepted.
     */
    private fun publish(call: MethodCall): String {
        val source = File(call.argument<String>("path")!!)
        val displayName = safeName(call.argument<String>("displayName")!!)
        val mime = mimeFor(displayName)

        val staging = prefs.getString(KEY_STAGING, null)
            ?: throw IllegalStateException("There is no downloaded file to add.")
        if (!source.isFile || source.canonicalFile.parentFile != File(staging).canonicalFile) {
            throw IllegalStateException("That file is not one the downloader made.")
        }

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
            // MediaStore itself renames a clash ("name (1).m4a").
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
            val target = claimUnique(dir, displayName)
            try {
                // The empty file is ours (just created), so overwriting it is safe.
                source.copyTo(target, overwrite = true)
            } catch (e: Exception) {
                target.delete()
                throw e
            }
            MediaScannerConnection.scanFile(app, arrayOf(target.absolutePath), arrayOf(mime), null)
            published = target.absolutePath
        }
        source.delete()
        return published
    }
}
