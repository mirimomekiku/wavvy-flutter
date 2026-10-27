package com.mirimomekiku.wavvy.ytdlp

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine

/**
 * The Play build has no downloader: this stand-in keeps MainActivity the same
 * in both flavors and registers nothing. The real one is in src/full.
 */
object YtDlpPlugin {
    @Suppress("UNUSED_PARAMETER")
    fun register(context: Context, engine: FlutterEngine) = Unit
}
