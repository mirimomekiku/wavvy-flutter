import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

Widget _wrap(Widget child, double scale) => MaterialApp(
  theme: WavvyTheme.light(WvAppearance.green),
  builder: (context, c) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: c!,
  ),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  final cases = <String, Widget>{
    'WvSearchField': WvSearchField(onTap: () {}, hint: 'Search songs, artists'),
    'WvChips(4)': WvChips(
      labels: const ['Player', 'Queue', 'Lyrics', 'Artist'],
      selected: 0,
      onChanged: (_) {},
    ),
    'WvChips(2)': WvChips(
      labels: const ['Blue', 'Graphite'],
      selected: 0,
      onChanged: (_) {},
    ),
    'WvSectionHeader': const WvSectionHeader(
      title: 'Recently Played',
      trailing: Text('See All'),
    ),
    'WvPanel': const WvPanel(
      child: Text('A fairly long song title that wraps'),
    ),
    'WvButton capsule': WvButton(
      width: 92,
      onPressed: () {},
      child: const Text('Cancel'),
    ),
  };

  for (final scale in [1.0, 1.5, 2.0]) {
    for (final e in cases.entries) {
      testWidgets('${e.key} @ $scale', (tester) async {
        tester.view.physicalSize = const Size(360 * 3, 640 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_wrap(e.value, scale));
        await tester.pump();
        final ex = tester.takeException();
        expect(ex, isNull, reason: '${e.key} overflowed at text scale $scale');
      });
    }
  }
}
