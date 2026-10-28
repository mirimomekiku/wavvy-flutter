import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The most recent unexpected errors, newest last, for the recovery screen's
/// details and for bug reports.
final List<String> recentErrors = [];
const _maxRecent = 20;

void _remember(String what, Object error, StackTrace? stack) {
  recentErrors.add('$what: $error');
  if (recentErrors.length > _maxRecent) recentErrors.removeAt(0);
  debugPrint('$what: $error${stack == null ? '' : '\n$stack'}');
}

/// Catches what would otherwise go unseen: errors thrown while building or
/// painting (shown by Flutter as a red or grey box), and errors from futures
/// and streams nobody awaited. They are logged and remembered instead of
/// being lost, and a widget that fails to build shows a small notice in place
/// of the grey release-mode box, so one broken row does not look like a dead
/// app.
void installErrorHooks() {
  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    _remember('Flutter error', details.exception, details.stack);
    // Keep Flutter's own reporting (the console in debug builds).
    if (presentError != null) {
      presentError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    _remember('Unhandled error', error, stack);
    // Handled: it is logged, and does not take the app down in debug runs.
    return true;
  };

  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const _BrokenWidget();
  }
}

class _BrokenWidget extends StatelessWidget {
  const _BrokenWidget();

  @override
  Widget build(BuildContext context) => const Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Something went wrong here.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
        ),
      ),
    ),
  );
}
