# Playback features

What the audio core does beyond play, pause and queue, and where it lives
(`lib/playback/`, `lib/instances/`).

| Feature | Where | Notes |
| --- | --- | --- |
| Resume last session | `session.dart`, `coordination.dart`, `PlayerNotifier.restoreSession` | The queue is saved as song ids, with the index, position, shuffle and repeat. It is reopened paused once the library is known. Songs that were deleted are dropped. Setting: Resume last session. |
| Audio focus and headphones | `focus.dart`, `coordination.dart`, the handler | Wavvy handles calls, notifications and headphones itself (the player's own handling is switched off) so the settings apply: pause on unplug, lower the volume instead of pausing, resume after interruptions, resume when headphones return within ten minutes. |
| Volume leveling (ReplayGain) | `replay_gain.dart` | Reads the ReplayGain tags of the file (ID3, Vorbis/FLAC/Opus, APE, MP4), track or album mode. A cut lowers the player volume; a lift (capped at 9 dB, and kept under the peak) goes through the loudness enhancer. Files without tags are not changed; loudness is not measured. |
| Sleep timer | `PlayerNotifier`, the handler | Minutes (shows the time it ends), end of this track, or end of the queue, each with a slow fade-out. |
| Smart shuffle | `smart_shuffle.dart`, `PlayerNotifier` | Songs go in a weighted random order (liked songs and songs played less come earlier), then the same artist is kept apart when another artist is near by. A fresh order is made each time shuffle is turned on, with the current song first. Songs added later go to a random place. Setting: Smart shuffle. |
| Crossfade | `crossfade.dart`, `instances/crossfader.dart` | Experimental, off by default (2 to 12 s). See below. |
| Favorites | `favorites.dart` | A heart on the player and in the song menu, a Liked songs list in Library and on Home. Table `favorites` (database version 5). |
| A-B loop, 15 s skip | `ab_loop.dart`, the player | One button: set A, set B, clear. The loop is marked on the seek bar and belongs to one song. Jumps are checked on each position tick (about 200 ms). |
| Remembered speed | `rates.dart` | Speed and pitch are kept per album (or per folder without one) and applied when the album changes. Setting: Remember speed. |
| Home-screen widget | `core/home_widget.dart`, `android/.../widget/` | Shows the playing song and previous / play-pause / next. The buttons send media-button events to audio_service, like a headset does. |

## Crossfade

One just_audio player can only play one track, so a second player plays the
incoming track while the first fades out (equal-power curve). Afterwards the
first player is moved into the next track at the same point and the second one
is stopped, so the queue, notification and effects still only deal with one
player.

Limits, which need checking on a device:

- The second player has its own equalizer and loudness enhancer, copied from the
  first when the crossfade starts. Bass boost, virtualizer and reverb belong to
  the first player's audio session, so they are not heard on the incoming track
  until the hand-over.
- The hand-over seeks the first player, which can cause a short gap on slow
  storage; if anything goes wrong the crossfade is abandoned and the track
  changes normally.
- Consecutive tracks that are meant to run together (live albums, mixes) are
  crossfaded too; there is no per-album exception yet.
- Tracks shorter than twice the fade plus two seconds are not crossfaded.
