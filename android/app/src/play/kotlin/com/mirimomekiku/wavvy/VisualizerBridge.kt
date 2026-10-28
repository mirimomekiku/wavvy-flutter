package com.mirimomekiku.wavvy

import android.app.Activity
import io.flutter.plugin.common.BinaryMessenger

/**
 * The Play build has no visualizer (it would need the microphone permission):
 * this stand-in keeps MainActivity the same in both flavors and registers
 * nothing. The real one is in src/full.
 */
class VisualizerBridge private constructor() {
    companion object {
        @Suppress("UNUSED_PARAMETER")
        fun register(activity: Activity, messenger: BinaryMessenger): VisualizerBridge =
            VisualizerBridge()
    }

    fun release() = Unit
}
