import 'dart:isolate';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/instances/audio_handler.instance.dart';
import 'package:wavvy/providers/audio_coordinator.dart';
import 'package:wavvy/providers/audio_effects_provider.dart';
import 'package:wavvy/providers/downloads_provider.dart';
import 'package:wavvy/providers/palette_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/downloader/downloader.screen.dart';
import 'package:wavvy/screens/home/home.screen.dart';
import 'package:wavvy/screens/library/albums/albums.screen.dart';
import 'package:wavvy/screens/library/artists/artists.screen.dart';
import 'package:wavvy/screens/library/playlists/playlists.screen.dart';
import 'package:wavvy/screens/search/search.screen.dart';
import 'package:wavvy/screens/settings/settings.screen.dart';
import 'package:wavvy/theme/wavvy_theme.dart';

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
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text("Wavvy failed to start:\n$e"),
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
      home: const HomeScreen(),
      routes: <String, WidgetBuilder>{
        "/home": (context) => const HomeScreen(),
        "/search": (context) => SearchScreen(),
        "/albums": (context) => AllAlbumsScreen(),
        "/artists": (context) => AllArtistsScreen(),
        "/playlists": (context) => AllLocalPlaylistsScreen(),
        "/downloader": (context) => DownloaderHubScreen(),
        "/settings": (context) => SettingsScreen(),
      },
    );
  }
}
