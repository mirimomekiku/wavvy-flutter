import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/player_sheets/full_player_sheet.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/player_sheet_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// iTunes-style bottom area: a brushed-metal player bar (transport gel
/// buttons + LCD now-playing display) over an Aqua tab bar.
class BottomMiniPlayer extends ConsumerWidget {
  final bool showTabView;

  const BottomMiniPlayer({super.key, this.showTabView = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final a = Aqua.of(context);

    {
      final song = ref.watch(playerProvider.select((s) => s.currentSong));
      final bool showTabs = showTabView;

      if (song == null && !showTabs) {
        return SizedBox(height: bottomPadding);
      }

      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: a.toolbar,
          ),
          border: Border(top: BorderSide(color: a.toolbarBorder)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (song != null) _buildPlayerBar(context, ref, song, a),
                if (song != null && showTabs)
                  Container(height: 1, color: a.toolbarHighlight),
                if (showTabs) const _AquaTabBar(),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _openPlayer(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        ref.read(sheetPageIndexProvider.notifier).set(0);
        return FullPlayerSheet();
      },
    );
  }

  Widget _buildPlayerBar(
    BuildContext context,
    WidgetRef ref,
    SongModel song,
    AquaPalette a,
  ) {
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final player = ref.read(playerProvider.notifier);

    return SizedBox(
      height: 64,
      child: Row(
        children: [
          const SizedBox(width: 4),
          GelButton(
            circular: true,
            size: 30,
            tooltip: "Previous",
            onPressed: player.previous,
            child: const Icon(Icons.skip_previous_rounded),
          ),
          GelButton(
            circular: true,
            primary: true,
            size: 40,
            tooltip: isPlaying ? "Pause" : "Play",
            onPressed: player.togglePlay,
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
          GelButton(
            circular: true,
            size: 30,
            tooltip: "Next",
            onPressed: player.next,
            child: const Icon(Icons.skip_next_rounded),
          ),
          const SizedBox(width: 2),
          // LCD display; tap to open the full player.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openPlayer(context, ref),
              child: AquaLcd(
                child: Row(
                  children: [
                    _LcdArtwork(songId: song.id, fallback: a.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: a.text,
                            ),
                          ),
                          Text(
                            song.artist ?? "Unknown",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: a.textSecondary,
                            ),
                          ),
                          Consumer(
                            builder: (context, ref, child) {
                              final max = ref
                                  .watch(durationProvider)
                                  .inMilliseconds
                                  .toDouble();
                              final current = ref
                                  .watch(positionProvider)
                                  .inMilliseconds
                                  .toDouble();
                              return AquaScrubber(
                                value: max > 0 ? current / max : 0,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}

/// Tiny bordered artwork thumbnail for the LCD.
class _LcdArtwork extends StatelessWidget {
  final int songId;
  final Color fallback;

  const _LcdArtwork({required this.songId, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: a.lcdBorder),
        borderRadius: BorderRadius.circular(2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(1),
        child: QueryArtworkWidget(
          id: songId,
          type: ArtworkType.AUDIO,
          artworkFit: BoxFit.cover,
          artworkWidth: 36,
          artworkHeight: 36,
          artworkBorder: BorderRadius.zero,
          nullArtworkWidget: SizedBox(
            width: 36,
            height: 36,
            child: Icon(Icons.music_note_rounded, size: 20, color: fallback),
          ),
        ),
      ),
    );
  }
}

class _AquaTabBar extends ConsumerWidget {
  const _AquaTabBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabController = DefaultTabController.maybeOf(context);
    if (tabController == null) return const SizedBox.shrink();

    // Watching so toggling the downloader setting rebuilds the tab list.
    {
      final enableDownloader = ref.watch(
        settingsProvider.select((s) => s.enableDownloader),
      );
      final tabs = <(IconData, String)>[
        (Icons.music_note_rounded, "Songs"),
        (Icons.library_music_rounded, "Library"),
        if (enableDownloader) (Icons.download_rounded, "Downloads"),
      ];

      return AnimatedBuilder(
        animation: tabController,
        builder: (context, _) {
          return SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  for (int i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _TabItem(
                        icon: tabs[i].$1,
                        label: tabs[i].$2,
                        selected: tabController.index == i,
                        onTap: () => tabController.animateTo(i),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    }
  }
}

class _TabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);
    final Color fg = selected ? Colors.white : a.glyph;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: Ds.fast,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Ds.radiusM),
            gradient: selected ? Aqua.gel(a.gelBlue) : null,
            border: selected ? Border.all(color: a.gelBlueBorder) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: fg),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
