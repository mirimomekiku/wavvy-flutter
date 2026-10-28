import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/player_sheets/layouts/player_layout.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// The Settings row for the Now Playing layout: shows the current one and
/// opens a picker with a thumbnail of each.
class PlayerLayoutSettingTile extends ConsumerWidget {
  const PlayerLayoutSettingTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final chosen = ref.watch(settingsProvider.select((s) => s.playerLayout));
    final layout =
        PlayerLayout.values[chosen.clamp(0, PlayerLayout.values.length - 1)];
    return ListTile(
      dense: true,
      onTap: () => showPlayerLayoutPicker(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(Icons.album_outlined, color: a.textSecondary, size: 22),
      title: Text(
        'Now Playing layout',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: a.text,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          layout.label,
          style: TextStyle(fontSize: 12, height: 1.4, color: a.textSecondary),
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: a.textSecondary),
    );
  }
}

/// The picker: a grid of layout thumbnails and the wide-screen switch.
Future<void> showPlayerLayoutPicker(BuildContext context) {
  return showAquaSheet<void>(
    context: context,
    title: 'Now Playing layout',
    subtitle: 'Only the Player page changes',
    builder: (_) => const PlayerLayoutPicker(),
  );
}

class PlayerLayoutPicker extends ConsumerWidget {
  const PlayerLayoutPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final chosen = settings.playerLayout.clamp(
      0,
      PlayerLayout.values.length - 1,
    );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              const gap = 12.0;
              final columns = c.maxWidth >= 520 ? 3 : 2;
              final width = (c.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final layout in PlayerLayout.values)
                    SizedBox(
                      width: width,
                      child: PlayerLayoutTile(
                        layout: layout,
                        selected: layout.index == chosen,
                        onTap: () => notifier.setPlayerLayout(layout.index),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            onTap: () => notifier.togglePlayerLayoutAdaptive(
              !settings.playerLayoutAdaptive,
            ),
            title: Text(
              'Two panes on wide screens',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: a.text,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'In landscape and on tablets, show the player and the queue or '
                'lyrics side by side, whichever layout is chosen',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: a.textSecondary,
                ),
              ),
            ),
            trailing: AquaSwitch(
              value: settings.playerLayoutAdaptive,
              onChanged: notifier.togglePlayerLayoutAdaptive,
            ),
          ),
        ],
      ),
    );
  }
}

/// One layout in the picker: its thumbnail, name and a one-line description.
class PlayerLayoutTile extends StatelessWidget {
  const PlayerLayoutTile({
    super.key,
    required this.layout,
    required this.selected,
    required this.onTap,
  });
  final PlayerLayout layout;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final preview = kPlayerLayoutPreviews[layout];
    return Semantics(
      button: true,
      selected: selected,
      label: '${layout.label}. ${layout.description}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 0.78,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: a.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? a.accent
                        : a.outline.withValues(alpha: 0.6),
                    width: selected ? 2.5 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: a.accent.withValues(alpha: 0.35),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
                child: preview != null
                    ? preview(context)
                    : Center(
                        child: Icon(
                          Icons.album_rounded,
                          size: 34,
                          color: a.textSecondary,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    layout.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: a.text,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, size: 16, color: a.accent),
              ],
            ),
            Text(
              layout.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                color: a.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
