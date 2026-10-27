import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Immutable snapshot of every user setting (replaces SettingsService's Rx
/// fields). Field names are unchanged from the GetX version.
class SettingsState {
  final bool enableDoubleTapSeek;
  final bool enableShakeToSkip;
  final bool enableFadeInOut;
  final bool enableDynamicColors;
  final bool enableLyricsFetching;
  final bool enableArtistInfoFetching;
  final bool showStats;
  final bool enableDownloader;
  final bool enableWakeLock;
  final bool isDarkMode;
  final bool isIncognitoMode;

  /// 0 = Blue, 1 = Graphite (Aqua appearance).
  final int currentThemeIndex;

  const SettingsState({
    this.enableDoubleTapSeek = true,
    this.enableShakeToSkip = false,
    this.enableFadeInOut = false,
    this.enableDynamicColors = true,
    this.enableLyricsFetching = true,
    this.enableArtistInfoFetching = true,
    this.showStats = true,
    this.enableDownloader = true,
    this.enableWakeLock = false,
    this.isDarkMode = false,
    this.isIncognitoMode = false,
    this.currentThemeIndex = 0,
  });

  SettingsState copyWith({
    bool? enableDoubleTapSeek,
    bool? enableShakeToSkip,
    bool? enableFadeInOut,
    bool? enableDynamicColors,
    bool? enableLyricsFetching,
    bool? enableArtistInfoFetching,
    bool? showStats,
    bool? enableDownloader,
    bool? enableWakeLock,
    bool? isDarkMode,
    bool? isIncognitoMode,
    int? currentThemeIndex,
  }) => SettingsState(
    enableDoubleTapSeek: enableDoubleTapSeek ?? this.enableDoubleTapSeek,
    enableShakeToSkip: enableShakeToSkip ?? this.enableShakeToSkip,
    enableFadeInOut: enableFadeInOut ?? this.enableFadeInOut,
    enableDynamicColors: enableDynamicColors ?? this.enableDynamicColors,
    enableLyricsFetching: enableLyricsFetching ?? this.enableLyricsFetching,
    enableArtistInfoFetching:
        enableArtistInfoFetching ?? this.enableArtistInfoFetching,
    showStats: showStats ?? this.showStats,
    enableDownloader: enableDownloader ?? this.enableDownloader,
    enableWakeLock: enableWakeLock ?? this.enableWakeLock,
    isDarkMode: isDarkMode ?? this.isDarkMode,
    isIncognitoMode: isIncognitoMode ?? this.isIncognitoMode,
    currentThemeIndex: currentThemeIndex ?? this.currentThemeIndex,
  );
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);

/// Port of SettingsService. Persists with SharedPreferencesAsync using the
/// SAME keys as before (feature_double_tap_seek, ..., theme_scheme_index).
class SettingsNotifier extends Notifier<SettingsState> {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  static const String _kDoubleTapSeek = 'feature_double_tap_seek';
  static const String _kShakeToSkip = 'feature_shake_to_skip';
  static const String _kFadeInOut = 'feature_fade_in_out';
  static const String _kDynamicColors = 'feature_dynamic_colors';
  static const String _kFetchLyrics = 'feature_fetch_lyrics';
  static const String _kFetchArtistInfo = 'feature_fetch_artist_info';
  static const String _kShowStats = 'feature_show_stats';
  static const String _kEnableDownloader = 'feature_enable_downloader';
  static const String _kWakeLock = 'feature_wake_lock';
  static const String _kDarkMode = 'feature_dark_mode';
  static const String _kIncognito = 'feature_incognito';
  static const String _kThemeSchemeIndex = 'theme_scheme_index';

  @override
  SettingsState build() => const SettingsState();

  /// Reads preferences into state and applies the wake lock. Called once in
  /// main() before runApp. First run: dark mode follows the platform brightness.
  Future<void> load() async {
    final storedIndex = await _prefs.getInt(_kThemeSchemeIndex) ?? 0;
    final storedTheme = await _prefs.getBool(_kDarkMode);

    final loaded = SettingsState(
      enableDoubleTapSeek: await _prefs.getBool(_kDoubleTapSeek) ?? true,
      enableShakeToSkip: await _prefs.getBool(_kShakeToSkip) ?? false,
      enableFadeInOut: await _prefs.getBool(_kFadeInOut) ?? false,
      enableDynamicColors: await _prefs.getBool(_kDynamicColors) ?? true,
      enableLyricsFetching: await _prefs.getBool(_kFetchLyrics) ?? true,
      enableArtistInfoFetching: await _prefs.getBool(_kFetchArtistInfo) ?? true,
      showStats: await _prefs.getBool(_kShowStats) ?? true,
      enableDownloader: await _prefs.getBool(_kEnableDownloader) ?? true,
      enableWakeLock: await _prefs.getBool(_kWakeLock) ?? false,
      isIncognitoMode: await _prefs.getBool(_kIncognito) ?? false,
      // 0 = Blue, 1 = Graphite (Aqua appearance).
      currentThemeIndex: storedIndex.clamp(0, 1),
      isDarkMode:
          storedTheme ??
          PlatformDispatcher.instance.platformBrightness == Brightness.dark,
    );
    state = loaded;
    _applyWakeLock();
  }

  Future<void> toggleDoubleTapSeek(bool value) async {
    state = state.copyWith(enableDoubleTapSeek: value);
    await _prefs.setBool(_kDoubleTapSeek, value);
  }

  Future<void> toggleShakeToSkip(bool value) async {
    state = state.copyWith(enableShakeToSkip: value);
    await _prefs.setBool(_kShakeToSkip, value);
  }

  Future<void> toggleFadeInOut(bool value) async {
    state = state.copyWith(enableFadeInOut: value);
    await _prefs.setBool(_kFadeInOut, value);
  }

  Future<void> toggleDynamicColors(bool value) async {
    state = state.copyWith(enableDynamicColors: value);
    await _prefs.setBool(_kDynamicColors, value);
  }

  Future<void> toggleLyricsFetching(bool value) async {
    state = state.copyWith(enableLyricsFetching: value);
    await _prefs.setBool(_kFetchLyrics, value);
  }

  Future<void> toggleArtistInfoFetching(bool value) async {
    state = state.copyWith(enableArtistInfoFetching: value);
    await _prefs.setBool(_kFetchArtistInfo, value);
  }

  Future<void> toggleShowStats(bool value) async {
    state = state.copyWith(showStats: value);
    await _prefs.setBool(_kShowStats, value);
  }

  Future<void> toggleDownloader(bool value) async {
    state = state.copyWith(enableDownloader: value);
    await _prefs.setBool(_kEnableDownloader, value);
  }

  Future<void> toggleWakeLock(bool value) async {
    state = state.copyWith(enableWakeLock: value);
    await _prefs.setBool(_kWakeLock, value);
    _applyWakeLock();
  }

  Future<void> toggleDarkMode(bool value) async {
    state = state.copyWith(isDarkMode: value);
    await _prefs.setBool(_kDarkMode, value);
  }

  Future<void> toggleIncognito(bool value) async {
    state = state.copyWith(isIncognitoMode: value);
    await _prefs.setBool(_kIncognito, value);
  }

  /// Clamped to 0..1.
  Future<void> updateThemeIndex(int index) async {
    final clamped = index.clamp(0, 1);
    state = state.copyWith(currentThemeIndex: clamped);
    await _prefs.setInt(_kThemeSchemeIndex, clamped);
  }

  void _applyWakeLock() {
    WakelockPlus.toggle(enable: state.enableWakeLock);
  }
}
