import 'package:flutter/material.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// A consistent mobile counterpart to Kaisu's page heading and toolbar.
class WvPageHeading extends StatelessWidget {
  const WvPageHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.actions = const [],
    this.back = false,
    this.settings = false,
  });
  final String title;
  final String? subtitle;
  final String? eyebrow;
  final List<Widget> actions;
  final bool back;
  final bool settings;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    // Screens that already sit inside a SafeArea see a zero top inset here, so
    // this only pads headings that draw behind the status bar (the tab shell).
    return Container(
      padding: EdgeInsets.fromLTRB(
        back ? 8 : 16,
        10 + MediaQuery.paddingOf(context).top,
        10,
        12,
      ),
      decoration: BoxDecoration(
        gradient: a.chromeGradient,
        border: Border(
          bottom: BorderSide(color: a.outline.withValues(alpha: 0.55)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (back)
            IconButton(
              tooltip: 'Back',
              onPressed: AppNav.pop,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!,
                    style: TextStyle(
                      color: a.textSecondary,
                      fontSize: 11,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    height: 1.15,
                    letterSpacing: -0.4,
                    fontWeight: FontWeight.w600,
                    color: a.text,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: a.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
          if (settings)
            IconButton(
              tooltip: 'Settings',
              onPressed: () => AppNav.pushNamed('/settings'),
              icon: const Icon(Icons.tune_rounded),
            ),
        ],
      ),
    );
  }
}
