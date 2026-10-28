import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/artwork/album_art_match.dart';
import 'package:wavvy/providers/album_art_provider.dart';
import 'package:wavvy/theme/pixel_art.dart';

/// What shows where the library has no artwork: the cover fetched for the
/// album if there is one, else the pixel-art placeholder.
///
/// A row only reads memory: the song's album key comes from a map built once
/// per library change, and the picture from the cache index with a `select` on
/// its own key. There is no file listing and no network call here. Until the
/// index has loaded (or when it has nothing) the placeholder shows, so a cover
/// that exists appears in place of it and nothing flashes in between.
class AlbumArtFallback extends ConsumerWidget {
  const AlbumArtFallback({
    super.key,
    required this.id,
    required this.type,
    required this.size,
    required this.seed,
  });

  /// A song id ([ArtworkType.AUDIO]) or an album id ([ArtworkType.ALBUM]).
  final int id;
  final ArtworkType type;
  final double size;

  /// Seed of the placeholder picture.
  final int seed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = WvMediaPlaceholder(seed: seed, size: size);
    final String? key;
    switch (type) {
      case ArtworkType.ALBUM:
        key = albumKey(albumId: id);
      case ArtworkType.AUDIO:
        key = ref.watch(songArtRefsProvider.select((m) => m[id]?.key));
      default:
        key = null;
    }
    if (key == null) return placeholder;
    final file = ref.watch(albumArtFileProvider(key));
    if (file == null) return placeholder;

    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(
      64,
      1000,
    );
    return Image.file(
      file,
      // A re-fetched cover is a new File object: reload even on the same path.
      key: ValueKey('${file.path}#${identityHashCode(file)}'),
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: pixels,
      gaplessPlayback: true,
      filterQuality: size >= 96 ? FilterQuality.high : FilterQuality.medium,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}
