import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/widgets/song_menu.dart';

/// iTunes-style song table: sortable column header, striped rows, and a
/// blue gel highlight on the playing row.
class SongsView extends ConsumerWidget {
  const SongsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(libraryProvider.select((s) => s.songs));

    if (songs.isEmpty) {
      return _buildEmptyState(context);
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPersistentHeader(pinned: true, delegate: _ColumnHeaderDelegate()),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _SongRow(song: songs[index], index: index),
            childCount: songs.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final a = Aqua.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GelButton(
            circular: true,
            size: 72,
            onPressed: null,
            child: const Icon(Icons.music_off_rounded),
          ),
          const SizedBox(height: 16),
          Text(
            "No Songs",
            style: TextStyle(
              color: a.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Add music to your device to get started",
            style: TextStyle(color: a.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Column header
// ----------------------------------------------------------------------

class _ColumnHeaderDelegate extends SliverPersistentHeaderDelegate {
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
      child: Consumer(
        builder: (context, ref, child) {
          final sort = ref.watch(libraryProvider.select((s) => s.sort));
          final nameAsc = sort == SortOption.titleAZ;
          final nameActive = nameAsc || sort == SortOption.titleZA;
          final artistActive = sort == SortOption.artistAZ;

          return Row(
            children: [
              Expanded(
                flex: 5,
                child: _HeaderCell(
                  label: "Name",
                  active: nameActive,
                  ascending: nameAsc,
                  onTap: () => ref
                      .read(libraryProvider.notifier)
                      .changeSortOption(
                        nameAsc ? SortOption.titleZA : SortOption.titleAZ,
                      ),
                ),
              ),
              _divider(a),
              Expanded(
                flex: 3,
                child: _HeaderCell(
                  label: "Artist",
                  active: artistActive,
                  ascending: true,
                  onTap: () => ref
                      .read(libraryProvider.notifier)
                      .changeSortOption(SortOption.artistAZ),
                ),
              ),
              _divider(a),
              const SizedBox(
                width: 52,
                child: _HeaderCell(label: "Time", alignEnd: true),
              ),
              const SizedBox(width: 44),
            ],
          );
        },
      ),
    );
  }

  Widget _divider(AquaPalette a) =>
      Container(width: 1, height: 18, color: a.headerBorder);
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final bool active;
  final bool ascending;
  final bool alignEnd;
  final VoidCallback? onTap;

  const _HeaderCell({
    required this.label,
    this.active = false,
    this.ascending = true,
    this.alignEnd = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: a.text,
                ),
              ),
            ),
            if (active)
              Icon(
                ascending
                    ? Icons.arrow_drop_up_rounded
                    : Icons.arrow_drop_down_rounded,
                size: 20,
                color: a.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Row
// ----------------------------------------------------------------------

class _SongRow extends ConsumerWidget {
  final SongModel song;
  final int index;

  const _SongRow({required this.song, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Aqua.of(context);

    {
      final isCurrent = ref.watch(
        playerProvider.select((s) => s.currentSong?.id == song.id),
      );
      final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));

      final Color primaryText = isCurrent ? Colors.white : a.text;
      final Color secondaryText = isCurrent
          ? Colors.white.withValues(alpha: 0.85)
          : a.textSecondary;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref
            .read(playerProvider.notifier)
            .playSong(song, contextList: ref.read(libraryProvider).songs),
        onLongPress: () => SongMenuHelper.show(
          context,
          ref,
          song,
          options: const SongMenuOptions(showDelete: true),
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
                      if (isCurrent) ...[
                        Icon(
                          isPlaying
                              ? Icons.volume_up_rounded
                              : Icons.volume_mute_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                      ],
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
                    song.artist ?? "Unknown Artist",
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
                  onPressed: () => SongMenuHelper.show(
                    context,
                    ref,
                    song,
                    options: const SongMenuOptions(showDelete: true),
                  ),
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
