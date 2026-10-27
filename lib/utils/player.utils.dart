import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wavvy/models/lyric.dart';
import 'package:wavvy/utils/snackbar.utils.dart';

class PlayerUtils {
  static String formatDuration(Duration d) {
    if (d.inHours > 0) {
      final hours = d.inHours;
      final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return "$hours:$minutes:$seconds";
    }
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  static String formatDurationInt(int? ms) {
    if (ms == null) return "--:--";
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  static String formatBytes(int bytes, int decimals) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return "${size.toStringAsFixed(i == 0 ? 0 : decimals)} ${suffixes[i]}";
  }

  static List<Lyric> parseLrc(String lrc) {
    final List<String> lines = lrc.split('\n');
    final List<Lyric> parsedLyrics = [];
    final RegExp regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');

    for (String line in lines) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        String msString = match.group(3)!;
        if (msString.length == 2) msString += "0"; // 12 -> 120ms
        final milliseconds = int.parse(msString);

        final text = match.group(4)!.trim();

        parsedLyrics.add(
          Lyric(
            Duration(
              minutes: minutes,
              seconds: seconds,
              milliseconds: milliseconds,
            ),
            text,
          ),
        );
      }
    }

    return parsedLyrics;
  }

  static Future<void> openEqualizer(dynamic sessionId) async {
    if (Platform.isAndroid) {
      try {
        final intent = AndroidIntent(
          action: 'android.media.action.DISPLAY_AUDIO_EFFECT_CONTROL_PANEL',
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
          arguments: {'android.media.extra.AUDIO_SESSION': sessionId},
        );
        await intent.launch();
      } catch (e) {
        AppSnackbar.showErrorSnackBar(
          "Error",
          "No equalizer found on this device",
        );
      }
    }
  }

  static String extractTextFromDom(dynamic node) {
    if (node is String) return node;

    if (node is List) {
      return node.map((n) => extractTextFromDom(n)).join('');
    }

    if (node is Map) {
      final String content = node['children'] != null
          ? extractTextFromDom(node['children'])
          : '';

      return (node['tag'] == 'p') ? "$content\n\n" : content;
    }

    return '';
  }

  static Future<void> shareSong(SongModel song) async {
    final File file = File(song.data);

    if (await file.exists()) {
      try {
        // Create an XFile from the path
        final songFile = XFile(song.data);
        final params = ShareParams(
          text: "Share ${song.title} - ${song.artist}",
          files: [songFile],
        );

        await SharePlus.instance.share(params);
      } catch (e) {
        AppSnackbar.showErrorSnackBar("Error", "Could not share file: $e");
      }
    } else {
      AppSnackbar.showErrorSnackBar("Error", "File not found on device");
    }
  }

  static IconData getLoopIcon(LoopMode mode) {
    switch (mode) {
      case LoopMode.one:
        return Icons.repeat_one_rounded;
      case LoopMode.all:
        return Icons.repeat_rounded;
      default:
        return Icons.repeat_rounded;
    }
  }
}
