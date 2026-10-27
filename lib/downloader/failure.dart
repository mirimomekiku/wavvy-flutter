/// Turns what yt-dlp or the platform reports into a sentence a person can act
/// on. The raw text is long, technical and often multi-line.
String describeDownloadFailure(String raw) {
  final text = raw.toLowerCase();
  bool has(String s) => text.contains(s);

  if (has('sign in to confirm') || has('not a bot')) {
    return 'YouTube is asking this network to prove it is not a bot. '
        'Try again later, or from a different network.';
  }
  if (has('private video') || has('members-only') || has('join this channel')) {
    return 'This video is private or for members only.';
  }
  if (has('video unavailable') ||
      has('has been removed') ||
      has('no longer available') ||
      has('this video is not available')) {
    return 'This video is no longer available.';
  }
  if (has('not available in your country') ||
      has('geo restricted') ||
      has('geo-restricted')) {
    return 'This video is not available in your country.';
  }
  if (has('age-restricted') || has('confirm your age')) {
    return 'This video is age-restricted and cannot be downloaded.';
  }
  if (has('unsupported url')) {
    return 'That link is not something the downloader can use.';
  }
  if (has('waiting for wi-fi')) {
    return 'Waiting for Wi-Fi: this download is set to Wi-Fi only.';
  }
  if (has('unable to download') ||
      has('timed out') ||
      has('timeout') ||
      has('network is unreachable') ||
      has('name or service not known') ||
      has('unknownhost') ||
      has('connection reset') ||
      has('connection refused')) {
    return 'Could not reach the server. Check your connection and try again.';
  }
  if (has('http error 403') || has('http error 429')) {
    return 'The site refused the request. If this keeps happening, update the '
        'downloader in Settings.';
  }
  if (has('no space left') || has('enospc')) {
    return 'There is not enough free storage on this device.';
  }
  if (has('no audio file was found')) {
    return 'The download finished but produced no audio file.';
  }
  // Last resort: the last line of yt-dlp's output is usually the reason.
  final lines = raw
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final last = lines.isEmpty ? 'Unknown error' : lines.last;
  final clean = last
      .replaceFirst(RegExp(r'^(ERROR|error):\s*'), '')
      .replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '');
  return clean.length > 140 ? '${clean.substring(0, 137)}...' : clean;
}
