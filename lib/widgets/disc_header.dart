import 'package:flutter/material.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// "Disc 2" row between the groups of a multi-disc album: an Aqua chrome bar
/// with the disc name and its song count. It wraps rather than clips at large
/// text sizes.
class DiscHeaderRow extends StatelessWidget {
  const DiscHeaderRow({super.key, required this.disc, required this.count});
  final int disc;
  final int count;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Semantics(
      header: true,
      label: 'Disc $disc, $count ${count == 1 ? 'song' : 'songs'}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        decoration: BoxDecoration(
          gradient: a.chromeGradient,
          border: Border(
            top: BorderSide(color: a.separator),
            bottom: BorderSide(color: a.separator),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.album_rounded, size: 16, color: a.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Disc $disc',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: a.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count ${count == 1 ? 'song' : 'songs'}',
              style: TextStyle(fontSize: 11.5, color: a.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
