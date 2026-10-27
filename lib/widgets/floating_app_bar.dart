import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Aqua unified toolbar: brushed-metal gradient, centered embossed title,
/// gel buttons on the sides and an inset search field underneath.
/// Public API is unchanged.
class FloatingAppBar extends ConsumerWidget {
  final String title;
  final bool showSearch;
  final bool showThemeToggle;
  final Widget? leading;
  final List<Widget>? actions;
  final VoidCallback? onSearchTap;

  const FloatingAppBar({
    super.key,
    this.title = "Wavvy",
    this.showSearch = true,
    this.showThemeToggle = false,
    this.leading,
    this.actions,
    this.onSearchTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Aqua.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final trailing = <Widget>[
      ...?actions,
      if (showThemeToggle)
        GelButton(
          circular: true,
          tooltip: "Toggle theme",
          onPressed: () =>
              ref.read(settingsProvider.notifier).toggleDarkMode(!isDark),
          child: Icon(
            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          ),
        ),
    ];

    return AquaBar(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 56),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: a.text,
                          // Embossed title.
                          shadows: [
                            Shadow(
                              color: a.dark
                                  ? Colors.black.withValues(alpha: 0.8)
                                  : Colors.white.withValues(alpha: 0.85),
                              offset: Offset(0, a.dark ? -1 : 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (leading != null)
                      Align(alignment: Alignment.centerLeft, child: leading!),
                    if (trailing.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: trailing,
                        ),
                      ),
                  ],
                ),
              ),
              if (showSearch)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: AquaSearchField(
                    hint: "Search songs, artists",
                    onTap: onSearchTap ?? () => AppNav.pushNamed("/search"),
                  ),
                ),
              if (showSearch) const SizedBox(height: 2),
            ],
          ),
        ),
      ),
    );
  }
}
