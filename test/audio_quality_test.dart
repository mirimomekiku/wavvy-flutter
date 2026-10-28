import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/audio_quality.dart';
import 'package:wavvy/player_sheets/full_player_sheet.dart';
import 'package:wavvy/player_sheets/player_dialogs.dart';
import 'package:wavvy/providers/artist_info_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/aqua_quality_badge.dart';
import 'package:wavvy/core/app_context.dart';

SongModel _song({
  int id = 1,
  String ext = 'mp3',
  int size = 8 * 1024 * 1024,
  int duration = 200000,
  String? uri = 'content://media/1',
  int? track,
}) => SongModel({
  '_id': id,
  '_data': '/music/s$id.$ext',
  '_uri': uri,
  '_display_name': 's$id.$ext',
  '_display_name_wo_ext': 's$id',
  '_size': size,
  'file_extension': ext,
  'title': 'Song $id',
  'artist': 'Artist',
  'album': 'Album',
  'duration': duration,
  'track': track,
  'is_music': true,
});

class _FakeInfo implements AudioInfoChannel {
  _FakeInfo({this.result, this.error});
  AudioQuality? result;
  Object? error;
  final calls = <(String?, int?)>[];
  @override
  Future<AudioQuality?> probe({String? uri, int? id}) async {
    calls.add((uri, id));
    if (error != null) throw error!;
    return result;
  }
}

const _flac96 = AudioQuality(
  codec: 'FLAC',
  sampleRate: 96000,
  bitDepth: 24,
  channels: 2,
  lossless: true,
);

class _FakePlayer extends PlayerNotifier {
  _FakePlayer(this.song);
  final SongModel song;
  @override
  PlayerState build() =>
      PlayerState(queue: [song], currentSong: song, currentIndex: 0);
}

class _Position extends PositionNotifier {
  @override
  Duration build() => const Duration(seconds: 42);
}

class _Duration extends DurationNotifier {
  @override
  Duration build() => const Duration(minutes: 3, seconds: 20);
}

class _Settings extends SettingsNotifier {
  @override
  SettingsState build() => const SettingsState();
}

class _Lyrics extends LyricsNotifier {
  @override
  LyricsState build() => const LyricsState();
}

class _Artist extends ArtistInfoNotifier {
  @override
  ArtistInfoState build() => const ArtistInfoState();
}

class _Library extends LibraryNotifier {
  @override
  LibraryState build() => const LibraryState();
}

class _Playlists extends PlaylistsNotifier {
  @override
  PlaylistsState build() => PlaylistsState();
}

Widget _host(
  Widget child, {
  required AudioInfoChannel info,
  bool dark = false,
  double scale = 1,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [audioInfoChannelProvider.overrideWithValue(info), ...overrides],
  child: MaterialApp(
    navigatorKey: navigatorKey,
    theme: WavvyTheme.light(WvAppearance.aqua),
    darkTheme: WavvyTheme.dark(WvAppearance.aqua),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  group('classifier and formatter', () {
    // codec, rate, depth, kbps, lossless -> tier, label, short
    final table =
        <
          ({
            String name,
            AudioQuality q,
            QualityTier tier,
            String label,
            String short,
          })
        >[
          (
            name: 'mp3 320',
            q: const AudioQuality(codec: 'MP3', bitrate: 320000),
            tier: QualityTier.lossy,
            label: 'MP3 320 kbps',
            short: 'MP3 320k',
          ),
          (
            name: 'aac 256 rounds',
            q: const AudioQuality(codec: 'AAC', bitrate: 255700),
            tier: QualityTier.lossy,
            label: 'AAC 256 kbps',
            short: 'AAC 256k',
          ),
          (
            name: 'opus 44.1 ignores depth',
            q: const AudioQuality(
              codec: 'Opus',
              bitrate: 128000,
              sampleRate: 48000,
              bitDepth: 24,
            ),
            tier: QualityTier.lossy,
            label: 'Opus 128 kbps',
            short: 'Opus 128k',
          ),
          (
            name: 'flac 16/44.1',
            q: const AudioQuality(
              codec: 'FLAC',
              sampleRate: 44100,
              bitDepth: 16,
            ),
            tier: QualityTier.lossless,
            label: 'FLAC 16-bit / 44.1 kHz',
            short: 'FLAC 16/44.1',
          ),
          (
            name: 'flac 24/96',
            q: _flac96,
            tier: QualityTier.hiRes,
            label: 'FLAC 24-bit / 96 kHz',
            short: 'FLAC 24/96',
          ),
          (
            name: 'flac 24/48 is lossless',
            q: const AudioQuality(
              codec: 'FLAC',
              sampleRate: 48000,
              bitDepth: 24,
            ),
            tier: QualityTier.lossless,
            label: 'FLAC 24-bit / 48 kHz',
            short: 'FLAC 24/48',
          ),
          (
            name: 'flac 16/96 is lossless',
            q: const AudioQuality(
              codec: 'FLAC',
              sampleRate: 96000,
              bitDepth: 16,
            ),
            tier: QualityTier.lossless,
            label: 'FLAC 16-bit / 96 kHz',
            short: 'FLAC 16/96',
          ),
          (
            name: 'flac 96 kHz with unknown depth is not hi-res',
            q: const AudioQuality(codec: 'FLAC', sampleRate: 96000),
            tier: QualityTier.lossless,
            label: 'FLAC 96 kHz',
            short: 'FLAC 96k',
          ),
          (
            name: 'alac 24/88.2',
            q: const AudioQuality(
              codec: 'ALAC',
              sampleRate: 88200,
              bitDepth: 24,
              lossless: true,
            ),
            tier: QualityTier.hiRes,
            label: 'ALAC 24-bit / 88.2 kHz',
            short: 'ALAC 24/88.2',
          ),
          (
            name: 'wav 16/44.1 by codec name',
            q: const AudioQuality(
              codec: 'WAV',
              sampleRate: 44100,
              bitDepth: 16,
            ),
            tier: QualityTier.lossless,
            label: 'WAV 16-bit / 44.1 kHz',
            short: 'WAV 16/44.1',
          ),
          (
            name: 'lossless with only a bitrate',
            q: const AudioQuality(codec: 'FLAC', bitrate: 912000),
            tier: QualityTier.lossless,
            label: 'FLAC 912 kbps',
            short: 'FLAC 912k',
          ),
          (
            name: 'lossless with nothing else',
            q: const AudioQuality(codec: 'FLAC'),
            tier: QualityTier.lossless,
            label: 'FLAC',
            short: 'FLAC',
          ),
          (
            name: 'lossy codec only',
            q: const AudioQuality(codec: 'MP3'),
            tier: QualityTier.lossy,
            label: 'MP3',
            short: 'MP3',
          ),
          (
            name: 'native says lossless for an unknown codec',
            q: const AudioQuality(codec: 'DSD', lossless: true),
            tier: QualityTier.lossless,
            label: 'DSD',
            short: 'DSD',
          ),
          (
            name: 'native says lossy even for a lossless-sounding name',
            q: const AudioQuality(codec: 'FLAC', lossless: false),
            tier: QualityTier.lossy,
            label: 'FLAC',
            short: 'FLAC',
          ),
        ];
    for (final row in table) {
      test(row.name, () {
        expect(row.q.tier, row.tier);
        expect(row.q.label, row.label);
        expect(row.q.shortLabel, row.short);
      });
    }

    test('empty quality has no data and an empty label', () {
      const q = AudioQuality();
      expect(q.hasData, isFalse);
      expect(q.label, '');
      expect(q.semanticsLabel, '');
      expect(q.tier, QualityTier.lossy);
    });

    test('tier names and semantics', () {
      expect(_flac96.tierName, 'Hi-Res Lossless');
      expect(
        _flac96.semanticsLabel,
        'Hi-Res Lossless, FLAC, 24-bit, 96 kilohertz',
      );
      expect(
        const AudioQuality(
          codec: 'FLAC',
          sampleRate: 44100,
          bitDepth: 16,
        ).semanticsLabel,
        'Lossless, FLAC, 16-bit, 44.1 kilohertz',
      );
      expect(
        const AudioQuality(codec: 'MP3', bitrate: 320000).semanticsLabel,
        'Lossy, MP3, 320 kilobits per second',
      );
    });

    test('kHz and channels text', () {
      expect(formatKhz(44100), '44.1');
      expect(formatKhz(48000), '48');
      expect(formatKhz(192000), '192');
      expect(formatKhz(22050), '22.1');
      expect(channelsLabel(1), 'Mono');
      expect(channelsLabel(2), 'Stereo');
      expect(channelsLabel(6), '6 channels');
    });

    test('codec names from MIME types and extensions', () {
      expect(codecFromMime('audio/mpeg'), 'MP3');
      expect(codecFromMime('audio/mp4a-latm'), 'AAC');
      expect(codecFromMime('audio/flac'), 'FLAC');
      expect(codecFromMime('audio/opus'), 'Opus');
      expect(codecFromMime('audio/raw'), 'WAV');
      expect(codecFromMime('audio/x-ape'), 'APE');
      expect(codecFromMime(null), isNull);
      expect(codecFromMime(' '), isNull);
      expect(codecFromExtension('.MP3'), 'MP3');
      expect(codecFromExtension('m4a'), 'M4A');
      expect(codecFromExtension('ogg'), 'Vorbis');
      expect(codecFromExtension(''), isNull);
    });
  });

  group('fromMap', () {
    test('reads a native answer', () {
      final q = AudioQuality.fromMap({
        'mime': 'audio/flac',
        'codec': 'FLAC',
        'sampleRate': 96000,
        'channels': 2,
        'bitrate': 2300000,
        'bitDepth': 24,
        'durationMs': 200000,
        'lossless': true,
      })!;
      expect(q.codec, 'FLAC');
      expect(q.sampleRate, 96000);
      expect(q.bitDepth, 24);
      expect(q.bitrate, 2300000);
      expect(q.channels, 2);
      expect(q.lossless, isTrue);
      expect(q.estimated, isFalse);
      expect(q.tier, QualityTier.hiRes);
    });

    test('nulls, zeros, odd depths and wrong types are unknown', () {
      final q = AudioQuality.fromMap({
        'mime': 'audio/mpeg',
        'sampleRate': 0,
        'channels': null,
        'bitrate': '320',
        'bitDepth': 99,
        'lossless': 'yes',
      })!;
      expect(q.codec, 'MP3');
      expect(q.sampleRate, isNull);
      expect(q.channels, isNull);
      expect(q.bitrate, isNull);
      expect(q.bitDepth, isNull);
      expect(q.lossless, isNull);
    });

    test('not a map, an empty map or no details give null', () {
      expect(AudioQuality.fromMap(null), isNull);
      expect(AudioQuality.fromMap('x'), isNull);
      expect(AudioQuality.fromMap(<String, Object?>{}), isNull);
    });
  });

  group('fallback from MediaStore', () {
    test('extension and average bitrate', () {
      final q = AudioQuality.fromSong(
        _song(size: 8 * 1024 * 1024, duration: 200000),
      );
      expect(q.estimated, isTrue);
      expect(q.codec, 'MP3');
      // 8 MiB * 8 bits / 200 s
      expect(q.bitrate, 335544);
      expect(q.label, 'MP3 336 kbps');
      expect(q.tier, QualityTier.lossy);
    });

    test('flac is lossless but never hi-res without the probe', () {
      final q = AudioQuality.fromSong(_song(ext: 'flac'));
      expect(q.tier, QualityTier.lossless);
      expect(q.bitDepth, isNull);
    });

    test('no size, duration or extension still works', () {
      expect(
        AudioQuality.fromSong(_song(ext: '', size: 0, duration: 0)).hasData,
        isFalse,
      );
      final q = AudioQuality.estimate(extension: 'opus');
      expect(q.label, 'Opus');
      expect(q.bitrate, isNull);
    });

    test('a raw row without fields does not throw', () {
      final q = AudioQuality.fromSong(SongModel({'_id': 1}));
      expect(q.estimated, isTrue);
    });

    test('fillFrom keeps probed values and fills the bitrate', () {
      final merged = _flac96.fillFrom(
        const AudioQuality(bitrate: 1000000, estimated: true),
      );
      expect(merged.sampleRate, 96000);
      expect(merged.bitrate, 1000000);
      expect(merged.estimated, isFalse);
    });
  });

  group('provider', () {
    QualityKey key([SongModel? s]) => QualityKey.fromSong(s ?? _song());

    test('uses the native details and passes uri and id', () async {
      final info = _FakeInfo(result: _flac96);
      final c = ProviderContainer(
        overrides: [audioInfoChannelProvider.overrideWithValue(info)],
      );
      addTearDown(c.dispose);
      final q = await c.read(audioQualityProvider(key()).future);
      expect(q.codec, 'FLAC');
      expect(q.tier, QualityTier.hiRes);
      // The estimate fills the bitrate the probe did not give.
      expect(q.bitrate, isNotNull);
      expect(info.calls.single, ('content://media/1', 1));
    });

    test('null from the probe falls back to the estimate', () async {
      final info = _FakeInfo();
      final c = ProviderContainer(
        overrides: [audioInfoChannelProvider.overrideWithValue(info)],
      );
      addTearDown(c.dispose);
      final q = await c.read(audioQualityProvider(key()).future);
      expect(q.estimated, isTrue);
      expect(q.codec, 'MP3');
    });

    test('an error falls back to the estimate', () async {
      final info = _FakeInfo(error: StateError('boom'));
      final c = ProviderContainer(
        overrides: [audioInfoChannelProvider.overrideWithValue(info)],
      );
      addTearDown(c.dispose);
      final q = await c.read(audioQualityProvider(key()).future);
      expect(q.estimated, isTrue);
      expect(q.label, 'MP3 336 kbps');
    });

    test('is probed once per song', () async {
      final info = _FakeInfo(result: _flac96);
      final c = ProviderContainer(
        overrides: [audioInfoChannelProvider.overrideWithValue(info)],
      );
      addTearDown(c.dispose);
      await c.read(audioQualityProvider(key()).future);
      await c.read(audioQualityProvider(key(_song())).future);
      expect(info.calls, hasLength(1));
      await c.read(audioQualityProvider(key(_song(id: 2, uri: 'x'))).future);
      expect(info.calls, hasLength(2));
    });

    test('an external song is probed by its content uri', () async {
      final info = _FakeInfo(result: _flac96);
      final c = ProviderContainer(
        overrides: [audioInfoChannelProvider.overrideWithValue(info)],
      );
      addTearDown(c.dispose);
      await c.read(
        audioQualityProvider(
          key(_song(id: -77, uri: 'content://docs/audio/9')),
        ).future,
      );
      // The channel drops a negative id; the uri is what counts.
      expect(info.calls.single.$1, 'content://docs/audio/9');
    });
  });

  group('badge', () {
    Future<void> show(
      WidgetTester tester,
      AudioQuality q, {
      bool dark = false,
      double scale = 1,
      bool compact = false,
      double width = 400,
    }) async {
      tester.view.physicalSize = Size(width * 2, 800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          AquaQualityBadge(quality: q, compact: compact),
          info: _FakeInfo(),
          dark: dark,
          scale: scale,
        ),
      );
    }

    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.5]) {
        for (final q in [
          const AudioQuality(codec: 'MP3', bitrate: 320000),
          const AudioQuality(codec: 'FLAC', sampleRate: 44100, bitDepth: 16),
          _flac96,
        ]) {
          testWidgets(
            '${q.tierName} dark=$dark x$scale shows text without overflow',
            (tester) async {
              await show(tester, q, dark: dark, scale: scale);
              expect(find.text(q.label), findsOneWidget);
              expect(tester.takeException(), isNull);
              expect(find.bySemanticsLabel(q.semanticsLabel), findsOneWidget);
            },
          );
        }
      }
    }

    testWidgets('semantics reads the tier, codec, depth and rate', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await show(tester, _flac96);
      expect(
        find.bySemanticsLabel('Hi-Res Lossless, FLAC, 24-bit, 96 kilohertz'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('compact text fits a narrow slot at 1.5x', (tester) async {
      await show(tester, _flac96, compact: true, scale: 1.5);
      expect(find.text('FLAC 24/96'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Even the long text in 60 px scales down instead of overflowing.
      tester.view.physicalSize = const Size(640, 800);
      await tester.pumpWidget(
        _host(
          SizedBox(width: 60, child: AquaQualityBadge(quality: _flac96)),
          info: _FakeInfo(),
          scale: 1.5,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('tiers differ in look', (tester) async {
      BoxDecoration decoration(WidgetTester t) =>
          t
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byType(AquaQualityBadge),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      final gradients = <Gradient?>[];
      for (final q in [
        const AudioQuality(codec: 'MP3', bitrate: 320000),
        const AudioQuality(codec: 'FLAC', sampleRate: 44100, bitDepth: 16),
        _flac96,
      ]) {
        await show(tester, q);
        gradients.add(decoration(tester).gradient);
      }
      expect(gradients.toSet(), hasLength(3));
      // Hi-Res carries a star.
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    });

    testWidgets('an empty quality shows nothing', (tester) async {
      await show(tester, const AudioQuality());
      expect(find.byType(Text), findsNothing);
    });
  });

  group('screens', () {
    testWidgets('song details lists the probed quality', (tester) async {
      tester.view.physicalSize = const Size(640, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final info = _FakeInfo(result: _flac96);
      await tester.pumpWidget(
        _host(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () =>
                  showSongDetailsDialog(_song(ext: 'flac', track: 2003)),
              child: const Text('open'),
            ),
          ),
          info: info,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final label in [
        'Quality',
        'Codec',
        'Sample rate',
        'Bit depth',
        'Channels',
        'Track',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Hi-Res Lossless'), findsOneWidget);
      expect(find.text('96 kHz'), findsOneWidget);
      expect(find.text('24-bit'), findsOneWidget);
      expect(find.text('Stereo'), findsOneWidget);
      expect(find.text('Disc 2 - Track 3'), findsOneWidget);
      expect(find.byType(AquaQualityBadge), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('song details without a probe say Unknown', (tester) async {
      tester.view.physicalSize = const Size(640, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          TextButton(
            onPressed: () => showSongDetailsDialog(_song()),
            child: const Text('open'),
          ),
          info: _FakeInfo(),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Sample rate'), findsOneWidget);
      expect(find.text('Unknown'), findsNWidgets(2));
      expect(find.text('Lossy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final scale in [1.0, 1.5]) {
      testWidgets('the player seek row shows the quality at 320 wide x$scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(640, 1280);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final song = _song(ext: 'flac', size: 40 * 1024 * 1024);
        await tester.pumpWidget(
          _host(
            const FullPlayerSheet(),
            info: _FakeInfo(result: _flac96),
            scale: scale,
            overrides: [
              playerProvider.overrideWith(() => _FakePlayer(song)),
              positionProvider.overrideWith(_Position.new),
              durationProvider.overrideWith(_Duration.new),
              settingsProvider.overrideWith(_Settings.new),
              lyricsProvider.overrideWith(_Lyrics.new),
              artistInfoProvider.overrideWith(_Artist.new),
              libraryProvider.overrideWith(_Library.new),
              playlistsProvider.overrideWith(_Playlists.new),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(AquaQualityBadge), findsOneWidget);
        expect(find.text('FLAC 24/96'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
