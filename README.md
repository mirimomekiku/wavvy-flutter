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
- Sleep timer: minutes, end of the track or end of the queue, with a fade-out.
- Reopens with the queue and position you left; headphone and call handling you can tune.
- Volume leveling from ReplayGain tags; crossfade (experimental).
- Favorites with a Liked songs list, and a home-screen widget.
- Fade in and out on play and pause, and skip silence (both off by default).
- Sound: a 5-band equalizer with presets, bass boost, virtualizer, reverb and a
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

### Lyrics & metadata
- Time-synced lyrics from [LRCLib](https://lrclib.net).
- Artist biographies and photos from Genius.
- Lyric cards: pick up to four lines and share them as an image.
- Tag editing (title, artist, album, year, genre).

### Library
- Songs, albums, artists and playlists, with in-place filtering and sorting.
- Home feed built from your own listening history (incognito mode pauses it).
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
| `play` | No downloader. Safe for the Play Store. |
| `full` | Adds the yt-dlp downloader. It downloads and runs code from outside any store, so it is for sideloading only. |

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
