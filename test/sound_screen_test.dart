import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show AndroidEqualizerBand;
import 'package:wavvy/providers/audio_effects_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/screens/audio_effects/effects.screen.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

class _Band extends Fake implements AndroidEqualizerBand {
  _Band(this.centerFrequency);
  double _gain = 0;
  @override
  final double centerFrequency;
  @override
  double get gain => _gain;
  @override
  Stream<double> get gainStream => Stream.value(_gain);
  @override
  Future<void> setGain(double gain) async => _gain = gain;
}

class _Eq extends EqualizerNotifier {
  _Eq(this.initial);
  final EqualizerState initial;
  final gains = <int, double>{};
  @override
  EqualizerState build() => initial;
  @override
  Future<void> setBandGain(int bandIndex, double gainDb) async =>
      gains[bandIndex] = gainDb;
}

class _Fx extends EffectsNotifier {
  _Fx(this.initial);
  final EffectsState initial;
  @override
  EffectsState build() => initial;
}

class _Player extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}

Widget _app({
  required EqualizerState eq,
  EffectsState fx = const EffectsState(),
  _Eq? eqNotifier,
  double topInset = 0,
  double scale = 1,
  bool dark = false,
}) => ProviderScope(
  overrides: [
    equalizerProvider.overrideWith(() => eqNotifier ?? _Eq(eq)),
    effectsProvider.overrideWith(() => _Fx(fx)),
    playerProvider.overrideWith(_Player.new),
  ],
  child: MaterialApp(
    theme: WavvyTheme.light(WvAppearance.aqua),
    darkTheme: WavvyTheme.dark(WvAppearance.aqua),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        padding: EdgeInsets.only(top: topInset),
      ),
      child: child!,
    ),
    home: const AudioEffectsScreen(),
  ),
);

EqualizerState _withBands() => EqualizerState(
  isEnabled: true,
  bands: [
    for (final f in [60.0, 230.0, 910.0, 3600.0, 14000.0]) _Band(f),
  ],
  minDecibels: -15,
  maxDecibels: 15,
  currentPreset: 'Flat',
);

void _size(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the toolbar sits below the status bar and paints behind it', (
    tester,
  ) async {
    _size(tester, 360, 740);
    await tester.pumpWidget(_app(eq: _withBands(), topInset: 40));
    await tester.pump();
    // Title is pushed below the 40px status bar...
    expect(tester.getTopLeft(find.text('Sound')).dy, greaterThanOrEqualTo(40));
    // ...while the toolbar itself starts at the very top of the screen.
    final toolbar = find.ancestor(
      of: find.text('Sound'),
      matching: find.byType(Container),
    );
    expect(tester.getTopLeft(toolbar.last).dy, 0);
  });

  testWidgets('equalizer shows a slider and a readout per band', (
    tester,
  ) async {
    _size(tester, 360, 900);
    await tester.pumpWidget(_app(eq: _withBands()));
    await tester.pump();
    expect(find.byType(AquaVerticalSlider), findsNWidgets(5));
    expect(find.text('60 Hz'), findsOneWidget);
    expect(find.text('14k Hz'), findsOneWidget);
    expect(find.text('Preset'), findsOneWidget);
    expect(find.text('Flat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging a band sets its gain', (tester) async {
    _size(tester, 360, 900);
    final eq = _Eq(_withBands());
    await tester.pumpWidget(_app(eq: _withBands(), eqNotifier: eq));
    await tester.pump();
    final slider = find.byType(AquaVerticalSlider).first;
    final top = tester.getTopLeft(slider);
    // Tapping near the top of the groove asks for a high gain.
    await tester.tapAt(top + const Offset(18, 14));
    await tester.pump();
    expect(eq.gains[0], greaterThan(10));
  });

  testWidgets('a disabled equalizer cannot be dragged', (tester) async {
    _size(tester, 360, 900);
    final eq = _Eq(_withBands().copyWith(isEnabled: false));
    await tester.pumpWidget(_app(eq: _withBands(), eqNotifier: eq));
    await tester.pump();
    await tester.tapAt(
      tester.getTopLeft(find.byType(AquaVerticalSlider).first) +
          const Offset(18, 14),
    );
    await tester.pump();
    expect(eq.gains, isEmpty);
  });

  testWidgets('without bands the equalizer explains why', (tester) async {
    _size(tester, 360, 740);
    await tester.pumpWidget(
      _app(eq: const EqualizerState(error: 'This device has no equalizer.')),
    );
    await tester.pump();
    expect(find.text('Equalizer not available'), findsOneWidget);
    expect(find.text('This device has no equalizer.'), findsOneWidget);
    expect(find.byType(AquaVerticalSlider), findsNothing);
  });

  testWidgets('effects: sliders, reverb pop-up and volume boost', (
    tester,
  ) async {
    _size(tester, 360, 900);
    await tester.pumpWidget(_app(eq: _withBands()));
    await tester.tap(find.text('Effects'));
    await tester.pumpAndSettle();
    expect(find.byType(AquaSlider), findsNWidgets(2));
    expect(find.text('Bass boost'), findsOneWidget);
    expect(find.text('Virtualizer'), findsOneWidget);
    expect(find.text('Room'), findsOneWidget);
    expect(find.text('Volume boost'), findsOneWidget);
    expect(find.byType(AquaSwitch), findsOneWidget);
  });

  testWidgets('unsupported effects are marked and disabled', (tester) async {
    _size(tester, 360, 900);
    await tester.pumpWidget(
      _app(
        eq: _withBands(),
        fx: const EffectsState(support: EffectSupport.none),
      ),
    );
    await tester.tap(find.text('Effects'));
    await tester.pumpAndSettle();
    expect(find.text('N/A'), findsNWidgets(2));
    expect(find.text('Not supported on this device'), findsOneWidget);
    final sliders = tester.widgetList<AquaSlider>(find.byType(AquaSlider));
    expect(sliders.every((s) => s.onChanged == null), isTrue);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('both tabs fit 320 wide (scale $scale, dark: $dark)', (
        tester,
      ) async {
        _size(tester, 320, 640);
        await tester.pumpWidget(
          _app(eq: _withBands(), dark: dark, scale: scale, topInset: 24),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Effects'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
