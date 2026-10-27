import 'dart:isolate';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:wavvy/instances/audio_handler.instance.dart';
import 'package:wavvy/providers/audio_coordinator.dart';
import 'package:wavvy/providers/audio_effects_provider.dart';
import 'package:wavvy/providers/downloads_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/home/home.screen.dart';
import 'package:wavvy/screens/settings/settings.screen.dart';
import 'package:wavvy/wavvy_app.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName(
    'downloader_send_port',
  );

  if (send != null) {
    send.send([id, status, progress]);
  } else {
    debugPrint("DownloadCallback: SendPort not found");
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Work Sans',
    ], await rootBundle.loadString('assets/fonts/OFL-WorkSans.txt'));
  });
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("No .env loaded: $e");
  }

  await FlutterDownloader.initialize(debug: kDebugMode);
  await FlutterDownloader.registerCallback(downloadCallback);
  await MetadataGod.initialize();

  final WavvyAudioHandler handler;
  final AndroidEqualizer equalizer = AndroidEqualizer();
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    handler = await AudioService.init(
      builder: () => WavvyAudioHandler(equalizer: equalizer),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.mirimomekiku.wavvy.channel.audio',
        androidNotificationChannelName: 'Wavvy',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (e) {
    debugPrint("INIT ERROR: $e");
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: WavvyTheme.light(WvAppearance.aqua),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.headphones_outlined, size: 44),
                  const SizedBox(height: 20),
                  Text(
                    'Playback could not start',
                    style: WavvyTheme.light(
                      WvAppearance.aqua,
                    ).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Close and reopen Wavvy to try again.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }

  final container = ProviderContainer(
    overrides: [
      audioHandlerProvider.overrideWithValue(handler),
      equalizerInstanceProvider.overrideWithValue(equalizer),
      nativeEffectsChannelProvider.overrideWithValue(NativeEffectsChannel()),
    ],
  );

  await container.read(settingsProvider.notifier).load();

  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep app-lifetime providers alive without rebuilding on every event.
    ref.watch(audioCoordinatorProvider);
    ref.watch(downloadEventsProvider.notifier);
    ref.watch(ytdlpProvider.notifier);
    ref.watch(tiktokProvider.notifier);

    return WavvyMaterialApp(
      home: const HomeScreen(),
      routes: <String, WidgetBuilder>{
        "/home": (context) => const HomeScreen(),
        "/settings": (context) => SettingsScreen(),
      },
    );
  }
}
