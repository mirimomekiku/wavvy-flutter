import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavvy/downloader/engine.dart';
import 'package:wavvy/providers/settings_provider.dart';

/// The yt-dlp engine. Overridden in tests with a fake.
final ytDlpEngineProvider = Provider<YtDlpEngine>(
  (ref) => PlatformYtDlpEngine(),
);

final engineProvider = NotifierProvider<EngineNotifier, EngineStatus>(
  EngineNotifier.new,
);

/// Whether the engine is set up, and the one place that sets it up or updates
/// it. YouTube changes often, so yt-dlp is checked for updates about once a day.
class EngineNotifier extends Notifier<EngineStatus> {
  static const _kLastUpdate = 'ytdlp_last_update';
  static const updateEvery = Duration(hours: 24);

  YtDlpEngine get _engine => ref.read(ytDlpEngineProvider);

  @override
  EngineStatus build() {
    Future.microtask(refresh);
    return const EngineStatus(EngineState.unknown);
  }

  Future<void> refresh() async {
    try {
      state = await _engine.status();
    } on DownloaderException catch (e) {
      state = EngineStatus(EngineState.failed, message: e.message);
    }
  }

  /// Sets the engine up, or updates it. Safe to call while one is running.
  Future<void> install() async {
    if (state.isBusy) return;
    final before = state;
    state = EngineStatus(
      EngineState.installing,
      version: before.version,
      message: 'Preparing the downloader…',
    );
    final sub = _engine.events
        .where((e) => e is EngineProgress)
        .cast<EngineProgress>()
        .listen((e) {
          if (!state.isBusy) return;
          state = EngineStatus(
            EngineState.installing,
            version: before.version,
            message: switch (e.phase) {
              'starting' => 'Starting the engine…',
              'downloading' => 'Downloading yt-dlp…',
              _ => state.message,
            },
          );
        });
    try {
      state = await _engine.install();
      await SharedPreferencesAsync().setInt(
        _kLastUpdate,
        DateTime.now().millisecondsSinceEpoch,
      );
    } on IntegrityException catch (e) {
      // The file on disk may be the unverified one: never keep it "ready".
      state = EngineStatus(
        EngineState.failed,
        version: before.version,
        message: e.message,
      );
    } on DownloaderException catch (e) {
      // A failed update leaves the engine usable; a failed first setup does not.
      state = EngineStatus(
        before.isReady ? EngineState.ready : EngineState.failed,
        version: before.version,
        message: before.isReady ? 'Update failed: ${e.message}' : e.message,
      );
    } finally {
      await sub.cancel();
    }
  }

  /// Updates yt-dlp if it has not been checked for a day. Quiet: a failure
  /// keeps the working version. Does nothing while the downloader is switched
  /// off in Settings.
  Future<void> updateIfDue() async {
    if (!ref.read(settingsProvider).downloaderOn) return;
    if (!state.isReady || state.isBusy) return;
    final last = await SharedPreferencesAsync().getInt(_kLastUpdate);
    final age = last == null
        ? updateEvery
        : DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last));
    if (age >= updateEvery) await install();
  }
}
