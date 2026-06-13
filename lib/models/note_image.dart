import 'dart:ui';

/// An embedded raster image (e.g. a pasted screenshot) positioned on a page,
/// in logical page coordinates.
class NoteImage {
  NoteImage({
    required this.id,
    required this.assetFile,
    required this.rect,
  });

  final String id;

  /// File name (relative to the note's `assets/` directory).
  final String assetFile;

  /// Position and size on the page, in logical page pixels.
  Rect rect;

  Map<String, dynamic> toJson() => {
        'id': id,
        'file': assetFile,
        'x': rect.left,
        'y': rect.top,
        'w': rect.width,
        'h': rect.height,
      };

  factory NoteImage.fromJson(Map<String, dynamic> json) => NoteImage(
        id: json['id'] as String,
        assetFile: json['file'] as String,
        rect: Rect.fromLTWH(
          (json['x'] as num).toDouble(),
          (json['y'] as num).toDouble(),
          (json['w'] as num).toDouble(),
          (json['h'] as num).toDouble(),
        ),
      );
}
