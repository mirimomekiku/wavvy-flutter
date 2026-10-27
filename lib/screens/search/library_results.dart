import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/screens/library/albums/view/album.screen.dart';
import 'package:wavvy/screens/library/artists/view/artist.screen.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/song_menu.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

/// Aqua empty state shared by the Search sources: a gel orb, a title and an
/// optional hint.
class SearchEmptyState extends StatelessWidget {
  final String message;
  final String? hint;
  final IconData icon;
  final Widget? action;

  const SearchEmptyState({
    super.key,
    required this.message,
    this.hint,
    this.icon = Icons.search_rounded,
    this.action,
  });

  @override
  Widget build(BuildContext context) =>
      AquaEmptyState(icon: icon, title: message, hint: hint, action: action);
}

/// Section title with a pixel kicker, used above result groups.
class SearchSectionHeader extends StatelessWidget {
  final String kicker;
  final String title;

  const SearchSectionHeader({
    super.key,
    required this.kicker,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WvKicker(kicker),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 26,
              fontFamily: 'WorkSans',
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: a.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Local search results, computed purely from [libraryProvider] (nothing is
/// written back to any provider).
class LibraryResults extends ConsumerWidget {
  final String query;

  const LibraryResults({super.key, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: SearchEmptyState(
          icon: Icons.search_rounded,
          message: 'Search your library',
          hint: 'Find songs, albums and artists on this device.',
        ),
      );
    }

    final songs = ref.watch(libraryProvider.select((s) => s.songs));
    final albums = ref.watch(libraryProvider.select((s) => s.albums));
    final artists = ref.watch(libraryProvider.select((s) => s.artists));

    bool has(String? v) => v != null && v.toLowerCase().contains(q);

    final matchSongs = songs
        .where((s) => has(s.title) || has(s.artist) || has(s.album))
        .toList();
    final matchAlbums = albums
        .where((al) => has(al.album) || has(al.artist))
        .toList();
    final matchArtists = artists.where((ar) => has(ar.artist)).toList();

    if (matchSongs.isEmpty && matchAlbums.isEmpty && matchArtists.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: SearchEmptyState(
          icon: Icons.search_off_rounded,
          message: 'No results',
          hint: 'Check the spelling or try a different search.',
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        if (matchSongs.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: SearchSectionHeader(kicker: 'TRACKS', title: 'Songs'),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                return _SongResult(song: matchSongs[i], matches: matchSongs);
              }, childCount: matchSongs.length),
            ),
          ),
        ],
        if (matchAlbums.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: SearchSectionHeader(kicker: 'RECORDS', title: 'Albums'),
          ),
          SliverToBoxAdapter(
            child: _Shelf(
              count: matchAlbums.length,
              builder: (context, i, size) {
                final album = matchAlbums[i];
                return _ResultTile(
                  title: album.album,
                  subtitle: album.artist ?? 'Unknown',
                  index: i,
                  size: size,
                  id: album.id,
                  type: ArtworkType.ALBUM,
                  onTap: () => AppNav.push(AlbumDetailScreen(album: album)),
                );
              },
            ),
          ),
        ],
        if (matchArtists.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: SearchSectionHeader(kicker: 'PEOPLE', title: 'Artists'),
          ),
          SliverToBoxAdapter(
            child: _Shelf(
              count: matchArtists.length,
              builder: (context, i, size) {
                final artist = matchArtists[i];
                return _ResultTile(
                  circular: true,
                  title: artist.artist,
                  subtitle: 'Artist',
                  index: i,
                  size: size,
                  id: artist.id,
                  type: ArtworkType.ARTIST,
                  onTap: () => AppNav.push(ArtistDetailScreen(artist: artist)),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// Artwork with the procedural pixel cover as the fallback.
Widget _art(int id, ArtworkType type, double size) => QueryArtworkWidget(
  id: id,
  type: type,
  artworkFit: BoxFit.cover,
  artworkWidth: size,
  artworkHeight: size,
  artworkBorder: BorderRadius.zero,
  nullArtworkWidget: WvMediaPlaceholder(seed: id * 31 + type.index, size: size),
);

class _SongResult extends ConsumerWidget {
  final SongModel song;
  final List<SongModel> matches;

  const _SongResult({required this.song, required this.matches});

  @override
  Widget build(BuildContext buildContext, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    return WvSongRow(
      song: song,
      index: matches.indexOf(song),
      isCurrent: player.currentSong?.id == song.id,
      isPlaying: player.isPlaying,
      secondary: song.artist ?? 'Unknown Artist',
      onTap: () => ref
          .read(playerProvider.notifier)
          .playSong(song, contextList: matches),
      onAction: () => SongMenuHelper.show(buildContext, ref, song),
      onLongPress: () => SongMenuHelper.show(buildContext, ref, song),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final int index;
  final double size;
  final int id;
  final ArtworkType type;
  final bool circular;
  final VoidCallback onTap;

  const _ResultTile({
    required this.title,
    required this.subtitle,
    required this.index,
    required this.size,
    required this.id,
    required this.type,
    required this.onTap,
    this.circular = false,
  });

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final align = circular ? TextAlign.center : TextAlign.start;
    final (ring, _) = a.tonal(index);

    Widget art = WvArtwork(
      circular: circular,
      shape: circular ? null : Ds.tileShape(index),
      child: _art(id, type, circular ? size - 8 : size),
    );
    if (circular) {
      art = Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
        child: art,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: circular
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.stretch,
        children: [
          art,
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: a.text,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: TextStyle(fontSize: 12, color: a.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Horizontal shelf of tiles; the height follows the text scale.
class _Shelf extends StatelessWidget {
  final int count;
  final Widget Function(BuildContext context, int index, double size) builder;

  const _Shelf({required this.count, required this.builder});

  @override
  Widget build(BuildContext context) {
    const side = 128.0;
    final scaler = MediaQuery.textScalerOf(context);
    final height =
        side + 8 + scaler.scale(14) * 1.5 + scaler.scale(12) * 1.5 + 8;

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) =>
            SizedBox(width: side, child: builder(context, i, side)),
      ),
    );
  }
}
