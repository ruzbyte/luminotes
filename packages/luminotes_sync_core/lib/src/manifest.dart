import 'dart:io';

import 'package:path/path.dart' as p;

import 'hashing.dart';

/// One file's state in a [Manifest]. Identity is [sha256]; [size] and
/// [modifiedMs] are advisory (used for display and tie-breaking, not equality).
class ManifestEntry {
  const ManifestEntry({
    required this.size,
    required this.sha256,
    required this.modifiedMs,
  });

  final int size;
  final String sha256;
  final int modifiedMs;

  factory ManifestEntry.fromJson(Map<String, dynamic> json) => ManifestEntry(
        size: (json['size'] as num).toInt(),
        sha256: json['sha256'] as String,
        modifiedMs: (json['modifiedMs'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'size': size,
        'sha256': sha256,
        'modifiedMs': modifiedMs,
      };

  /// Two entries refer to the same content iff their hashes match.
  bool sameContentAs(ManifestEntry other) => sha256 == other.sha256;
}

/// A snapshot of a file tree: relative POSIX path -> [ManifestEntry].
class Manifest {
  Manifest([Map<String, ManifestEntry>? entries])
      : entries = entries ?? <String, ManifestEntry>{};

  final Map<String, ManifestEntry> entries;

  factory Manifest.fromJson(Map<String, dynamic> json) {
    final raw = (json['entries'] as Map?) ?? const {};
    return Manifest({
      for (final e in raw.entries)
        e.key as String:
            ManifestEntry.fromJson((e.value as Map).cast<String, dynamic>()),
    });
  }

  Map<String, dynamic> toJson() => {
        'entries': {
          for (final e in entries.entries) e.key: e.value.toJson(),
        },
      };

  /// Builds a manifest by walking [rootDir]. Paths are stored relative to the
  /// root using forward slashes so they are stable across platforms.
  static Future<Manifest> fromDirectory(String rootDir) async {
    final root = Directory(rootDir);
    final manifest = Manifest();
    if (!await root.exists()) return manifest;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.posix.joinAll(p.split(p.relative(entity.path, from: rootDir)));
      final bytes = await entity.readAsBytes();
      final stat = await entity.stat();
      manifest.entries[rel] = ManifestEntry(
        size: bytes.length,
        sha256: sha256Hex(bytes),
        modifiedMs: stat.modified.millisecondsSinceEpoch,
      );
    }
    return manifest;
  }
}
