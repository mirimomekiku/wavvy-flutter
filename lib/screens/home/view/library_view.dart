import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/screens/library/albums/view/album.screen.dart';
import 'package:wavvy/screens/library/artists/view/artist.screen.dart';
import 'package:wavvy/screens/library/playlists/view/playlist.screen.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Library as photo-framed grids under Aqua section bars.
class LibraryView extends ConsumerWidget {
  const LibraryView({super.key});

  static const int _previewCount = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    {
      final albums = ref.watch(libraryProvider.select((s) => s.albums));
      final artists = ref.watch(libraryProvider.select((s) => s.artists));
      final playlists = ref.watch(playlistsProvider.select((s) => s.playlists));
      final a = Aqua.of(context);

      return CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          if (albums.isNotEmpty) ...[
            _sectionBar("Albums", () => AppNav.pushNamed("/albums"), a),
            _grid(
              maxExtent: 190,
              count: albums.length.clamp(0, _previewCount),
              builder: (context, index) {
                final album = albums[index];
                return _LibraryTile(
                  label: album.album,
                  sublabel: "${album.numOfSongs} songs",
                  onTap: () => AppNav.push(AlbumDetailScreen(album: album)),
                  artwork: QueryArtworkWidget(
                    id: album.id,
                    type: ArtworkType.ALBUM,
                    artworkFit: BoxFit.cover,
                    artworkBorder: BorderRadius.zero,
                    nullArtworkWidget: _placeholder(a, Icons.album_rounded),
                  ),
                );
              },
            ),
          ],
          if (artists.isNotEmpty) ...[
            _sectionBar("Artists", () => AppNav.pushNamed("/artists"), a),
            _grid(
              maxExtent: 170,
              count: artists.length.clamp(0, _previewCount),
              builder: (context, index) {
                final artist = artists[index];
                return _LibraryTile(
                  label: artist.artist,
                  circular: true,
                  onTap: () => AppNav.push(ArtistDetailScreen(artist: artist)),
                  artwork: QueryArtworkWidget(
                    id: artist.id,
                    type: ArtworkType.ARTIST,
                    artworkFit: BoxFit.cover,
                    artworkBorder: BorderRadius.zero,
                    nullArtworkWidget: _placeholder(a, Icons.person_rounded),
                  ),
                );
              },
            ),
          ],
          _sectionBar("Playlists", () => AppNav.pushNamed("/playlists"), a),
          if (playlists.isNotEmpty)
            _grid(
              maxExtent: 170,
              count: playlists.length.clamp(0, _previewCount),
              builder: (context, index) {
                final playlist = playlists[index];
                return _LibraryTile(
                  label: playlist['name'],
                  onTap: () => AppNav.push(
                    PlaylistDetailScreen(
                      playlistId: playlist['id'],
                      playlistName: playlist['name'],
                    ),
                  ),
                  artwork: _placeholder(a, Icons.queue_music_rounded),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      );
    }
  }

  Widget _placeholder(AquaPalette a, IconData icon) {
    return Container(
      color: a.stripe,
      child: Center(child: Icon(icon, size: 44, color: a.textSecondary)),
    );
  }

  Widget _sectionBar(String title, VoidCallback onTap, AquaPalette a) {
    return SliverToBoxAdapter(
      child: AquaSectionBar(
        title: title,
        trailing: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: 1,
                child: Text(
                  "See All",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: a.accent,
                    decoration: TextDecoration.underline,
                    decorationColor: a.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid({
    required double maxExtent,
    required int count,
    required IndexedWidgetBuilder builder,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxExtent,
          childAspectRatio: 0.8,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        delegate: SliverChildBuilderDelegate(builder, childCount: count),
      ),
    );
  }
}

/// Photo-framed artwork with a centered caption.
class _LibraryTile extends StatelessWidget {
  final Widget artwork;
  final String label;
  final String? sublabel;
  final bool circular;
  final VoidCallback onTap;

  const _LibraryTile({
    required this.artwork,
    required this.label,
    required this.onTap,
    this.sublabel,
    this.circular = false,
  });

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: AquaPhotoFrame(circular: circular, child: artwork),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: a.text,
              ),
            ),
            if (sublabel != null)
              Text(
                sublabel!,
                maxLines: 1,
                style: TextStyle(fontSize: 11.5, color: a.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
