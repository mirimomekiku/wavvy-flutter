package com.mirimomekiku.wavvy

import android.content.ContentUris
import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Reads the technical details of one audio file for the quality badge: codec,
 * sample rate, channels, bitrate, bit depth and whether the codec is lossless.
 *
 * The `info` call takes a content/file URI string ("uri") or a MediaStore audio
 * id ("id") and answers a map, or null when the file cannot be read. The work
 * runs on a single background thread; every resource is released in finally and
 * nothing here throws, so a bad file only costs the badge its details.
 * Bit depth is known only when the platform exposes it (FLAC header, PCM
 * encoding, or the retriever on Android 12+); otherwise it is null.
 */
object AudioInfo {
    private const val TAG = "Wavvy"
    const val CHANNEL = "com.mirimomekiku.wavvy/audio_info"

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "info") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val uriText = call.argument<String>("uri")
            val id = call.argument<Number>("id")?.toLong()
            try {
                worker.execute {
                    val described = try {
                        describe(app, uriText, id)
                    } catch (e: Throwable) {
                        Log.w(TAG, "Could not read audio info", e)
                        null
                    }
                    main.post {
                        try {
                            result.success(described)
                        } catch (e: Exception) {
                            Log.w(TAG, "Could not answer audio info", e)
                        }
                    }
                }
            } catch (e: Exception) {
                // The executor refused the task: answer without details.
                result.success(null)
            }
        }
    }

    private fun resolveUri(uriText: String?, id: Long?): Uri? {
        if (!uriText.isNullOrBlank()) return Uri.parse(uriText.trim())
        if (id != null && id > 0) {
            return ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
        }
        return null
    }

    private fun describe(context: Context, uriText: String?, id: Long?): Map<String, Any?>? {
        val uri = resolveUri(uriText, id) ?: return null

        var mime: String? = null
        var sampleRate: Int? = null
        var channels: Int? = null
        var bitrate: Long? = null
        var bitDepth: Int? = null
        var durationMs: Long? = null

        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(context, uri, null)
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val trackMime = format.getString(MediaFormat.KEY_MIME)
                if (trackMime == null || !trackMime.startsWith("audio/")) continue
                mime = trackMime
                sampleRate = intOf(format, MediaFormat.KEY_SAMPLE_RATE)
                channels = intOf(format, MediaFormat.KEY_CHANNEL_COUNT)
                bitrate = intOf(format, MediaFormat.KEY_BIT_RATE)?.toLong()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    bitDepth = depthOfEncoding(intOf(format, MediaFormat.KEY_PCM_ENCODING))
                }
                if (format.containsKey(MediaFormat.KEY_DURATION)) {
                    durationMs = format.getLong(MediaFormat.KEY_DURATION) / 1000
                }
                break
            }
        } catch (e: Exception) {
            // Fall back to the retriever below.
            Log.w(TAG, "MediaExtractor could not read $uri", e)
        } finally {
            try {
                extractor.release()
            } catch (e: Exception) {
                // Nothing to do.
            }
        }

        // The retriever fills what the extractor lacks (and covers formats it
        // refuses).
        if (mime == null || bitrate == null || sampleRate == null || bitDepth == null || durationMs == null) {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(context, uri)
                if (mime == null) {
                    mime = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE)
                }
                if (bitrate == null) {
                    bitrate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLongOrNull()
                }
                if (durationMs == null) {
                    durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (sampleRate == null) {
                        sampleRate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE)?.toIntOrNull()
                    }
                    if (bitDepth == null) {
                        bitDepth = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITS_PER_SAMPLE)?.toIntOrNull()
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "MediaMetadataRetriever could not read $uri", e)
            } finally {
                try {
                    retriever.release()
                } catch (e: Exception) {
                    // Nothing to do.
                }
            }
        }

        // FLAC carries sample rate, channels and bits per sample in its first
        // metadata block, which Android's extractor does not report.
        if (mime == null || mime == "audio/flac" || mime == "audio/x-flac") {
            val header = readFlacHeader(context, uri)
            if (header != null) {
                if (mime == null) mime = "audio/flac"
                if (sampleRate == null) sampleRate = header.sampleRate
                if (channels == null) channels = header.channels
                if (bitDepth == null) bitDepth = header.bitDepth
            }
        }

        val type = mime ?: return null
        if (bitDepth != null && (bitDepth < 8 || bitDepth > 32)) bitDepth = null
        val codec = codecName(type)
        return mapOf(
            "mime" to type,
            "codec" to codec,
            "sampleRate" to sampleRate?.takeIf { it > 0 },
            "channels" to channels?.takeIf { it > 0 },
            "bitrate" to bitrate?.takeIf { it > 0 },
            "bitDepth" to bitDepth,
            "durationMs" to durationMs?.takeIf { it > 0 },
            "lossless" to isLossless(type),
        )
    }

    private fun intOf(format: MediaFormat, key: String): Int? =
        try {
            if (format.containsKey(key)) format.getInteger(key) else null
        } catch (e: Exception) {
            null
        }

    /** Bits per sample for an AudioFormat.ENCODING_PCM_* value (ints, to avoid API gating). */
    private fun depthOfEncoding(encoding: Int?): Int? = when (encoding) {
        3 -> 8 // ENCODING_PCM_8BIT
        2 -> 16 // ENCODING_PCM_16BIT
        21 -> 24 // ENCODING_PCM_24BIT_PACKED
        22 -> 32 // ENCODING_PCM_32BIT
        4 -> 32 // ENCODING_PCM_FLOAT
        else -> null
    }

    private class FlacHeader(val sampleRate: Int, val channels: Int, val bitDepth: Int)

    /** Reads the STREAMINFO block at the start of a FLAC file, or null. */
    private fun readFlacHeader(context: Context, uri: Uri): FlacHeader? {
        var stream: InputStream? = null
        try {
            stream = context.contentResolver.openInputStream(uri) ?: return null
            val bytes = ByteArray(26)
            var read = 0
            while (read < bytes.size) {
                val n = stream.read(bytes, read, bytes.size - read)
                if (n < 0) break
                read += n
            }
            if (read < bytes.size) return null
            // "fLaC", then a block header (type 0 = STREAMINFO, 34 bytes long).
            if (bytes[0] != 'f'.code.toByte() || bytes[1] != 'L'.code.toByte() ||
                bytes[2] != 'a'.code.toByte() || bytes[3] != 'C'.code.toByte()
            ) return null
            if ((bytes[4].toInt() and 0x7F) != 0) return null
            // STREAMINFO starts at byte 8: 16+16 bit block sizes, 24+24 bit frame
            // sizes, then 20 bits rate, 3 bits channels - 1, 5 bits depth - 1.
            val b = IntArray(4) { bytes[18 + it].toInt() and 0xFF }
            val rate = (b[0] shl 12) or (b[1] shl 4) or (b[2] shr 4)
            val channels = ((b[2] shr 1) and 0x07) + 1
            val depth = (((b[2] and 0x01) shl 4) or (b[3] shr 4)) + 1
            if (rate <= 0) return null
            return FlacHeader(rate, channels, depth)
        } catch (e: Exception) {
            return null
        } finally {
            try {
                stream?.close()
            } catch (e: Exception) {
                // Nothing to do.
            }
        }
    }

    private fun codecName(mime: String): String {
        return when (mime.lowercase(Locale.ROOT)) {
            "audio/mpeg", "audio/mpeg-l1", "audio/mpeg-l2", "audio/mp3" -> "MP3"
            "audio/mp4a-latm", "audio/aac", "audio/aacp", "audio/aac-adts" -> "AAC"
            "audio/flac", "audio/x-flac" -> "FLAC"
            "audio/alac", "audio/x-alac" -> "ALAC"
            "audio/vorbis" -> "Vorbis"
            "audio/opus" -> "Opus"
            "audio/raw", "audio/x-wav", "audio/wav", "audio/wave", "audio/vnd.wave" -> "WAV"
            "audio/amr-wb", "audio/3gpp", "audio/amr" -> "AMR"
            "audio/ac3" -> "AC-3"
            "audio/eac3" -> "E-AC-3"
            "audio/x-ape", "audio/ape" -> "APE"
            "audio/x-wavpack", "audio/wavpack" -> "WavPack"
            "audio/x-ms-wma", "audio/wma" -> "WMA"
            else -> mime.substringAfter('/').removePrefix("x-").uppercase(Locale.ROOT)
        }
    }

    private fun isLossless(mime: String): Boolean = when (codecName(mime)) {
        "FLAC", "ALAC", "WAV", "APE", "WavPack" -> true
        else -> false
    }
}
