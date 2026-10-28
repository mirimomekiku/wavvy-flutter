import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wavvy/artwork/album_art_cache.dart';
import 'package:wavvy/artwork/album_art_client.dart';
import 'package:wavvy/artwork/album_art_match.dart';

/// Smallest things that pass for a JPEG and a PNG (type + signature).
final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5, 6]);
final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  1,
]);

String _search(List<Map<String, Object?>> releases) =>
    jsonEncode({'releases': releases});

Map<String, Object?> _release(
  String id,
  String title,
  String artist, {
  int score = 100,
  String? group = 'rg-$kDefault',
}) => {
  'id': id,
  'title': title,
  'score': score,
  'artist-credit': [
    {
      'name': artist,
      'artist': {'name': artist},
    },
  ],
  'release-group': ?(group == null ? null : {'id': group}),
};

const kDefault = 'x';

/// A fake clock that [RateLimiter] sleeps on.
class _Clock {
  DateTime now = DateTime(2026, 1, 1);
  final sleeps = <Duration>[];
  Future<void> sleep(Duration d) async {
    sleeps.add(d);
    now = now.add(d);
  }
}

AlbumArtClient _client(
  Future<http.Response> Function(http.Request) handler, {
  _Clock? clock,
  Duration timeout = const Duration(seconds: 5),
  int maxBytes = kMaxArtBytes,
}) {
  final c = clock ?? _Clock();
  return AlbumArtClient(
    client: MockClient(handler),
    userAgent: () async => 'Wavvy/1.2.3 ( https://example.com/contact )',
    limiter: RateLimiter(now: () => c.now, sleep: c.sleep),
    timeout: timeout,
    maxBytes: maxBytes,
  );
}

http.Response _image(Uint8List bytes, {String type = 'image/jpeg'}) =>
    http.Response.bytes(bytes, 200, headers: {'content-type': type});

void main() {
  group('names and keys', () {
    test('normalizeName ignores case, punctuation, brackets and "the"', () {
      expect(
        normalizeName('The Dark Side of the Moon (Remastered)'),
        'dark side of the moon',
      );
      expect(normalizeName('Guns N\' Roses'), 'guns n roses');
      expect(normalizeName('Simon & Garfunkel'), 'simon and garfunkel');
      expect(normalizeName('  AC/DC '), 'ac dc');
      // All-bracket titles keep their words.
      expect(
        normalizeName('(What\'s the Story) Morning Glory?'),
        'morning glory',
      );
      expect(normalizeName('(Untitled)'), 'untitled');
    });

    test('nameSimilarity: equal, partial, different', () {
      expect(nameSimilarity('Abbey Road', 'abbey road (2019 Mix)'), 1);
      expect(
        nameSimilarity('Abbey Road', 'Abbey Road Sessions'),
        closeTo(2 / 3, 1e-9),
      );
      expect(nameSimilarity('Abbey Road', 'Revolver'), 0);
      expect(nameSimilarity('', 'x'), 0);
    });

    test('albumKey: the album id when there is one, else a stable hash', () {
      expect(albumKey(albumId: 42, album: 'A', artist: 'B'), 'id42');
      final a = albumKey(album: 'Abbey Road', artist: 'The Beatles');
      expect(a, startsWith('n'));
      expect(a.length, 17);
      expect(RegExp(r'^[a-z0-9]+$').hasMatch(a), isTrue);
      // Normalized: case and punctuation do not matter.
      expect(albumKey(album: 'abbey road!', artist: 'beatles'), a);
      expect(albumKey(album: 'Revolver', artist: 'The Beatles'), isNot(a));
      // Artist and album are not interchangeable.
      expect(albumKey(album: 'The Beatles', artist: 'Abbey Road'), isNot(a));
    });

    test('what is worth looking up', () {
      expect(isLookupWorthy('Abbey Road', 'The Beatles'), isTrue);
      expect(isLookupWorthy('<unknown>', 'The Beatles'), isFalse);
      expect(isLookupWorthy('', 'The Beatles'), isFalse);
      expect(isLookupWorthy(null, 'The Beatles'), isFalse);
      expect(isLookupWorthy('Abbey Road', '<unknown>'), isFalse);
      expect(isLookupWorthy('Now 99', 'Various Artists'), isFalse);
      expect(isLookupWorthy('Now 99', 'various artists'), isFalse);
    });
  });

  group('query', () {
    test('escapes quotes and backslashes, drops control characters', () {
      expect(escapeLucenePhrase('say "hi"'), r'say \"hi\"');
      expect(escapeLucenePhrase(r'a\b'), r'a\\b');
      expect(escapeLucenePhrase('a\nb\tc'), 'a b c');
      // Characters that are special outside quotes are fine inside them.
      expect(
        escapeLucenePhrase('AC/DC: (Live) + [x] ~ ! *'),
        'AC/DC: (Live) + [x] ~ ! *',
      );
    });

    test('the search URL is https with the query encoded', () {
      final uri = buildSearchUri('The "Best" of', r'Ye\s & Co');
      expect(uri.scheme, 'https');
      expect(uri.host, 'musicbrainz.org');
      expect(uri.path, '/ws/2/release/');
      expect(uri.queryParameters['fmt'], 'json');
      expect(uri.queryParameters['limit'], '5');
      expect(
        uri.queryParameters['query'],
        r'release:"The \"Best\" of" AND artist:"Ye\\s & Co"',
      );
      // On the wire the special characters are percent-encoded.
      expect(uri.toString(), isNot(contains('"')));
      expect(uri.toString(), isNot(contains(' ')));
    });
  });

  group('matching', () {
    Map<String, Object?> json(List<Map<String, Object?>> r) => {'releases': r};

    test('picks the matching release and orders by score', () {
      final r = pickReleases(
        json([
          _release('other', 'Revolver', 'The Beatles'),
          _release('lower', 'Abbey Road', 'The Beatles', score: 80),
          _release('best', 'Abbey Road', 'The Beatles', score: 100),
        ]),
        album: 'Abbey Road',
        artist: 'Beatles',
      );
      expect([for (final c in r) c.id], ['best', 'lower']);
      expect(r.first.groupId, 'rg-x');
    });

    test('rejects another artist and weak title matches', () {
      expect(
        pickReleases(
          json([_release('a', 'Abbey Road', 'Some Cover Band')]),
          album: 'Abbey Road',
          artist: 'The Beatles',
        ),
        isEmpty,
      );
      expect(
        pickReleases(
          json([
            _release('a', 'Abbey Road Revisited Again Live', 'The Beatles'),
          ]),
          album: 'Abbey Road',
          artist: 'The Beatles',
        ),
        isEmpty,
      );
    });

    test('malformed shapes are skipped, never thrown', () {
      for (final bad in <Object?>[
        null,
        'x',
        <Object?>[],
        {'releases': 'nope'},
        {
          'releases': [
            1,
            null,
            {'id': 5},
            {'id': 'a'},
            {'title': 'x'},
          ],
        },
      ]) {
        expect(
          pickReleases(bad, album: 'A', artist: 'B'),
          isEmpty,
          reason: '$bad',
        );
      }
    });

    test('a missing score counts as a usable match', () {
      final r = pickReleases(
        {
          'releases': [
            {
              'id': 'a',
              'title': 'Abbey Road',
              'artist-credit': [
                {'name': 'The Beatles'},
              ],
            },
          ],
        },
        album: 'Abbey Road',
        artist: 'The Beatles',
      );
      expect(r.single.id, 'a');
      expect(r.single.groupId, isNull);
    });

    test('misses expire after 30 days', () {
      final t = DateTime(2026, 3, 1);
      expect(isMissFresh(t, t.add(const Duration(days: 29))), isTrue);
      expect(isMissFresh(t, t.add(const Duration(days: 30))), isFalse);
      expect(isMissFresh(t, t.add(const Duration(days: 90))), isFalse);
    });
  });

  group('client', () {
    test(
      'found through the release, with a User-Agent on every request',
      () async {
        final seen = <http.Request>[];
        final client = _client((r) async {
          seen.add(r);
          if (r.url.host == 'musicbrainz.org') {
            return http.Response(
              _search([_release('rel-1', 'Abbey Road', 'The Beatles')]),
              200,
            );
          }
          return _image(_jpeg);
        });
        final result = await client.find(
          album: 'Abbey Road',
          artist: 'The Beatles',
        );
        expect(result.outcome, ArtOutcome.found);
        expect(result.extension, 'jpg');
        expect(result.bytes, _jpeg);
        expect(seen.length, 2);
        expect(
          seen[1].url.toString(),
          'https://coverartarchive.org/release/rel-1/front-500',
        );
        for (final r in seen) {
          expect(r.url.scheme, 'https');
          expect(r.headers['User-Agent'], contains('Wavvy/1.2.3'));
          expect(r.headers['User-Agent'], contains('https://example.com'));
        }
      },
    );

    test(
      'found through the release group when the release has no cover',
      () async {
        final urls = <String>[];
        final client = _client((r) async {
          urls.add(r.url.toString());
          if (r.url.host == 'musicbrainz.org') {
            return http.Response(
              _search([
                _release('rel-1', 'Abbey Road', 'The Beatles', group: 'grp-9'),
              ]),
              200,
            );
          }
          if (r.url.path.startsWith('/release/')) {
            return http.Response('Not Found', 404);
          }
          return _image(_png, type: 'image/png');
        });
        final result = await client.find(
          album: 'Abbey Road',
          artist: 'The Beatles',
        );
        expect(result.outcome, ArtOutcome.found);
        expect(result.extension, 'png');
        expect(
          urls.last,
          'https://coverartarchive.org/release-group/grp-9/front-500',
        );
      },
    );

    test('no matching release: not found, one request', () async {
      var calls = 0;
      final client = _client((r) async {
        calls++;
        return http.Response(_search([_release('x', 'Other', 'Nobody')]), 200);
      });
      final r = await client.find(album: 'Abbey Road', artist: 'The Beatles');
      expect(r.outcome, ArtOutcome.notFound);
      expect(r.stopsBatch, isFalse);
      expect(calls, 1);
    });

    test('404 from the archive for both sources is a plain miss', () async {
      final client = _client((r) async {
        if (r.url.host == 'musicbrainz.org') {
          return http.Response(
            _search([_release('rel-1', 'Abbey Road', 'The Beatles')]),
            200,
          );
        }
        return http.Response('nope', 404);
      });
      final r = await client.find(album: 'Abbey Road', artist: 'The Beatles');
      expect(r.outcome, ArtOutcome.notFound);
      expect(r.stopsBatch, isFalse);
    });

    test('503 and 429 mean rate limited and stop a batch', () async {
      for (final status in [503, 429]) {
        final client = _client((r) async => http.Response('busy', status));
        final r = await client.find(album: 'A', artist: 'B');
        expect(r.outcome, ArtOutcome.rateLimited);
        expect(r.stopsBatch, isTrue);
      }
      // From the archive too.
      final client = _client((r) async {
        if (r.url.host == 'musicbrainz.org') {
          return http.Response(_search([_release('r', 'A', 'B')]), 200);
        }
        return http.Response('busy', 503);
      });
      expect(
        (await client.find(album: 'A', artist: 'B')).outcome,
        ArtOutcome.rateLimited,
      );
    });

    test(
      'offline (socket error, timeout) is quiet and stops a batch',
      () async {
        final c1 = _client((r) async => throw const SocketException('down'));
        final r1 = await c1.find(album: 'A', artist: 'B');
        expect(r1.outcome, ArtOutcome.offline);
        expect(r1.stopsBatch, isTrue);

        final c2 = _client((r) async => throw http.ClientException('reset'));
        expect(
          (await c2.find(album: 'A', artist: 'B')).outcome,
          ArtOutcome.offline,
        );

        final never = Completer<http.Response>();
        final c3 = _client(
          (r) => never.future,
          timeout: const Duration(milliseconds: 20),
        );
        expect(
          (await c3.find(album: 'A', artist: 'B')).outcome,
          ArtOutcome.offline,
        );
      },
    );

    test(
      'malformed JSON and other statuses are errors, not exceptions',
      () async {
        final bad = _client((r) async => http.Response('{not json', 200));
        expect(
          (await bad.find(album: 'A', artist: 'B')).outcome,
          ArtOutcome.error,
        );
        final nonMap = _client((r) async => http.Response('[1,2]', 200));
        expect(
          (await nonMap.find(album: 'A', artist: 'B')).outcome,
          ArtOutcome.notFound,
        );
        final s500 = _client((r) async => http.Response('boom', 500));
        expect(
          (await s500.find(album: 'A', artist: 'B')).outcome,
          ArtOutcome.error,
        );
      },
    );

    http.Response Function(http.Request) withImage(http.Response image) =>
        (r) => r.url.host == 'musicbrainz.org'
        ? http.Response(
            _search([_release('rel-1', 'Abbey Road', 'The Beatles')]),
            200,
          )
        : image;

    test('an oversize image is refused', () async {
      final big = Uint8List(64)..setRange(0, 4, [0xFF, 0xD8, 0xFF, 0xE0]);
      final handler = withImage(_image(big));
      final client = _client((r) async => handler(r), maxBytes: 32);
      final r = await client.find(album: 'Abbey Road', artist: 'The Beatles');
      expect(r.outcome, ArtOutcome.notFound);
      expect(r.bytes, isNull);
    });

    test('a non-image content type or a bad signature is refused', () async {
      for (final image in [
        http.Response(
          '<html>oops</html>',
          200,
          headers: {'content-type': 'text/html'},
        ),
        _image(_png), // says JPEG, is PNG
        _image(_jpeg, type: 'image/gif'),
        http.Response.bytes(_jpeg, 200), // no content type at all
      ]) {
        final handler = withImage(image);
        final client = _client((r) async => handler(r));
        final r = await client.find(album: 'Abbey Road', artist: 'The Beatles');
        expect(r.outcome, ArtOutcome.notFound, reason: '${image.headers}');
        expect(r.bytes, isNull);
      }
    });
  });

  group('rate limiter', () {
    test('spaces calls by the interval, in order, across callers', () async {
      final clock = _Clock();
      final limiter = RateLimiter(now: () => clock.now, sleep: clock.sleep);
      final start = clock.now;
      await Future.wait([for (var i = 0; i < 4; i++) limiter.acquire()]);
      // The first goes at once; each of the others waits one interval.
      expect(clock.sleeps, [
        for (var i = 0; i < 3; i++) const Duration(seconds: 1),
      ]);
      expect(clock.now.difference(start), const Duration(seconds: 3));
    });

    test('does not wait when enough time has passed', () async {
      final clock = _Clock();
      final limiter = RateLimiter(now: () => clock.now, sleep: clock.sleep);
      await limiter.acquire();
      clock.now = clock.now.add(const Duration(seconds: 5));
      await limiter.acquire();
      expect(clock.sleeps, isEmpty);
    });

    test('one find() keeps its requests a second apart', () async {
      final clock = _Clock();
      final client = _client(
        (r) async => r.url.host == 'musicbrainz.org'
            ? http.Response(_search([_release('r', 'A', 'B')]), 200)
            : _image(_jpeg),
        clock: clock,
      );
      final start = clock.now;
      await client.find(album: 'A', artist: 'B');
      // Two requests: the second waited the full interval.
      expect(clock.now.difference(start), kArtRequestInterval);
    });
  });

  group('cache', () {
    late Directory dir;
    late DateTime now;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('wavvy_art_test');
      now = DateTime(2026, 5, 1);
    });
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    AlbumArtCache make({int maxBytes = kMaxArtBytes}) => AlbumArtCache(
      directory: () async => Directory('${dir.path}/album_art'),
      now: () => now,
      maxBytes: maxBytes,
    );

    test('store, lookup, reload from disk and remove', () async {
      final cache = make();
      await cache.load();
      expect(cache.lookup('id1'), isNull);

      final file = await cache.store('id1', _jpeg, 'jpg');
      expect(file, isNotNull);
      expect(file!.path, endsWith('album_art${Platform.pathSeparator}id1.jpg'));
      expect(await file.readAsBytes(), _jpeg);
      expect(cache.lookup('id1'), isNotNull);

      // A fresh instance finds it by listing the folder once.
      final again = make();
      await again.load();
      expect(again.files.keys, ['id1']);

      // Replacing with another format leaves one file for the album.
      await cache.store('id1', _png, 'png');
      final names = dir
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(names, ['id1.png']);

      await cache.remove('id1');
      expect(cache.lookup('id1'), isNull);
      expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
    });

    test(
      'is bounded: oversize, empty and odd formats are not stored',
      () async {
        final cache = make(maxBytes: 8);
        expect(await cache.store('id1', _jpeg, 'jpg'), isNull); // 10 > 8
        expect(await cache.store('id1', Uint8List(0), 'jpg'), isNull);
        expect(await cache.store('id1', Uint8List(4), 'gif'), isNull);
        expect(cache.files, isEmpty);
      },
    );

    test('a miss is remembered for 30 days, across restarts', () async {
      final cache = make();
      await cache.load();
      expect(cache.hasFreshMiss('id2'), isFalse);
      await cache.recordMiss('id2');
      expect(cache.hasFreshMiss('id2'), isTrue);

      now = now.add(const Duration(days: 20));
      final restarted = make();
      await restarted.load();
      expect(restarted.hasFreshMiss('id2'), isTrue);

      now = now.add(const Duration(days: 11));
      expect(restarted.hasFreshMiss('id2'), isFalse);
    });

    test(
      'storing a cover clears the miss; removing does not add one',
      () async {
        final cache = make();
        await cache.recordMiss('id3');
        await cache.store('id3', _jpeg, 'jpg');
        expect(cache.hasFreshMiss('id3'), isFalse);
        await cache.remove('id3');
        expect(cache.hasFreshMiss('id3'), isFalse);
      },
    );

    test('ignores stray files and a broken index', () async {
      final folder = Directory('${dir.path}/album_art')..createSync();
      File('${folder.path}/notes.txt').writeAsStringSync('x');
      File('${folder.path}/id9.jpg.tmp').writeAsBytesSync(_jpeg);
      File('${folder.path}/misses.json').writeAsStringSync('{broken');
      final cache = make();
      await cache.load();
      expect(cache.files, isEmpty);
    });
  });
}
