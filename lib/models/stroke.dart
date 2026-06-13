import 'dart:ui';

/// A single freehand pen stroke, stored in logical page coordinates
/// (independent of the on-screen display size / zoom).
class Stroke {
  Stroke({
    required this.points,
    required this.color,
    required this.width,
    this.isHighlighter = false,
  });

  /// Ordered points making up the stroke, in logical page pixels.
  final List<Offset> points;

  /// ARGB color value.
  final int color;

  /// Stroke width in logical page pixels.
  final double width;

  /// Highlighter strokes are drawn semi-transparent and behind ink.
  final bool isHighlighter;

  Map<String, dynamic> toJson() => {
        // Flattened [x0, y0, x1, y1, ...] for compactness.
        'p': [
          for (final pt in points) ...[pt.dx, pt.dy],
        ],
        'c': color,
        'w': width,
        'h': isHighlighter,
      };

  factory Stroke.fromJson(Map<String, dynamic> json) {
    final flat = (json['p'] as List).cast<num>();
    final pts = <Offset>[
      for (var i = 0; i + 1 < flat.length; i += 2)
        Offset(flat[i].toDouble(), flat[i + 1].toDouble()),
    ];
    return Stroke(
      points: pts,
      color: json['c'] as int,
      width: (json['w'] as num).toDouble(),
      isHighlighter: json['h'] as bool? ?? false,
    );
  }
}
