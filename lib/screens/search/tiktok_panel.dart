import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/downloads_provider.dart';
import 'package:wavvy/screens/search/library_results.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// TikTok body: loading, empty prompt, or the fetched video hero card.
class TikTokPanel extends ConsumerWidget {
  /// Called after a download started (the page clears its field).
  final VoidCallback onDownloadStarted;

  /// Fetches the video for the page's current field text.
  final VoidCallback onFetch;

  const TikTokPanel({
    super.key,
    required this.onDownloadStarted,
    required this.onFetch,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(tiktokProvider.select((s) => s.isLoading));
    final video = ref.watch(tiktokProvider.select((s) => s.fetchedVideo));
    final a = Wv.of(context);

    if (loading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: PixelLoader(size: 40)),
      );
    }

    if (video == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: SearchEmptyState(
          message: 'Copy a link from TikTok and paste it above',
          icon: Icons.link_rounded,
          action: WvButton(
            primary: true,
            width: 120,
            tooltip: 'Fetch',
            onPressed: onFetch,
            child: const Text('Fetch'),
          ),
        ),
      );
    }

    final cover = video['cover'];
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: a.frame(color: a.tertiaryContainer),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WvKicker('TIKTOK CLIP', color: a.onTertiaryContainer),
              const SizedBox(height: 12),
              if (cover != null)
                Center(
                  child: WvArtwork(
                    radius: 28,
                    elevated: true,
                    child: Image.network(
                      cover.toString(),
                      height: 250,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        height: 250,
                        width: 180,
                        color: a.surfaceHigh,
                        child: Icon(
                          Icons.broken_image_rounded,
                          color: a.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                video['title']?.toString() ?? 'No Title',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: a.onTertiaryContainer,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.person_rounded,
                    size: 18,
                    color: a.onTertiaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '@${video['author']}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: a.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Center(
                child: WvButton(
                  primary: true,
                  size: 52,
                  width: 220,
                  tooltip: 'Download Video',
                  onPressed: () async {
                    final ok = await ref
                        .read(tiktokProvider.notifier)
                        .downloadVideo(video);
                    if (ok) onDownloadStarted();
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download_rounded),
                      SizedBox(width: 6),
                      Text('Download Video'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
