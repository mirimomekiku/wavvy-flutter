# Wavvy / Kaisu companion redesign

This supersedes the pastel redesign. Kaisu remains the desktop app and Wavvy the mobile app, sharing the Mac OS X Aqua visual language rather than introducing a separate mobile brand.

## Source of the design

Inspected the existing Kaisu desktop implementation under `D:/laragon/www/kaisu`, especially `desktop/src/App.css`, `PageHeading.tsx`, `PlayerBar.tsx`, `LibraryPage.tsx`, `CustomizationSettings.tsx`, and the full-screen player styles. Kaisu itself was not modified.

The shared vocabulary is silver unified toolbars, paper content, pale blue alternating rows, blue selection, recessed LCD displays, gel buttons, connected segmented controls, compact typography, and restrained borders. The Work Sans font is converted from Kaisu's existing local font package and bundled with its OFL license. Its license is registered in Flutter's license registry. No font network request is needed.

## Screens and layout

- **Shell:** two floating silver trays: artwork, recessed title/artist/progress display and previous/play/next controls above icon-only Home / Search / Library navigation. The selected icon has a blue gel highlight; tooltips and accessibility labels identify each destination. Horizontal swipes skip tracks; tapping the display or swiping upward opens the vinyl player. Long-pressing the display opens the queue. Scrollable content has clearance below the trays.
- **Home:** compact window heading, continue-listening panel, quick controls, recently played rows, aligned recent albums, daily mix, most-played tracks and local rediscovery. Secondary recommendations follow the primary listening tasks instead of filling the initial view with shelves.
- **Library:** in-place filtering, pinned connected section controls, track count, sort menu, Play all / Shuffle, column heading, striped rows with a duration column and blue playing-row selection. Wider layouts also show album metadata. Album grids are aligned; artists use compact source-list rows; playlists have visible options.
- **Collection details:** cover and metadata share a compact inspector-style header, followed by Play / Shuffle controls, a striped track list, and persistent mini-player access.
- **Search:** source-specific draft retention, clear/submit controls, user-triggered clipboard paste for TikTok, local grouped results, and explicit YouTube loading/error/empty states. Search responses are guarded against out-of-order completion.
- **Downloads:** combined task history, active/completed counts, title search, All / Active / Completed / Failed views, progress, file opening and confirmed deletion.
- **Full player:** vinyl and tonearm retained, now in a silver deck. Connected Player / Queue / Lyrics / Artist controls sit above the content. Seeking and transport remain available on every tab. Speed, sleep timer and sound tools are direct actions; short layouts retain access through the action menu.
- **Queue:** reorder handles, remove controls and Clear upcoming. Changes update the visible queue and underlying audio-source list together.
- **Lyrics:** clearer loading/empty/error feedback, retry, readable active/inactive lines, tap-to-seek and lyric-card creation.
- **Artist:** cover/image, biography and neutral content panels. Missing configuration is presented as content unavailability rather than a technical setup instruction.
- **Settings:** compact Aqua/Graphite/System previews, checkbox preference groups, rescan, playback gestures, screen wake lock, enrichment/downloader controls, and listening-history options. Playback stays available below settings.
- **Sound:** unified heading and equalizer/effects sections, persistent mini-player, and access to the existing native reverb presets.
- **Dialogs, sheets and lyric cards:** shared typography and controls; song actions use compact native list rows instead of nested cards. Lyric cards follow the paper/Aqua system and support selecting up to four lines.
- **Startup failure:** themed, user-facing recovery guidance replaces the raw initialization exception display; diagnostic details remain in the debug log.

## Existing data and behavior

Playlists, music files, history and preference storage remain in place. Aqua is the new default (index 5), Graphite is index 6, and System remains index 2. Retired appearance indices migrate to Aqua while retaining brightness and feature preferences. Explicit theme selection disables album adaptation; Album colors remains an opt-in accent mode.

The desktop/mobile relationship implemented here is visual and organizational. No cross-device transport, synchronization, account, or remote-control service is implied.

## Verification

Final checks: **249 tests passed**, including the floating icon-only navigation and scroll clearance checks. Static analysis has **9 pre-existing informational findings**, with no errors or warnings. Thirty-eight light/dark widget previews were rendered and reviewed. An ARM64 debug build completed before the user requested that further builds and runs be left to them; no further builds are scheduled.

The widget/unit suite covers the shell, sources, library navigation/filtering/sorting, appearance persistence and migration, queue/audio-source order, stale YouTube responses, request failure/disposal, download filters, retained drafts and lyric rendering.

Screen checks cover light/dark layouts for nineteen views, the player at 320 logical pixels with enlarged text, and short landscape playback. The design intentionally retains compact desktop-like density rather than expanding every control into a mobile card.

Preview export:

```powershell
flutter test test/redesign_test.dart --dart-define=CAPTURE_PREVIEWS=true --dart-define=PREVIEW_ICON_FONT=<flutter-sdk>/bin/cache/artifacts/material_fonts/materialicons-regular.otf
```

Previews are written to `build/kaisu-previews`. Work Sans is loaded from the bundled font for preview capture; the optional local icon-font input makes native icon glyphs readable in exported test images. Test content is synthetic. These are rendered widget previews, not device screenshots.

Native audio, notification behavior, real downloads, file permissions, metadata writes and system sharing still require live-device checks in addition to compilation and widget/unit tests.
