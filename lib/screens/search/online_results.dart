import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/downloader/models.dart';
import 'package:wavvy/downloader/search_provider.dart';
import 'package:wavvy/downloader/ui/engine_card.dart';
import 'package:wavvy/screens/search/library_results.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

String _duration(int? seconds) {
  if (seconds == null) return '';
  final d = Duration(seconds: seconds);
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// The Online source of Search: the downloader's setup card until it is ready,
/// then results (or the one item a pasted link points to), each with a download
/// button.
class OnlineResults extends ConsumerWidget {
  const OnlineResults({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engineReady = ref.watch(engineProvider.select((e) => e.isReady));
    if (!engineReady) {
      return const SliverToBoxAdapter(child: EngineSetupCard());
    }

    final state = ref.watch(onlineSearchProvider);
    if (state.isLoading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: AquaSpinner(size: 36)),
      );
    }
    if (state.error.isNotEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: SearchEmptyState(
          message: state.error,
          icon: Icons.cloud_off_rounded,
          action: TextButton.icon(
            onPressed: () =>
                ref.read(onlineSearchProvider.notifier).submit(state.query),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ),
      );
    }
    if (state.results.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: SearchEmptyState(
          message: state.hasSearched
              ? 'No results for ${state.query}'
              : 'Search for music, or paste a link',
          hint: state.hasSearched
              ? null
              : 'YouTube, TikTok and many other sites work.',
          icon: state.hasSearched
              ? Icons.search_off_rounded
              : Icons.cloud_download_rounded,
        ),
      );
    }

    final isLink = MediaInfo.looksLikeUrl(state.query);
    return SliverToBoxAdapter(
      child: AquaWindow(
        title: isLink ? 'Link' : 'Results',
        subtitle: isLink ? null : state.query,
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          children: [
            for (var i = 0; i < state.results.length; i++)
              _ResultRow(info: state.results[i], index: i),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends ConsumerWidget {
  const _ResultRow({required this.info, required this.index});
  final MediaInfo info;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final task = ref.watch(
      downloadsProvider.select(
        (tasks) => tasks.where((t) => t.videoId == info.id).firstOrNull,
      ),
    );
    final duration = _duration(info.durationSeconds);
    final detail = [
      if (info.artist.isNotEmpty) info.artist,
      if (duration.isNotEmpty) duration,
    ].join(' · ');
    final notifier = ref.read(downloadsProvider.notifier);

    Widget action;
    if (task == null || task.status == DownloadStatus.canceled) {
      action = WvButton(
        primary: true,
        circular: true,
        size: 38,
        tooltip: 'Download',
        onPressed: () => notifier.enqueue(info),
        child: const Icon(Icons.download_rounded),
      );
    } else if (task.status.active) {
      action = Tooltip(
        message: 'Downloading, tap to cancel',
        child: InkResponse(
          onTap: () => notifier.cancel(task.id),
          radius: 22,
          child: SizedBox.square(
            dimension: 38,
            child: AquaProgressRing(
              value: task.status == DownloadStatus.running && task.progress > 0
                  ? task.progress / 100
                  : null,
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: a.textSecondary,
              ),
            ),
          ),
        ),
      );
    } else if (task.status == DownloadStatus.complete) {
      action = SizedBox.square(
        dimension: 38,
        child: const Tooltip(
          message: 'Downloaded',
          child: Center(child: AquaCheckMark(size: 26)),
        ),
      );
    } else {
      action = WvButton(
        circular: true,
        size: 38,
        tooltip: 'Try again',
        onPressed: () => notifier.retry(task.id),
        child: const Icon(Icons.refresh_rounded),
      );
    }

    return Container(
      color: index.isOdd ? a.stripe : a.surface,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          WvArtwork(
            radius: 6,
            child: SizedBox(
              width: 72,
              height: 54,
              child: info.thumbnail.isEmpty
                  ? Icon(Icons.music_note_rounded, color: a.textSecondary)
                  : Image.network(
                      info.thumbnail,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.music_note_rounded,
                        color: a.textSecondary,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: a.text,
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: a.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          action,
        ],
      ),
    );
  }
}
