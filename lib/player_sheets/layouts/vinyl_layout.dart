import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/player_sheets/layouts/layout_parts.dart';
import 'package:wavvy/player_sheets/layouts/player_layout_data.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/seekable_artwork.dart';

/// The original Player page: the record and tonearm, then the title row, seek
/// bar, extras, transport and the mode dock.
class VinylLayout extends ConsumerWidget {
  const VinylLayout({super.key, required this.data});
  final PlayerLayoutData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final song = data.song;
    return LayoutBuilder(
      builder: (context, c) {
        final width = math.min(c.maxWidth, 480.0) - 32;
        // Room for everything under the artwork: title, seek bar, the extras
        // row, transport and the mode dock.
        final side = math.min(width, math.max(140.0, c.maxHeight - 384));
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: SizedBox.square(
                          dimension: side,
                          child: AnimatedSeekableArtwork(
                            song: song,
                            size: side,
                            iconColor: a.text,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: PlayerTitleBlock(
                              song: song,
                              onArtist: data.onArtist,
                            ),
                          ),
                          const SizedBox(width: 12),
                          PlayerSongActions(
                            song: song,
                            onLyrics: data.onLyrics,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      PlayerSeekRow(song: song),
                      const SizedBox(height: 6),
                      const PlayerExtras(),
                      const SizedBox(height: 10),
                      const PlayerTransport(),
                      const SizedBox(height: 14),
                      const PlayerModeDock(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The picker thumbnail: a record with a tonearm over a title bar, a seek line
/// and a round play button, drawn in theme colors.
class VinylLayoutPreview extends StatelessWidget {
  const VinylLayoutPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return CustomPaint(
      painter: _VinylPreviewPainter(
        record: a.text,
        label: a.accent,
        bar: a.textSecondary,
        line: a.outline,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _VinylPreviewPainter extends CustomPainter {
  _VinylPreviewPainter({
    required this.record,
    required this.label,
    required this.bar,
    required this.line,
  });
  final Color record;
  final Color label;
  final Color bar;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.46, h * 0.34);
    final radius = math.min(w * 0.36, h * 0.26);

    canvas.drawCircle(
      center,
      radius,
      Paint()..color = record.withValues(alpha: 0.85),
    );
    for (final f in const [0.8, 0.62]) {
      canvas.drawCircle(
        center,
        radius * f,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.white.withValues(alpha: 0.18),
      );
    }
    canvas.drawCircle(center, radius * 0.3, Paint()..color = label);
    canvas.drawCircle(center, radius * 0.05, Paint()..color = Colors.white);

    // The tonearm: a pivot at the top right and an arm down to the record.
    final pivot = Offset(w * 0.88, h * 0.1);
    final tip = Offset(center.dx + radius * 0.55, center.dy - radius * 0.1);
    canvas.drawLine(
      pivot,
      tip,
      Paint()
        ..color = line
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pivot, w * 0.04, Paint()..color = line);

    // Title, artist, seek line and a round play button.
    final barPaint = Paint()..color = bar.withValues(alpha: 0.7);
    RRect bar0(double top, double width, double height) =>
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.12, top, width, height),
          Radius.circular(height / 2),
        );
    canvas.drawRRect(bar0(h * 0.66, w * 0.5, h * 0.04), barPaint);
    canvas.drawRRect(
      bar0(h * 0.73, w * 0.32, h * 0.03),
      barPaint..color = bar.withValues(alpha: 0.4),
    );
    canvas.drawRRect(bar0(h * 0.8, w * 0.76, h * 0.02), Paint()..color = line);
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.9),
      h * 0.05,
      Paint()..color = label,
    );
  }

  @override
  bool shouldRepaint(_VinylPreviewPainter old) =>
      old.record != record ||
      old.label != label ||
      old.bar != bar ||
      old.line != line;
}
