import 'dart:io';

import 'package:flutter/foundation.dart';

/// A file in the private staging folder and when it last changed.
typedef StagedFile = ({String path, DateTime modified});

/// Staged files that belong to nothing: not in [keep] (the files of tasks that
/// still need theirs, and of results not yet handled) and not changed for
/// [maxAge]. A recent file may be a download in progress, so it is never
/// picked, whatever it is called.
List<String> orphanedStagingFiles(
  Iterable<StagedFile> files, {
  required Set<String> keep,
  required DateTime now,
  Duration maxAge = const Duration(days: 1),
}) => [
  for (final f in files)
    if (!keep.contains(f.path) && now.difference(f.modified) >= maxAge) f.path,
];

/// Deletes the orphans in [dir] (not its subfolders, and never through a link).
/// Best effort; returns what was deleted.
Future<List<String>> sweepStaging(
  String dir, {
  required Set<String> keep,
  DateTime? now,
  Duration maxAge = const Duration(days: 1),
}) async {
  final deleted = <String>[];
  try {
    final folder = Directory(dir);
    if (!await folder.exists()) return deleted;
    final files = <StagedFile>[];
    await for (final e in folder.list(followLinks: false)) {
      if (e is! File) continue;
      files.add((path: e.path, modified: await e.lastModified()));
    }
    for (final path in orphanedStagingFiles(
      files,
      keep: keep,
      now: now ?? DateTime.now(),
      maxAge: maxAge,
    )) {
      try {
        await File(path).delete();
        deleted.add(path);
      } on FileSystemException {
        // In use or already gone.
      }
    }
  } catch (e) {
    debugPrint('staging sweep failed: $e');
  }
  return deleted;
}

/// Whether [path] is a file inside [dir] once links are resolved, so a path
/// handed over by another layer can't point out of the staging folder.
Future<bool> isInsideStaging(String path, String dir) async {
  try {
    final root = await Directory(dir).resolveSymbolicLinks();
    final file = await File(path).resolveSymbolicLinks();
    return file.startsWith(
      root.endsWith(Platform.pathSeparator)
          ? root
          : '$root${Platform.pathSeparator}',
    );
  } on FileSystemException {
    return false;
  }
}

/// Deletes the staged file at [path] if it is inside [dir]. Quiet.
Future<void> deleteStaged(String path, String dir) async {
  if (path.isEmpty || !await isInsideStaging(path, dir)) return;
  try {
    await File(path).delete();
  } on FileSystemException {
    // Already gone.
  }
}
