import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/vinyl_deck.dart';

class AnimatedSeekableArtwork extends ConsumerStatefulWidget {
  final SongModel song;
  final double size;
  final Color iconColor;

  const AnimatedSeekableArtwork({
    super.key,
    required this.song,
    required this.size,
    required this.iconColor,
  });

  @override
  ConsumerState<AnimatedSeekableArtwork> createState() =>
      _AnimatedSeekableArtworkState();
}

class _AnimatedSeekableArtworkState
    extends ConsumerState<AnimatedSeekableArtwork> {
  bool _showForward = false;
  bool _showRewind = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _triggerOverlay({required bool forward}) {
    _timer?.cancel();
    setState(() {
      if (forward) {
        _showForward = true;
        _showRewind = false;
      } else {
        _showRewind = true;
        _showForward = false;
      }
    });

    // Hide after 600ms
    _timer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _showForward = false;
          _showRewind = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: VinylDeck(
            playing: ref.watch(playerProvider.select((s) => s.isPlaying)),
            label: QueryArtworkWidget(
              id: widget.song.id,
              type: ArtworkType.AUDIO,
              artworkFit: BoxFit.cover,
              artworkBorder: BorderRadius.zero,
              artworkWidth: widget.size,
              artworkHeight: widget.size,
              size: 1000,
              nullArtworkWidget: WvMediaPlaceholder(
                seed: widget.song.id,
                size: widget.size,
              ),
            ),
          ),
        ),

        Positioned(
          left: 0,
          right: widget.size / 2,
          child: _buildOverlayIcon(
            context,
            isVisible: _showRewind,
            icon: Icons.replay_10_rounded,
            text: "-10",
          ),
        ),

        Positioned(
          left: widget.size / 2,
          right: 0,
          child: _buildOverlayIcon(
            context,
            isVisible: _showForward,
            icon: Icons.forward_10_rounded,
            text: "+10",
          ),
        ),

        if (ref.watch(settingsProvider.select((s) => s.enableDoubleTapSeek)))
          Positioned.fill(
            child: Row(
              children: [
                // LEFT (Rewind)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: () {
                      _triggerOverlay(forward: false);
                      ref
                          .read(playerProvider.notifier)
                          .seek(const Duration(seconds: -10), relative: true);
                    },
                    child: Container(color: Colors.transparent),
                  ),
                ),
                const Expanded(flex: 1, child: SizedBox()),
                // RIGHT (Forward)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: () {
                      _triggerOverlay(forward: true);
                      ref
                          .read(playerProvider.notifier)
                          .seek(const Duration(seconds: 10), relative: true);
                    },
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildOverlayIcon(
    BuildContext context, {
    required bool isVisible,
    required IconData icon,
    required String text,
  }) {
    final a = Wv.of(context);
    return AnimatedScale(
      duration: const Duration(milliseconds: 300),
      curve: Ds.spring,
      scale: isVisible ? 1.0 : 0.6,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        opacity: isVisible ? 1.0 : 0.0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: a.primaryContainer.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: a.onPrimaryContainer, size: 32),
                Text(
                  text,
                  style: TextStyle(
                    color: a.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
