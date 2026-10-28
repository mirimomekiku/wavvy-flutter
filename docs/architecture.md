# Wavvy architecture

Android-only Flutter app, offline first, with optional online enrichment.

## Layers

| Layer | Files | Role |
| --- | --- | --- |
| Startup | `lib/main.dart`, `screens/startup/` | Optional services start best-effort; audio is required and failure shows the recovery screen, whose Try Again re-runs `_launch()` |
| App/theme | `wavvy_app.dart`, `theme/` | `MaterialApp`, the Aqua/Graphite/System palettes (`WvPalette`), shared widgets. Built themes are cached (`WavvyTheme`), and a theme change switches at once while `ThemeCrossFade` fades the old frame away, instead of Material's per-frame tween |
| Shell | `screens/home/home.screen.dart`, `widgets/bottom_bar.dart` | Home / Library / Search tabs, floating mini-player and nav, full player as a modal sheet |
| Playback | `providers/player_provider.dart`, `instances/audio_handler.instance.dart` | Queue, transport, shuffle/repeat, sleep timer; the handler owns the `just_audio` player, notification and fade |
| Coordination | `providers/audio_coordinator.dart` | Cross-provider effects: palette, lyrics, artist info, play logging, shake, effects session, settings, library reload |
| Library | `providers/library_provider.dart`, `playlists_provider.dart`, `home_feed_provider.dart` | Device music, SQLite playlists and history, derived Home feed |
| Online | `lyrics_provider.dart`, `artist_info_provider.dart` | LRCLib and Genius |
| Downloader (full flavor) | `lib/downloader/`, `android/app/src/full/` | yt-dlp search, downloads and publishing; see `docs/flavors.md` |
| Platform | `core/storage_permissions.dart`, `core/media_store.dart`, `core/app_restart.dart`, `MainActivity.kt` | Runtime permissions, scoped-storage consent, restart, native audio effects |

## Queue

`PlayerState.queue` has the same order as the player's audio sources, so a
queue index is a source index. Shuffle only changes the order the player visits
them in. Every queue change goes through `PlayerNotifier._edit`: one at a time,
state first, rolled back if the player rejects it. "Clear upcoming" uses the
player's effective order, so it is right with shuffle on. With shuffle on,
"Play next" queues the song but just_audio picks where it falls in the shuffled
order.

## Storage and permissions

- Library: `READ_MEDIA_AUDIO` (13+) or `READ_EXTERNAL_STORAGE`.
- Delete and tag edits: `MediaStore.createDeleteRequest` / `createWriteRequest`
  (Android 11+), the recoverable-security prompt (Android 10), plain access
  before that. Never raw `File` writes to other apps' media.
- Downloads (full flavor): staged in app-private storage, tagged, then inserted into
  `MediaStore.Audio` (`Music/Wavvy`) by the native downloader; Android 9 and below
  copy into the Music folder and need the storage permission.
- A permanent refusal is `LibraryState.permissionBlocked`; the UI then offers
  only Open Settings.

## Native effects

`MainActivity.kt` creates BassBoost, Virtualizer and PresetReverb per audio
session, each independently, and reports which exist. `EffectsNotifier` keeps
the user's values and reapplies them when the session changes. A rejected call
switches that effect off and sets `EffectsState.error`. The equalizer works in
decibels, as `just_audio` does; preset curves are interpolated across the
device's band count.

## Persistence

- SQLite (`wavvy_playlists.db`, version 3): `playlists`, `playlist_songs`
  (unique per playlist and song), `song_stats`.
- SharedPreferences: `feature_*` flags and `theme_scheme_index`. Theme index 5
  is Aqua (default), 6 Graphite, 7-12 the accents, 13 Pinstripe, 14 Brushed
  Metal; older indices (including the retired System, 2) migrate.
- Textures (`theme/wavvy_texture.dart`): Pinstripe and Brushed Metal use a tiny
  `ui.Image` tile per kind and brightness, built once from a seeded generator
  and kept (`WvTextures`). The page uses `WvBackdrop` (opaque page color, then
  one `RepaintBoundary` painting the tile shader), applied by `WvSystemUi` and
  the tab shell; their Scaffolds use `pageColor` (transparent only when
  textured), so every page is still opaque during transitions. Chrome adds
  `image: a.chromeGrain` to its `BoxDecoration` (brushed only). The other looks
  get no extra layer. Album colors tint the accent only; textures stay neutral.


## Not covered by tests

The suite uses fakes. Real playback, notification controls, native effects,
MediaStore consent dialogs, downloads and sharing need a device.
