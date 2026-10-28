# Wavvy / Kaisu companion redesign

This supersedes the pastel redesign. Kaisu remains the desktop app and Wavvy the mobile app, sharing the Mac OS X Aqua visual language rather than introducing a separate mobile brand.

## Source of the design

Inspected the existing Kaisu desktop implementation under `D:/laragon/www/kaisu`, especially `desktop/src/App.css`, `PageHeading.tsx`, `PlayerBar.tsx`, `LibraryPage.tsx`, `CustomizationSettings.tsx`, and the full-screen player styles. Kaisu itself was not modified.

The shared vocabulary is silver unified toolbars, paper content, pale blue alternating rows, blue selection, recessed LCD displays, gel buttons, connected segmented controls, compact typography, and restrained borders. The Work Sans font is converted from Kaisu's existing local font package and bundled with its OFL license. Its license is registered in Flutter's license registry. No font network request is needed.

## Screens and layout

- **Shell:** two floating silver trays: artwork, recessed title/artist/progress display and previous/play/next controls above icon-only Home / Search / Library navigation. The selected icon has a blue gel highlight; tooltips and accessibility labels identify each destination. Horizontal swipes skip tracks; tapping the display or swiping upward opens the vinyl player. Long-pressing the display opens the queue. Scrollable content has clearance below the trays.
- **Home:** a stack of Aqua windows (silver title bar over paper): continue listening with an LCD readout and Play / Shuffle / Albums / Downloads, a library readout (songs, albums, artists, playlists, total time), quick access to playlists and albums, recently played, recently added albums, top artists, the daily mix, more from your top artist, on repeat, new songs, your playlists and rediscover. Sections built from listening history follow the Personalized Home setting.
- **Library:** in-place filtering, pinned connected section controls, track count, sort menu, Play all / Shuffle, column heading, striped rows with a duration column and blue playing-row selection. Wider layouts also show album metadata. Album grids are aligned; artists use compact source-list rows; playlists have visible options.
- **Collection details:** cover and metadata share a compact inspector-style header, followed by Play / Shuffle controls, a striped track list, and persistent mini-player access.
- **Search:** the source chooser is two icons (Library, Online) in the toolbar under the subtitle, with a Downloads icon beside Settings that opens the history as a full-screen Aqua sheet. Online is one field: a pasted link is looked up, anything else is searched on YouTube. Until the downloader is set up, Online shows a setup card. The Online source, Downloads icon and the downloader's Settings group exist only in the full build (see docs/flavors.md).
- **Downloads:** task history with active/completed counts, title and artist search, All / Active / Completed / Failed views, progress, cancel, retry (with the reason a download failed), play, and Remove from list or Delete file.
- **Full player:** vinyl and tonearm retained, now in a silver deck. Connected Player / Queue / Lyrics / Artist controls sit above the content. Seeking and transport remain available on every tab. Speed, sleep timer and sound tools are direct actions; short layouts retain access through the action menu.
- **Queue:** reorder handles, remove controls and Clear upcoming. Changes update the visible queue and underlying audio-source list together.
- **Lyrics:** clearer loading/empty/error feedback, retry, readable active/inactive lines, tap-to-seek and lyric-card creation.
- **Artist:** three Aqua windows: the artist (photo, name and an LCD readout of tracks, albums and playing time), the biography from Genius (collapsible when long, with loading, unavailable and retry states) and their songs in your library.
- **Settings:** compact Aqua/Graphite/System previews, checkbox preference groups, rescan, playback gestures, screen wake lock, enrichment/downloader controls, and listening-history options. Playback stays available below settings.
- **Sound:** a unified toolbar that paints behind the status bar, with Equalizer / Effects in the toolbar. Equalizer: an enable switch and a preset pop-up, then a graphic equalizer of vertical Aqua sliders with LCD dB readouts. Effects: bass boost and virtualizer on horizontal Aqua sliders with LCD percentages, a reverb pop-up and a volume boost switch. Unsupported effects are shown as unavailable.
- **Dialogs, sheets and lyric cards:** modal bottom sheets are Aqua sheets: a silver title bar with the red close light over paper, and grouped source-list menus with pale blue striping. A pressed row fills with the blue gel selection and turns white. The song menu shows the song in an LCD header, then Queue, Sound, About and Delete groups; Add to Playlist offers New Playlist. Dialogs and lyric cards share the same typography and controls.
- **Toasts, check marks and spinners:** toasts are Mac OS X heads-up panels (dark, glossy, with a gel orb that carries a check, an exclamation or an info mark). The check mark is the same blue gel orb, and the spinner is the twelve-spoke Aqua activity indicator, which holds still when animations are reduced.
- **Startup failure:** an Aqua alert window (silver title bar with traffic lights, gel orb, recessed steps panel) explains the likely cause, offers Try Again and Restart Wavvy, and keeps the raw error under Details with Copy.

## Existing data and behavior

Playlists, music files, history and preference storage remain in place. Aqua is the default (index 5) and Graphite is 6. The accent colors are Kaisu's: Aqua's blue turned around the color wheel by the same angles (orange 175, green 265, purple 65, pink 115, red 145, teal 320 degrees) with contrast kept readable, saved as 7 to 12. Pinstripe (13) and Brushed Metal (14) are two textured looks from Mac OS X: Panther's horizontal pinstripes (1 px every 3 px, a faint tint of the page) behind Aqua-blue gel, and Tiger's brushed aluminum (seeded horizontal grain over a silver gradient, steel-blue accent) on toolbars, trays, sheet headers and the page, each with a dark version. The texture is a cached tile painted once behind each screen. The System (wallpaper) theme is gone. Older saved themes are carried over (Mint to Green, Rose to Red, Lilac to Purple, Peach to Orange, System to Aqua), keeping brightness and feature preferences. Explicit theme selection disables album adaptation; Album colors remains an opt-in accent mode.

The desktop/mobile relationship implemented here is visual and organizational. No cross-device transport, synchronization, account, or remote-control service is implied.

## Verification

Final checks: **399 tests passed** (3 skipped), including the floating icon-only navigation and scroll clearance checks, the startup-failure screen and the effects and queue logic. Static analysis is clean. Thirty-eight light/dark widget previews were rendered and reviewed. An ARM64 debug build completed before the user requested that further builds and runs be left to them; no further builds are scheduled.

The widget/unit suite covers the shell, sources, library navigation/filtering/sorting, appearance persistence and migration, queue/audio-source order, stale YouTube responses, request failure/disposal, download filters, retained drafts and lyric rendering.

Screen checks cover light/dark layouts for nineteen views, the player at 320 logical pixels with enlarged text, and short landscape playback. The design intentionally retains compact desktop-like density rather than expanding every control into a mobile card.

Preview export:

```powershell
flutter test test/redesign_test.dart --dart-define=CAPTURE_PREVIEWS=true --dart-define=PREVIEW_ICON_FONT=<flutter-sdk>/bin/cache/artifacts/material_fonts/materialicons-regular.otf
```

Previews are written to `build/kaisu-previews`. Work Sans is loaded from the bundled font for preview capture; the optional local icon-font input makes native icon glyphs readable in exported test images. Test content is synthetic. These are rendered widget previews, not device screenshots.

Native audio, notification behavior, real downloads, file permissions, metadata writes and system sharing still require live-device checks in addition to compilation and widget/unit tests.
