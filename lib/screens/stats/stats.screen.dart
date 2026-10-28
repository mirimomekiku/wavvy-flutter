import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/playback/history.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/bottom_bar.dart';
import 'package:wavvy/widgets/page_heading.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

/// What you play most and when, from the recorded listening history.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final stats = ref.watch(statsProvider);
    // Keep showing the last numbers while a new period loads.
    final summary = stats.valueOrNull;

    Widget body;
    if (summary != null) {
      body = summary.isEmpty
          ? const WvEmptyMessage(
              message:
                  'No plays yet. Songs you listen to will show up here. '
                  'Incognito mode does not record plays.',
              icon: Icons.insert_chart_outlined_rounded,
            )
          : _Content(summary: summary);
    } else if (stats.hasError) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not load your listening history.',
                textAlign: TextAlign.center,
                style: TextStyle(color: a.textSecondary, fontSize: 15),
              ),
              TextButton(
                onPressed: () => ref.invalidate(statsProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    } else {
      body = const Center(child: AquaSpinner(size: 28));
    }

    return WvSystemUi(
      child: Scaffold(
        backgroundColor: a.pageColor,
        bottomNavigationBar: const BottomMiniPlayer(showTabView: false),
        // No SafeArea: the heading pads itself below the status bar.
        body: Column(
          children: [
            WvPageHeading(
              title: 'Listening stats',
              subtitle: 'What you play most and when.',
              back: true,
              bottom: WvChips(
                labels: [for (final p in StatsPeriod.values) p.label],
                selected: ref.watch(statsPeriodProvider).index,
                onChanged: (i) => ref
                    .read(statsPeriodProvider.notifier)
                    .set(StatsPeriod.values[i]),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.summary});
  final StatsSummary summary;

  /// Plays the song if it is still in the library.
  VoidCallback? _player(WidgetRef ref, int songId) {
    final SongModel? song = ref
        .read(libraryProvider)
        .songs
        .where((s) => s.id == songId)
        .firstOrNull;
    if (song == null) return null;
    return () =>
        ref.read(playerProvider.notifier).playSong(song, contextList: [song]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.only(top: 14, bottom: 28),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: AquaLcdCell(
                      value: '${summary.totalPlays}',
                      label: 'Plays',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AquaLcdCell(
                      value: '${summary.uniqueSongs}',
                      label: 'Songs',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: AquaLcdCell(
                      value: '${summary.uniqueArtists}',
                      label: 'Artists',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AquaLcdCell(
                      value: formatListening(summary.listening),
                      label: 'Est. listening time',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        AquaWindow(
          title: 'Last 14 days',
          subtitle: 'Plays per day',
          padding: const EdgeInsets.all(12),
          child: _ActivityChart(daily: summary.dailyPlays, now: now),
        ),
        if (summary.topSongs.isNotEmpty)
          AquaWindow(
            title: 'Top songs',
            child: _Ranked([
              for (final t in summary.topSongs)
                _RankItem(
                  title: t.name,
                  subtitle: t.subtitle,
                  plays: t.plays,
                  onTap: _player(ref, t.songId!),
                ),
            ]),
          ),
        if (summary.topArtists.isNotEmpty)
          AquaWindow(
            title: 'Top artists',
            child: _Ranked([
              for (final t in summary.topArtists)
                _RankItem(title: t.name, plays: t.plays),
            ]),
          ),
        if (summary.topAlbums.isNotEmpty)
          AquaWindow(
            title: 'Top albums',
            child: _Ranked([
              for (final t in summary.topAlbums)
                _RankItem(title: t.name, subtitle: t.subtitle, plays: t.plays),
            ]),
          ),
        AquaWindow(
          title: 'Recently played',
          subtitle: 'The last ${summary.recent.length}',
          child: _Ranked([
            for (final e in summary.recent)
              _RankItem(
                title: e.title,
                subtitle: [
                  if (e.artist != null && e.artist!.isNotEmpty) e.artist!,
                  relativeTime(e.playedAt, now),
                ].join(' · '),
                onTap: _player(ref, e.songId),
              ),
          ], numbered: false),
        ),
        AquaMenuGroup(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          rows: [
            AquaMenuRow(
              icon: Icons.delete_outline_rounded,
              label: 'Clear history',
              destructive: true,
              onTap: () => showConfirmDialog(
                title: 'Clear listening history?',
                message:
                    'This deletes every recorded play and resets these stats. '
                    'Your library and playlists are not affected.',
                confirmText: 'Clear',
                destructive: true,
                onConfirm: () => ref.read(statsProvider.notifier).clear(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Bars for the plays on each of the last 14 days, oldest first.
class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.daily, required this.now});
  final List<int> daily;
  final DateTime now;

  static const _height = 84.0;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final peak = daily.fold<int>(0, (m, v) => v > m ? v : m);
    final total = daily.fold<int>(0, (s, v) => s + v);
    final label = StringBuffer(
      '$total plays in the last ${daily.length} days. ',
    );
    for (var i = 0; i < daily.length; i++) {
      final ago = daily.length - 1 - i;
      label.write(
        '${ago == 0
            ? 'Today'
            : ago == 1
            ? 'Yesterday'
            : '$ago days ago'}: ${daily[i]}. ',
      );
    }
    return Semantics(
      label: label.toString().trim(),
      child: ExcludeSemantics(
        child: Column(
          children: [
            SizedBox(
              height: _height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < daily.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            // A day with plays always shows a visible bar.
                            height: daily[i] == 0
                                ? 2
                                : 6 + (_height - 6) * daily[i] / peak,
                            decoration: BoxDecoration(
                              color: daily[i] == 0
                                  ? a.separator
                                  : (i == daily.length - 1
                                        ? a.accent
                                        : a.accent.withValues(alpha: 0.65)),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${daily.length} days ago',
                  style: TextStyle(color: a.textSecondary, fontSize: 11),
                ),
                Text(
                  'Today',
                  style: TextStyle(color: a.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RankItem {
  const _RankItem({required this.title, this.subtitle, this.plays, this.onTap});
  final String title;
  final String? subtitle;
  final int? plays;
  final VoidCallback? onTap;
}

/// Striped rows with an optional rank number and a play count at the right.
class _Ranked extends StatelessWidget {
  const _Ranked(this.items, {this.numbered = true});
  final List<_RankItem> items;
  final bool numbered;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Divider(height: 1, color: a.separator),
          ColoredBox(
            color: i.isOdd ? a.stripe : a.surface,
            child: _row(a, i, items[i]),
          ),
        ],
      ],
    );
  }

  Widget _row(WvPalette a, int i, _RankItem item) {
    final plays = item.plays;
    final sub = item.subtitle;
    return Semantics(
      button: item.onTap != null,
      label: [
        if (numbered) '${i + 1}.',
        item.title,
        if (sub != null && sub.isNotEmpty) sub,
        if (plays != null) '$plays ${plays == 1 ? 'play' : 'plays'}',
      ].join(', '),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: item.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                children: [
                  if (numbered)
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: a.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: a.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (sub != null && sub.isNotEmpty)
                          Text(
                            sub,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: a.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (plays != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      '$plays ${plays == 1 ? 'play' : 'plays'}',
                      style: TextStyle(
                        color: a.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
