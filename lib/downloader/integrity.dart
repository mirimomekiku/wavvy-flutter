import 'dart:async';

import 'package:http/http.dart' as http;

/// Checks the installed yt-dlp against the checksum its release publishes.
///
/// Native code hashes the installed file (SHA-256); this class fetches the
/// release's `SHA2-256SUMS` and compares the entry for the `yt-dlp` asset (the
/// file youtubedl-android installs). It proves the file is the one published
/// under that release tag on github.com. It does not prove the release is
/// honest: the sums come from the same host as the file, and the GPG
/// signature of the sums file is not checked.
enum IntegrityResult {
  /// The hash equals the published one.
  match,

  /// The release publishes a different hash for this file.
  mismatch,

  /// The sums were fetched but have no entry for the yt-dlp asset.
  noEntry,

  /// The sums could not be fetched or read.
  unavailable,
}

/// The asset youtubedl-android installs (the python zipapp).
const kYtDlpAsset = 'yt-dlp';

/// Reads a `SHA2-256SUMS` file (`<64 hex>  <name>`, the name may start with
/// `*` for binary mode) into name -> lowercase hash. Lines that do not look
/// like an entry are ignored.
Map<String, String> parseSha256Sums(String text) {
  final out = <String, String>{};
  final line = RegExp(r'^([0-9a-fA-F]{64})[ \t]+\*?(\S.*?)\s*$');
  for (final raw in text.split('\n')) {
    final m = line.firstMatch(raw.trimRight());
    if (m != null) out[m.group(2)!] = m.group(1)!.toLowerCase();
  }
  return out;
}

/// Compares [sha256] with the entry for [asset] in [sums]. Never `unavailable`.
IntegrityResult compareChecksum(
  Map<String, String> sums,
  String sha256, {
  String asset = kYtDlpAsset,
}) {
  final expected = sums[asset];
  if (expected == null) return IntegrityResult.noEntry;
  return expected == sha256.trim().toLowerCase()
      ? IntegrityResult.match
      : IntegrityResult.mismatch;
}

class EngineIntegrity {
  EngineIntegrity({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.maxBytes = 1 << 20,
  }) : _client = client;

  final http.Client? _client;
  final Duration timeout;

  /// A sums file is a few kilobytes; anything bigger is not one.
  final int maxBytes;

  /// A yt-dlp release tag looks like `2025.10.22`; anything else is not put in
  /// a URL.
  static final _tag = RegExp(r'^[0-9A-Za-z][0-9A-Za-z._-]{0,40}$');

  static Uri? sumsUri(String version) => _tag.hasMatch(version)
      ? Uri.parse(
          'https://github.com/yt-dlp/yt-dlp/releases/download/$version/'
          'SHA2-256SUMS',
        )
      : null;

  /// Checks [sha256] (of the installed yt-dlp) against release [version].
  Future<IntegrityResult> check(String version, String sha256) async {
    final uri = sumsUri(version);
    if (uri == null) return IntegrityResult.unavailable;
    final client = _client ?? http.Client();
    try {
      final text = await _fetch(client, uri);
      if (text == null) return IntegrityResult.unavailable;
      return compareChecksum(parseSha256Sums(text), sha256);
    } catch (_) {
      return IntegrityResult.unavailable;
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<String?> _fetch(http.Client client, Uri uri) async {
    final response = await client
        .send(http.Request('GET', uri))
        .timeout(timeout);
    if (response.statusCode != 200) return null;
    final length = response.contentLength;
    if (length != null && length > maxBytes) return null;
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) return null;
    }
    return String.fromCharCodes(bytes);
  }
}

/// A sentence for the user for a result that is not [IntegrityResult.match].
String describeIntegrity(IntegrityResult result, String version) =>
    switch (result) {
      IntegrityResult.match => 'yt-dlp $version is verified.',
      IntegrityResult.mismatch =>
        'The downloaded yt-dlp does not match the checksum published for '
            '$version, so it was not used.',
      IntegrityResult.noEntry =>
        'The published checksums for $version have no entry for yt-dlp, so it '
            'could not be verified and was not used.',
      IntegrityResult.unavailable =>
        'Could not check yt-dlp $version against its published checksum. '
            'Check your connection and try again; it is not used until it is '
            'verified.',
    };
