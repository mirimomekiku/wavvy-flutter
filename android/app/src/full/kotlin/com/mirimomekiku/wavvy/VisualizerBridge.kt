package com.mirimomekiku.wavvy

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

/**
 * Spectrum for the player's visualizer, from android.media.audiofx.Visualizer
 * attached to the player's own audio session.
 *
 * Android requires RECORD_AUDIO for this even though nothing is recorded:
 * the Visualizer only ever sees the output of Wavvy's own session. Unlike the
 * audio effects it only matters while the player page is on screen, so it is
 * released with the Activity.
 *
 * Channels: `com.mirimomekiku.wavvy/visualizer` (start / stop) and an event
 * channel `com.mirimomekiku.wavvy/visualizer_frames` that delivers one
 * FloatArray of band levels (0..1, low to high) per frame. The band math is
 * mirrored in lib/playback/visualizer_math.dart; keep them in step.
 */
class VisualizerBridge(private val activity: Activity) : EventChannel.StreamHandler {
    companion object {
        private const val TAG = "WavvyVisualizer"
        private const val METHOD_CHANNEL = "com.mirimomekiku.wavvy/visualizer"
        private const val EVENT_CHANNEL = "com.mirimomekiku.wavvy/visualizer_frames"

        private const val MAX_CAPTURE_SIZE = 1024
        private const val DEFAULT_BANDS = 32
        private const val FLOOR_DB = -52.0
        private const val CEIL_DB = -6.0
        private const val TILT_DB = 10.0
        private const val FIRST_BIN = 2
        private const val LAST_FRACTION = 0.73

        /** Creates the bridge and registers its channels on [messenger]. */
        fun register(activity: Activity, messenger: BinaryMessenger): VisualizerBridge {
            val bridge = VisualizerBridge(activity)
            MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result -> bridge.onMethodCall(call, result) }
            EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(bridge)
            return bridge
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private var visualizer: Visualizer? = null
    private var sink: EventChannel.EventSink? = null

    // Bumped on every start/stop so frames queued by a released Visualizer
    // are dropped instead of reaching a newer session's listener.
    private var generation = 0

    private fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    val bands = (call.argument<Int>("bands") ?: DEFAULT_BANDS).coerceIn(1, 128)
                    start(sessionId, bands, result)
                }
                "stop" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            // IllegalStateException, UnsupportedOperationException, security
            // and runtime errors from the audio framework all end up here.
            Log.w(TAG, "Visualizer call ${call.method} failed", e)
            stop()
            result.error("visualizer_unavailable", e.message, null)
        }
    }

    private fun start(sessionId: Int, bands: Int, result: MethodChannel.Result) {
        stop()
        if (sessionId <= 0) {
            result.error("bad_session", "Invalid audio session $sessionId", null)
            return
        }
        if (activity.packageManager.checkPermission(
                Manifest.permission.RECORD_AUDIO,
                activity.packageName,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            result.error("permission", "Microphone permission is needed for the visualizer", null)
            return
        }

        val token = ++generation
        val created = Visualizer(sessionId)
        visualizer = created
        try {
            val range = Visualizer.getCaptureSizeRange()
            val size = min(range[1], MAX_CAPTURE_SIZE).coerceAtLeast(range[0])
            if (created.setCaptureSize(size) != Visualizer.SUCCESS) {
                throw IllegalStateException("Capture size $size was rejected")
            }
            val rate = (Visualizer.getMaxCaptureRate() / 2).coerceAtLeast(1)
            val listener = object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(v: Visualizer?, waveform: ByteArray?, samplingRate: Int) {}

                override fun onFftDataCapture(v: Visualizer?, fft: ByteArray?, samplingRate: Int) {
                    if (fft == null) return
                    val levels = try {
                        fftToBands(fft, bands)
                    } catch (e: Exception) {
                        return
                    }
                    main.post {
                        if (token == generation) sink?.success(levels)
                    }
                }
            }
            if (created.setDataCaptureListener(listener, rate, false, true) != Visualizer.SUCCESS) {
                throw IllegalStateException("The capture listener was rejected")
            }
            if (created.setEnabled(true) != Visualizer.SUCCESS) {
                throw IllegalStateException("The visualizer could not be enabled")
            }
            result.success(null)
        } catch (e: Exception) {
            Log.w(TAG, "Visualizer start failed", e)
            stop()
            result.error("visualizer_unavailable", e.message, null)
        }
    }

    /** Releases the Visualizer, if there is one. Never throws. */
    fun stop() {
        generation++
        val v = visualizer ?: return
        visualizer = null
        try {
            v.setEnabled(false)
        } catch (e: Exception) {
            Log.w(TAG, "Visualizer disable failed", e)
        }
        try {
            v.setDataCaptureListener(null, 0, false, false)
        } catch (e: Exception) {
            // Releasing below is what matters.
        }
        try {
            v.release()
        } catch (e: Exception) {
            Log.w(TAG, "Visualizer release failed", e)
        }
    }

    /** Called from MainActivity.onDestroy. */
    fun release() {
        stop()
        sink = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    /**
     * One FFT frame to [bands] log-spaced levels in 0..1. [fft] holds the DC
     * value, the Nyquist value, then a real and an imaginary byte per bin.
     */
    private fun fftToBands(fft: ByteArray, bands: Int): FloatArray {
        val out = FloatArray(bands)
        val bins = fft.size / 2
        if (bins < 4) return out
        val lo = FIRST_BIN.toDouble()
        val hi = max(lo + bands, bins * LAST_FRACTION)
        fun edge(i: Int): Double = lo * (hi / lo).pow(i.toDouble() / bands)
        for (b in 0 until bands) {
            val start = floor(edge(b)).toInt().coerceIn(1, bins - 1)
            val end = max(start + 1, ceil(edge(b + 1)).toInt()).coerceIn(start + 1, bins)
            var peak = 0.0
            for (k in start until end) {
                val re = fft[2 * k].toDouble()
                val im = fft[2 * k + 1].toDouble()
                peak = max(peak, sqrt(re * re + im * im))
            }
            val tilt = if (bands > 1) TILT_DB * b / (bands - 1) else 0.0
            val db = 20 * log10(peak / 128.0 + 1e-6) + tilt
            out[b] = ((db - FLOOR_DB) / (CEIL_DB - FLOOR_DB)).coerceIn(0.0, 1.0).toFloat()
        }
        return out
    }
}
