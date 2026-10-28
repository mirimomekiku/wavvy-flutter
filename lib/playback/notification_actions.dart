import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:wavvy/core/external_audio.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';

/// Names of the custom notification buttons, as they reach
/// [AudioHandler.customAction].
const kLikeAction = 'wavvy_like';
const kShuffleAction = 'wavvy_shuffle';
const kRepeatAction = 'wavvy_repeat';

/// Android shows at most five buttons; Stop is the first to go.
const kMaxNotificationControls = 5;

/// The collapsed notification shows Previous, Play/Pause and Next, however many
/// extras follow.
const kCompactActionIndices = [0, 1, 2];

/// Handles a tap on a custom notification button. Set on the audio handler by
/// the app once the providers exist.
typedef CustomActionDelegate =
    Future<void> Function(String name, Map<String, dynamic>? extras);

/// What the custom notification buttons need to know: which are switched on
/// (Settings > Playback) and the state each one shows.
@immutable
class NotificationExtras {
  const NotificationExtras({
    this.likeEnabled = false,
    this.shuffleEnabled = false,
    this.repeatEnabled = false,
    this.canLike = false,
    this.liked = false,
    this.shuffle = false,
    this.repeat = LoopMode.off,
  });

  final bool likeEnabled;
  final bool shuffleEnabled;
  final bool repeatEnabled;

  /// A library song is playing: the only time Like makes sense.
  final bool canLike;
  final bool liked;
  final bool shuffle;
  final LoopMode repeat;

  @override
  bool operator ==(Object other) =>
      other is NotificationExtras &&
      likeEnabled == other.likeEnabled &&
      shuffleEnabled == other.shuffleEnabled &&
      repeatEnabled == other.repeatEnabled &&
      canLike == other.canLike &&
      liked == other.liked &&
      shuffle == other.shuffle &&
      repeat == other.repeat;

  @override
  int get hashCode => Object.hash(
    likeEnabled,
    shuffleEnabled,
    repeatEnabled,
    canLike,
    liked,
    shuffle,
    repeat,
  );
}

MediaControl _like(bool liked) => MediaControl.custom(
  androidIcon: liked
      ? 'drawable/ic_notif_like_filled'
      : 'drawable/ic_notif_like',
  label: liked ? 'Unlike' : 'Like',
  name: kLikeAction,
);

MediaControl _shuffle(bool on) => MediaControl.custom(
  androidIcon: on
      ? 'drawable/ic_notif_shuffle_on'
      : 'drawable/ic_notif_shuffle',
  label: on ? 'Shuffle on' : 'Shuffle off',
  name: kShuffleAction,
);

MediaControl _repeat(LoopMode mode) => switch (mode) {
  LoopMode.off => MediaControl.custom(
    androidIcon: 'drawable/ic_notif_repeat',
    label: 'Repeat off',
    name: kRepeatAction,
  ),
  LoopMode.all => MediaControl.custom(
    androidIcon: 'drawable/ic_notif_repeat_all',
    label: 'Repeat all',
    name: kRepeatAction,
  ),
  LoopMode.one => MediaControl.custom(
    androidIcon: 'drawable/ic_notif_repeat_one',
    label: 'Repeat one',
    name: kRepeatAction,
  ),
};

/// The notification's buttons: Previous, Play/Pause, Next, then the chosen
/// extras (Like, Shuffle, Repeat), with Stop last and only if there is room.
/// Never more than five: with all three extras Repeat is cut.
/// Like is left out when no library song is playing.
List<MediaControl> buildNotificationControls({
  required bool playing,
  required NotificationExtras extras,
}) {
  final controls = [
    MediaControl.skipToPrevious,
    if (playing) MediaControl.pause else MediaControl.play,
    MediaControl.skipToNext,
    if (extras.likeEnabled && extras.canLike) _like(extras.liked),
    if (extras.shuffleEnabled) _shuffle(extras.shuffle),
    if (extras.repeatEnabled) _repeat(extras.repeat),
  ];
  if (controls.length < kMaxNotificationControls) {
    controls.add(MediaControl.stop);
  }
  // All three extras make six: Repeat, the last, does not fit.
  return controls.take(kMaxNotificationControls).toList();
}

/// Keeps the notification's custom buttons in step with the app (called from
/// [wirePlayback]):
///  - pushes the favorite state of the playing song, the shuffle and loop
///    modes and the three settings to the handler, now and on every change;
///  - turns a tap on a button into the same call the player screen makes.
void wireNotificationActions(Ref ref) {
  final handler = ref.read(audioHandlerProvider);

  NotificationExtras current() {
    final settings = ref.read(settingsProvider);
    final player = ref.read(playerProvider);
    final song = player.currentSong;
    final canLike = song != null && !song.isExternal;
    return NotificationExtras(
      likeEnabled: settings.notifLike,
      shuffleEnabled: settings.notifShuffle,
      repeatEnabled: settings.notifRepeat,
      canLike: canLike,
      liked: canLike && ref.read(favoritesProvider).containsKey(song.id),
      shuffle: player.isShuffleModeEnabled,
      repeat: player.loopMode,
    );
  }

  void push() => handler.updateCustomControls(current());

  ref.listen(favoritesProvider, (_, _) => push());
  ref.listen(playerProvider.select((s) => s.currentSong?.id), (_, _) => push());
  ref.listen(
    playerProvider.select((s) => s.isShuffleModeEnabled),
    (_, _) => push(),
  );
  ref.listen(playerProvider.select((s) => s.loopMode), (_, _) => push());
  ref.listen(
    settingsProvider.select(
      (s) => (s.notifLike, s.notifShuffle, s.notifRepeat),
    ),
    (_, _) => push(),
  );

  handler.customActionDelegate = (name, extras) async {
    switch (name) {
      case kLikeAction:
        final song = ref.read(playerProvider).currentSong;
        // Nothing playing, or a file from outside the library: a quiet no-op.
        if (song == null || song.isExternal) return;
        await ref.read(favoritesProvider.notifier).toggle(song);
      case kShuffleAction:
        await ref.read(playerProvider.notifier).toggleShuffle();
      case kRepeatAction:
        await ref.read(playerProvider.notifier).cycleLoopMode();
    }
  };
  ref.onDispose(() => handler.customActionDelegate = null);

  push();
}
