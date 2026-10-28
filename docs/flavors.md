# Flavors, the downloader and the visualizer

Wavvy is built in two flavors from one code base.

| | `play` | `full` |
| --- | --- | --- |
| Downloader | none | yt-dlp |
| Visualizer | none | spectrum page in the player |
| Intended for | Google Play | sideloading |
| Native code | no Python | embedded Python (arm64 only) |
| Extra permissions | none | `FOREGROUND_SERVICE_DATA_SYNC`, `RECORD_AUDIO` (visualizer) |
| Install size | smaller | larger (Python runtime) |

```sh
flutter run --flavor full            # default when no flavor is given
flutter run --flavor play
flutter build apk --flavor full --release
flutter build appbundle --flavor play --release
flutter test --flavor play test/flavor_test.dart
```

## How the split works

- **Dart:** `kDownloaderAvailable` (`lib/downloader/flavor.dart`) is a compile-time
  constant from Flutter's `appFlavor`. Every entry point to the downloader
  (the Online search source, the Downloads icon, the Settings group, the Home
  button, the providers started in `main.dart`) is behind it or behind
  `SettingsState.downloaderOn`, so the code is removed from the Play build.
  `kVisualizerAvailable` (same file) does the same for the visualizer: the
  Settings toggle and the player sheet's Visualizer page are behind it.
  Builds without a flavor (tests, IDE runs) count as `full`.
- **Android:** `app/src/full/` holds the real `YtDlpPlugin`, `YtDlpRunner` and
  `YtDlpService`, the service declaration and permission, and the Gradle
  dependency (`fullImplementation`). `app/src/play/` holds a no-op `YtDlpPlugin`
  with the same name, so `MainActivity` is identical in both flavors. The
  visualizer works the same way: the real `VisualizerBridge` and the
  `RECORD_AUDIO` permission are in `app/src/full/`, and `app/src/play/` has a
  no-op `VisualizerBridge`, so the Play build has no visualizer code and does
  not declare the microphone permission.
- **Packaging:** the full flavor extracts native libraries to disk
  (`useLegacyPackaging`) so Python can run as a process, and is limited to
  `arm64-v8a`.

## The downloader (full flavor)

- **Engine.** The app downloads yt-dlp the first time the downloader is used
  (Online search shows a "Set up the downloader" card, or Settings > Downloader)
  and checks for an update about once a day. The Python runtime comes from
  [youtubedl-android](https://github.com/yausername/youtubedl-android); the
  library also contains a copy of yt-dlp, but Wavvy treats the downloader as set up
  only after it has fetched the current one.
- **Search.** One field: a link is resolved (`yt-dlp --dump-single-json`),
  anything else is searched on YouTube (`ytsearch`).
- **Download.** Audio only (`bestaudio[ext=m4a]/bestaudio`), one download at a time,
  in a foreground service with a notification. The file lands in private
  storage, is tagged with `MetadataGod` (title, artist, cover), then published to
  `Music/Wavvy` through MediaStore, and the library is rescanned.
- **Tasks.** Kept in the `downloads` table (database version 4), so retry,
  cancel, failure reasons and recovery after a restart work. A download that
  finishes while the UI is gone is held natively until the app acknowledges it.
- **Replace the backend.** `YtDlpEngine` (`lib/downloader/engine.dart`) is the
  interface; tests use `FakeYtDlpEngine`.

## Limits

- Not Play-compatible: it downloads and runs code from outside the store, and
  downloading from YouTube or TikTok is against their terms.
- yt-dlp may still be blocked by a site (for example YouTube's bot check on a
  flagged network); the error says so.
- No ffmpeg: audio is saved as the site provides it (usually m4a or opus). The
  checksum of the downloaded yt-dlp is not verified by Wavvy; the update comes
  from the library's own update call.
- TikTok audio-only extraction is not included.

## The visualizer (full flavor)

The player's optional Visualizer page uses Android's `Visualizer` effect, which
only works if the app holds `RECORD_AUDIO`, even though it reads Wavvy's own
audio session and nothing is recorded. Because the Play build must not ask for
a microphone permission, the visualizer is not part of it: the permission is in
`app/src/full/AndroidManifest.xml`, the setting is hidden and the page does not
exist in the Play flavor. In the `full` flavor the permission is only requested
when the user turns the Visualizer on in Settings.

## Checking a build

```sh
# Tests that follow the flavor (run both):
flutter test test/flavor_test.dart
flutter test --flavor play test/flavor_test.dart

# The Play APK has no downloader code, text, native libraries or permission:
flutter build apk --release --flavor play --target-platform android-arm64
unzip -p build/app/outputs/flutter-apk/app-play-release.apk lib/arm64-v8a/libapp.so \
  | strings | grep -ci "yt-dlp\|Set up the downloader"        # expect 0
unzip -p build/app/outputs/flutter-apk/app-play-release.apk lib/arm64-v8a/libapp.so \n  | strings | grep -ci "Visualizer unavailable\|visualizer_frames"   # expect 0
unzip -l build/app/outputs/flutter-apk/app-play-release.apk | grep -ci "libpython\|libqjs"  # expect 0
```

Entry points to the downloader must be guarded by `kDownloaderAvailable` directly
(`if (kDownloaderAvailable) ...`), and entry points to the visualizer by
`kVisualizerAvailable`. A runtime local such as `if (enabled)` keeps
the code in the build, because the compiler cannot prove it false.
