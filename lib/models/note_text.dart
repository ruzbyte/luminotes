import 'dart:ui';

/// A free-floating text box placed on a page, in logical page coordinates.
class NoteText {
  NoteText({
    required this.id,
    required this.position,
    required this.width,
    required this.fontSize,
    required this.color,
    this.text = '',
  });

  final String id;

  /// Top-left position on the page, in logical page pixels.
  Offset position;

  /// Wrap width in logical page pixels (height grows with content).
  double width;

  /// Font size in logical page pixels.
  double fontSize;

  /// ARGB color value.
  int color;

  String text;

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': position.dx,
        'y': position.dy,
        'w': width,
        'fs': fontSize,
        'c': color,
        't': text,
      };

  factory NoteText.fromJson(Map<String, dynamic> json) => NoteText(
        id: json['id'] as String,
        position: Offset(
          (json['x'] as num).toDouble(),
          (json['y'] as num).toDouble(),
        ),
        width: (json['w'] as num).toDouble(),
        fontSize: (json['fs'] as num?)?.toDouble() ?? 24,
        color: json['c'] as int? ?? 0xFF1A1A1A,
        text: json['t'] as String? ?? '',
      );
}
