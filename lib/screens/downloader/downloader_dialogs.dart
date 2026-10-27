import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/downloads_provider.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/snackbar.utils.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Shows a loader, fetches the audio streams for [video] and lets the user
/// pick one to download.
Future<void> showYoutubeDownloadDialog(WidgetRef ref, Video video) async {
  final notifier = ref.read(ytdlpProvider.notifier);

  showAppDialog<void>(
    builder: (context) => const Center(child: PixelLoader(size: 40)),
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
      final a = Wv.of(context);
      return WvDialog(
        title: "Download",
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: streams.length,
            itemBuilder: (context, i) {
              final s = streams[i];
              final (bg, fg) = a.tonal(i);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: bg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: a.outline.withValues(alpha: 0.35)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      AppNav.pop();
                      notifier.startBackgroundDownload(
                        s.url.toString(),
                        video.title,
                        s.container.name,
                      );
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 64),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.audiotrack_rounded, size: 24, color: fg),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "${(s.bitrate.kiloBitsPerSecond).round()} kbps (${s.container.name})",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: fg,
                                    ),
                                  ),
                                  Text(
                                    "${s.size.totalMegaBytes.toStringAsFixed(2)} MB",
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: fg.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.download_rounded, size: 24, color: fg),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [wvDialogButton("Cancel", () => AppNav.pop())],
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
