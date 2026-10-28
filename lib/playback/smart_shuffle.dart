import 'dart:math';

import 'package:just_audio/just_audio.dart';

/// What the smart shuffle knows about one song in the queue.
class ShuffleCandidate {
  const ShuffleCandidate({
    required this.index,
    this.artist = '',
    this.weight = 1,
  });

  /// The song's index in the queue (and so in the player's sources).
  final int index;

  /// Songs by the same artist are kept apart; empty means unknown, which is
  /// never treated as the same artist.
  final String artist;

  /// How likely the song is to come early; 1 is neutral.
  final double weight;
}

/// How much more likely a liked song is to come early.
const likedShuffleWeight = 1.6;

/// The weight of a song from how often it was played (less played songs get a
/// small lift, so the shuffle surfaces the rest of the library) and whether it
/// is liked.
double shuffleWeight({required int plays, required bool liked}) =>
    (liked ? likedShuffleWeight : 1.0) * (1 + 1 / (1 + plays));

/// A shuffle that reads as more random than a plain one.
///
/// Songs are put in a weighted random order (liked and rarely played songs tend
/// to come earlier), then the order is adjusted so that the same artist does
/// not play twice in a row when there is another choice a little further on.
/// [first], when given, plays first.
List<int> smartShuffleOrder(
  List<ShuffleCandidate> songs, {
  int? first,
  Random? random,
  int lookahead = 40,
}) {
  if (songs.length <= 1) return [for (final s in songs) s.index];
  final rng = random ?? Random();

  // Weighted random order (Efraimidis and Spirakis): a larger weight raises
  // the key, and the keys sort the songs.
  final keyed = [
    for (final s in songs)
      (song: s, key: pow(rng.nextDouble(), 1 / max(s.weight, 0.01)).toDouble()),
  ]..sort((a, b) => b.key.compareTo(a.key));
  final pending = [for (final k in keyed) k.song];

  final order = <int>[];
  String lastArtist = '';
  void take(int at) {
    final song = pending.removeAt(at);
    order.add(song.index);
    lastArtist = song.artist;
  }

  if (first != null) {
    final at = pending.indexWhere((s) => s.index == first);
    if (at >= 0) take(at);
  }
  while (pending.isNotEmpty) {
    var pick = 0;
    final reach = min(lookahead, pending.length);
    for (var i = 0; i < reach; i++) {
      final artist = pending[i].artist;
      if (artist.isEmpty || artist != lastArtist) {
        pick = i;
        break;
      }
    }
    take(pick);
  }
  return order;
}

/// The player's shuffle order, made by [smartShuffleOrder]. Adding songs later
/// is left to the default (a random place), which is good enough for one song.
class SmartShuffleOrder extends DefaultShuffleOrder {
  SmartShuffleOrder({required this.describe, super.random})
    : _random = random ?? Random();

  /// What is known about the song at a queue index.
  final ShuffleCandidate Function(int index) describe;
  final Random _random;

  @override
  void shuffle({int? initialIndex}) {
    if (indices.length <= 1) return;
    final order = smartShuffleOrder(
      [for (final i in indices) describe(i)],
      first: initialIndex,
      random: _random,
    );
    indices
      ..clear()
      ..addAll(order);
  }
}
