import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A cover image the downloader fetched.
typedef CoverImage = ({Uint8List bytes, String mime});

/// Looks a host name up. Replaced in tests.
typedef HostResolver = Future<List<InternetAddress>> Function(String host);

const kCoverMaxBytes = 5 << 20;
const _maxRedirects = 3;

/// Whether [address] is somewhere a cover must never be fetched from: this
/// device, the local network, or another reserved range.
bool isPrivateAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return true;
  }
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return _privateV4(b[0], b[1]);
  }
  if (b.length != 16) return true;
  if (b.every((x) => x == 0)) return true; // ::
  if ((b[0] & 0xFE) == 0xFC) return true; // fc00::/7 unique local
  // IPv4-mapped (::ffff:a.b.c.d) takes the IPv4 rules.
  final mapped =
      b.sublist(0, 10).every((x) => x == 0) && b[10] == 0xFF && b[11] == 0xFF;
  return mapped && _privateV4(b[12], b[13]);
}

bool _privateV4(int a, int b) =>
    a == 0 ||
    a == 10 ||
    a == 127 ||
    (a == 100 && b >= 64 && b <= 127) || // carrier-grade NAT
    (a == 169 && b == 254) ||
    (a == 172 && b >= 16 && b <= 31) ||
    (a == 192 && b == 168) ||
    a >= 224; // multicast and reserved

/// The checks that need no network: https only, a real host name or a public
/// IP address. A name can still resolve to a private address; [fetchCover]
/// checks that too.
bool isAllowedCoverUri(Uri uri) {
  if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    return false;
  }
  final host = uri.host.toLowerCase();
  final literal = InternetAddress.tryParse(host);
  if (literal != null) return !isPrivateAddress(literal);
  if (!host.contains('.')) return false; // "localhost", intranet names
  return !(host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.internal') ||
      host.endsWith('.lan') ||
      host.endsWith('.home.arpa'));
}

/// [isAllowedCoverUri] for text from a site's JSON.
bool isAllowedCoverUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  return uri != null && isAllowedCoverUri(uri);
}

Future<List<InternetAddress>> _lookup(String host) =>
    InternetAddress.lookup(host);

/// Downloads a cover from [url], which a site chose: https only, never a
/// private or local address (checked again after each redirect and after name
/// resolution), at most [maxBytes] (the body is read as a stream and dropped
/// as soon as it is bigger) and [timeout] overall. Returns null, never throws.
/// A name that changes its answer between this check and the connection
/// (DNS rebinding) is not caught.
Future<CoverImage?> fetchCover(
  String url, {
  http.Client? client,
  HostResolver resolve = _lookup,
  int maxBytes = kCoverMaxBytes,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final own = client == null;
  final session = client ?? http.Client();
  try {
    return await _fetch(
      session,
      Uri.parse(url.trim()),
      resolve,
      maxBytes,
    ).timeout(timeout);
  } catch (e) {
    debugPrint('cover download failed: $e');
    return null;
  } finally {
    if (own) session.close();
  }
}

Future<CoverImage?> _fetch(
  http.Client client,
  Uri start,
  HostResolver resolve,
  int maxBytes,
) async {
  var uri = start;
  for (var hop = 0; hop <= _maxRedirects; hop++) {
    if (!isAllowedCoverUri(uri)) return null;
    if (InternetAddress.tryParse(uri.host) == null) {
      final addresses = await resolve(uri.host);
      if (addresses.isEmpty || addresses.any(isPrivateAddress)) return null;
    }
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await client.send(request);
    final code = response.statusCode;
    if (code >= 300 && code < 400) {
      final location = response.headers['location'];
      await response.stream.drain<void>();
      if (location == null) return null;
      uri = uri.resolve(location);
      continue;
    }
    if (code != 200) {
      await response.stream.drain<void>();
      return null;
    }
    final length = response.contentLength;
    if (length != null && length > maxBytes) return null;
    final mime = (response.headers['content-type'] ?? 'image/jpeg')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    if (!mime.startsWith('image/')) return null;
    final out = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      out.add(chunk);
      if (out.length > maxBytes) return null; // leaving the loop cancels it
    }
    return out.isEmpty ? null : (bytes: out.takeBytes(), mime: mime);
  }
  return null; // too many redirects
}
