# Pastel redesign

Historical implementation notes. Superseded by [the Kaisu companion redesign](kaisu-companion-redesign.md).

Implemented 2026-10-27, against the existing modified working tree.

## Visual changes

- Shared pastel surfaces, outlined frames, subtle gradients, raised control edges, compact segmented tabs, framed artwork, grouped settings, and serif headings with offline system body/monospace fonts.
- Home, Library and its four sections, album/artist/playlist details, Search and its sources, mini-player, all full-player tabs, settings, audio controls, lyric-card editor and shared dialogs/sheets use the revised system.
- The full player features a procedural vinyl record and tonearm with album artwork as its center label. Rotation follows play/pause, honors reduced motion and stops when its route is hidden. Existing double-tap seeking remains available.
- The transport controls sit in a framed dock with a simple thin seek slider.
- Presets: Mint, Rose, System, Lilac and Peach, with light/dark variants. Existing preference indices 0-2 remain valid; indices 3-4 add Lilac/Peach. New installs default to Lilac without automatic album colors. Selecting a preset disables album adaptation; users can explicitly enable Album colors again. Existing saved preferences are retained.
- Downloads now filters task titles using the search field and provides a no-matches state.

## Scope

The audio engine, background service, database, permissions and download integrations retain their existing responsibilities. This implementation does not introduce a sequencer, cassette skin, particles, grain, arbitrary per-part color editing or named custom presets.

## Verification

The full suite passes: **218 tests**. Static analysis reports **9 pre-existing informational findings**, with no warnings or errors (the sharing deprecations identified in the audit were resolved). Additional tests cover preset precedence/persistence, Downloads filtering, light/dark layouts for ten major screens, and full-player tab navigation at 320 logical pixels with 1.5x text. Existing coverage includes navigation, local feed/search, library sections, theme readability, text scaling and mini-player opening.

Twenty light/dark screen previews were exported and visually reviewed. Preview fixtures include populated album and playlist details. The lyric export now uses the pastel card treatment and the current SharePlus API.

The ARM64 Android debug build succeeded with `flutter build apk --debug --no-pub --target-platform android-arm64`. Artifact: `build/app/outputs/flutter-apk/app-debug.apk`. Initial attempts encountered an external Gradle shutdown and a shared native-library file lock while another Flutter run was using the checkout; the final retry completed successfully. Existing Gradle/AGP/Kotlin future-compatibility notices remain.

`test/redesign_test.dart` can optionally export previews to `build/redesign-previews`:

```powershell
flutter test test/redesign_test.dart --dart-define=CAPTURE_PREVIEWS=true --dart-define=PREVIEW_FONT_DIR=C:/Windows/Fonts --dart-define=PREVIEW_ICON_FONT=<flutter-sdk>/bin/cache/artifacts/material_fonts/materialicons-regular.otf
```

The preview-only font inputs are optional local font files used to render readable test images; they are not bundled or redistributed. Normal tests do not require these files. Device fonts may differ from preview fonts. Preview data and artwork are deterministic fixtures, not a scan of the user's music.

Live-device validation of audio playback, notification controls, effects, third-party downloads, file operations and sharing remains separate from widget/layout verification.
