# Wavvy
***An offline music player for Android, built with Flutter, in the Mac OS X Aqua style of its desktop sibling Kaisu.***

Wavvy plays the music already on your phone and adds synced lyrics and artist
information when you are online. The **full** build can also search online and
download audio with [yt-dlp](https://github.com/yt-dlp/yt-dlp); the **Play**
build has no downloader (see [Builds](#builds)).

## Features

### Playback & audio
- Gapless playback of MP3, FLAC, M4A, WAV and anything else Android can decode.
- Background playback with notification and lock-screen controls.
- Editable queue: play next, add, reorder, remove, clear upcoming.
- Shuffle, repeat, speed and pitch (remembered per album), A-B loop and 15 second skips.
- Sleep timer: minutes, end of the track, after N tracks or end of the queue, with a
  fade-out. Add time from the dialog, or by shaking the phone near the end.
- Smart shuffle: keeps an artist's songs apart and favors liked and less played songs.
- Reopens with the queue and position you left; headphone and call handling you can tune.
- Volume leveling from ReplayGain tags; crossfade (experimental).
- Quality badge in the player and Song details: codec, bitrate, sample rate and bit
  depth, marked Lossy, Lossless or Hi-Res Lossless (sample rate and bit depth can be
  unknown for some files).
- Favorites with a Liked songs list, and a home-screen widget.
- Hold volume up for the next song and volume down for the previous one (Settings,
  off by default). Android only passes the keys to Wavvy while it is on screen, so
  this does not work with the screen off or in another app.
- Open with Wavvy: audio files from a file manager or another app play in Wavvy.
  Files outside your library play as temporary queue items (no delete, tag
  editing, favorites or playlists).
- Fade in and out on play and pause, and skip silence (both off by default).
- Sound: a 5-band equalizer with 19 presets, your own saved presets and a preamp
  that prevents clipping, bass boost, virtualizer, reverb and a
  volume boost. Effects the device does not support are shown as unavailable.

### Look and feel
- Aqua design: silver toolbars, recessed LCD display, gel buttons, paper content.
- Appearances: Aqua (default), Graphite and System (Material You wallpaper
  colors), each in light and dark.
- **Pinstripe** (Mac OS X Panther: fine horizontal pinstripes on the page) and
  **Brushed Metal** (Tiger: brushed-aluminum grain on toolbars, trays, sheet
  headers and the page, steel-blue accent), each in light and dark.
- Optional **Album colors**: tint the whole app from the current artwork.
- A vinyl-and-tonearm player sheet with Player, Queue, Lyrics and Artist tabs.
- Optional **Visualizer** tab (full build only, off by default): a real spectrum,
  in Aqua gel bars, from Android's audio-effects `Visualizer` on Wavvy's own
  audio session. Android requires the microphone permission for this; nothing is
  recorded or sent. The Play build has no visualizer and does not ask for it.

### Lyrics & metadata
- Time-synced lyrics from [LRCLib](https://lrclib.net).
- Artist biographies and photos from Genius.
- Missing album covers from MusicBrainz and the Cover Art Archive: off by default
  (Settings > Find missing album covers); sends only album and artist names, keeps the
  pictures in the app's private folder and never writes into your music files. A "Find
  cover" action on each album works even with the setting off.
- Lyric cards: pick up to four lines and share them as an image.
- Tag editing (title, artist, album, year, genre).

### Library
- Songs, albums, artists and playlists, with in-place filtering and sorting.
- Multi-disc albums: tracks grouped under Disc 1, Disc 2 and so on, played in disc and
  track order.
- A fast scroller on long lists (30+ items): drag the thumb to scrub, with a
  letter bubble for the Title and Artist sorts.
- Home shelves "Continue listening" (albums you played lately) and
  "Rediscover" (songs not played in 90 days, re-rollable with Shuffle).
- Select several songs (long press) to play, queue, add to a playlist, like, share
  or delete them together.
- Home feed built from your own listening history (incognito mode pauses it).
- Listening stats: plays, top songs, artists and albums, a 14-day activity
  chart and a recent-plays list, with a clear-history option (Settings).
- Search your library. In the full build, also search online or paste a link
  (YouTube, TikTok and many other sites) and download the audio into your
  library, tagged with title, artist and cover.

## Permissions

| Android | What Wavvy asks for |
| --- | --- |
| 13+ | `READ_MEDIA_AUDIO` to list your music; notifications for playback controls |
| 6 to 12 | `READ_EXTERNAL_STORAGE` to list your music |
| 9 and below | also `WRITE_EXTERNAL_STORAGE`, to add downloads to your music folder |

Editing tags or deleting a song needs no standing permission on Android 10+:
Android shows its own confirmation each time. Downloads (full build) are saved
to `Music/Wavvy` in your music library.

If access is refused for good, Wavvy shows an **Open Settings** button instead
of asking again. The library stays empty until music access is granted.

## Builds

| Flavor | What it is |
| --- | --- |
| `play` | No downloader and no visualizer (so no microphone permission). Safe for the Play Store. |
| `full` | Adds the yt-dlp downloader and the visualizer. The downloader downloads and runs code from outside any store, so this build is for sideloading only. yt-dlp is checked against its release's published SHA-256 before it runs (see `docs/flavors.md`). |

```sh
flutter run --flavor full      # or: --flavor play
flutter build apk --flavor full --release
flutter build appbundle --flavor play --release
```

Plain `flutter run` uses `full`. See [docs/flavors.md](docs/flavors.md).

## If playback cannot start

Wavvy cannot run without its audio service. If it fails to start, an alert
explains the likely cause and offers **Try Again** and **Restart Wavvy**. The
raw error is under **Details**, with a copy button.

## Developing

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

- Artist information needs a Genius token: put `GENIUS_ACCESS_TOKEN=...` in a
  `.env` file at the project root (it is gitignored and bundled as an asset).
- `docs/architecture.md` describes how the app is put together.
- `docs/kaisu-companion-redesign.md` records the Aqua design.
- `flutter_riverpod` and `dynamic_color` are held on their current major
  versions on purpose; see the notes in `pubspec.yaml`.
