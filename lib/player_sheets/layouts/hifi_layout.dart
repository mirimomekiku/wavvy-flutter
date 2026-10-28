import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/downloader/flavor.dart';
import 'package:wavvy/player_sheets/layouts/hifi_jog.dart';
import 'package:wavvy/player_sheets/layouts/hifi_live_meters.dart';
import 'package:wavvy/player_sheets/layouts/hifi_meters.dart';
import 'package:wavvy/player_sheets/layouts/layout_parts.dart';
import 'package:wavvy/player_sheets/layouts/player_layout_data.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';

/// A hi-fi component faceplate: a brushed-metal panel with an LCD for the
/// song, two analog meters (live bass and treble levels when the visualizer
/// is on, time gauges otherwise), a jog wheel that scrubs, the seek bar, the
/// transport and the mode dock.
class HifiLayout extends ConsumerWidget {
  const HifiLayout({super.key, required this.data});
  final PlayerLayoutData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final song = data.song;
    final actions = PlayerSongActions(
      song: song,
      onLyrics: data.onLyrics,
      size: 40,
    );
    return LayoutBuilder(
      builder: (context, c) {
        final width = math.min(c.maxWidth, 480.0) - 24;
        final wheel = (width * 0.5).clamp(140.0, 210.0);
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: a.chromeGradient,
                      image: a.chromeGrain,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: a.outline.withValues(alpha: 0.7),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: a.dark ? 0.5 : 0.18,
                          ),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: CustomPaint(
                      foregroundPainter: _FaceplatePainter(a),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Lcd(data: data),
                            const SizedBox(height: 12),
                            // The visualizer code is only reached through this
                            // constant, so the Play build drops it.
                            if (kVisualizerAvailable)
                              HifiLiveMeters(trailing: actions)
                            else ...[
                              const HifiTimeMeters(),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: actions,
                              ),
                            ],
                            const SizedBox(height: 6),
                            Center(child: HifiJogWheel(size: wheel)),
                            const SizedBox(height: 6),
                            PlayerSeekRow(song: song),
                            const SizedBox(height: 8),
                            const PlayerExtras(),
                            const SizedBox(height: 10),
                            const PlayerTransport(
                              sideHeight: 54,
                              playHeight: 60,
                              playWidth: 84,
                              sideIcon: 28,
                              playIcon: 32,
                              gap: 10,
                            ),
                            const SizedBox(height: 12),
                            const PlayerModeDock(),
                          ],
                        ),
                      ),
                    ),
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

/// The LCD window: a small cover, title, artist, and elapsed / remaining.
class _Lcd extends StatelessWidget {
  const _Lcd({required this.data});
  final PlayerLayoutData data;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return DecoratedBox(
      decoration: a.lcdDecoration.copyWith(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PlayerTitleBlock(
                    song: data.song,
                    onArtist: data.onArtist,
                    titleSize: 17,
                    artistSize: 13,
                  ),
                  const SizedBox(height: 8),
                  const _LcdTimes(),
                ],
              ),
            ),
            const SizedBox(width: 10),
            PlayerCover(song: data.song, size: 56, radius: 6, elevated: false),
          ],
        ),
      ),
    );
  }
}

class _LcdTimes extends ConsumerWidget {
  const _LcdTimes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final position = ref.watch(positionProvider);
    final duration = ref.watch(durationProvider);
    final left = duration > position ? duration - position : Duration.zero;
    final style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: a.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        Flexible(
          child: Text(
            PlayerUtils.formatDuration(position),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            '-${PlayerUtils.formatDuration(left)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// Bevel highlight and four faceplate screws, drawn over the panel.
class _FaceplatePainter extends CustomPainter {
  _FaceplatePainter(this.a);
  final WvPalette a;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bevel = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(1.5),
      const Radius.circular(16.5),
    );
    canvas.drawRRect(
      bevel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: a.dark ? 0.22 : 0.9),
            Colors.transparent,
            Colors.black.withValues(alpha: a.dark ? 0.4 : 0.18),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(Offset.zero & size),
    );
    const inset = 10.0;
    const r = 3.6;
    for (final p in [
      const Offset(inset, inset),
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
    ]) {
      canvas.drawCircle(
        p + const Offset(0, 0.8),
        r,
        Paint()..color = Colors.white.withValues(alpha: a.dark ? 0.12 : 0.8),
      );
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.5),
            colors: a.dark
                ? const [Color(0xFF8A919B), Color(0xFF3A4048)]
                : const [Color(0xFFFFFFFF), Color(0xFF8F959D)],
          ).createShader(Rect.fromCircle(center: p, radius: r)),
      );
      // A slot, turned a different way on each screw.
      final turn = (p.dx * 7 + p.dy * 3) % math.pi;
      final d = Offset(math.cos(turn), math.sin(turn)) * (r * 0.75);
      canvas.drawLine(
        p - d,
        p + d,
        Paint()
          ..strokeWidth = 1
          ..color = Colors.black.withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_FaceplatePainter old) => old.a != a;
}

/// The thumbnail for the layout picker: a metal panel with an LCD strip, two
/// small dials and a knob, in the theme's colors.
class HifiLayoutPreview extends StatelessWidget {
  const HifiLayoutPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Semantics(
        label: 'Hi-Fi deck preview',
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: a.chromeGradient,
            image: a.chromeGrain,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: a.outline.withValues(alpha: 0.6)),
          ),
          child: CustomPaint(
            painter: _PreviewPainter(a),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.a);
  final WvPalette a;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final ink = a.text.withValues(alpha: 0.7);
    // The LCD strip with a cover square and two lines of text.
    final lcd = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.1, h * 0.08, w * 0.8, h * 0.2),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      lcd,
      Paint()
        ..color = a.dark ? const Color(0xFF1E2A30) : const Color(0xFFE9EEEC),
    );
    canvas.drawRRect(
      lcd,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = a.outline,
    );
    final line = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = ink;
    canvas.drawLine(
      Offset(w * 0.16, h * 0.15),
      Offset(w * 0.52, h * 0.15),
      line,
    );
    canvas.drawLine(
      Offset(w * 0.16, h * 0.22),
      Offset(w * 0.38, h * 0.22),
      line..color = a.textSecondary,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.72, h * 0.11, h * 0.14, h * 0.14),
        const Radius.circular(2),
      ),
      Paint()..color = a.accent.withValues(alpha: 0.8),
    );
    // Two small dials with needles.
    for (final (i, tilt) in [(0, -0.5), (1, 0.45)]) {
      final cx = w * (i == 0 ? 0.3 : 0.7);
      final cy = h * 0.5;
      final r = w * 0.17;
      final box = Rect.fromCenter(
        center: Offset(cx, cy - r * 0.2),
        width: r * 2.3,
        height: r * 1.6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(3)),
        Paint()
          ..color = a.dark ? const Color(0xFF1E2A30) : const Color(0xFFE9EEEC),
      );
      final pivot = Offset(cx, cy + r * 0.45);
      canvas.drawArc(
        Rect.fromCircle(center: pivot, radius: r),
        hifiNeedleAngle(0),
        kHifiNeedleSweep * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = ink,
      );
      final ang = -math.pi / 2 + tilt;
      canvas.drawLine(
        pivot,
        pivot + Offset(math.cos(ang), math.sin(ang)) * (r * 0.95),
        Paint()
          ..strokeWidth = 1.4
          ..color = const Color(0xFF9A2B20),
      );
    }
    // The knob.
    final kc = Offset(w * 0.5, h * 0.8);
    final kr = math.min(w * 0.2, h * 0.14);
    canvas.drawCircle(
      kc,
      kr * 1.25,
      Paint()..color = ink.withValues(alpha: 0.25),
    );
    canvas.drawCircle(
      kc,
      kr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: a.dark
              ? const [Color(0xFF6B727C), Color(0xFF2A2F35)]
              : const [Color(0xFFFFFFFF), Color(0xFF9EA3AA)],
        ).createShader(Rect.fromCircle(center: kc, radius: kr)),
    );
    canvas.drawLine(
      kc,
      kc + Offset(kr * 0.6, -kr * 0.6),
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = a.accent,
    );
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.a != a;
}
