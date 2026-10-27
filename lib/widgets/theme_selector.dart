import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// The color themes, in the order they are shown: Kaisu's Aqua, its accent
/// colors, then Graphite.
const _items = [
  (5, 'Aqua'),
  (7, 'Orange'),
  (8, 'Green'),
  (9, 'Purple'),
  (10, 'Pink'),
  (11, 'Red'),
  (12, 'Teal'),
  (6, 'Graphite'),
];

/// A grid of color themes, each a small window in its own accent.
class ThemeSelector extends ConsumerWidget {
  const ThemeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final selected = ref.watch(
      settingsProvider.select((s) => s.currentThemeIndex),
    );

    Widget tile((int, String) item) {
      final isSelected = selected == item.$1;
      // Each card previews its own accent in the current light/dark mode.
      final palette = WvPalette(
        dark: a.dark,
        appearance: WavvyTheme.appearanceFor(item.$1),
      );
      return Semantics(
        selected: isSelected,
        button: true,
        label: item.$2,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () =>
              ref.read(settingsProvider.notifier).updateThemeIndex(item.$1),
          child: Container(
            padding: const EdgeInsets.fromLTRB(7, 7, 7, 8),
            decoration: BoxDecoration(
              color: a.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? a.accent : a.separator,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: a.surfaceHigh,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: a.separator),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 11,
                        decoration: BoxDecoration(
                          color: a.shellBottom,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(3),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  gradient: palette.gelGradient(primary: true),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(height: 4, color: a.separator),
                              const SizedBox(height: 4),
                              Container(height: 4, color: a.separator),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  item.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: a.text,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GroupHeader('Color theme'),
        for (var row = 0; row < _items.length; row += 4) ...[
          if (row > 0) const SizedBox(height: 10),
          Row(
            children: [
              for (var i = row; i < row + 4; i++) ...[
                if (i > row) const SizedBox(width: 10),
                Expanded(child: tile(_items[i])),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
