import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/providers/palette_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/theme_crossfade.dart';
import 'package:wavvy/theme/wavvy_theme.dart';

/// The MaterialApp, themed from settings and the album art.
///
///  * light/dark comes from [SettingsState.isDarkMode];
///  * the accent comes from the selected color theme (Aqua, an accent turned
///    from it, or Graphite) or, when Album colors is on, from the current album
///    art ([PaletteState.accent]), which becomes a full tonal scheme.
///
/// Kept separate from `MyApp` so the theming can be tested without starting
/// the audio stack.
class WavvyMaterialApp extends ConsumerWidget {
  final Widget home;
  final Map<String, WidgetBuilder> routes;

  const WavvyMaterialApp({
    super.key,
    required this.home,
    this.routes = const <String, WidgetBuilder>{},
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(settingsProvider.select((s) => s.isDarkMode));
    final themeIndex = ref.watch(
      settingsProvider.select((s) => s.currentThemeIndex),
    );
    final dynamicColors = ref.watch(
      settingsProvider.select((s) => s.enableDynamicColors),
    );
    final accent = ref.watch(paletteProvider.select((p) => p.accent));

    final appearance = WavvyTheme.appearanceFor(themeIndex);
    final seed = dynamicColors ? accent : null;

    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      title: 'Wavvy',
      debugShowCheckedModeBanner: false,
      theme: WavvyTheme.light(appearance, seed: seed),
      darkTheme: WavvyTheme.dark(appearance, seed: seed),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      // Switch at once; ThemeCrossFade fades the old frame away instead of
      // Material rebuilding the whole app on every frame of a theme tween.
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => ThemeCrossFade(
        themeKey: (isDark, themeIndex, seed?.toARGB32()),
        child: child ?? const SizedBox.shrink(),
      ),
      home: home,
      routes: routes,
    );
  }
}
