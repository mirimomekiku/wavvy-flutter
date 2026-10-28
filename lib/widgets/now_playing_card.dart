import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';

/// The three looks of the "Now playing" share card.
enum NowPlayingCardStyle {
  aqua('Aqua'),
  poster('Poster'),
  minimal('Minimal');

  const NowPlayingCardStyle(this.label);
  final String label;
}

/// The shapes the card can be exported in.
enum NowPlayingCardAspect {
  square(1, 'Square 1:1'),
  portrait(4 / 5, 'Portrait 4:5'),
  story(9 / 16, 'Story 9:16');

  const NowPlayingCardAspect(this.ratio, this.label);

  /// Width over height.
  final double ratio;
  final String label;
}

/// Every card is laid out at this logical width, whatever the aspect.
const double kNowPlayingCardWidth = 360;

/// The exported PNG is about this many pixels wide.
const double kNowPlayingCardOutputWidth = 1080;

/// The logical size a card is laid out at and the pixel ratio that turns it
/// into the exported image.
@immutable
class NowPlayingCardSizing {
  const NowPlayingCardSizing(this.logical, this.pixelRatio);
  final Size logical;
  final double pixelRatio;

  /// The size of the PNG.
  Size get pixels =>
      Size(logical.width * pixelRatio, logical.height * pixelRatio);

  @override
  bool operator ==(Object other) =>
      other is NowPlayingCardSizing &&
      other.logical == logical &&
      other.pixelRatio == pixelRatio;

  @override
  int get hashCode => Object.hash(logical, pixelRatio);
}

/// [aspect] as a logical size (360 wide) and the ratio that makes the PNG
/// [outputWidth] pixels wide: 1080x1080, 1080x1350 and 1080x1920 by default.
/// The tallest card is 8 MB of pixels, which is what bounds the width.
NowPlayingCardSizing nowPlayingCardSizing(
  NowPlayingCardAspect aspect, {
  double outputWidth = kNowPlayingCardOutputWidth,
}) => NowPlayingCardSizing(
  Size(
    kNowPlayingCardWidth,
    (kNowPlayingCardWidth / aspect.ratio).roundToDouble(),
  ),
  outputWidth / kNowPlayingCardWidth,
);

/// The largest font size from [maxSize] down to [minSize] (in [step]s) at
/// which [text] fits [maxLines] lines in [maxWidth]; [minSize] when none does
/// (the text then ends in an ellipsis).
double fitFontSize(
  String text,
  TextStyle style,
  double maxWidth, {
  int maxLines = 1,
  required double maxSize,
  required double minSize,
  double step = 1,
}) {
  if (text.isEmpty || maxWidth <= 0) return maxSize;
  for (var size = maxSize; size > minSize; size -= step) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontSize: size),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
    final fits = !painter.didExceedMaxLines;
    painter.dispose();
    if (fits) return size;
  }
  return minSize;
}

/// What a card shows. Plain values, so a card needs no providers.
@immutable
class NowPlayingCardData {
  const NowPlayingCardData({
    required this.title,
    required this.artist,
    required this.accent,
    this.album,
    this.cover,
    this.seed = 0,
    this.position,
    this.duration,
  });

  final String title;
  final String artist;
  final String? album;

  /// The cover as an image file's bytes; null draws the pixel-art placeholder.
  final Uint8List? cover;

  /// Flat color of the Minimal card: the album color or the theme accent.
  final Color accent;

  /// Seed of the placeholder picture.
  final int seed;

  /// Elapsed and total time; both null (or a zero total) hides the time line.
  final Duration? position;
  final Duration? duration;

  bool get hasTime =>
      position != null && duration != null && duration! > Duration.zero;

  double get progress => hasTime
      ? (position!.inMilliseconds / duration!.inMilliseconds).clamp(0.0, 1.0)
      : 0;
}

/// The card: [style] at [aspect], in the colors, texture and light or dark of
/// the surrounding theme. It lays itself out at [kNowPlayingCardWidth] and
/// ignores the user's text scale, so what is exported is what was previewed.
class NowPlayingCard extends StatelessWidget {
  const NowPlayingCard({
    super.key,
    required this.data,
    required this.style,
    required this.aspect,
    this.showMark = true,
  });

  final NowPlayingCardData data;
  final NowPlayingCardStyle style;
  final NowPlayingCardAspect aspect;

  /// The "Wavvy" wordmark in a corner.
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final size = nowPlayingCardSizing(aspect).logical;
    final card = switch (style) {
      NowPlayingCardStyle.aqua => _AquaCard(data: data, showMark: showMark),
      NowPlayingCardStyle.poster => _PosterCard(data: data, showMark: showMark),
      NowPlayingCardStyle.minimal => _MinimalCard(
        data: data,
        showMark: showMark,
      ),
    };
    return MediaQuery.withNoTextScaling(
      child: SizedBox.fromSize(
        size: size,
        child: ClipRect(child: card),
      ),
    );
  }
}

// ------------------------------------------------------------------- Pieces

/// The page color of the look, with its stripes or brushed grain.
class _PageBackdrop extends StatelessWidget {
  const _PageBackdrop({this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: a.background,
        gradient: a.backdropGradient,
        image: a.pageTexture,
      ),
      child: child ?? const SizedBox.expand(),
    );
  }
}

/// A square cover, or the placeholder when there is none (or it will not
/// decode).
class _Cover extends StatelessWidget {
  const _Cover(this.data, this.side);
  final NowPlayingCardData data;
  final double side;

  @override
  Widget build(BuildContext context) {
    final placeholder = WvMediaPlaceholder(seed: data.seed, size: side);
    final bytes = data.cover;
    if (bytes == null) return placeholder;
    return Image.memory(
      bytes,
      width: side,
      height: side,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

/// A square as large as the space allows, centered or at the start.
class _Square extends StatelessWidget {
  const _Square({required this.builder, this.alignment = Alignment.center});
  final Widget Function(double side) builder;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final side = c.biggest.shortestSide.clamp(0.0, double.infinity);
      return Align(
        alignment: alignment,
        child: side.isFinite && side > 0 ? builder(side) : const SizedBox(),
      );
    },
  );
}

/// Text that shrinks from [maxSize] to [minSize] to fit [maxLines], then ends
/// in an ellipsis.
class _FitText extends StatelessWidget {
  const _FitText(
    this.text, {
    required this.style,
    required this.maxSize,
    required this.minSize,
    this.maxLines = 1,
  });
  final String text;
  final TextStyle style;
  final double maxSize, minSize;
  final int maxLines;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final size = fitFontSize(
        text,
        style,
        c.maxWidth,
        maxLines: maxLines,
        maxSize: maxSize,
        minSize: minSize,
      );
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(fontSize: size),
      );
    },
  );
}

class _Mark extends StatelessWidget {
  const _Mark(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) =>
      WvKicker('Wavvy', color: color.withValues(alpha: 0.8));
}

/// "elapsed ---o--- total": a thin line with the times at its ends.
class _SeekLine extends StatelessWidget {
  const _SeekLine({
    required this.data,
    required this.textColor,
    required this.track,
    required this.fill,
    this.fillGradient,
    this.height = 4,
  });
  final NowPlayingCardData data;
  final Color textColor, track, fill;
  final Gradient? fillGradient;
  final double height;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      color: textColor,
      fontWeight: FontWeight.w600,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        Text(PlayerUtils.formatDuration(data.position!), style: style),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: track,
                borderRadius: BorderRadius.circular(height / 2),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: data.progress,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: fill,
                      gradient: fillGradient,
                      borderRadius: BorderRadius.circular(height / 2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(PlayerUtils.formatDuration(data.duration!), style: style),
      ],
    );
  }
}

// --------------------------------------------------------------------- Aqua

/// One of the three window lights, in the gel of the app's close light.
class _Light extends StatelessWidget {
  const _Light(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 13,
    height: 13,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        center: const Alignment(-0.3, -0.5),
        colors: [Color.lerp(color, Colors.white, 0.55)!, color],
      ),
      border: Border.all(
        color: Color.lerp(color, Colors.black, 0.35)!,
        width: 0.8,
      ),
    ),
  );
}

/// A Mac OS X window: title bar with lights, the cover in a glass-topped
/// bezel and an LCD panel with the song.
class _AquaCard extends StatelessWidget {
  const _AquaCard({required this.data, required this.showMark});
  final NowPlayingCardData data;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final edge = a.outline.withValues(alpha: 0.55);
    return _PageBackdrop(
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 14, 14, showMark ? 6 : 14),
        child: Column(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: a.surface,
                  image: a.pageTexture,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: edge),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: a.dark ? 0.4 : 0.18,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _titleBar(a, edge),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: _Square(builder: (side) => _bezel(a, side)),
                        ),
                      ),
                      _lcd(a),
                    ],
                  ),
                ),
              ),
            ),
            if (showMark)
              SizedBox(
                height: 20,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _Mark(a.text),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _titleBar(WvPalette a, Color edge) => Container(
    height: 28,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      gradient: a.chromeGradient,
      image: a.chromeGrain,
      border: Border(bottom: BorderSide(color: edge)),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Light(Color(0xFFFF5F57)),
              SizedBox(width: 6),
              _Light(Color(0xFFFEBC2E)),
              SizedBox(width: 6),
              _Light(Color(0xFF28C840)),
            ],
          ),
        ),
        Text(
          'Now Playing',
          maxLines: 1,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: a.text,
          ),
        ),
      ],
    ),
  );

  /// The cover framed in a dark bezel, with a glass reflection on its top half.
  Widget _bezel(WvPalette a, double side) {
    const frame = 5.0;
    final inner = (side - frame * 2).clamp(0.0, double.infinity);
    return Container(
      width: side,
      height: side,
      padding: const EdgeInsets.all(frame),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: a.dark
              ? const [Color(0xFF59616B), Color(0xFF262B32)]
              : const [Color(0xFFD9DCE1), Color(0xFF8E959F)],
        ),
        border: Border.all(color: a.outline.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Cover(data, inner),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: inner * 0.5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.38),
                      Colors.white.withValues(alpha: 0.05),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lcd(WvPalette a) {
    final album = data.album;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: a.lcdDecoration.copyWith(
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: a.text,
            ),
          ),
          Text(
            data.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: a.text),
          ),
          if (album != null && album.isNotEmpty)
            Text(
              album,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: a.textSecondary),
            ),
          if (data.hasTime) ...[
            const SizedBox(height: 8),
            _SeekLine(
              data: data,
              textColor: a.textSecondary,
              track: a.dark ? const Color(0xFF0C1114) : const Color(0xFFB4BDBA),
              fill: a.accent,
              fillGradient: aquaGel(a.accent),
              height: 6,
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- Poster

/// The cover blurred and washed with the card color behind a large sharp
/// cover and bold type.
class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.data, required this.showMark});
  final NowPlayingCardData data;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final bytes = data.cover;
    final text = a.text;
    final titleStyle = TextStyle(
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: -0.5,
      color: text,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        const _PageBackdrop(),
        if (bytes != null)
          ClipRect(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Transform.scale(
                scale: 1.35,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.expand(),
                ),
              ),
            ),
          ),
        // The wash: enough of the card color that the type always reads.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                a.background.withValues(alpha: 0.5),
                a.background.withValues(alpha: 0.88),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 14,
                child: showMark
                    ? Align(
                        alignment: Alignment.centerRight,
                        child: _Mark(text),
                      )
                    : null,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _Square(
                  builder: (side) => DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _Cover(data, side),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _FitText(
                data.title,
                style: titleStyle,
                maxSize: 30,
                minSize: 18,
                maxLines: 2,
              ),
              const SizedBox(height: 4),
              Text(
                data.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: a.textSecondary,
                ),
              ),
              if (data.hasTime) ...[
                const SizedBox(height: 14),
                _SeekLine(
                  data: data,
                  textColor: a.textSecondary,
                  track: text.withValues(alpha: 0.2),
                  fill: a.accent,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ Minimal

/// The cover on a flat color of the album, with big type.
class _MinimalCard extends StatelessWidget {
  const _MinimalCard({required this.data, required this.showMark});
  final NowPlayingCardData data;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final bg = data.accent;
    final on = bg.computeLuminance() > 0.5
        ? const Color(0xFF111418)
        : Colors.white;
    return ColoredBox(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Square(
                alignment: Alignment.centerLeft,
                builder: (side) => DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: _Cover(data, side),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            _FitText(
              data.title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                height: 1.05,
                letterSpacing: -1,
                color: on,
              ),
              maxSize: 40,
              minSize: 20,
              maxLines: 3,
            ),
            const SizedBox(height: 6),
            Text(
              data.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: on.withValues(alpha: 0.85),
              ),
            ),
            if (data.hasTime) ...[
              const SizedBox(height: 14),
              _SeekLine(
                data: data,
                textColor: on.withValues(alpha: 0.85),
                track: on.withValues(alpha: 0.25),
                fill: on,
                height: 3,
              ),
            ],
            SizedBox(
              height: 26,
              child: showMark
                  ? Align(alignment: Alignment.bottomRight, child: _Mark(on))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
