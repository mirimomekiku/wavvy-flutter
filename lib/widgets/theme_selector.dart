import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Aqua "Appearance" control: Blue or Graphite, like System Preferences.
class ThemeSelector extends ConsumerWidget {
  const ThemeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeIndex = ref.watch(
      settingsProvider.select((s) => s.currentThemeIndex),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GroupHeader("Appearance"),
        AquaSegmented(
          labels: const ["Blue", "Graphite"],
          selected: themeIndex.clamp(0, 1),
          onChanged: ref.read(settingsProvider.notifier).updateThemeIndex,
        ),
      ],
    );
  }
}
