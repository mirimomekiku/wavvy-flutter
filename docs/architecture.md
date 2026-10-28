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
| Online | `lyrics_provider.dart`, `artist_info_provider.dart` | LRCLib and Genius; album covers (`album_art_provider.dart`, `artwork/`), see "Missing album covers" |
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

## Visualizer

Full flavor only (`kVisualizerAvailable`; the Play build has neither the code nor
the permission, see `docs/flavors.md`), and off by default (`feature_visualizer`). Native: `VisualizerBridge.kt` attaches an
`android.media.audiofx.Visualizer` to the audio session (capture size up to
1024, half the maximum capture rate), turns each FFT frame into 32 log-spaced
bands in 0..1 and sends them over an EventChannel; it is released on stop, on a
new start and with the Activity. Dart: `VisualizerNotifier`
(`providers/visualizer_provider.dart`) runs it only while the setting is on, the
player's Visualizer page is showing, the app is in the foreground and music
plays; it re-attaches on a new session id, smooths the bands (fast attack, slow
decay, peak caps, `playback/visualizer_math.dart`) and reports a status (off,
needsPermission, unavailable, running). `AquaVisualizer` draws one
`CustomPainter` and respects reduced motion. Page index 4 of the player sheet
exists only when the setting is on. The permission: Android requires
`RECORD_AUDIO` even for a session's own output; it is asked when the setting is
turned on (a permanent refusal offers Open Settings and leaves it off) and
nothing is recorded or sent. Unverified without a device: the native code and
the level scaling (`kVisualizer*Db` in Dart and `FLOOR_DB`/`CEIL_DB` in Kotlin).

## Persistence

- SQLite (`wavvy_playlists.db`, version 6): `playlists`, `playlist_songs`
  (unique per playlist and song), `song_stats`, `downloads`, `favorites`,
  `play_history`.
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

## Listening history and stats

`AudioCoordinator` logs a play when a song passes its threshold (skipped in
incognito mode), next to the `song_stats` counter. `HistoryLogger`
(`playback/history.dart`) inserts one `play_history` row per play with the
title, artist, album and duration copied in, so deleted songs still show and
stats need no library join; a failed insert is logged and ignored.
`StatsSummary.fromRows` is pure: totals, estimated listening time (the summed
song lengths), top 10 songs/artists/albums (ties go to the latest play), plays
per local day for the last 14 days and the latest 100 plays. `statsProvider`
loads it for the period chosen on the Listening stats screen (Settings), and
"Clear history" deletes the table and reloads.

## Not covered by tests

The suite uses fakes. Real playback, notification controls, native effects,
MediaStore consent dialogs, downloads and sharing need a device.

## Picking several songs

A long press on a song row starts picking (`selection_provider.dart`); while
picking, a tap picks or drops a song and the selection bar
(`widgets/selection_bar.dart`) replaces the mini-player tray in
`BottomMiniPlayer`, so every screen with song lists gets it. Rows use
`SelectableSongRow` (a `WvSongRow` plus the picked state); Home and the artist
tab keep the plain row. Picking ends on a page change (a `NavigatorObserver`)
and on Back, which leaves picking first, then returns to the Home tab. Bulk
actions: `PlayerNotifier.playNextAll`, `addAllToQueue` (one `_edit`, rolled
back as a whole), `deleteSongs` (one `createDeleteRequest` on Android 11+),
`FavoritesNotifier.setAll`, `PlaylistsNotifier.addSongsToLocalPlaylist` (one
transaction) and `PlayerUtils.shareSongs`.

## Queue selection and full-screen lyrics

Queue selection (`providers/queue_selection_provider.dart`,
`player_sheets/queue_selection.dart`). A long press on a queue row starts
picking; rows are picked by queue INDEX (the same song can be queued twice), not
song id, so the song selection provider is not reused. The notifier is
`autoDispose`: leaving the Queue page or closing the sheet ends selecting, and
any queue change other than appending clears it, so indices never go stale.
While picking, the Queue header becomes a selection header (count, Select all /
none, Remove, Play next, Move to end, Add to playlist, Save as playlist) and
Back ends picking before it closes the sheet. `PlayerNotifier.removeQueueIndices`,
`moveQueueIndicesToNext` and `moveQueueIndicesToEnd` each run as one `_edit`;
their player calls (highest-first removals, `moveAudioSource` with the shifting
indices tracked) are undone in reverse if one is rejected, so a failure half way
leaves queue and sources equal. `_QueueEdit.currentIndex` sets the playing row at
once (and is rolled back with the queue). Removing the playing row is allowed
after a confirmation and works like the row's own X: the player moves on. Move
next keeps the playing row where it is as the anchor, even if it is picked. With
shuffle on, queue index is still source index; just_audio decides where a moved
source falls in the shuffled order, as with Play next.

Full-screen lyrics (`player_sheets/lyrics_fullscreen.dart`). A pushed fade route
over the sheet. It has its own `ItemScrollController` and listens to
`lyricsProvider`'s current line itself (jumping instead of animating with
reduced motion), so it never uses `lyricsScrollControllerProvider`, which the
coordinator drives for the sheet's list (it only scrolls an attached controller,
and the list detaches when disposed). Immersive sticky mode and the wake lock
(`lyricsScreenAwakeProvider`) start with the page; leaving restores edge-to-edge
and hands the wake lock back to the Settings value, not simply off. The text size
(`lyrics_fullscreen_scale`, 0.8 to 1.8) is kept in SharedPreferences. Lyrics
without timestamps (one block at time zero) are shown as plain text with no
seek.

## Volume keys and Open with

Both are a small Kotlin helper plus a Dart wrapper behind an overridable provider
(`core/volume_keys.dart`, `core/external_audio.dart`, watched in `MyApp`).

- Volume keys (`VolumeKeySkip.kt`, `MainActivity.dispatchKeyEvent`): off by
  default (`volumeKeySkip`). When on, a press is held back; released early it
  changes the music volume itself, held past the long-press time it sends `skip`
  ("next" / "previous") once. Activities only see the keys while their window has
  focus, so it does nothing with the screen off or in another app.
- Open with (`ExternalAudio.kt`, manifest `VIEW` filter, `singleTask`): the tags are
  read with `MediaMetadataRetriever` off the main thread; the launch file waits
  for Dart's `takePending`, later files are pushed. A file found in the library
  (MediaStore id) plays in the library queue; any other becomes a temporary
  `SongModel` with a negative id (`isExternal`) that plays alone. It has no
  delete, tag editing, favorites, playlists or play counter, and no artwork. The
  read permission of a content URI lasts only as long as Android keeps it for the app.

## Audio quality badges

`AudioInfo.kt` (one registration line in `MainActivity.configureFlutterEngine`) answers
the `audio_info` channel's `info` call for a content URI (or MediaStore id): it runs
`MediaExtractor` on the first audio track, then `MediaMetadataRetriever` for what is
missing, on a single background thread, releases everything in `finally` and answers
null instead of throwing. It reports mime, codec, sample rate, channels, bitrate, bit
depth, duration and lossless. Bit depth comes from the FLAC STREAMINFO header, PCM
encoding, or the retriever on Android 12+, so it (and sometimes the sample rate) can be
unknown, and then the file is never called Hi-Res. Dart (`core/audio_quality.dart`):
`AudioQuality` classifies Lossy, Lossless (FLAC, ALAC, WAV, AIFF, APE, WavPack, or the
native flag) and Hi-Res Lossless, which here means lossless, 24-bit or more and above
48 kHz (24-bit / 48 kHz stays Lossless). `audioQualityProvider` (a `FutureProvider.family`
over `QualityKey`, so one probe per song per session) merges the probe with the quick
estimate from MediaStore (extension, size / duration); a null or failed probe leaves
the estimate. The estimate shows at once, so nothing waits on the native call.
`AquaQualityBadge` (`widgets/aqua_quality_badge.dart`) is the capsule (silver, blue gel,
gold gel) used in the player's seek row (short text, scales down at large text) and at
the top of Song details, whose table adds codec, sample rate, bit depth, bitrate and
channels. Song rows do not show it: that would need a probe per row. External songs
(negative id) are probed by their content URI.

## Disc numbers

MediaStore stores `disc * 1000 + track` in the track tag and `SongModel.track` returns it
as is. `core/disc_numbers.dart`: `discOf` (1 when there is no disc part),
`trackNumberOf` (null when missing), `groupByDisc` (by disc, then track number, then
title; unnumbered songs after the numbered ones, ties in incoming order). The album screen
plays, shuffles and picks from that one ordered list; with more than one disc it adds
`DiscHeaderRow`s and puts the track number in front of the artist in each row, and a
single-disc album looks as before. Song details shows "Disc 2 - Track 3".

## Fast scroller and Home shelves

`FastScroller` (`widgets/fast_scroller.dart`) wraps the Library scroll view. A
`NotificationListener` shows a thumb while the list scrolls and hides it 1.2 s
after the last interaction; hidden, it ignores touches, and visible it only
catches a 28 px strip. Dragging sets `controller.jumpTo(fraction *
maxScrollExtent)`, so no item extents are needed. Only an overlay driven by
`ValueNotifier`s rebuilds, never the rows. The bubble shows `letterFor` of the
item at `fraction * (count - 1)`, taken from the field the songs are sorted by
(none for "Recently added", so a plain thumb); albums and artists get letters
only if `lettersAscending` says they really are alphabetical. It does nothing
under 30 items and is excluded from semantics.

`home_shelves_provider.dart` holds the pure selections. "Continue listening"
(`buildContinueListening`) maps `play_history` rows, newest first, to library
albums by song id, else by album name and artist, one tile per album, at most
10. "Rediscover" (`buildRediscover`) takes songs whose `song_stats.last_played`
is missing or older than 90 days, shuffles them with a seed from the date (plus
the Shuffle press count) and keeps 20; under 8 candidates the shelf is hidden.
Both read through `historyStoreProvider` and `songStatsStoreProvider` (fakes in
tests), follow the `showStats` setting, and the stats are read once per session.

## Missing album covers

Albums and songs with no embedded art can get a cover from MusicBrainz and the
Cover Art Archive. Off by default (`fetchMissingArt`, `feature_fetch_missing_art`,
Settings > Library & online content).

- Sent: only the album and artist names, as a MusicBrainz release search
  (`musicbrainz.org/ws/2/release/`, `release:"..." AND artist:"..."`, quotes and
  backslashes escaped), then the front image from `coverartarchive.org`
  (`/release/<mbid>/front-500`, else the release group's). Always https. Nothing
  else leaves the device. Albums with an unknown name or artist, "Various Artists"
  and singles without an album are never looked up.
- Etiquette and limits (`artwork/album_art_client.dart`): a User-Agent with the app
  name, version and a contact URL (`kArtContactUrl`, still a placeholder), one
  request per second through one shared `RateLimiter`, a 12 s timeout on every
  request, only `image/jpeg` or `image/png` whose first bytes match, at most 2 MB.
  Offline, 429/503 and malformed answers are quiet: a batch stops and nothing
  throws into the UI. The best release is chosen by normalized title and artist
  similarity times MusicBrainz's score (`artwork/album_art_match.dart`).
- Cache (`artwork/album_art_cache.dart`): `<app support dir>/album_art/<key>.jpg|png`,
  key `id<albumId>` (else a hash of the normalized artist and album), plus
  `misses.json`: a miss is not asked again for 30 days. Failures from the network are
  not recorded as misses. The folder is listed once; `albumArtIndexProvider` keeps
  the files by key in memory.
- Where it shows: `AlbumArtFallback` (`widgets/album_art_fallback.dart`) is the
  `nullArtworkWidget` of `wvArtwork` and the direct `QueryArtworkWidget`s, so every
  place that fell back to the pixel placeholder shows the cached cover when there is
  one. A row only reads memory (a `select` on its own album key). The palette and the
  home widget read a downscaled copy (`cachedArtThumbForSong`), and the notification
  gets the file as `MediaItem.artUri` (set through `WavvyAudioHandler.cachedArtUri`;
  the notification keeps the old picture until the next track).
- Triggers (`providers/album_art_provider.dart`): the Settings row "Find missing
  artwork" (shown when the setting is on) runs `AlbumArtBatchNotifier.startManual`:
  one album at a time, progress "12 of 48 albums, 9 found", Cancel, a summary; it
  lives in the notifier, so it survives leaving the screen, and a second start while
  running is ignored. With the setting on, a library load starts small automatic
  batches (25 albums, 2 minute pause, only while the app is in the foreground; an
  error or offline stops it for an hour). The album screen's cover button has "Find
  cover" (explicit tap, works with the setting off) and "Remove fetched cover".
- Albums "without art" are those for which `queryArtwork` returns null or nothing
  (`albumArtProbeProvider`); no image is decoded to find out.
- No tag writing: covers are never embedded into the audio files (that would need
  the per-file write consent of "Edit tags"). Other apps do not see them.

## Performance notes

- The seek bar reports `onChangeEnd` and the player sheet seeks once per
  gesture, not per touch event.
- `wvArtwork` asks for the size it is shown at, in device pixels.
- The Library filter is debounced and its matches are a provider
  (`librarySongsProvider`) over search keys built once per library change.
- Home, the artist tab and song rows watch only what they show.
- `ThemeCrossFade.tintKey` makes the album-color fade cheap: screen
  resolution, short, skipped while fading, in the background or when the color
  hardly changed.
- `installErrorHooks` (`core/error_hooks.dart`) logs and remembers framework
  and unhandled async errors.

