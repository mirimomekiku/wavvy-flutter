import 'dart:async';

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
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/playlist_dialogs.dart';
import 'package:wavvy/widgets/song_menu.dart';
import 'package:wavvy/widgets/wv_song_list.dart';
import 'package:wavvy/widgets/song_selection.dart';
import 'package:wavvy/widgets/page_heading.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/screens/library/liked/liked.screen.dart';

/// The text typed into the Library filter field.
final libraryQueryProvider = NotifierProvider<LibraryQueryNotifier, String>(
  LibraryQueryNotifier.new,
);

class LibraryQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

/// What each song is searched on, lowercased once per library change instead
/// of once per keystroke.
final _searchKeysProvider = Provider<List<String>>((ref) {
  final songs = ref.watch(libraryProvider.select((s) => s.songs));
  return [
    for (final s in songs)
      '${s.title} ${s.artist ?? ''} ${s.album ?? ''}'.toLowerCase(),
  ];
});

/// The songs that match the filter field (all of them when it is empty).
final librarySongsProvider = Provider<List<SongModel>>((ref) {
  final songs = ref.watch(libraryProvider.select((s) => s.songs));
  final q = ref.watch(libraryQueryProvider).trim().toLowerCase();
  if (q.isEmpty) return songs;
  final keys = ref.watch(_searchKeysProvider);
  return [
    for (var i = 0; i < songs.length; i++)
      if (keys[i].contains(q)) songs[i],
  ];
});

/// The albums that match the filter field.
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

    final inset = MediaQuery.paddingOf(context).top;
    final chrome = Wv.of(context).chromeGradient.colors.first;

    // The scroll view starts below the status bar, so the pinned chips stop
    // right under it instead of behind it, and nothing is added while they are
    // not pinned. A strip in the toolbar's top color fills the status bar, and
    // the heading (which would pad itself below the status bar) is told the
    // inset is already taken.
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: inset,
          child: ColoredBox(color: chrome),
        ),
        Positioned.fill(
          top: inset,
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(libraryProvider.notifier).fetchAllSongs(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _Header(section: section)),
                  const SliverToBoxAdapter(child: _LibrarySearch()),
                  if (ref.watch(libraryProvider.select((s) => s.isLoading)))
                    const SliverToBoxAdapter(
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (ref
                      .watch(libraryProvider.select((s) => s.error))
                      .isNotEmpty)
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
                    child: SizedBox(
                      height: 24 + MediaQuery.paddingOf(context).bottom,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Tall enough for the compact chips (+ indicator) at the current text scale.
  static double _chipsExtent(BuildContext context) {
    final label = MediaQuery.textScalerOf(context).scale(13) * 1.4;
    return (label + 28).clamp(52.0, 110.0);
  }
}

        final songs = ref.watch(librarySongsProvider);
        count = songs.length;
        labelAt = switch (ref.watch(libraryProvider.select((s) => s.sort))) {
          SortOption.titleAZ || SortOption.titleZA => (i) => songs[i].title,
          SortOption.artistAZ => (i) => songs[i].artist ?? '',
          SortOption.dateNewest || SortOption.dateOldest => null,
        };
      case LibrarySection.albums:
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
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _hadText = _query.text.isNotEmpty;
    _query.addListener(_onText);
  }

  bool _hadText = false;

  /// Redraws only when the clear button has to appear or go.
  void _onText() {
    final has = _query.text.isNotEmpty;
    if (has != _hadText) setState(() => _hadText = has);
  }

  /// Filters after a short pause in typing, not on every key.
  void _filterSoon(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      ref.read(libraryQueryProvider.notifier).set(text);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: AquaSearchFrame(
        child: TextField(
          controller: _query,
          onChanged: _filterSoon,
          style: const TextStyle(fontSize: 14),
          decoration: aquaSearchDecoration(
            context,
            hint: 'Search songs, albums, artists',
            prefix: Icon(
              Icons.search_rounded,
              size: 19,
              color: a.textSecondary,
            ),
            suffix: !_hadText
                ? null
                : IconButton(
                    tooltip: 'Clear filter',
                    icon: Icon(
                      Icons.cancel_rounded,
                      size: 18,
                      color: a.textSecondary,
                    ),
                    onPressed: () {
                      _debounce?.cancel();
                      _query.clear();
                      ref.read(libraryQueryProvider.notifier).set('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
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
    final a = Wv.of(context);
    return Container(
      height: extent,
      decoration: BoxDecoration(
        gradient: a.chromeGradient,
        border: Border(
          bottom: BorderSide(color: a.outline.withValues(alpha: 0.55)),
        ),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _SectionPills(selected: selected),
    );
  }
}

/// Pinned, scrollable section pills with a live count on each.
class _SectionPills extends ConsumerWidget {
  const _SectionPills({required this.selected});
  final int selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final counts = [
      ref.watch(libraryProvider.select((s) => s.songs.length)),
      ref.watch(libraryProvider.select((s) => s.albums.length)),
      ref.watch(libraryProvider.select((s) => s.artists.length)),
      ref.watch(playlistsProvider.select((s) => s.playlists.length)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < _sectionLabels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                button: true,
                selected: selected == i,
                label: _sectionLabels[i],
                child: Material(
                  color: Colors.transparent,
                  shape: const StadiumBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    decoration: ShapeDecoration(
                      gradient: a.gelGradient(primary: selected == i),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: selected == i
                              ? Color.lerp(a.accent, Colors.black, 0.25)!
                              : a.outline.withValues(alpha: 0.7),
                        ),
                      ),
                      shadows: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: a.dark ? 0.25 : 0.14,
                          ),
                          blurRadius: 1,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: InkWell(
                      onTap: () => ref
                          .read(librarySectionProvider.notifier)
                          .set(LibrarySection.values[i]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _sectionLabels[i],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: selected == i ? a.onAccent : a.text,
                                shadows: selected == i
                                    ? const [
                                        Shadow(
                                          color: Color(0x66305792),
                                          offset: Offset(0, -1),
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${counts[i]}',
                              style: TextStyle(
                                fontSize: 12,
                                color: selected == i
                                    ? a.onAccent.withValues(alpha: 0.85)
                                    : a.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
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
    final songs = ref.watch(librarySongsProvider);

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
    final player = ref.read(playerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 6),
      child: Row(
        children: [
          WvButton(
            primary: true,
            width: 112,
            size: 40,
            onPressed: songs.isEmpty
                ? null
                : () => player.playSong(songs.first, contextList: songs),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded),
                SizedBox(width: 4),
                Text('Play all'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          WvButton(
            circular: true,
            size: 40,
            tooltip: 'Shuffle',
            onPressed: songs.isEmpty
                ? null
                : () {
                    final mix = [...songs]..shuffle();
                    player.playSong(mix.first, contextList: mix);
                  },
            child: const Icon(Icons.shuffle_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<SortOption>(
                tooltip: 'Sort tracks',
                initialValue: sort,
                color: a.surface,
                elevation: 6,
                shape: aquaMenuShape(a),
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
                child: AquaPopupLabel(
                  label: _sortLabels[_sortOptions.indexOf(sort).clamp(0, 2)],
                ),
              ),
            ),
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
    // Only the current row shows play or pause, so the others do not rebuild
    // when playback toggles.
    final isPlaying =
        isCurrent && ref.watch(playerProvider.select((s) => s.isPlaying));

    void showMenu() => SongMenuHelper.show(
      context,
      ref,
      song,
      options: const SongMenuOptions(showDelete: true),
    );

    return SelectableSongRow(
      song: song,
      index: index,
      scope: ref.read(librarySongsProvider),
      isCurrent: isCurrent,
      isPlaying: isPlaying,
      secondary: song.artist ?? 'Unknown Artist',
      onTap: () => ref
          .read(playerProvider.notifier)
          .playSong(song, contextList: ref.read(librarySongsProvider)),
      onAction: showMenu,
    );
  }
}

class _SongsEmptyState extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final denied = ref.watch(libraryProvider.select((s) => s.permissionDenied));
    final blocked = ref.watch(
      libraryProvider.select((s) => s.permissionBlocked),
    );

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
                  ? blocked
                        ? "Turn on music access for Wavvy in Settings, then come back."
                        : "Allow Wavvy to read your music, then come back and retry."
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
                    primary: blocked,
                    onPressed: openAppSettings,
                    child: const Text("Open Settings"),
                  ),
                if (!blocked)
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
  int columns = 2,
}) {
  return SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    sliver: SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
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
        _grid(
          count: items.length,
          columns: 3,
          aspectRatio: 0.74,
          builder: (context, index) {
            final artist = items[index];
            return WvGridTile(
              index: index,
              circular: true,
              title: artist.artist,
              subtitle: '${artist.numberOfTracks} tracks',
              onTap: () => AppNav.push(ArtistDetailScreen(artist: artist)),
              artworkBuilder: (size) => wvArtwork(
                context,
                id: artist.id,
                type: ArtworkType.ARTIST,
                size: size,
                placeholder: Icons.person_outline_rounded,
              ),
            );
          },
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

    // Favorites sits first, then the way to make a new playlist.
    final showLiked = q.isEmpty || 'liked songs'.contains(q);
    final lead = showLiked ? 2 : 1;

    return SliverMainAxisGroup(
      slivers: [
        _countLabel(context, "${playlists.length} playlists"),
        _grid(
          count: playlists.length + lead,
          aspectRatio: 0.95,
          builder: (context, i) {
            if (showLiked && i == 0) return const _LikedTile();
            if (i == lead - 1) return const _NewPlaylistTile();
            final index = i - lead;
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

/// Favorites, shown with the playlists.
class _LikedTile extends ConsumerWidget {
  const _LikedTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final count = ref.watch(likedSongsProvider.select((s) => s.length));
    return WvGridTile(
      title: 'Liked songs',
      subtitle: '$count tracks',
      onTap: () => AppNav.push(const LikedSongsScreen()),
      artworkBuilder: (size) => Container(
        color: a.tertiaryContainer,
        alignment: Alignment.center,
        child: Icon(
          Icons.favorite_rounded,
          size: size * 0.4,
          color: kHeartColor,
        ),
      ),
    );
  }
}

class _NewPlaylistTile extends ConsumerWidget {
  const _NewPlaylistTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    return Material(
      color: a.primaryContainer.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: a.accent.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showNewPlaylistDialog(ref),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline_rounded, size: 36, color: a.accent),
            const SizedBox(height: 8),
            Text(
              'New playlist',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: a.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
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
