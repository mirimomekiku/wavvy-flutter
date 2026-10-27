import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Loads Roboto from the Flutter SDK so text is measured with real glyph
/// widths (the default test font is a fixed-width square). Returns false when
/// the SDK fonts can't be located, in which case the tests are skipped.
Future<bool> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return false;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  final files = [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ].map((f) => File('$dir/$f')).toList();
  if (!files.every((f) => f.existsSync())) return false;

  final loader = FontLoader('Roboto');
  for (final f in files) {
    loader.addFont(f.readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
  return true;
}

Widget _app(Widget child) {
  final theme = WavvyTheme.dark(WvAppearance.green);
  return MaterialApp(
    theme: theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
    ),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: child,
      ),
    ),
  );
}

void main() {
  late bool haveFont;
  setUpAll(() async => haveFont = await _loadRoboto());

  // The Library section toggle should be fully visible on common phone widths
  // without having to scroll the chip row.
  for (final width in [411.0, 393.0, 360.0]) {
    testWidgets('all four Library chips fit at ${width}dp', (tester) async {
      if (!haveFont) {
        markTestSkipped('Flutter SDK fonts not found');
        return;
      }
      tester.view.physicalSize = Size(width * 3, 740 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          WvChips(
            labels: const ['Songs', 'Albums', 'Artists', 'Playlists'],
            selected: 0,
            onChanged: (_) {},
            uppercase: true,
            indicator: true,
          ),
        ),
      );
      await tester.pump();

      // Inside the 16dp page padding of the row (plus the pill's own padding).
      final right = tester.getTopRight(find.text('PLAYLISTS')).dx;
      expect(right, lessThanOrEqualTo(width - 16 - 13));
    });
  }
}
