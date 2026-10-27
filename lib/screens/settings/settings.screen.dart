import 'package:flutter/material.dart' hide AppBar;
import 'package:flutter/services.dart';
import 'package:flutter_appbar/flutter_appbar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/widgets/floating_app_bar.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/theme_selector.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: theme.scaffoldBackgroundColor,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: AppBarConnection(
            appBars: [
              AppBar(
                behavior: const MaterialAppBarBehavior(floating: true),
                body: FloatingAppBar(
                  title: "Settings",
                  showSearch: false,
                  leading: GelButton(
                    tooltip: "Back",
                    onPressed: () => AppNav.pop(),
                    child: const Icon(Icons.chevron_left_rounded),
                  ),
                ),
              ),
            ],
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                const SizedBox(height: 8),
                const ThemeSelector(),

                const SizedBox(height: 8),

                // --- PLAYER FEATURES ---
                _buildSectionHeader(context, "Player Features"),
                _buildSettingsCard(
                  context,
                  children: [
                    _buildSwitchTile(
                      context,
                      title: "Double Tap to Seek",
                      subtitle: "Double tap artwork to skip 10s",
                      icon: Icons.touch_app_rounded,
                      color: Colors.blueAccent,
                      value: settings.enableDoubleTapSeek,
                      onChanged: notifier.toggleDoubleTapSeek,
                    ),
                    _buildDivider(context),
                    _buildSwitchTile(
                      context,
                      title: "Shake to Skip",
                      subtitle: "Shake your device to skip track",
                      icon: Icons.vibration_rounded,
                      color: Colors.orangeAccent,
                      value: settings.enableShakeToSkip,
                      onChanged: notifier.toggleShakeToSkip,
                    ),
                    _buildDivider(context),
                    // _buildSwitchTile(
                    //   title: "Fade In/Out",
                    //   subtitle: "Smooth transition between tracks",
                    //   icon: Icons.blur_linear_rounded,
                    //   color: Colors.teal,
                    //   value: controller.enableFadeInOut,
                    //   onChanged: controller.toggleFadeInOut,
                    // ),
                    _buildDivider(context),
                    _buildSwitchTile(
                      context,
                      title: "Dynamic Colors",
                      subtitle: "Theme player based on album art",
                      icon: Icons.palette_rounded,
                      color: Colors.purpleAccent,
                      value: settings.enableDynamicColors,
                      onChanged: notifier.toggleDynamicColors,
                    ),
                    _buildDivider(context),
                    _buildSwitchTile(
                      context,
                      title: "Dark mode",
                      subtitle: "Switch to dark mode",
                      icon: Icons.dark_mode_rounded,
                      color: Colors.indigoAccent,
                      value: settings.isDarkMode,
                      onChanged: notifier.toggleDarkMode,
                    ),
                  ],
                ),

                // --- CONTENT & LIBRARY ---
                _buildSectionHeader(context, "Content & Library"),
                _buildSettingsCard(
                  context,
                  children: [
                    _buildSwitchTile(
                      context,
                      title: "Fetch Lyrics",
                      subtitle: "Automatically find song lyrics",
                      icon: Icons.lyrics_rounded,
                      color: Colors.pinkAccent,
                      value: settings.enableLyricsFetching,
                      onChanged: notifier.toggleLyricsFetching,
                    ),
                    _buildDivider(context),
                    _buildSwitchTile(
                      context,
                      title: "Artist Info",
                      subtitle: "Load bios and artist images",
                      icon: Icons.person_search_rounded,
                      color: Colors.indigoAccent,
                      value: settings.enableArtistInfoFetching,
                      onChanged: notifier.toggleArtistInfoFetching,
                    ),
                    _buildDivider(context),
                    _buildSwitchTile(
                      context,
                      title: "Show Stats",
                      subtitle: "Most played & recently played",
                      icon: Icons.bar_chart_rounded,
                      color: Colors.green,
                      value: settings.showStats,
                      onChanged: notifier.toggleShowStats,
                    ),
                  ],
                ),

                // --- PRIVACY ---
                _buildSectionHeader(context, "Privacy"),
                _buildSettingsCard(
                  context,
                  children: [
                    _buildSwitchTile(
                      context,
                      title: "Incognito Mode",
                      subtitle: "Don't record listening history",
                      icon: Icons.visibility_off_rounded,
                      color: Colors.grey,
                      value: settings.isIncognitoMode,
                      onChanged: notifier.toggleIncognito,
                    ),
                  ],
                ),

                // --- SYSTEM ---
                _buildSectionHeader(context, "System"),
                _buildSettingsCard(
                  context,
                  children: [
                    _buildSwitchTile(
                      context,
                      title: "Enable Downloader",
                      subtitle: "Allow downloading external content",
                      icon: Icons.download_rounded,
                      color: Colors.redAccent,
                      value: settings.enableDownloader,
                      onChanged: notifier.toggleDownloader,
                    ),
                    _buildDivider(context),
                    // _buildSwitchTile(
                    //   title: "Keep Screen On",
                    //   subtitle: "Prevent sleep while viewing lyrics",
                    //   icon: Icons.wb_sunny_rounded,
                    //   color: Colors.amber,
                    //   value: controller.enableWakeLock,
                    //   onChanged: controller.toggleWakeLock,
                    // ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- REUSABLE WIDGETS ---

  Widget _buildSectionHeader(BuildContext context, String title) {
    return GroupHeader(title);
  }

  Widget _buildSettingsCard(
    BuildContext context, {
    required List<Widget> children,
  }) {
    // Dividers are inserted by InsetGroup, so drop the manual ones.
    return InsetGroup(children: children.where((w) => w is! Divider).toList());
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
          child: Row(
            children: [
              IconBadge(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color:
                            (Theme.of(
                              context,
                            ).extension<AquaPalette>()?.textSecondary ??
                            Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
              AquaCheckbox(value: value, onChanged: onChanged),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Divider(
      height: Ds.hairline,
      thickness: Ds.hairline,
      indent: 60,
      color: Ds.separator(context),
    );
  }
}
