import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/page_heading.dart';
import 'package:wavvy/utils/player.utils.dart';

class WvSystemUi extends StatelessWidget {
  const WvSystemUi({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: a.dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: a.surface,
        systemNavigationBarIconBrightness: a.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: child,
    );
  }
}

class WvTopBar extends StatelessWidget {
  const WvTopBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.kicker,
  });
  final String title;
  final List<Widget> actions;
  final String? kicker;
  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: WvPageHeading(
      title: title,
      eyebrow: kicker,
      actions: actions,
      back: true,
    ),
  );
}

class WvGridTile extends StatelessWidget {
  const WvGridTile({
    super.key,
    required this.artworkBuilder,
    required this.title,
    this.subtitle,
    this.circular = false,
    this.onTap,
    this.onLongPress,
    this.index = 0,
  });
  final Widget Function(double size) artworkBuilder;
  final String title;
  final String? subtitle;
  final bool circular;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final int index;
  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final side = c.biggest.shortestSide.clamp(1.0, 1000.0);
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: WvArtwork(
                        circular: circular,
                        radius: 10,
                        child: SizedBox.square(
                          dimension: side,
                          child: artworkBuilder(side),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: a.text,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: a.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class WvEmptyMessage extends StatelessWidget {
  const WvEmptyMessage({
    super.key,
    required this.message,
    this.icon = Icons.music_off_outlined,
    this.sprite = PixelSprites.mascotSleepy,
  });
  final String message;
  final IconData icon;
  final PixelSprite sprite;
  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AquaOrb(icon: icon, size: 68),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: a.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WvMascotBox extends StatelessWidget {
  const WvMascotBox({
    super.key,
    this.sprite = PixelSprites.mascot,
    this.size = 72,
  });
  final PixelSprite sprite;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Wv.of(context).surfaceHigh,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Icon(
      Icons.library_music_outlined,
      size: size * 0.45,
      color: Wv.of(context).accent,
    ),
  );
}

/// Compact collection cover and metadata, followed by immediately useful actions.
class WvDetailHeader extends StatelessWidget {
  const WvDetailHeader({
    super.key,
    required this.artwork,
    required this.title,
    this.circular = false,
    this.subtitle,
    this.detail,
    this.kicker,
    this.onPlay,
    this.onShuffle,
  });
  final Widget artwork;
  final String title;
  final bool circular;
  final String? subtitle;
  final String? detail;
  final String? kicker;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Container(
      decoration: BoxDecoration(
        color: a.surface,
        border: Border(bottom: BorderSide(color: a.separator)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  wvBackButton(),
                  const SizedBox(width: 4),
                  Text(
                    kicker ?? 'Collection',
                    style: TextStyle(color: a.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: LayoutBuilder(
                builder: (context, c) {
                  final cover = (c.maxWidth * 0.3).clamp(80.0, 132.0);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      WvArtwork(
                        circular: circular,
                        radius: 10,
                        elevated: true,
                        child: SizedBox.square(
                          dimension: cover,
                          child: artwork,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                height: 1.15,
                                letterSpacing: -0.6,
                                color: a.text,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: a.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                            if (detail != null) ...[
                              const SizedBox(height: 5),
                              Text(
                                detail!,
                                style: TextStyle(
                                  color: a.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: WvButton(
                      primary: true,
                      width: double.infinity,
                      size: 36,
                      onPressed: onPlay,
                      tooltip: 'Play',
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded),
                          SizedBox(width: 6),
                          Text('Play'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: WvButton(
                      width: double.infinity,
                      size: 36,
                      onPressed: onShuffle,
                      tooltip: 'Shuffle',
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
            ),
          ],
        ),
      ),
    );
  }
}

/// Mobile adaptation of Kaisu's striped music table.
class WvSongRow extends StatelessWidget {
  const WvSongRow({
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
    this.actionTooltip = 'More options',
  });
  final SongModel song;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final String secondary;
  final VoidCallback onTap;
  final VoidCallback onAction;
  final VoidCallback? onLongPress;
  final IconData actionIcon;
  final String actionTooltip;
  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Semantics(
      selected: isCurrent,
      button: true,
      label: '${song.title}, $secondary',
      child: Material(
        color: isCurrent
            ? a.accent
            : index.isOdd
            ? a.stripe
            : a.surface,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: isCurrent ? a.accent : Colors.transparent,
                  width: 3,
                ),
                bottom: BorderSide(color: a.separator.withValues(alpha: 0.35)),
              ),
            ),
            padding: const EdgeInsets.only(left: 13, right: 4),
            child: Row(
              children: [
                WvArtwork(
                  radius: 7,
                  child: wvArtwork(
                    context,
                    id: song.id,
                    type: ArtworkType.AUDIO,
                    size: 34,
                    placeholder: Icons.music_note_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isCurrent) ...[
                              Icon(
                                isPlaying
                                    ? Icons.equalizer_rounded
                                    : Icons.pause_rounded,
                                size: 15,
                                color: a.onAccent,
                              ),
                              const SizedBox(width: 5),
                            ],
                            Expanded(
                              child: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isCurrent ? a.onAccent : a.text,
                                  fontWeight: isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          secondary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isCurrent ? a.onAccent : a.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (MediaQuery.sizeOf(context).width > 560)
                  SizedBox(
                    width: 120,
                    child: Text(
                      song.album ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isCurrent ? a.onAccent : a.textSecondary,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    PlayerUtils.formatDurationInt(song.duration),
                    style: TextStyle(
                      fontSize: 10,
                      color: isCurrent ? a.onAccent : a.textSecondary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: actionTooltip,
                  onPressed: onAction,
                  icon: Icon(
                    actionIcon,
                    size: 19,
                    color: isCurrent ? a.onAccent : a.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget wvArtwork(
  BuildContext context, {
  required int id,
  required ArtworkType type,
  required double size,
  required IconData placeholder,
}) => QueryArtworkWidget(
  id: id,
  type: type,
  artworkFit: BoxFit.cover,
  artworkQuality: FilterQuality.high,
  size: 600,
  artworkWidth: size,
  artworkHeight: size,
  artworkBorder: BorderRadius.zero,
  nullArtworkWidget: WvMediaPlaceholder(seed: id, size: size),
);
Widget wvBackButton() => IconButton(
  tooltip: 'Back',
  onPressed: AppNav.pop,
  icon: const Icon(Icons.arrow_back_rounded),
);
