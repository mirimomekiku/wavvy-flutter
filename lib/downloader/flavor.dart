import 'package:flutter/services.dart' show appFlavor;

/// Whether this build includes the downloader.
///
/// The app has two flavors: `play` (no downloader, safe for the Play Store) and
/// `full` (with the yt-dlp downloader, for sideloading). Builds made without a
/// flavor, such as tests and plain `flutter run`, include it. This is a
/// compile-time constant, so the downloader's code drops out of the Play build.
const bool kDownloaderAvailable = appFlavor != 'play';

/// Whether this build includes the audio visualizer.
///
/// Like the downloader, the visualizer is left out of the `play` flavor: it
/// needs the microphone permission (Android asks for it even to read the
/// player's own audio levels), which the Play build does not declare. Builds
/// without a flavor include it. A compile-time constant, so the visualizer's
/// code drops out of the Play build.
const bool kVisualizerAvailable = appFlavor != 'play';
