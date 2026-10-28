import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavvy/downloader/flavor.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Immutable snapshot of every user setting.
class SettingsState {
  final bool enableDoubleTapSeek;
  final bool enableShakeToSkip;
  final bool enableFadeInOut;
  final bool enableSkipSilence;
  final bool enableDynamicColors;
  final bool enableLyricsFetching;
  final bool enableArtistInfoFetching;

  /// Look up missing album covers on MusicBrainz and the Cover Art Archive
  /// (sends album and artist names). Off by default.
  final bool fetchMissingArt;

  /// The spectrum page in the player; needs the microphone permission.
  final bool enableVisualizer;
  final bool showStats;
  final bool enableDownloader;

  /// Reopen with the queue and position you left.
  final bool resumeSession;

  /// Pause when headphones are unplugged.
  final bool pauseOnUnplug;

  /// Lower the volume, instead of pausing, for short sounds such as notifications.
  final bool duckOnInterruption;

  /// Carry on after a call or other interruption ends.
  final bool resumeAfterInterruption;

  /// Resume when headphones are plugged back in soon after unplugging.
  final bool resumeOnReconnect;

  /// Keep the speed and pitch you choose for each album.
  final bool rememberRates;

  /// Shuffle that keeps an artist's songs apart and favors liked and rarely
  /// played songs.
  final bool smartShuffle;

  /// A shake near the end of the sleep timer adds more time.
  final bool shakeExtendsSleep;

  /// Hold volume up / down for the next / previous song (while the app is open).
  final bool volumeKeySkip;

  /// The Now Playing layout, as an index into `PlayerLayout` (0 is the vinyl
  /// deck).
  final int playerLayout;

  /// Show two panes on wide screens (landscape, tablets) whatever layout is
  /// chosen.
  final bool playerLayoutAdaptive;

  /// 0 off, 1 track gain, 2 album gain.
  final int replayGainMode;

  /// 0 is off.
  final int crossfadeSeconds;

  /// Extra buttons in the media notification and on the lock screen.
  final bool notifLike;
  final bool notifShuffle;
  final bool notifRepeat;

  /// Only start downloads on an unmetered (Wi-Fi) connection.
  final bool downloadWifiOnly;
  final bool enableWakeLock;
  final bool isDarkMode;
  final bool isIncognitoMode;

  /// The color theme: see [WavvyTheme.byIndex]. Values saved by older versions
  /// migrate on load ([WavvyTheme.normalizeIndex]).
  final int currentThemeIndex;

  const SettingsState({
    this.enableDoubleTapSeek = true,
    this.enableShakeToSkip = false,
    this.enableFadeInOut = false,
    this.enableSkipSilence = false,
    this.enableDynamicColors = false,
    this.enableLyricsFetching = true,
    this.enableArtistInfoFetching = true,
    this.fetchMissingArt = false,
    this.enableVisualizer = false,
    this.showStats = true,
    this.enableDownloader = true,
    this.downloadWifiOnly = false,
    this.resumeSession = true,
    this.pauseOnUnplug = true,
    this.duckOnInterruption = true,
    this.resumeAfterInterruption = true,
    this.resumeOnReconnect = false,
    this.rememberRates = true,
    this.smartShuffle = true,
    this.shakeExtendsSleep = false,
    this.volumeKeySkip = false,
    this.playerLayout = 0,
    this.playerLayoutAdaptive = true,
    this.replayGainMode = 0,
    this.crossfadeSeconds = 0,
    this.notifLike = true,
    this.notifShuffle = false,
    this.notifRepeat = false,
    this.enableWakeLock = false,
    this.isDarkMode = false,
    this.isIncognitoMode = false,
    this.currentThemeIndex = 5,
  });

  /// Whether downloads are on: this build has the downloader (see
  /// [kDownloaderAvailable]) and the user has not turned it off.
  bool get downloaderOn => kDownloaderAvailable && enableDownloader;

  SettingsState copyWith({
    bool? enableDoubleTapSeek,
    bool? enableShakeToSkip,
    bool? enableFadeInOut,
    bool? enableSkipSilence,
    bool? enableDynamicColors,
    bool? enableLyricsFetching,
    bool? enableArtistInfoFetching,
    bool? fetchMissingArt,
    bool? enableVisualizer,
    bool? showStats,
    bool? enableDownloader,
    bool? downloadWifiOnly,
    bool? resumeSession,
    bool? pauseOnUnplug,
    bool? duckOnInterruption,
    bool? resumeAfterInterruption,
    bool? resumeOnReconnect,
    bool? rememberRates,
    bool? smartShuffle,
    bool? shakeExtendsSleep,
    bool? volumeKeySkip,
    int? playerLayout,
    bool? playerLayoutAdaptive,
    int? replayGainMode,
    int? crossfadeSeconds,
    bool? notifLike,
    bool? notifShuffle,
    bool? notifRepeat,
    bool? enableWakeLock,
    bool? isDarkMode,
    bool? isIncognitoMode,
    int? currentThemeIndex,
  }) => SettingsState(
    enableDoubleTapSeek: enableDoubleTapSeek ?? this.enableDoubleTapSeek,
    enableShakeToSkip: enableShakeToSkip ?? this.enableShakeToSkip,
    enableFadeInOut: enableFadeInOut ?? this.enableFadeInOut,
    enableSkipSilence: enableSkipSilence ?? this.enableSkipSilence,
    enableDynamicColors: enableDynamicColors ?? this.enableDynamicColors,
    enableLyricsFetching: enableLyricsFetching ?? this.enableLyricsFetching,
    enableArtistInfoFetching:
        enableArtistInfoFetching ?? this.enableArtistInfoFetching,
    fetchMissingArt: fetchMissingArt ?? this.fetchMissingArt,
    enableVisualizer: enableVisualizer ?? this.enableVisualizer,
    showStats: showStats ?? this.showStats,
    enableDownloader: enableDownloader ?? this.enableDownloader,
    downloadWifiOnly: downloadWifiOnly ?? this.downloadWifiOnly,
    resumeSession: resumeSession ?? this.resumeSession,
    pauseOnUnplug: pauseOnUnplug ?? this.pauseOnUnplug,
    duckOnInterruption: duckOnInterruption ?? this.duckOnInterruption,
    resumeAfterInterruption:
        resumeAfterInterruption ?? this.resumeAfterInterruption,
    resumeOnReconnect: resumeOnReconnect ?? this.resumeOnReconnect,
    rememberRates: rememberRates ?? this.rememberRates,
    smartShuffle: smartShuffle ?? this.smartShuffle,
    shakeExtendsSleep: shakeExtendsSleep ?? this.shakeExtendsSleep,
    volumeKeySkip: volumeKeySkip ?? this.volumeKeySkip,
    playerLayout: playerLayout ?? this.playerLayout,
    playerLayoutAdaptive: playerLayoutAdaptive ?? this.playerLayoutAdaptive,
    replayGainMode: replayGainMode ?? this.replayGainMode,
    crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
    notifLike: notifLike ?? this.notifLike,
    notifShuffle: notifShuffle ?? this.notifShuffle,
    notifRepeat: notifRepeat ?? this.notifRepeat,
    enableWakeLock: enableWakeLock ?? this.enableWakeLock,
    isDarkMode: isDarkMode ?? this.isDarkMode,
    isIncognitoMode: isIncognitoMode ?? this.isIncognitoMode,
    currentThemeIndex: currentThemeIndex ?? this.currentThemeIndex,
  );
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);

/// Persists settings with SharedPreferencesAsync (feature_double_tap_seek, ...,
/// theme_scheme_index). Existing keys keep their meaning so saved preferences
/// carry over between versions.
class SettingsNotifier extends Notifier<SettingsState> {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  static const String _kDoubleTapSeek = 'feature_double_tap_seek';
  static const String _kShakeToSkip = 'feature_shake_to_skip';
  static const String _kFadeInOut = 'feature_fade_in_out';
  static const String _kSkipSilence = 'feature_skip_silence';
  static const String _kDynamicColors = 'feature_dynamic_colors';
  static const String _kFetchLyrics = 'feature_fetch_lyrics';
  static const String _kFetchArtistInfo = 'feature_fetch_artist_info';
  static const String _kFetchMissingArt = 'feature_fetch_missing_art';
  static const String _kVisualizer = 'feature_visualizer';
  static const String _kShowStats = 'feature_show_stats';
  static const String _kEnableDownloader = 'feature_enable_downloader';
  static const String _kDownloadWifiOnly = 'feature_download_wifi_only';
  static const String _kResumeSession = 'feature_resume_session';
  static const String _kPauseOnUnplug = 'feature_pause_on_unplug';
  static const String _kDuckOnInterruption = 'feature_duck_on_interruption';
  static const String _kResumeAfterInterruption =
      'feature_resume_after_interruption';
  static const String _kResumeOnReconnect = 'feature_resume_on_reconnect';
  static const String _kRememberRates = 'feature_remember_rates';
  static const String _kSmartShuffle = 'feature_smart_shuffle';
  static const String _kShakeExtendsSleep = 'feature_shake_extends_sleep';
  static const String _kVolumeKeySkip = 'feature_volume_key_skip';
  static const String _kPlayerLayout = 'feature_player_layout';
  static const String _kPlayerLayoutAdaptive = 'feature_player_layout_adaptive';
  static const String _kReplayGainMode = 'feature_replay_gain';
  static const String _kCrossfadeSeconds = 'feature_crossfade_seconds';
  static const String _kNotifLike = 'feature_notif_like';
  static const String _kNotifShuffle = 'feature_notif_shuffle';
  static const String _kNotifRepeat = 'feature_notif_repeat';
  static const String _kWakeLock = 'feature_wake_lock';
  static const String _kDarkMode = 'feature_dark_mode';
  static const String _kIncognito = 'feature_incognito';
  static const String _kThemeSchemeIndex = 'theme_scheme_index';

  @override
  SettingsState build() => const SettingsState();

  /// Reads preferences into state and applies the wake lock. Called once in
  /// main() before runApp. First run: dark mode follows the platform brightness.
  Future<void> load() async {
    // New installs use Kaisu Aqua; older saved themes are carried over.
    final storedIndex = await _prefs.getInt(_kThemeSchemeIndex);
    final storedTheme = await _prefs.getBool(_kDarkMode);

    final loaded = SettingsState(
      enableDoubleTapSeek: await _prefs.getBool(_kDoubleTapSeek) ?? true,
      enableShakeToSkip: await _prefs.getBool(_kShakeToSkip) ?? false,
      enableFadeInOut: await _prefs.getBool(_kFadeInOut) ?? false,
      enableSkipSilence: await _prefs.getBool(_kSkipSilence) ?? false,
      enableDynamicColors: await _prefs.getBool(_kDynamicColors) ?? false,
      enableLyricsFetching: await _prefs.getBool(_kFetchLyrics) ?? true,
      enableArtistInfoFetching: await _prefs.getBool(_kFetchArtistInfo) ?? true,
      fetchMissingArt: await _prefs.getBool(_kFetchMissingArt) ?? false,
      enableVisualizer: await _prefs.getBool(_kVisualizer) ?? false,
      showStats: await _prefs.getBool(_kShowStats) ?? true,
      enableDownloader: await _prefs.getBool(_kEnableDownloader) ?? true,
      downloadWifiOnly: await _prefs.getBool(_kDownloadWifiOnly) ?? false,
      resumeSession: await _prefs.getBool(_kResumeSession) ?? true,
      pauseOnUnplug: await _prefs.getBool(_kPauseOnUnplug) ?? true,
      duckOnInterruption: await _prefs.getBool(_kDuckOnInterruption) ?? true,
      resumeAfterInterruption:
          await _prefs.getBool(_kResumeAfterInterruption) ?? true,
      resumeOnReconnect: await _prefs.getBool(_kResumeOnReconnect) ?? false,
      rememberRates: await _prefs.getBool(_kRememberRates) ?? true,
      smartShuffle: await _prefs.getBool(_kSmartShuffle) ?? true,
      shakeExtendsSleep: await _prefs.getBool(_kShakeExtendsSleep) ?? false,
      volumeKeySkip: await _prefs.getBool(_kVolumeKeySkip) ?? false,
      playerLayout: (await _prefs.getInt(_kPlayerLayout)) ?? 0,
      playerLayoutAdaptive:
          await _prefs.getBool(_kPlayerLayoutAdaptive) ?? true,
      replayGainMode: (await _prefs.getInt(_kReplayGainMode)) ?? 0,
      crossfadeSeconds: (await _prefs.getInt(_kCrossfadeSeconds)) ?? 0,
      notifLike: await _prefs.getBool(_kNotifLike) ?? true,
      notifShuffle: await _prefs.getBool(_kNotifShuffle) ?? false,
      notifRepeat: await _prefs.getBool(_kNotifRepeat) ?? false,
      enableWakeLock: await _prefs.getBool(_kWakeLock) ?? false,
      isIncognitoMode: await _prefs.getBool(_kIncognito) ?? false,
      // Existing saved indices remain compatible.
      currentThemeIndex: WavvyTheme.normalizeIndex(storedIndex),
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

  Future<void> toggleSkipSilence(bool value) async {
    state = state.copyWith(enableSkipSilence: value);
    await _prefs.setBool(_kSkipSilence, value);
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

  Future<void> toggleFetchMissingArt(bool value) async {
    state = state.copyWith(fetchMissingArt: value);
    await _prefs.setBool(_kFetchMissingArt, value);
  }

  Future<void> toggleVisualizer(bool value) async {
    state = state.copyWith(enableVisualizer: value);
    await _prefs.setBool(_kVisualizer, value);
  }

  Future<void> toggleShowStats(bool value) async {
    state = state.copyWith(showStats: value);
    await _prefs.setBool(_kShowStats, value);
  }

  Future<void> toggleDownloader(bool value) async {
    state = state.copyWith(enableDownloader: value);
    await _prefs.setBool(_kEnableDownloader, value);
  }

  Future<void> toggleResumeSession(bool value) async {
    state = state.copyWith(resumeSession: value);
    await _prefs.setBool(_kResumeSession, value);
  }

  Future<void> togglePauseOnUnplug(bool value) async {
    state = state.copyWith(pauseOnUnplug: value);
    await _prefs.setBool(_kPauseOnUnplug, value);
  }

  Future<void> toggleDuckOnInterruption(bool value) async {
    state = state.copyWith(duckOnInterruption: value);
    await _prefs.setBool(_kDuckOnInterruption, value);
  }

  Future<void> toggleResumeAfterInterruption(bool value) async {
    state = state.copyWith(resumeAfterInterruption: value);
    await _prefs.setBool(_kResumeAfterInterruption, value);
  }

  Future<void> toggleResumeOnReconnect(bool value) async {
    state = state.copyWith(resumeOnReconnect: value);
    await _prefs.setBool(_kResumeOnReconnect, value);
  }

  Future<void> toggleRememberRates(bool value) async {
    state = state.copyWith(rememberRates: value);
    await _prefs.setBool(_kRememberRates, value);
  }

  Future<void> toggleSmartShuffle(bool value) async {
    state = state.copyWith(smartShuffle: value);
    await _prefs.setBool(_kSmartShuffle, value);
  }

  Future<void> toggleShakeExtendsSleep(bool value) async {
    state = state.copyWith(shakeExtendsSleep: value);
    await _prefs.setBool(_kShakeExtendsSleep, value);
  }

  Future<void> toggleVolumeKeySkip(bool value) async {
    state = state.copyWith(volumeKeySkip: value);
    await _prefs.setBool(_kVolumeKeySkip, value);
  }

  Future<void> setPlayerLayout(int index) async {
    state = state.copyWith(playerLayout: index);
    await _prefs.setInt(_kPlayerLayout, index);
  }

  Future<void> togglePlayerLayoutAdaptive(bool value) async {
    state = state.copyWith(playerLayoutAdaptive: value);
    await _prefs.setBool(_kPlayerLayoutAdaptive, value);
  }

  Future<void> setReplayGainMode(int value) async {
    state = state.copyWith(replayGainMode: value);
    await _prefs.setInt(_kReplayGainMode, value);
  }

  Future<void> setCrossfadeSeconds(int value) async {
    state = state.copyWith(crossfadeSeconds: value);
    await _prefs.setInt(_kCrossfadeSeconds, value);
  }

  Future<void> toggleNotifLike(bool value) async {
    state = state.copyWith(notifLike: value);
    await _prefs.setBool(_kNotifLike, value);
  }

  Future<void> toggleNotifShuffle(bool value) async {
    state = state.copyWith(notifShuffle: value);
    await _prefs.setBool(_kNotifShuffle, value);
  }

  Future<void> toggleNotifRepeat(bool value) async {
    state = state.copyWith(notifRepeat: value);
    await _prefs.setBool(_kNotifRepeat, value);
  }

  Future<void> toggleDownloadWifiOnly(bool value) async {
    state = state.copyWith(downloadWifiOnly: value);
    await _prefs.setBool(_kDownloadWifiOnly, value);
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

  /// Select a preset and turn off album-adaptive recoloring.
  Future<void> updateThemeIndex(int index) async {
    final clamped = WavvyTheme.normalizeIndex(index);
    // An explicit preset wins over album-adaptive colors.
    state = state.copyWith(
      currentThemeIndex: clamped,
      enableDynamicColors: false,
    );
    await _prefs.setBool(_kDynamicColors, false);
    await _prefs.setInt(_kThemeSchemeIndex, clamped);
  }

  void _applyWakeLock() {
    WakelockPlus.toggle(enable: state.enableWakeLock);
  }
}
