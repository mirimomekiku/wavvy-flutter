import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/library_section_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/screens/library/albums/view/album.screen.dart';
import 'package:wavvy/screens/library/artists/view/artist.screen.dart';
import 'package:wavvy/screens/library/playlists/view/playlist.screen.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/playlist_dialogs.dart';
import 'package:wavvy/widgets/song_menu.dart';
import 'package:wavvy/widgets/wv_song_list.dart';
import 'package:wavvy/widgets/page_heading.dart';

final libraryQueryProvider = StateProvider<String>((ref) => '');

const _sectionLabels = ['Songs', 'Albums', 'Artists', 'Playlists'];

const _sortLabels = ['Title', 'Artist', 'Recently added'];
const _sortOptions = [
  SortOption.titleAZ,
  SortOption.artistAZ,
  SortOption.dateNewest,
];

/// The Library tab: Songs / Albums / Artists / Playlists behind toggle chips.
class LibraryTab extends ConsumerWidget {
  const LibraryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(librarySectionProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(libraryProvider.notifier).fetchAllSongs(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _Header(section: section)),
          const SliverToBoxAdapter(child: _LibrarySearch()),
          if (ref.watch(libraryProvider.select((s) => s.isLoading)))
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (ref.watch(libraryProvider.select((s) => s.error)).isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(ref.watch(libraryProvider).error),
              ),
            ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SectionChipsDelegate(
              selected: section.index,
              extent: _chipsExtent(context),
            ),
          ),
          ...switch (section) {
            LibrarySection.songs => const [_SongsSection()],
            LibrarySection.albums => const [_AlbumsSection()],
            LibrarySection.artists => const [_ArtistsSection()],
            LibrarySection.playlists => const [_PlaylistsSection()],
          },
          SliverToBoxAdapter(
            child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }

  /// Tall enough for the compact chips (+ indicator) at the current text scale.
  static double _chipsExtent(BuildContext context) {
    final label = MediaQuery.textScalerOf(context).scale(12) * 1.4;
    return (label + 24).clamp(48.0, 100.0);
  }
}

class _Header extends ConsumerWidget {
  final LibrarySection section;

  const _Header({required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(libraryProvider.select((s) => s.songs.length));
    return WvPageHeading(
      title: 'Library',
      subtitle: '$count tracks on this device',
      settings: true,
      actions: [
        if (section == LibrarySection.playlists)
          IconButton(
            tooltip: 'New Playlist',
            onPressed: () => showNewPlaylistDialog(ref),
            icon: const Icon(Icons.add_rounded),
          ),
      ],
    );
  }
}

class _LibrarySearch extends ConsumerStatefulWidget {
  const _LibrarySearch();
  @override
  ConsumerState<_LibrarySearch> createState() => _LibrarySearchState();
}

class _LibrarySearchState extends ConsumerState<_LibrarySearch> {
  late final TextEditingController _query = TextEditingController(
    text: ref.read(libraryQueryProvider),
  );
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: TextField(
      controller: _query,
      onChanged: (v) => ref.read(libraryQueryProvider.notifier).state = v,
      decoration: InputDecoration(
        hintText: 'Filter your library',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: ref.watch(libraryQueryProvider).isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear filter',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _query.clear();
                  ref.read(libraryQueryProvider.notifier).state = '';
                },
              ),
      ),
    ),
  );
}

class _SectionChipsDelegate extends SliverPersistentHeaderDelegate {
  final int selected;
  final double extent;

  _SectionChipsDelegate({required this.selected, required this.extent});

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;

  @override
  bool shouldRebuild(covariant _SectionChipsDelegate old) =>
      old.selected != selected || old.extent != extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // A persistent header's child is laid out loosely: fill the extent.
    return Container(
      height: extent,
      color: Wv.of(context).background,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Consumer(
        builder: (context, ref, _) => WvChips(
          labels: _sectionLabels,
          uppercase: true,
          indicator: true,
          selected: selected,
          onChanged: (i) => ref
              .read(librarySectionProvider.notifier)
              .set(LibrarySection.values[i]),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Songs
// ----------------------------------------------------------------------

class _SongsSection extends ConsumerWidget {
  const _SongsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(libraryProvider.select((s) => s.songs));
    final q = ref.watch(libraryQueryProvider).trim().toLowerCase();
    final songs = all
        .where(
          (s) => '${s.title} ${s.artist ?? ''} ${s.album ?? ''}'
              .toLowerCase()
              .contains(q),
        )
        .toList();

    if (songs.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: all.isNotEmpty
            ? const WvEmptyMessage(
                message: 'No matching tracks',
                icon: Icons.search_off_rounded,
              )
            : _SongsEmptyState(),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: _SortRow(songs: songs)),
        SliverToBoxAdapter(
          child: Container(
            decoration: BoxDecoration(
              gradient: Wv.of(context).chromeGradient,
              border: Border.symmetric(
                horizontal: BorderSide(color: Wv.of(context).separator),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 7, 54, 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Name / Artist',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Wv.of(context).textSecondary,
                    ),
                  ),
                ),
                Text(
                  'Time',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Wv.of(context).textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _SongRow(song: songs[index], index: index),
            childCount: songs.length,
          ),
        ),
      ],
    );
  }
}

class _SortRow extends ConsumerWidget {
  const _SortRow({required this.songs});
  final List<SongModel> songs;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final sort = ref.watch(libraryProvider.select((s) => s.sort));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${songs.length} tracks',
                  style: TextStyle(color: a.textSecondary, fontSize: 12),
                ),
              ),
              PopupMenuButton<SortOption>(
                tooltip: 'Sort tracks',
                initialValue: sort,
                onSelected: (s) =>
                    ref.read(libraryProvider.notifier).changeSortOption(s),
                itemBuilder: (_) => [
                  for (int i = 0; i < _sortOptions.length; i++)
                    CheckedPopupMenuItem(
                      value: _sortOptions[i],
                      checked: sort == _sortOptions[i],
                      child: Text(_sortLabels[i]),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sort_rounded,
                        size: 18,
                        color: a.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _sortLabels[_sortOptions.indexOf(sort).clamp(0, 2)],
                        style: TextStyle(color: a.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.expand_more_rounded,
                        size: 16,
                        color: a.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: WvButton(
                  primary: true,
                  width: double.infinity,
                  onPressed: songs.isEmpty
                      ? null
                      : () => ref
                            .read(playerProvider.notifier)
                            .playSong(songs.first, contextList: songs),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded),
                      SizedBox(width: 6),
                      Text('Play all'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WvButton(
                  width: double.infinity,
                  onPressed: songs.isEmpty
                      ? null
                      : () {
                          final mix = [...songs]..shuffle();
                          ref
                              .read(playerProvider.notifier)
                              .playSong(mix.first, contextList: mix);
                        },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shuffle_rounded),
                      SizedBox(width: 6),
                      Text('Shuffle'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SongRow extends ConsumerWidget {
  final SongModel song;
  final int index;

  const _SongRow({required this.song, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrent = ref.watch(
      playerProvider.select((s) => s.currentSong?.id == song.id),
    );
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));

    void showMenu() => SongMenuHelper.show(
      context,
      ref,
      song,
      options: const SongMenuOptions(showDelete: true),
    );

    return WvSongRow(
      song: song,
      index: index,
      isCurrent: isCurrent,
      isPlaying: isPlaying,
      secondary: song.artist ?? 'Unknown Artist',
      onTap: () => ref
          .read(playerProvider.notifier)
          .playSong(
            song,
            contextList: ref
                .read(libraryProvider)
                .songs
                .where(
                  (s) => '${s.title} ${s.artist ?? ""} ${s.album ?? ""}'
                      .toLowerCase()
                      .contains(
                        ref.read(libraryQueryProvider).trim().toLowerCase(),
                      ),
                )
                .toList(),
          ),
      onLongPress: showMenu,
      onAction: showMenu,
    );
  }
}

class _SongsEmptyState extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final denied = ref.watch(libraryProvider.select((s) => s.permissionDenied));

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WvMascotBox(
              size: 88,
              sprite: denied ? PixelSprites.mascot : PixelSprites.mascotSleepy,
            ),
            const SizedBox(height: 20),
            Text(
              denied ? "Storage Access Needed" : "No Songs",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: a.text,
                fontSize: 24,
                fontFamily: 'WorkSans',
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              denied
                  ? "Allow Wavvy to read your music, then come back and retry."
                  : "Add music to your device to get started",
              textAlign: TextAlign.center,
              style: TextStyle(color: a.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                if (denied)
                  WvButton(
                    width: 132,
                    squircle: true,
                    size: 52,
                    onPressed: openAppSettings,
                    child: const Text("Open Settings"),
                  ),
                WvButton(
                  width: 108,
                  squircle: true,
                  size: 52,
                  primary: true,
                  onPressed: () =>
                      ref.read(libraryProvider.notifier).fetchAllSongs(),
                  child: Text(denied ? "Retry" : "Refresh"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Grids
// ----------------------------------------------------------------------

Widget _grid({
  required int count,
  required IndexedWidgetBuilder builder,
  double aspectRatio = 0.78,
}) {
  return SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    sliver: SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: aspectRatio,
      ),
      delegate: SliverChildBuilderDelegate(builder, childCount: count),
    ),
  );
}

/// Staggers a grid tile: the right column sits a little lower.
Widget _stagger(int index, Widget child) => child;

Widget _countLabel(BuildContext context, String text) {
  final a = Wv.of(context);
  return SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: a.textSecondary,
        ),
      ),
    ),
  );
}

class _AlbumsSection extends ConsumerWidget {
  const _AlbumsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(libraryQueryProvider).trim().toLowerCase();
    final items = ref
        .watch(libraryProvider.select((s) => s.albums))
        .where((a) => '${a.album} ${a.artist ?? ''}'.toLowerCase().contains(q))
        .toList();

    if (items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: WvEmptyMessage(
          message: q.isEmpty ? 'No Albums Found' : 'No matching albums',
          icon: Icons.album_rounded,
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        _countLabel(context, "${items.length} albums"),
        _grid(
          count: items.length,
          builder: (context, index) {
            final album = items[index];
            return _stagger(
              index,
              WvGridTile(
                index: index,
                onTap: () => AppNav.push(AlbumDetailScreen(album: album)),
                title: album.album,
                subtitle:
                    "${album.numOfSongs} Songs • ${album.artist ?? 'Unknown'}",
                artworkBuilder: (size) => wvArtwork(
                  context,
                  id: album.id,
                  type: ArtworkType.ALBUM,
                  size: size,
                  placeholder: Icons.album_rounded,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ArtistsSection extends ConsumerWidget {
  const _ArtistsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(libraryQueryProvider).trim().toLowerCase();
    final items = ref
        .watch(libraryProvider.select((s) => s.artists))
        .where((a) => a.artist.toLowerCase().contains(q))
        .toList();

    if (items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: WvEmptyMessage(
          message: q.isEmpty ? 'No Artists Found' : 'No matching artists',
          icon: Icons.person_rounded,
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        _countLabel(context, '${items.length} artists'),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final artist = items[index];
            final a = Wv.of(context);
            return Material(
              color: index.isOdd ? a.stripe : a.surface,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                leading: WvArtwork(
                  circular: true,
                  child: wvArtwork(
                    context,
                    id: artist.id,
                    type: ArtworkType.ARTIST,
                    size: 44,
                    placeholder: Icons.person_outline_rounded,
                  ),
                ),
                title: Text(
                  artist.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  '${artist.numberOfAlbums} albums / ${artist.numberOfTracks} tracks',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: a.textSecondary,
                ),
                onTap: () => AppNav.push(ArtistDetailScreen(artist: artist)),
              ),
            );
          }, childCount: items.length),
        ),
      ],
    );
  }
}

class _PlaylistsSection extends ConsumerWidget {
  const _PlaylistsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(libraryQueryProvider).trim().toLowerCase();
    final playlists = ref
        .watch(playlistsProvider.select((s) => s.playlists))
        .where((p) => '${p['name']}'.toLowerCase().contains(q))
        .toList();

    if (playlists.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const WvEmptyMessage(
              message: "No custom playlists yet.",
              icon: Icons.queue_music_rounded,
              sprite: PixelSprites.mascotHappy,
            ),
            WvButton(
              primary: true,
              squircle: true,
              size: 52,
              width: 156,
              onPressed: () => showNewPlaylistDialog(ref),
              child: const Text("New playlist"),
            ),
          ],
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        _countLabel(context, "${playlists.length} playlists"),
        _grid(
          count: playlists.length,
          aspectRatio: 0.95,
          builder: (context, index) {
            final playlist = playlists[index];
            return _PlaylistTile(
              index: index,
              id: playlist['id'],
              name: playlist['name'],
              onTap: () => AppNav.push(
                PlaylistDetailScreen(
                  playlistId: playlist['id'],
                  playlistName: playlist['name'],
                ),
              ),
              onLongPress: () => showDeletePlaylistDialog(
                ref,
                playlist['id'],
                playlist['name'],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// A color-blocked playlist tile: a tonal container with a pixel sprite, the
/// name and the song count.
class _PlaylistTile extends ConsumerWidget {
  final int index;
  final int id;
  final String name;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PlaylistTile({
    required this.index,
    required this.id,
    required this.name,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final count = ref.watch(playlistSongsProvider(id)).valueOrNull?.length;
    return Stack(
      children: [
        WvGridTile(
          title: name,
          subtitle: count == null ? 'Playlist' : '$count tracks',
          onTap: onTap,
          onLongPress: onLongPress,
          artworkBuilder: (size) => Container(
            color: a.surfaceHigh,
            alignment: Alignment.center,
            child: Icon(
              Icons.queue_music_rounded,
              size: size * 0.35,
              color: a.accent,
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: PopupMenuButton<String>(
            tooltip: 'Playlist options',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (_) => onLongPress(),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete playlist'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
