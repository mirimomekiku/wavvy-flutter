import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavvy/playback/smart_shuffle.dart';

List<ShuffleCandidate> _songs(List<String> artists, {List<double>? weights}) =>
    [
      for (var i = 0; i < artists.length; i++)
        ShuffleCandidate(
          index: i,
          artist: artists[i],
          weight: weights == null ? 1 : weights[i],
        ),
    ];

void main() {
  group('smartShuffleOrder', () {
    test('is a permutation of the songs', () {
      final songs = _songs(List.generate(50, (i) => 'artist ${i % 7}'));
      final order = smartShuffleOrder(songs, random: Random(1));
      expect(order.toList()..sort(), List.generate(50, (i) => i));
    });

    test('plays the first song first', () {
      final songs = _songs(List.generate(20, (i) => 'a${i % 4}'));
      for (var seed = 0; seed < 10; seed++) {
        expect(
          smartShuffleOrder(songs, first: 13, random: Random(seed)).first,
          13,
        );
      }
    });

    test('keeps the same artist apart when there is a choice', () {
      // Two artists, ten songs each: they can alternate perfectly.
      final artists = [for (var i = 0; i < 20; i++) i.isEven ? 'a' : 'b'];
      final songs = _songs(artists);
      for (var seed = 0; seed < 20; seed++) {
        final order = smartShuffleOrder(songs, random: Random(seed));
        for (var i = 1; i < order.length; i++) {
          expect(
            artists[order[i]] == artists[order[i - 1]],
            isFalse,
            reason: 'seed $seed, position $i',
          );
        }
      }
    });

    test('does not loop forever when everything is one artist', () {
      final songs = _songs(List.filled(30, 'same'));
      final order = smartShuffleOrder(songs, random: Random(3));
      expect(order.toSet(), hasLength(30));
    });

    test('unknown artists are not kept apart from each other', () {
      final songs = _songs(['', '', '', '']);
      final order = smartShuffleOrder(songs, random: Random(2));
      expect(order.toSet(), hasLength(4));
    });

    test('heavier songs come earlier on average', () {
      final weights = [for (var i = 0; i < 40; i++) i < 5 ? 8.0 : 1.0];
      final songs = _songs(List.generate(40, (i) => 'x$i'), weights: weights);
      var heavy = 0.0, light = 0.0;
      const runs = 200;
      for (var seed = 0; seed < runs; seed++) {
        final order = smartShuffleOrder(songs, random: Random(seed));
        for (var pos = 0; pos < order.length; pos++) {
          if (order[pos] < 5) {
            heavy += pos;
          } else {
            light += pos;
          }
        }
      }
      expect(heavy / (5 * runs), lessThan(light / (35 * runs)));
    });

    test('handles zero and one songs', () {
      expect(smartShuffleOrder(const []), isEmpty);
      expect(smartShuffleOrder(_songs(['a'])), [0]);
    });
  });

  group('shuffleWeight', () {
    test('liked and less played songs weigh more', () {
      expect(
        shuffleWeight(plays: 0, liked: true),
        greaterThan(shuffleWeight(plays: 0, liked: false)),
      );
      expect(
        shuffleWeight(plays: 0, liked: false),
        greaterThan(shuffleWeight(plays: 30, liked: false)),
      );
    });
  });

  group('SmartShuffleOrder', () {
    test('shuffles the indices it holds, first one first', () {
      final artists = [for (var i = 0; i < 12; i++) 'a${i % 3}'];
      final order = SmartShuffleOrder(
        describe: (i) => ShuffleCandidate(index: i, artist: artists[i]),
        random: Random(5),
      )..insert(0, 12);
      order.shuffle(initialIndex: 7);
      expect(order.indices.first, 7);
      expect(order.indices.toList()..sort(), List.generate(12, (i) => i));
    });
  });
}
