import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wavvy/core/app_restart.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// What the user is told about a failed start: a one-line cause and the steps
/// most likely to fix it, most effective first.
class StartupAdvice {
  final String summary;
  final List<String> steps;

  const StartupAdvice(this.summary, this.steps);
}

/// Turns the raw initialization error into plain advice. The raw error is only
/// shown under "Details".
StartupAdvice describeStartupFailure(Object error) {
  final text = error.toString().toLowerCase();

  // Android 12+ refuses to start the playback service from the background.
  if (text.contains('foreground') || text.contains('notallowed')) {
    return const StartupAdvice(
      'Android would not let Wavvy start its playback service.',
      [
        'Tap Try Again while Wavvy is open on screen.',
        'In Settings > Apps > Wavvy > Battery, choose Unrestricted.',
        'Tap Restart Wavvy, or restart your phone.',
      ],
    );
  }

  // The audio session is held by a call or another app.
  if (text.contains('audiosession') ||
      text.contains('audio_session') ||
      text.contains('audio focus') ||
      text.contains('audiomanager')) {
    return const StartupAdvice(
      'Your phone’s audio is busy with something else.',
      [
        'Finish any call and close apps that play or record audio.',
        'Tap Try Again.',
        'Tap Restart Wavvy, or restart your phone.',
      ],
    );
  }

  return const StartupAdvice(
    'Wavvy could not set up audio playback on this device.',
    [
      'Tap Try Again.',
      'Close apps that play or record audio, then try again.',
      'Tap Restart Wavvy, or restart your phone if it keeps happening.',
    ],
  );
}

/// The app shown when audio cannot be initialized: nothing else in Wavvy can
/// work without it. Self-contained (no providers) and follows the system
/// light/dark setting.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({
    super.key,
    required this.error,
    required this.onRetry,
    this.onRestart = restartApp,
  });

  final Object error;

  /// Runs the startup again. The caller replaces this app when it succeeds or
  /// fails again.
  final Future<void> Function() onRetry;
  final Future<void> Function() onRestart;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wavvy',
      debugShowCheckedModeBanner: false,
      theme: WavvyTheme.light(WvAppearance.aqua),
      darkTheme: WavvyTheme.dark(WvAppearance.aqua),
      themeMode: ThemeMode.system,
      home: StartupFailureScreen(
        error: error,
        onRetry: onRetry,
        onRestart: onRestart,
      ),
    );
  }
}

/// A Mac OS X style alert window: silver title bar with the traffic lights, a
/// gel orb, the explanation, and Try Again / Restart buttons.
class StartupFailureScreen extends StatefulWidget {
  const StartupFailureScreen({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onRestart,
  });

  final Object error;
  final Future<void> Function() onRetry;
  final Future<void> Function() onRestart;

  @override
  State<StartupFailureScreen> createState() => _StartupFailureScreenState();
}

class _StartupFailureScreenState extends State<StartupFailureScreen> {
  bool _retrying = false;
  bool _details = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      // On success or failure the caller normally replaces this screen; this
      // only matters if it is still showing.
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _copyDetails() async {
    await Clipboard.setData(ClipboardData(text: widget.error.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Details copied')));
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final advice = describeStartupFailure(widget.error);

    return Scaffold(
      backgroundColor: a.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: DecoratedBox(
                key: const Key('startup_failure_window'),
                decoration: a.frame(color: a.surface, radius: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TitleBar(color: a),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const AquaOrb(
                                  icon: Icons.headset_off_rounded,
                                  size: 64,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Playback could not start',
                                        style: TextStyle(
                                          color: a.text,
                                          fontSize: 17,
                                          height: 1.25,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        advice.summary,
                                        style: TextStyle(
                                          color: a.textSecondary,
                                          fontSize: 13,
                                          height: 1.45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            DecoratedBox(
                              decoration: a.lcdDecoration.copyWith(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  12,
                                  14,
                                  12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'What you can do',
                                      style: TextStyle(
                                        color: a.text,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    for (
                                      var i = 0;
                                      i < advice.steps.length;
                                      i++
                                    )
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            SizedBox(
                                              width: 20,
                                              child: Text(
                                                '${i + 1}.',
                                                style: TextStyle(
                                                  color: a.textSecondary,
                                                  fontSize: 12.5,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                advice.steps[i],
                                                style: TextStyle(
                                                  color: a.text,
                                                  fontSize: 12.5,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                key: const Key('startup_details_toggle'),
                                onPressed: () =>
                                    setState(() => _details = !_details),
                                icon: Icon(
                                  _details
                                      ? Icons.keyboard_arrow_down_rounded
                                      : Icons.chevron_right_rounded,
                                  size: 18,
                                ),
                                label: const Text('Details'),
                              ),
                            ),
                            if (_details)
                              Container(
                                key: const Key('startup_details'),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: a.surfaceHighest,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: a.separator),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SelectableText(
                                      widget.error.toString(),
                                      style: TextStyle(
                                        color: a.textSecondary,
                                        fontSize: 11,
                                        height: 1.4,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    TextButton(
                                      onPressed: _copyDetails,
                                      child: const Text('Copy details'),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 14),
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                WvButton(
                                  key: const Key('startup_restart'),
                                  width: 140,
                                  size: 36,
                                  onPressed: _retrying
                                      ? null
                                      : () => widget.onRestart(),
                                  child: const Text('Restart Wavvy'),
                                ),
                                WvButton(
                                  key: const Key('startup_retry'),
                                  width: 120,
                                  size: 36,
                                  primary: true,
                                  onPressed: _retrying ? null : _retry,
                                  child: _retrying
                                      ? const AquaSpinner(
                                          size: 18,
                                          color: Colors.white,
                                        )
                                      : const Text('Try Again'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The silver title bar with the three window buttons, as on Mac OS X.
class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.color});
  final WvPalette color;

  @override
  Widget build(BuildContext context) {
    final a = color;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        gradient: a.chromeGradient,
        border: Border(
          bottom: BorderSide(color: a.outline.withValues(alpha: 0.55)),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Decorative: the alert has no window controls of its own.
          const ExcludeSemantics(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TrafficLight(Color(0xFFFF5F57)),
                  SizedBox(width: 7),
                  _TrafficLight(Color(0xFFFEBC2E)),
                  SizedBox(width: 7),
                  _TrafficLight(Color(0xFF28C840)),
                ],
              ),
            ),
          ),
          Text(
            'Wavvy',
            style: TextStyle(
              color: a.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficLight extends StatelessWidget {
  const _TrafficLight(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
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
}
