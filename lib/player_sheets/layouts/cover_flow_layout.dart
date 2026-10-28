import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/player_sheets/layouts/layout_parts.dart';
import 'package:wavvy/player_sheets/layouts/player_layout_data.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// How much of a cover's height its reflection takes.
const double _kReflect = 0.28;

/// How far (radians) the covers beside the middle one are turned away.
const double _kTilt = 1.0;

/// How many queue entries the back of a cover lists.
const int _kUpNext = 20;

/// The Cover Flow layout: the queue as a row of covers, the middle one facing
/// front and the others turned away with a reflection under each. Swiping
/// settles on a cover and the player jumps to that track; when the playing
/// track changes any other way the row slides to it without jumping the player
/// again. Tapping the middle cover turns it over to show the Up next list.
class CoverFlowLayout extends ConsumerStatefulWidget {
  const CoverFlowLayout({super.key, required this.data});
  final PlayerLayoutData data;

  @override
  ConsumerState<CoverFlowLayout> createState() => _CoverFlowLayoutState();
}

class _CoverFlowLayoutState extends ConsumerState<CoverFlowLayout>
    with SingleTickerProviderStateMixin {
  late final PageController _pc;
  late final AnimationController _flip;
  late final Listenable _motion;

  /// The queue length and playing index the carousel was last matched to.
  int _count = 1;
  int _seenCurrent = -1;

  /// The row the player was asked to jump to and has not reported yet. Its
  /// arrival (or any other change) is not echoed back into the carousel.
  int? _requested;

  bool _flipped = false;
  int _flipIndex = -1;
  bool _reduce = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(playerProvider);
    _count = math.max(1, s.queue.length);
    _seenCurrent = s.currentIndex;
    _pc = PageController(
      viewportFraction: 0.5,
      initialPage: s.currentIndex.clamp(0, _count - 1),
    );
    _flip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _motion = Listenable.merge([_pc, _flip]);
  }

  @override
  void dispose() {
    _flip.dispose();
    _pc.dispose();
    super.dispose();
  }

  /// The carousel's position in pages (fractional while moving).
  double _page() => _pc.hasClients && _pc.position.haveDimensions
      ? (_pc.page ?? _seenCurrent.clamp(0, _count - 1).toDouble())
      : _seenCurrent.clamp(0, _count - 1).toDouble();

  void _slideTo(int index) {
    if (!_pc.hasClients || index < 0 || index >= _count) return;
    if (_reduce) {
      _pc.jumpToPage(index);
    } else {
      _pc.animateToPage(
        index,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Moves the carousel to the playing row after a change that did not come
  /// from the carousel (or after an edit made the page out of range).
  void _follow(int target, {required bool jump}) {
    if (!mounted || !_pc.hasClients || !_pc.position.haveDimensions) return;
    if (_page().round() == target) return;
    if (jump || _reduce) {
      _pc.jumpToPage(target);
    } else {
      _slideTo(target);
    }
  }

  /// Asks the player for row [index]: the call a Queue row uses. It keeps
  /// playing if it was playing.
  void _jump(int index) {
    final state = ref.read(playerProvider);
    if (index < 0 || index >= state.queue.length) return;
    if (index == state.currentIndex) return;
    _requested = index;
    final player = ref.read(audioPlayerProvider);
    player.seek(Duration.zero, index: index);
    if (state.isPlaying) player.play();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.horizontal) return false;
    // Swiping (or sliding to another cover) turns the middle one back.
    if (n is ScrollStartNotification && _flipped) _setFlip(false);
    if (n is ScrollEndNotification) {
      final state = ref.read(playerProvider);
      final page = _page().round().clamp(0, _count - 1);
      if (state.queue.isNotEmpty) {
        if (page == state.currentIndex) {
          _requested = null;
        } else if (page != _requested) {
          _jump(page);
        }
      }
    }
    return false;
  }

  void _setFlip(bool value) {
    if (!mounted || _flipped == value) return;
    setState(() => _flipped = value);
    if (_reduce) {
      _flip.value = value ? 1 : 0;
    } else if (value) {
      _flip.forward();
    } else {
      _flip.reverse();
    }
  }

  void _tapCover(int index) {
    if (_page().round() == index) {
      _flipIndex = index;
      _setFlip(!_flipped);
    } else {
      _slideTo(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    _reduce = MediaQuery.disableAnimationsOf(context);
    final queue = ref.watch(playerProvider.select((s) => s.queue));
    final current = ref.watch(playerProvider.select((s) => s.currentIndex));
    final count = math.max(1, queue.length);
    final target = current.clamp(0, count - 1);
    if (current != _seenCurrent || count != _count) {
      final edited = count != _count;
      final moved = current != _seenCurrent;
      _seenCurrent = current;
      _count = count;
      // Whatever the player reports now, the carousel follows it.
      _requested = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (moved && _flipped) _setFlip(false);
        _follow(target, jump: edited);
      });
    }
    return LayoutBuilder(
      builder: (context, c) {
        final width = math.min(c.maxWidth, 560.0);
        final room = c.hasBoundedHeight ? c.maxHeight - 430 : 220.0;
        // Beside the middle cover there must be room for the turned ones.
        final side = math.max(100.0, math.min(width * 0.46, room));
        final faceHeight = side * (1 + _kReflect);
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: c.hasBoundedHeight ? c.maxHeight : 0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    SizedBox(
                      height: faceHeight + 12,
                      child: Semantics(
                        container: true,
                        label: 'Cover Flow',
                        value:
                            '${_seenCurrent.clamp(0, count - 1) + 1} of $count',
                        increasedValue: 'Next song',
                        decreasedValue: 'Previous song',
                        onIncrease: () => _slideTo(_page().round() + 1),
                        onDecrease: () => _slideTo(_page().round() - 1),
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _onScroll,
                          child: PageView.builder(
                            controller: _pc,
                            itemCount: count,
                            itemBuilder: (context, index) =>
                                _item(index, queue, side, target),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PlayerTitleBlock(
                            song: data.song,
                            onArtist: data.onArtist,
                            alignment: CrossAxisAlignment.center,
                            titleSize: 20,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              PlayerSongActions(
                                song: data.song,
                                onLyrics: data.onLyrics,
                                size: 40,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          PlayerSeekRow(song: data.song),
                          const SizedBox(height: 6),
                          const PlayerExtras(),
                          const SizedBox(height: 10),
                          const PlayerTransport(),
                          const SizedBox(height: 14),
                          const PlayerModeDock(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _item(int index, List<SongModel> queue, double side, int current) {
    final song = queue.isEmpty ? widget.data.song : queue[index];
    final isMiddle = index == current;
    final label = isMiddle
        ? '${song.title}, ${song.artist ?? 'Unknown Artist'}. '
              'Turn the cover over to see what is next'
        : 'Show ${song.title}';
    final front = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          onTap: () => _tapCover(index),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _tapCover(index),
            child: PlayerCover(song: song, size: side, radius: 4),
          ),
        ),
        ExcludeSemantics(
          child: _Reflection(song: song, side: side),
        ),
      ],
    );
    final flippedHere = _flipIndex == index;
    return _FlowItem(
      key: ValueKey('cover-flow-$index'),
      index: index,
      side: side,
      motion: _motion,
      pageOf: _page,
      flip: _flip,
      flipIndex: _flipIndex,
      reduce: _reduce,
      front: front,
      back: flippedHere && (_flipped || _flip.value > 0)
          ? _CoverBack(
              queue: queue,
              index: index,
              side: side,
              onLyrics: widget.data.onLyrics,
              onJump: (i) {
                _setFlip(false);
                _jump(i);
                _slideTo(i);
              },
              onFlipBack: () => _setFlip(false),
            )
          : null,
    );
  }
}

/// One cover in the row: moved, turned, scaled and faded by how far it is from
/// the middle. Only this repaints while the row moves; the cover itself is a
/// cached layer.
class _FlowItem extends StatelessWidget {
  const _FlowItem({
    super.key,
    required this.index,
    required this.side,
    required this.motion,
    required this.pageOf,
    required this.flip,
    required this.flipIndex,
    required this.reduce,
    required this.front,
    required this.back,
  });
  final int index;
  final double side;
  final Listenable motion;
  final double Function() pageOf;
  final Animation<double> flip;
  final int flipIndex;
  final bool reduce;
  final Widget front;
  final Widget? back;

  @override
  Widget build(BuildContext context) {
    final faceHeight = side * (1 + _kReflect);
    return Center(
      child: SizedBox(
        width: side,
        height: faceHeight,
        child: AnimatedBuilder(
          animation: motion,
          child: RepaintBoundary(child: front),
          builder: (context, child) {
            final o = index - pageOf();
            final far = math.min(o.abs(), 1.5);
            final c = math.max(-1.0, math.min(1.0, o));
            final t = index == flipIndex ? flip.value : 0.0;
            final showBack = t >= 0.5 && back != null;
            final angle = (reduce ? 0.0 : -c * _kTilt) + t * math.pi;
            final matrix = Matrix4.identity()
              ..setEntry(3, 2, 0.0011)
              ..rotateY(angle);
            Widget face = showBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationY(math.pi),
                    child: SizedBox(
                      height: faceHeight,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: RepaintBoundary(child: back),
                      ),
                    ),
                  )
                : child!;
            face = Transform(
              alignment: Alignment.center,
              transform: matrix,
              child: face,
            );
            // Covers sit on one baseline: they shrink toward the cover's foot.
            face = Transform.scale(
              scale: 1 - 0.2 * far,
              alignment: Alignment(0, 2 / (1 + _kReflect) - 1),
              child: face,
            );
            face = Transform.translate(
              offset: Offset(reduce ? 0 : -c * side * 0.3, 0),
              child: face,
            );
            final opacity = 1 - 0.3 * far;
            return opacity < 1 ? Opacity(opacity: opacity, child: face) : face;
          },
        ),
      ),
    );
  }
}

/// A flipped, faded copy of the bottom of the cover.
class _Reflection extends StatelessWidget {
  const _Reflection({required this.song, required this.side});
  final SongModel song;
  final double side;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: side,
      height: side * _kReflect,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x59FFFFFF), Color(0x00FFFFFF)],
        ).createShader(r),
        child: ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: _kReflect,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(1, -1, 1),
              child: PlayerCover(
                song: song,
                size: side,
                radius: 4,
                elevated: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The back of the middle cover: the next songs in the queue (a tap jumps to
/// one) and a button for the lyrics.
class _CoverBack extends StatelessWidget {
  const _CoverBack({
    required this.queue,
    required this.index,
    required this.side,
    required this.onLyrics,
    required this.onJump,
    required this.onFlipBack,
  });
  final List<SongModel> queue;
  final int index;
  final double side;
  final VoidCallback? onLyrics;
  final ValueChanged<int> onJump;
  final VoidCallback onFlipBack;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final first = index + 1;
    final upcoming = math.max(0, math.min(_kUpNext, queue.length - first));
    final extent = MediaQuery.textScalerOf(context).scale(30) + 8;
    return Semantics(
      container: true,
      child: Container(
        width: side,
        height: side,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: a.surfaceHigh,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: a.outline.withValues(alpha: 0.65)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onFlipBack,
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Up next. Turn the cover back',
                      excludeSemantics: true,
                      onTap: onFlipBack,
                      child: Text(
                        'Up next',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: a.text,
                        ),
                      ),
                    ),
                  ),
                  if (onLyrics != null)
                    WvButton(
                      circular: true,
                      squircle: true,
                      size: 28,
                      tooltip: 'View lyrics',
                      onPressed: onLyrics,
                      child: const Icon(Icons.lyrics_outlined, size: 16),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: upcoming == 0
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onFlipBack,
                      child: Center(
                        child: Text(
                          'Nothing after this',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: a.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemExtent: extent,
                      itemCount: upcoming,
                      itemBuilder: (context, k) {
                        final song = queue[first + k];
                        return InkWell(
                          // No ripple: the face is turning and painted in 3D.
                          splashFactory: NoSplash.splashFactory,
                          onTap: () => onJump(first + k),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.15,
                                    fontWeight: FontWeight.w600,
                                    color: a.text,
                                  ),
                                ),
                                Text(
                                  song.artist ?? 'Unknown Artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    height: 1.15,
                                    color: a.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The picker thumbnail: three tilted covers, the middle one larger, and a
/// soft reflection under each, in the theme's colors.
class CoverFlowLayoutPreview extends StatelessWidget {
  const CoverFlowLayoutPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return CustomPaint(
      size: Size.infinite,
      painter: _PreviewPainter(
        middle: a.accent,
        sides: a.textSecondary,
        line: a.outline,
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter({
    required this.middle,
    required this.sides,
    required this.line,
  });
  final Color middle;
  final Color sides;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final baseline = h * 0.56;
    final mid = w * 0.36;
    // A turned cover: a trapezoid, taller on the edge nearer the middle.
    void turned({required bool left}) {
      final outerX = left ? w * 0.07 : w * 0.93;
      final innerX = left ? w * 0.30 : w * 0.70;
      final outerH = mid * 0.72;
      final innerH = mid * 0.88;
      final path = Path()
        ..moveTo(outerX, baseline - outerH * 0.96)
        ..lineTo(innerX, baseline - innerH)
        ..lineTo(innerX, baseline)
        ..lineTo(outerX, baseline)
        ..close();
      canvas.drawPath(path, Paint()..color = sides.withValues(alpha: 0.5));
      final mirror = Path()
        ..moveTo(outerX, baseline)
        ..lineTo(innerX, baseline)
        ..lineTo(innerX, baseline + innerH * 0.3)
        ..lineTo(outerX, baseline + outerH * 0.3)
        ..close();
      canvas.drawPath(
        mirror,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [sides.withValues(alpha: 0.22), sides.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(0, baseline, w, innerH * 0.3)),
      );
    }

    turned(left: true);
    turned(left: false);
    final rect = Rect.fromLTWH((w - mid) / 2, baseline - mid, mid, mid);
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(2));
    canvas.drawRRect(r, Paint()..color = middle.withValues(alpha: 0.9));
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = line.withValues(alpha: 0.6),
    );
    final reflection = Rect.fromLTWH(rect.left, baseline, mid, mid * 0.3);
    canvas.drawRect(
      reflection,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [middle.withValues(alpha: 0.3), middle.withValues(alpha: 0)],
        ).createShader(reflection),
    );
    // The seek bar and the three transport buttons under it.
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.82, w * 0.76, 3),
      const Radius.circular(2),
    );
    canvas.drawRRect(bar, Paint()..color = line.withValues(alpha: 0.7));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.12, h * 0.82, w * 0.3, 3),
        const Radius.circular(2),
      ),
      Paint()..color = middle,
    );
    final dot = Paint()..color = sides.withValues(alpha: 0.55);
    for (final x in [0.32, 0.5, 0.68]) {
      canvas.drawCircle(Offset(w * x, h * 0.92), x == 0.5 ? 4.5 : 3.5, dot);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.middle != middle || old.sides != sides || old.line != line;
}
