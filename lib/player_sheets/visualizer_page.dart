import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/visualizer_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/aqua_visualizer.dart';
import 'package:wavvy/widgets/status_message.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

/// The Visualizer tab of the full player sheet. The native visualizer runs
/// only while [active] (this is the page on screen), the app is in the
/// foreground and music plays; the notifier handles the rest.
class VisualizerPage extends ConsumerStatefulWidget {
  const VisualizerPage({super.key, required this.song, required this.active});
  final SongModel song;
  final bool active;

  @override
  ConsumerState<VisualizerPage> createState() => _VisualizerPageState();
}

class _VisualizerPageState extends ConsumerState<VisualizerPage>
    with WidgetsBindingObserver {
  late final VisualizerNotifier _notifier = ref.read(
    visualizerProvider.notifier,
  );
  bool _foreground = true;

  void _sync() => _notifier.setVisible(widget.active && _foreground);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void didUpdateWidget(VisualizerPage old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifier.setVisible(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final status = ref.watch(visualizerProvider.select((s) => s.status));
    final blocked = ref.watch(visualizerProvider.select((s) => s.blocked));
    if (status == VisualizerStatus.needsPermission) {
      return WvStatusMessage(
        icon: Icons.mic_off_rounded,
        title: 'Microphone permission needed',
        message:
            'Android only lets Wavvy read its own audio levels with the '
            'microphone permission. Nothing is recorded or sent anywhere.',
        action: WvButton(
          primary: true,
          size: 40,
          width: 200,
          onPressed: blocked
              ? _notifier.openSystemSettings
              : _notifier.grantPermission,
          child: Text(blocked ? 'Open Settings' : 'Grant permission'),
        ),
      );
    }
    if (status == VisualizerStatus.unavailable) {
      return const WvStatusMessage(
        icon: Icons.graphic_eq_rounded,
        title: 'Visualizer unavailable',
        message:
            'This device would not give Wavvy its audio levels. You can turn '
            'the visualizer off in Settings.',
      );
    }
    final song = widget.song;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: a.outline.withValues(alpha: 0.6),
                      ),
                      borderRadius: BorderRadius.circular(16),
                      color: const Color(0xFF10161B),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // The album art, blurred and dimmed behind the bars.
                        ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: 22,
                            sigmaY: 22,
                            tileMode: TileMode.clamp,
                          ),
                          child: FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox.square(
                              dimension: 200,
                              child: wvArtwork(
                                context,
                                id: song.id,
                                type: ArtworkType.AUDIO,
                                size: 200,
                                placeholder: Icons.music_note_rounded,
                              ),
                            ),
                          ),
                        ),
                        ColoredBox(color: Colors.black.withValues(alpha: 0.6)),
                        Consumer(
                          builder: (context, ref, _) {
                            final bands = ref.watch(
                              visualizerProvider.select((s) => s.bands),
                            );
                            final peaks = ref.watch(
                              visualizerProvider.select((s) => s.peaks),
                            );
                            return AquaVisualizer(
                              bands: bands,
                              peaks: peaks,
                              panel: false,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: a.text,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                song.artist ?? 'Unknown Artist',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: a.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
