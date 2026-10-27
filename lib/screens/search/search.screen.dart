import 'package:flutter/material.dart' hide AppBar;
import 'package:flutter/services.dart';
import 'package:flutter_appbar/flutter_appbar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/widgets/song_menu.dart';
import 'package:wavvy/widgets/bottom_bar.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final LibraryNotifier _library;

  @override
  void initState() {
    super.initState();
    _library = ref.read(libraryProvider.notifier);
    // Start from the full list once per visit, not on every rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _library.search('');
    });
  }

  @override
  void dispose() {
    // Don't leave the filtered subset behind for the rest of the app.
    final library = _library;
    Future.microtask(() => library.search(''));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final hintColor = a.textSecondary;
    final navBarColor = a.toolbar[1];
    final filteredSongs = ref.watch(
      libraryProvider.select((s) => s.filteredSongs),
    );

    {

      final Brightness iconBrightness =
          ThemeData.estimateBrightnessForColor(navBarColor) == Brightness.dark
          ? Brightness.light
          : Brightness.dark;

      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          systemNavigationBarColor: navBarColor,
          systemNavigationBarIconBrightness: iconBrightness,
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              Theme.of(context).brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: backgroundColor,
          bottomNavigationBar: BottomMiniPlayer(showTabView: false),
          body: SafeArea(
            child: AppBarConnection(
              appBars: [
                AppBar(
                  behavior: const MaterialAppBarBehavior(floating: true),
                  body: AquaBar(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          GelButton(
                            width: 72,
                            size: 30,
                            tooltip: "Cancel",
                            onPressed: () => AppNav.pop(),
                            child: const Text("Cancel"),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _AquaEditableSearchField(
                              hint: "Search songs, artists...",
                              hintColor: hintColor,
                              onChanged: (val) => ref.read(libraryProvider.notifier).search(val),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              child: Builder(builder: (context) {
                if (filteredSongs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GelButton(
                          circular: true,
                          size: 72,
                          onPressed: null,
                          child: const Icon(Icons.search_off_rounded),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "No Songs Found",
                          style: TextStyle(
                            color: a.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Try a different title or artist",
                          style: TextStyle(color: a.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }

                final songs = filteredSongs;

                return CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    const SliverPersistentHeader(
                      pinned: true,
                      delegate: _ColumnHeaderDelegate(),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final song = songs[index];
                        return _SearchRow(
                          song: song,
                          index: index,
                        );
                      }, childCount: songs.length),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                );
              }),
            ),
          ),
        ),
      );
    }
  }
}

// ----------------------------------------------------------------------
// Editable inset search field (same look as AquaSearchField)
// ----------------------------------------------------------------------

class _AquaEditableSearchField extends StatelessWidget {
  final String hint;
  final Color? hintColor;
  final ValueChanged<String> onChanged;

  const _AquaEditableSearchField({
    required this.hint,
    required this.hintColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return SizedBox(
      height: 48,
      child: Center(
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: a.gelBorder),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: a.dark
                  ? const [Color(0xFF0C0C0C), Color(0xFF222222)]
                  : const [Color(0xFFD6D6D6), Color(0xFFFFFFFF)],
              stops: const [0.0, 0.4],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: a.dark ? 0.06 : 0.7),
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 18, color: a.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  cursorColor: a.accent,
                  style: TextStyle(fontSize: 13.5, color: a.text),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    hintText: hint,
                    hintStyle: TextStyle(fontSize: 13.5, color: hintColor),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Column header
// ----------------------------------------------------------------------

class _ColumnHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ColumnHeaderDelegate();

  @override
  double get minExtent => 30;
  @override
  double get maxExtent => 30;

  @override
  bool shouldRebuild(covariant _ColumnHeaderDelegate oldDelegate) => false;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final a = Aqua.of(context);

    Widget cell(String label, {bool alignEnd = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Align(
        alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: a.text,
          ),
        ),
      ),
    );

    Widget divider() => Container(width: 1, height: 18, color: a.headerBorder);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: a.header,
        ),
        border: Border(
          top: BorderSide(color: a.headerBorder),
          bottom: BorderSide(color: a.headerBorder),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 5, child: cell("Name")),
          divider(),
          Expanded(flex: 3, child: cell("Artist")),
          divider(),
          SizedBox(width: 52, child: cell("Time", alignEnd: true)),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Row
// ----------------------------------------------------------------------

class _SearchRow extends ConsumerWidget {
  final SongModel song;
  final int index;

  const _SearchRow({required this.song, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Aqua.of(context);

    {
      final isCurrent = ref.watch(
        playerProvider.select((s) => s.currentSong?.id == song.id),
      );

      final Color primaryText = isCurrent ? Colors.white : a.text;
      final Color secondaryText = isCurrent
          ? Colors.white.withValues(alpha: 0.85)
          : a.textSecondary;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref
            .read(playerProvider.notifier)
            .playSong(
              song,
              contextList: ref.read(libraryProvider).filteredSongs,
            ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          decoration: BoxDecoration(
            color: isCurrent ? null : (index.isEven ? a.background : a.stripe),
            gradient: isCurrent
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: a.selection,
                  )
                : null,
            border: isCurrent
                ? Border(top: BorderSide(color: a.selectionBorder))
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                  child: Row(
                    children: [
                      _Thumb(songId: song.id),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          song.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: primaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    song.artist ?? "Unknown",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: secondaryText),
                  ),
                ),
              ),
              SizedBox(
                width: 52,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    PlayerUtils.formatDurationInt(song.duration),
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 12.5, color: secondaryText),
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                child: IconButton(
                  tooltip: "More options",
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.more_horiz_rounded, color: secondaryText),
                  onPressed: () => SongMenuHelper.show(context, ref, song),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}

class _Thumb extends StatelessWidget {
  final int songId;

  const _Thumb({required this.songId});

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: a.frameBorder),
        borderRadius: BorderRadius.circular(2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(1),
        child: QueryArtworkWidget(
          id: songId,
          type: ArtworkType.AUDIO,
          artworkFit: BoxFit.cover,
          artworkWidth: 34,
          artworkHeight: 34,
          artworkBorder: BorderRadius.zero,
          nullArtworkWidget: Container(
            width: 34,
            height: 34,
            color: a.stripe,
            child: Icon(
              Icons.music_note_rounded,
              size: 18,
              color: a.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
