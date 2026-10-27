import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

class ThemeSelector extends ConsumerWidget {
  const ThemeSelector({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final selected = ref.watch(
      settingsProvider.select((s) => s.currentThemeIndex),
    );
    const items = [
      (5, 'Aqua', WvAppearance.aqua),
      (6, 'Graphite', WvAppearance.graphite),
      (2, 'System', WvAppearance.materialYou),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GroupHeader('Color theme'),
        Row(
          children: [
            for (final item in items) ...[
              if (item.$1 != 5) const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  selected: selected == item.$1,
                  button: true,
                  label: item.$2,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => ref
                        .read(settingsProvider.notifier)
                        .updateThemeIndex(item.$1),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: a.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: selected == item.$1 ? a.accent : a.separator,
                          width: selected == item.$1 ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            height: 54,
                            decoration: BoxDecoration(
                              color: a.surfaceHigh,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: a.separator),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 16,
                                  decoration: BoxDecoration(
                                    color: a.shellBottom,
                                    borderRadius: const BorderRadius.horizontal(
                                      left: Radius.circular(5),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(7),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Container(
                                          height: 7,
                                          color: WvPalette(
                                            dark: a.dark,
                                            appearance: item.$3,
                                          ).accent,
                                        ),
                                        const SizedBox(height: 5),
                                        Container(
                                          height: 5,
                                          color: a.separator,
                                        ),
                                        const SizedBox(height: 5),
                                        Container(
                                          height: 5,
                                          color: a.separator,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            item.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: a.text,
                              fontSize: 13,
                              fontWeight: selected == item.$1
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
