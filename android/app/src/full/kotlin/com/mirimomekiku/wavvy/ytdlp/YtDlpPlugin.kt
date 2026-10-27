package com.mirimomekiku.wavvy.ytdlp

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * The downloader's bridge to Flutter (full flavor only): one method channel for
 * requests and one event channel for engine and download progress. All the work
 * is in [YtDlpRunner].
 */
object YtDlpPlugin {
    private const val CHANNEL = "com.mirimomekiku.wavvy/ytdlp"
    private const val EVENTS = "com.mirimomekiku.wavvy/ytdlp_events"

    fun register(context: Context, engine: FlutterEngine) {
        val runner = YtDlpRunner.get(context.applicationContext)
        val messenger = engine.dartExecutor.binaryMessenger

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            runner.handle(call, result)
        }
        EventChannel(messenger, EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    runner.attach(events)
                }

                override fun onCancel(arguments: Any?) {
                    runner.attach(null)
                }
            },
        )
    }
}
