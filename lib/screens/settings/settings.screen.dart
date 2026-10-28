import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/downloader/flavor.dart';
import 'package:wavvy/downloader/ui/engine_card.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/screens/settings/album_art_setting.dart';
import 'package:wavvy/screens/settings/visualizer_setting.dart';
import 'package:wavvy/screens/stats/stats.screen.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/page_heading.dart';
import 'package:wavvy/widgets/theme_selector.dart';
import 'package:wavvy/widgets/bottom_bar.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

/// "1.0.0 (1)"; null until read, or when the platform can't supply it.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    Widget toggle(
      String title,
      String subtitle,
      IconData icon,
      bool value,
      ValueChanged<bool> change,
    ) => ListTile(
      dense: true,
      onTap: () => change(!value),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, color: a.textSecondary, size: 22),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: a.text,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          subtitle,
          style: TextStyle(fontSize: 12, height: 1.4, color: a.textSecondary),
        ),
      ),
      trailing: AquaSwitch(value: value, onChanged: change),
    );
    // A row with a pop-up menu of choices; [selected] is an index into [labels].
    Widget choice(
      String title,
      String subtitle,
      IconData icon,
      List<String> labels,
      int selected,
      ValueChanged<int> change,
    ) => ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, color: a.textSecondary, size: 22),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: a.text,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          subtitle,
          style: TextStyle(fontSize: 12, height: 1.4, color: a.textSecondary),
        ),
      ),
      trailing: PopupMenuButton<int>(
        tooltip: title,
        padding: EdgeInsets.zero,
        color: a.surface,
        elevation: 6,
        shape: aquaMenuShape(a),
        initialValue: selected,
        onSelected: change,
        itemBuilder: (_) => [
          for (var i = 0; i < labels.length; i++)
            CheckedPopupMenuItem(
              value: i,
              checked: i == selected,
              child: Text(labels[i]),
            ),
        ],
        child: AquaPopupLabel(
          label: labels[selected.clamp(0, labels.length - 1)],
        ),
      ),
    );
    return WvSystemUi(
      child: Scaffold(
        backgroundColor: a.pageColor,
        bottomNavigationBar: const BottomMiniPlayer(showTabView: false),
        // No SafeArea: the heading pads itself below the status bar.
        body: Column(
          children: [
            const WvPageHeading(
              title: 'Settings',
              subtitle: 'Make Wavvy work for you.',
              back: true,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                children: [
                  const ThemeSelector(),
                  const SizedBox(height: 14),
                  InsetGroup(
                    children: [
                      toggle(
                        'Dark mode',
                        'A comfortable view in low light',
                        Icons.dark_mode_outlined,
                        s.isDarkMode,
                        n.toggleDarkMode,
                      ),
                      toggle(
                        'Album colors',
                        'Use the playing artwork as your accent',
                        Icons.palette_outlined,
                        s.enableDynamicColors,
                        n.toggleDynamicColors,
                      ),
                    ],
                  ),
                  const GroupHeader('Your music'),
                  InsetGroup(
                    children: [
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        leading: Icon(
                          Icons.insert_chart_outlined_rounded,
                          color: a.textSecondary,
                          size: 22,
                        ),
                        title: Text(
                          'Listening stats',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: a.text,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            'What you play most and when',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: a.textSecondary,
                            ),
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: a.textSecondary,
                        ),
                        onTap: () => AppNav.push(const StatsScreen()),
                      ),
                    ],
                  ),
                  const GroupHeader('Playback'),
                  InsetGroup(
                    children: [
                      toggle(
                        'Double tap to seek',
                        'Seek 10 seconds on either side of the record',
                        Icons.touch_app_outlined,
                        s.enableDoubleTapSeek,
                        n.toggleDoubleTapSeek,
                      ),
                      toggle(
                        'Shake to skip',
                        'Advance to the next track with a shake',
                        Icons.vibration_rounded,
                        s.enableShakeToSkip,
                        n.toggleShakeToSkip,
                      ),
                      toggle(
                        'Fade in and out',
                        'Ease the volume when you play or pause',
                        Icons.graphic_eq_rounded,
                        s.enableFadeInOut,
                        n.toggleFadeInOut,
                      ),
                      toggle(
                        'Skip silence',
                        'Jump over silent gaps within tracks',
                        Icons.fast_forward_rounded,
                        s.enableSkipSilence,
                        n.toggleSkipSilence,
                      ),
                      toggle(
                        'Keep screen awake',
                        'Keep Wavvy visible while you listen',
                        Icons.light_mode_outlined,
                        s.enableWakeLock,
                        n.toggleWakeLock,
                      ),
                      toggle(
                        'Resume last session',
                        'Reopen with the queue and position you left',
                        Icons.history_toggle_off_rounded,
                        s.resumeSession,
                        n.toggleResumeSession,
                      ),
                      toggle(
                        'Remember speed',
                        'Keep the speed and pitch you set for each album',
                        Icons.speed_rounded,
                        s.rememberRates,
                        n.toggleRememberRates,
                      ),
                      toggle(
                        'Smart shuffle',
                        'Keep songs by one artist apart; favor liked and less played ones',
                        Icons.shuffle_rounded,
                        s.smartShuffle,
                        n.toggleSmartShuffle,
                      ),
                      toggle(
                        'Shake to extend sleep timer',
                        'Shake the phone in the last minute of the timer for 10 more minutes',
                        Icons.vibration_rounded,
                        s.shakeExtendsSleep,
                        n.toggleShakeExtendsSleep,
                      ),
                        'Volume keys',
                        'Hold volume up for the next song and volume down for the previous one. Works only while Wavvy is on screen',
                        Icons.volume_up_rounded,
                        s.volumeKeySkip,
                        n.toggleVolumeKeySkip,
                      ),
                      if (kVisualizerAvailable)
                        toggle(
                          'Visualizer',
                          'Adds a spectrum page to the player. Needs microphone permission only so Android lets Wavvy read its own audio levels; nothing is recorded or sent anywhere',
                          Icons.equalizer_rounded,
                          s.enableVisualizer,
                          (v) => setVisualizerEnabled(context, ref, v),
                        ),
                    ],
                  ),
                    ],
                  ),
                  const GroupHeader('Sound leveling'),
                  InsetGroup(
                    children: [
                      choice(
                        'Volume leveling',
                        'Even out loud and quiet tracks using their ReplayGain tags',
                        Icons.equalizer_rounded,
                        const ['Off', 'Track', 'Album'],
                        s.replayGainMode,
                        n.setReplayGainMode,
                      ),
                      choice(
                        'Crossfade',
                        'Overlap the end of a track with the next. Experimental',
                        Icons.blur_linear_rounded,
                        const [
                          'Off',
                          '2 s',
                          '4 s',
                          '6 s',
                          '8 s',
                          '10 s',
                          '12 s',
                        ],
                        s.crossfadeSeconds == 0 ? 0 : s.crossfadeSeconds ~/ 2,
                        (i) => n.setCrossfadeSeconds(i * 2),
                      ),
                    ],
                  ),
                  const GroupHeader('Headphones & calls'),
                  InsetGroup(
                    children: [
                      toggle(
                        'Pause when unplugged',
                        'Pause when headphones are unplugged',
                        Icons.headset_off_outlined,
                        s.pauseOnUnplug,
                        n.togglePauseOnUnplug,
                      ),
                      toggle(
                        'Lower volume for notifications',
                        'Quieten the music instead of pausing for short sounds',
                        Icons.volume_down_rounded,
                        s.duckOnInterruption,
                        n.toggleDuckOnInterruption,
                      ),
                      toggle(
                        'Resume after interruptions',
                        'Carry on when a call or other sound ends',
                        Icons.play_circle_outline_rounded,
                        s.resumeAfterInterruption,
                        n.toggleResumeAfterInterruption,
                      ),
                      toggle(
                        'Resume when plugged back in',
                        'Carry on if headphones return within ten minutes',
                        Icons.headphones_rounded,
                        s.resumeOnReconnect,
                        n.toggleResumeOnReconnect,
                      ),
                    ],
                  ),
                  const GroupHeader('Library & online content'),
                  InsetGroup(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        leading: Icon(
                          Icons.sync_rounded,
                          color: a.textSecondary,
                        ),
                        title: const Text(
                          'Rescan music',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Find new music on your device',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () =>
                            ref.read(libraryProvider.notifier).fetchAllSongs(),
                      ),
                      toggle(
                        'Lyrics',
                        'Find lyrics online when a track starts',
                        Icons.lyrics_outlined,
                        s.enableLyricsFetching,
                        n.toggleLyricsFetching,
                      ),
                      toggle(
                        'Artist information',
                        'Load artist biographies and images online',
                        Icons.person_outline_rounded,
                        s.enableArtistInfoFetching,
                        n.toggleArtistInfoFetching,
                      ),
                      toggle(
                        'Find missing album covers',
                        'Looks up albums that have no picture on MusicBrainz '
                            'and the Cover Art Archive. Only the album and '
                            'artist names are sent. Covers are kept on this '
                            'device; your music files are not changed.',
                        Icons.image_search_rounded,
                        s.fetchMissingArt,
                        n.toggleFetchMissingArt,
                      ),
                      if (s.fetchMissingArt) const FindMissingArtRow(),
                      if (kDownloaderAvailable)
                        toggle(
                          'Downloads',
                          'Search online and download audio',
                          Icons.download_outlined,
                          s.enableDownloader,
                          n.toggleDownloader,
                        ),
                    ],
                  ),
                  if (kDownloaderAvailable)
                    if (s.enableDownloader) ...[
                      const GroupHeader('Downloader'),
                      InsetGroup(
                        children: [
                          const EngineSettingsRow(),
                          toggle(
                            'Wi-Fi only',
                            'Do not download on mobile data',
                            Icons.wifi_rounded,
                            s.downloadWifiOnly,
                            n.toggleDownloadWifiOnly,
                          ),
                        ],
                      ),
                    ],
                  const GroupHeader('Listening history'),
                  InsetGroup(
                    children: [
                      toggle(
                        'Incognito',
                        'Pause recording new listening history',
                        Icons.visibility_off_outlined,
                        s.isIncognitoMode,
                        n.toggleIncognito,
                      ),
                      toggle(
                        'Personalized Home',
                        'Show recently played music on Home',
                        Icons.history_rounded,
                        s.showStats,
                        n.toggleShowStats,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 28, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wavvy',
                          style: TextStyle(
                            fontSize: 16,
                            color: a.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Consumer(
                          builder: (context, ref, _) {
                            final version = ref
                                .watch(appVersionProvider)
                                .valueOrNull;
                            return Text(
                              version == null ? '' : 'Version $version',
                              style: TextStyle(
                                color: a.textSecondary,
                                fontSize: 12,
                              ),
                            );
                          },
                        ),
                      ],
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
