import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as audio;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/player_sheets/player_dialogs.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/audio_dialogs.dart';

final _song = SongModel({
  '_id': 1,
  '_data': '/music/a long folder name/Some Song.mp3',
  '_uri': 'content://media/1',
  'title': 'Some Song',
  'artist': 'Some Artist',
  'album': 'Some Album',
  'duration': 215000,
  '_size': 5 * 1024 * 1024,
  '_display_name': 'Some Song.mp3',
  'file_extension': 'mp3',
});

class _Player extends Fake implements audio.AudioPlayer {
  double speedValue = 1;
  double pitchValue = 1;
  final _speed = StreamController<double>.broadcast();
  final _pitch = StreamController<double>.broadcast();
  @override
  double get speed => speedValue;
  @override
  double get pitch => pitchValue;
  @override
  Stream<double> get speedStream => _speed.stream;
  @override
  Stream<double> get pitchStream => _pitch.stream;
  @override
  Future<void> setSpeed(double v) async {
    speedValue = v;
    _speed.add(v);
  }

  @override
  Future<void> setPitch(double v) async {
    pitchValue = v;
    _pitch.add(v);
  }

  @override
  Stream<audio.PlayerState> get playerStateStream => const Stream.empty();
  @override
  Stream<audio.SequenceState> get sequenceStateStream => const Stream.empty();
}

class _SleepPlayer extends PlayerNotifier {
  int? minutes;
  @override
  PlayerState build() => const PlayerState();
  @override
  void setSleepTimer(int? m) => minutes = m;
}

/// A host whose [open] callback runs with a ref, once a button is tapped.
Widget _host(
  void Function(WidgetRef) open, {
  List<Override> overrides = const [],
  double scale = 1,
  bool dark = false,
}) => ProviderScope(
  overrides: overrides,
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
    home: Scaffold(
      body: Consumer(
        builder: (context, ref, _) => Center(
          child: TextButton(
            onPressed: () => open(ref),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ),
);

void _small(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('seek bar', () {
    Widget bar(void Function(double) onChanged, {double value = 0}) =>
        MaterialApp(
          theme: WavvyTheme.light(WvAppearance.aqua),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: AquaSeekBar(
                  value: value,
                  max: 1000,
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        );

    testWidgets('tapping seeks to that point', (tester) async {
      double? seen;
      await tester.pumpWidget(bar((v) => seen = v));
      final rect = tester.getRect(find.byType(AquaSeekBar));
      await tester.tapAt(Offset(rect.center.dx, rect.center.dy));
      expect(seen, closeTo(500, 40));
      await tester.tapAt(Offset(rect.left + 2, rect.center.dy));
      expect(seen, 0);
      await tester.tapAt(Offset(rect.right - 2, rect.center.dy));
      expect(seen, 1000);
    });

    testWidgets('dragging follows the finger and stays in range', (
      tester,
    ) async {
      final seen = <double>[];
      await tester.pumpWidget(bar(seen.add));
      final rect = tester.getRect(find.byType(AquaSeekBar));
      await tester.dragFrom(
        Offset(rect.left + 20, rect.center.dy),
        const Offset(400, 0),
      );
      expect(seen, isNotEmpty);
      expect(seen.every((v) => v >= 0 && v <= 1000), isTrue);
      expect(seen.last, 1000);
    });

    testWidgets('is a slider for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      double? seen;
      await tester.pumpWidget(bar((v) => seen = v, value: 500));
      final node = tester.getSemantics(find.bySemanticsLabel('Seek'));
      expect(node.value, '50%');
      tester.semantics.performAction(
        find.semantics.byLabel('Seek'),
        SemanticsAction.increase,
      );
      expect(seen, 550);
      handle.dispose();
    });
  });

  group('dialog shell', () {
    for (final dark in [false, true]) {
      testWidgets('is a titled window with buttons at 320 wide (dark: $dark)', (
        tester,
      ) async {
        _small(tester);
        await tester.pumpWidget(
          _host(
            (ref) => showAppDialog<void>(
              builder: (c) => WvDialog(
                title: 'A rather long dialog title that must not overflow',
                content: const Text('Body text'),
                actions: [
                  wvDialogButton('Cancel', () {}),
                  wvDialogButton('Delete', () {}, destructive: true),
                  wvDialogButton('Save', () {}, primary: true),
                ],
              ),
            ),
            dark: dark,
            scale: 1.5,
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('Body text'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);
        expect(find.byType(AquaCloseLight), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the close light dismisses it', (tester) async {
      await tester.pumpWidget(
        _host(
          (ref) => showAppDialog<void>(
            builder: (c) => const WvDialog(title: 'Hi', content: Text('x')),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AquaCloseLight));
      await tester.pumpAndSettle();
      expect(find.byType(WvDialog), findsNothing);
    });
  });

  group('speed & pitch', () {
    testWidgets('shows both rates and resets them', (tester) async {
      _small(tester);
      final player = _Player()
        ..speedValue = 1.5
        ..pitchValue = 0.75;
      await tester.pumpWidget(
        _host(
          showSpeedDialog,
          overrides: [audioPlayerProvider.overrideWithValue(player)],
          scale: 1.5,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Speed & Pitch'), findsOneWidget);
      expect(find.byType(AquaSlider), findsNWidgets(2));
      expect(find.text('1.50x'), findsOneWidget);
      expect(find.text('0.75x'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(player.speedValue, 1);
      expect(player.pitchValue, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('sleep timer', () {
    testWidgets('lists durations and sets the chosen one', (tester) async {
      final sleeper = _SleepPlayer();
      await tester.pumpWidget(
        _host(
          openSleepTimerDialog,
          overrides: [playerProvider.overrideWith(() => sleeper)],
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Music plays until you stop it'), findsOneWidget);
      expect(find.text('45 minutes'), findsOneWidget);
      await tester.tap(find.text('45 minutes'));
      await tester.pumpAndSettle();
      expect(sleeper.minutes, 45);
      expect(find.byType(WvDialog), findsNothing);
    });
  });

  group('song details', () {
    testWidgets('is a table of the file details', (tester) async {
      _small(tester);
      await tester.pumpWidget(
        _host((ref) => showSongDetailsDialog(_song), scale: 1.5),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Song Details'), findsOneWidget);
      for (final label in ['Title', 'Artist', 'Album', 'Duration', 'Size']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('3:35'), findsOneWidget);
      expect(find.text('5.00 MB'), findsOneWidget);
      expect(find.textContaining('Some Song.mp3'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('edit tags', () {
    testWidgets('shows aqua fields and returns the edited values', (
      tester,
    ) async {
      _small(tester);
      await tester.pumpWidget(
        _host((ref) => editSongTags(ref, _song), scale: 1.5),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Tags'), findsOneWidget);
      expect(find.byType(AquaField), findsNWidgets(5));
      for (final label in ['Title', 'Artist', 'Album', 'Year', 'Genre']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // The song's own values start in the fields.
      expect(find.widgetWithText(TextField, 'Some Song'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Some Song'),
        'Renamed',
      );
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Renamed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
