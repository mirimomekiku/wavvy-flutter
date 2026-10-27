import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/downloads_provider.dart';
import 'package:wavvy/screens/downloader/downloader_dialogs.dart';
import 'package:wavvy/screens/search/library_results.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

String _duration(Duration? d) {
  if (d == null) return '';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// YouTube search results; each row has a Download action.
class YoutubeResults extends ConsumerWidget {
  const YoutubeResults({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ytdlpProvider);
    final results = state.results;
    if (state.isSearching) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.searchError.isNotEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: SearchEmptyState(
          message: state.searchError,
          icon: Icons.cloud_off_rounded,
          action: TextButton.icon(
            onPressed: () =>
                ref.read(ytdlpProvider.notifier).search(state.searchQuery),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ),
      );
    }
    if (results.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: SearchEmptyState(
          message: state.hasSearched
              ? 'No results for ${state.searchQuery}'
              : 'Search YouTube for music to download',
          icon: state.hasSearched
              ? Icons.search_off_rounded
              : Icons.ondemand_video_rounded,
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, i) {
          final video = results[i];
          final a = Wv.of(context);
          final (bg, fg) = a.tonal(i);
          final dur = _duration(video.duration);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: a.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: a.outline.withValues(alpha: 0.35)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => showYoutubeDownloadDialog(ref, video),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 84),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                    child: Row(
                      children: [
                        WvArtwork(
                          radius: 18,
                          child: Image.network(
                            video.thumbnails.lowResUrl,
                            width: 88,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 88,
                              height: 60,
                              color: bg,
                              child: Icon(
                                Icons.ondemand_video_rounded,
                                size: 24,
                                color: fg,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                video.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: a.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dur.isEmpty
                                    ? video.author
                                    : '${video.author} · $dur',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: a.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        WvButton(
                          primary: true,
                          size: 40,
                          width: 48,
                          tooltip: 'Download',
                          onPressed: () =>
                              showYoutubeDownloadDialog(ref, video),
                          child: const Icon(Icons.download_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }, childCount: results.length),
      ),
    );
  }
}
