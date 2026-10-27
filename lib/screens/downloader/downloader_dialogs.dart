import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/downloads_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/snackbar.utils.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Shows a loader, fetches the audio streams for [video] and lets the user
/// pick one to download.
Future<void> showYoutubeDownloadDialog(WidgetRef ref, Video video) async {
  final notifier = ref.read(ytdlpProvider.notifier);

  showAppDialog<void>(
    builder: (context) => const Center(child: CircularProgressIndicator()),
  );

  final List<AudioOnlyStreamInfo>? streams = await notifier.fetchAudioStreams(
    video,
  );
  AppNav.pop();

  if (streams == null) {
    AppSnackbar.showErrorSnackBar("Error", "Could not fetch streams");
    return;
  }

  showAppDialog<void>(
    builder: (context) {
      final a = Aqua.of(context);
      return AlertDialog(
        title: Text(
          "Download",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: a.text,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: streams.length,
            itemBuilder: (context, i) {
              final s = streams[i];
              return ColoredBox(
                color: i.isEven ? a.background : a.stripe,
                child: ListTile(
                  leading: Icon(Icons.audiotrack, color: a.glyph),
                  title: Text(
                    "${(s.bitrate.kiloBitsPerSecond).round()} kbps (${s.container.name})",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: a.text,
                    ),
                  ),
                  subtitle: Text(
                    "${s.size.totalMegaBytes.toStringAsFixed(2)} MB",
                    style: TextStyle(fontSize: 12, color: a.textSecondary),
                  ),
                  trailing: Icon(Icons.download, color: a.accent),
                  onTap: () {
                    AppNav.pop();
                    notifier.startBackgroundDownload(
                      s.url.toString(),
                      video.title,
                      s.container.name,
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          GelButton(
            width: 88,
            onPressed: () => AppNav.pop(),
            child: const Text("Cancel"),
          ),
        ],
      );
    },
  );
}

void confirmDeleteYoutubeDownload(WidgetRef ref, String taskId) {
  showConfirmDialog(
    title: "Delete",
    message: "Delete this file?",
    confirmText: "Yes",
    cancelText: "No",
    destructive: true,
    onConfirm: () => ref.read(ytdlpProvider.notifier).removeDownload(taskId),
  );
}

void confirmDeleteTikTokDownload(WidgetRef ref, String taskId) {
  showConfirmDialog(
    title: "Delete Download",
    message: "Are you sure you want to remove this video?",
    confirmText: "Delete",
    destructive: true,
    onConfirm: () => ref.read(tiktokProvider.notifier).removeDownload(taskId),
  );
}
