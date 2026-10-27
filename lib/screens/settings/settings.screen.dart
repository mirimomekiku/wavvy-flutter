import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/page_heading.dart';
import 'package:wavvy/widgets/theme_selector.dart';
import 'package:wavvy/widgets/bottom_bar.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

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
    ) => CheckboxListTile(
      dense: true,
      value: value,
      onChanged: (value) {
        if (value != null) change(value);
      },
      controlAffinity: ListTileControlAffinity.trailing,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      secondary: Icon(icon, color: a.textSecondary, size: 22),
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
    );
    return WvSystemUi(
      child: Scaffold(
        backgroundColor: a.background,
        bottomNavigationBar: const BottomMiniPlayer(showTabView: false),
        body: SafeArea(
          bottom: false,
          child: Column(
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
                          'Keep screen awake',
                          'Keep Wavvy visible while you listen',
                          Icons.light_mode_outlined,
                          s.enableWakeLock,
                          n.toggleWakeLock,
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
                          onTap: () => ref
                              .read(libraryProvider.notifier)
                              .fetchAllSongs(),
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
                          'Downloads',
                          'Enable YouTube, TikTok and transfer history',
                          Icons.download_outlined,
                          s.enableDownloader,
                          n.toggleDownloader,
                        ),
                      ],
                    ),
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
                          Text(
                            'The mobile side of Kaisu.',
                            style: TextStyle(
                              color: a.textSecondary,
                              fontSize: 12,
                            ),
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
      ),
    );
  }
}
