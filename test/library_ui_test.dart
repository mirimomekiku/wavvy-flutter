import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/screens/library/library_tab.dart';
import 'package:wavvy/theme/color_utils.dart';
import 'package:wavvy/widgets/wv_song_list.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

class _FakeLibrary extends LibraryNotifier {
  final LibraryState initial;
  _FakeLibrary(this.initial);

  @override
  LibraryState build() => initial;
}

Widget _app(LibraryState library) {
  return ProviderScope(
    overrides: [libraryProvider.overrideWith(() => _FakeLibrary(library))],
    child: MaterialApp(
      theme: WavvyTheme.light(WvAppearance.green),
      home: const Scaffold(body: LibraryTab()),
    ),
  );
}

void main() {
  group('LibraryTab songs empty state', () {
    testWidgets('offers Refresh when the library is simply empty', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const LibraryState()));
      await tester.pump();

      expect(find.text('No Songs'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
      expect(find.byType(WvMascotBox), findsOneWidget); // mascot
    });

    testWidgets('explains denied access and offers Open Settings + Retry', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const LibraryState(permissionDenied: true)));
      await tester.pump();

      expect(find.text('Storage Access Needed'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No Songs'), findsNothing);
    });
  });

  group('ColorShadeX', () {
    test('darken lowers lightness and never goes below black', () {
      const grey = Color(0xFF808080);
      expect(
        HSLColor.fromColor(grey.darken(20)).lightness,
        closeTo(HSLColor.fromColor(grey).lightness - 0.2, 0.01),
      );
      expect(const Color(0xFF000000).darken(40), const Color(0xFF000000));
    });

    test('brighten adds white per channel and clamps at 255', () {
      expect(const Color(0xFF000000).brighten(10), const Color(0xFF1A1A1A));
      expect(const Color(0xFFF0F0F0).brighten(30), const Color(0xFFFFFFFF));
    });

    test('alpha is preserved', () {
      final c = const Color(0x80102030).brighten(10);
      expect((c.a * 255).round(), 0x80);
    });
  });
}
