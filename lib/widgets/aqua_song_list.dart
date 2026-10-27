import 'package:flutter/material.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';

/// Shared Aqua building blocks for the album / artist / playlist screens.

/// Photo-framed grid tile: framed artwork, bold title, secondary subtitle.
/// [artworkBuilder] receives the available square size.
class AquaGridTile extends StatelessWidget {
  final Widget Function(double size) artworkBuilder;
  final String title;
  final String? subtitle;
  final bool circular;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AquaGridTile({
    super.key,
    required this.artworkBuilder,
    required this.title,
    this.subtitle,
    this.circular = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = (constraints.biggest.shortestSide - 6).clamp(
                  1.0,
                  2000.0,
                );
                return Center(
                  child: AquaPhotoFrame(
                    circular: circular,
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: artworkBuilder(side),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: a.text,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: a.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// Centered empty-state message.
class AquaEmptyMessage extends StatelessWidget {
  final String message;
  final IconData icon;

  const AquaEmptyMessage({
    super.key,
    required this.message,
    this.icon = Icons.music_off_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GelButton(circular: true, size: 64, onPressed: null, child: Icon(icon)),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: a.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// iTunes-style header: framed artwork, title, subtitle, and gel
/// Play / Shuffle buttons.
class AquaDetailHeader extends StatelessWidget {
  final Widget artwork;
  final bool circular;
  final String title;
  final String? subtitle;
  final String? detail;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  const AquaDetailHeader({
    super.key,
    required this.artwork,
    required this.title,
    this.circular = false,
    this.subtitle,
    this.detail,
    this.onPlay,
    this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: a.stripe,
        border: Border(bottom: BorderSide(color: a.headerBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AquaPhotoFrame(
            circular: circular,
            child: SizedBox(width: 112, height: 112, child: artwork),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: a.text,
                    shadows: [
                      Shadow(
                        color: Colors.white.withValues(
                          alpha: a.dark ? 0.0 : 0.8,
                        ),
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: a.textSecondary),
                  ),
                ],
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: a.textSecondary),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    GelButton(
                      primary: true,
                      width: 84,
                      tooltip: "Play",
                      onPressed: onPlay,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded),
                          SizedBox(width: 2),
                          Text("Play"),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    GelButton(
                      width: 96,
                      tooltip: "Shuffle",
                      onPressed: onShuffle,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shuffle_rounded),
                          SizedBox(width: 4),
                          Text("Shuffle"),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned "Name / [secondary] / Time" column header for a song table.
class AquaColumnHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String secondaryLabel;

  AquaColumnHeaderDelegate({required this.secondaryLabel});

  @override
  double get minExtent => 30;
  @override
  double get maxExtent => 30;

  @override
  bool shouldRebuild(covariant AquaColumnHeaderDelegate oldDelegate) =>
      oldDelegate.secondaryLabel != secondaryLabel;

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
          Expanded(flex: 3, child: cell(secondaryLabel)),
          divider(),
          SizedBox(width: 52, child: cell("Time", alignEnd: true)),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

/// Striped song row with a blue gel highlight when current. Callers wrap it
/// in a [Consumer] that supplies [isCurrent] / [isPlaying].
class AquaSongRow extends StatelessWidget {
  final SongModel song;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final String secondary;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onAction;
  final IconData actionIcon;
  final String actionTooltip;

  const AquaSongRow({
    super.key,
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.secondary,
    required this.onTap,
    required this.onAction,
    this.onLongPress,
    this.actionIcon = Icons.more_horiz_rounded,
    this.actionTooltip = "More options",
  });

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    final Color primaryText = isCurrent ? Colors.white : a.text;
    final Color secondaryText = isCurrent
        ? Colors.white.withValues(alpha: 0.85)
        : a.textSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
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
                  secondary,
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
                tooltip: actionTooltip,
                padding: EdgeInsets.zero,
                icon: Icon(actionIcon, color: secondaryText),
                onPressed: onAction,
              ),
            ),
          ],
        ),
      ),
    );
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

/// Square artwork that fills its frame, with an Aqua placeholder.
Widget aquaArtwork(
  BuildContext context, {
  required int id,
  required ArtworkType type,
  required double size,
  required IconData placeholder,
}) {
  final a = Aqua.of(context);
  return QueryArtworkWidget(
    id: id,
    type: type,
    artworkFit: BoxFit.cover,
    artworkQuality: FilterQuality.high,
    size: 600,
    artworkWidth: size,
    artworkHeight: size,
    artworkBorder: BorderRadius.zero,
    nullArtworkWidget: Container(
      width: size,
      height: size,
      color: a.stripe,
      child: Icon(placeholder, size: size * 0.45, color: a.textSecondary),
    ),
  );
}

/// Aqua back button for toolbars.
Widget aquaBackButton() => GelButton(
  circular: true,
  tooltip: "Back",
  onPressed: () => AppNav.pop(),
  child: const Icon(Icons.arrow_back_rounded),
);
