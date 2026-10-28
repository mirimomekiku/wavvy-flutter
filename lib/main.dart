import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:wavvy/core/error_hooks.dart';
import 'package:wavvy/core/volume_keys.dart';
import 'package:wavvy/instances/audio_handler.instance.dart';
import 'package:wavvy/providers/audio_coordinator.dart';
import 'package:wavvy/providers/audio_effects_provider.dart';
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/downloader/flavor.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/home/home.screen.dart';
import 'package:wavvy/screens/settings/settings.screen.dart';
import 'package:wavvy/screens/startup/startup_failure.screen.dart';
import 'package:wavvy/wavvy_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHooks();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Work Sans',
    ], await rootBundle.loadString('assets/fonts/OFL-WorkSans.txt'));
  });

  // None of these stop music from playing, so a failure only disables the
  // feature that needs it (artist info, downloads, tag editing).
  await _bestEffort(".env", () => dotenv.load(fileName: ".env"));
  await _bestEffort("metadata", MetadataGod.initialize);

  await _launch();
}

Future<void> _bestEffort(String what, Future<void> Function() task) async {
  try {
    await task();
  } catch (e) {
    debugPrint("$what unavailable: $e");
  }
}

/// Starts audio, then the app. Audio is required, so if it can't start the
/// user gets the recovery screen, whose Try Again runs this again.
Future<void> _launch() async {
  final AndroidEqualizer equalizer = AndroidEqualizer();
  final WavvyAudioHandler handler;
  try {
    handler = await _startAudio(equalizer);
  } catch (e, stack) {
    debugPrint("INIT ERROR: $e\n$stack");
    // A fresh key gives each attempt a fresh screen (no leftover spinner).
    runApp(StartupFailureApp(key: UniqueKey(), error: e, onRetry: _launch));
    return;
  }

  final container = ProviderContainer(
    overrides: [
      audioHandlerProvider.overrideWithValue(handler),
      equalizerInstanceProvider.overrideWithValue(equalizer),
      nativeEffectsChannelProvider.overrideWithValue(NativeEffectsChannel()),
    ],
  );

  try {
    await container.read(settingsProvider.notifier).load();
  } catch (e) {
    debugPrint("Could not load settings, using defaults: $e");
  }

  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
}

Future<WavvyAudioHandler> _startAudio(AndroidEqualizer equalizer) async {
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  return AudioService.init(
    builder: () => WavvyAudioHandler(equalizer: equalizer, session: session),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.mirimomekiku.wavvy.channel.audio',
      androidNotificationChannelName: 'Wavvy',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep app-lifetime providers alive without rebuilding on every event.
    ref.watch(audioCoordinatorProvider);
    ref.watch(volumeKeysProvider);
    if (kDownloaderAvailable) {
      // Follows downloads (and finishes them) for the whole app lifetime.
      ref.watch(downloadsProvider.notifier);
      // yt-dlp breaks when sites change, so keep it current.
      ref.listen(engineProvider.select((e) => e.isReady), (_, ready) {
        if (ready) ref.read(engineProvider.notifier).updateIfDue();
      });
    }

    return WavvyMaterialApp(
      home: const HomeScreen(),
      routes: <String, WidgetBuilder>{
        "/home": (context) => const HomeScreen(),
        "/settings": (context) => SettingsScreen(),
      },
    );
  }
}
