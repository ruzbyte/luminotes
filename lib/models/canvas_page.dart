import 'note_image.dart';
import 'stroke.dart';

/// Logical A4 page size in pixels (210x297mm at ~96dpi). Strokes and images
/// are stored against this coordinate space so they stay sharp at any zoom.
const double kA4LogicalWidth = 794;
const double kA4LogicalHeight = 1123;

/// Spacing of the ruled/grid background, in logical pixels (~6mm).
const double kRuleSpacing = 28;

/// Paper template drawn behind the ink.
enum PageBackground { blank, grid, lines, dots }

PageBackground _backgroundFromName(String? name) {
  for (final b in PageBackground.values) {
    if (b.name == name) return b;
  }
  return PageBackground.grid;
}

/// One page of a note: an A4 (or PDF-sized) canvas holding ink strokes,
/// embedded images and an optional rasterized PDF background.
class CanvasPage {
  CanvasPage({
    required this.id,
    this.width = kA4LogicalWidth,
    this.height = kA4LogicalHeight,
    List<Stroke>? strokes,
    List<NoteImage>? images,
    this.backgroundAsset,
    this.background = PageBackground.grid,
  })  : strokes = strokes ?? [],
        images = images ?? [];

  final String id;

  /// Logical page dimensions in pixels (may differ from A4 for PDF pages).
  double width;
  double height;

  final List<Stroke> strokes;
  final List<NoteImage> images;

  /// Optional rasterized PDF page background (file name in `assets/`).
  String? backgroundAsset;

  /// Paper template (grid / lines / dots / blank). Ignored when a PDF
  /// background is present.
  PageBackground background;

  double get aspectRatio => height == 0 ? 1 : width / height;

  Map<String, dynamic> toJson() => {
        'id': id,
        'w': width,
        'h': height,
        'strokes': [for (final s in strokes) s.toJson()],
        'images': [for (final i in images) i.toJson()],
        'bg': backgroundAsset,
        'paper': background.name,
      };

  factory CanvasPage.fromJson(Map<String, dynamic> json) => CanvasPage(
        id: json['id'] as String,
        width: (json['w'] as num?)?.toDouble() ?? kA4LogicalWidth,
        height: (json['h'] as num?)?.toDouble() ?? kA4LogicalHeight,
        strokes: [
          for (final s in (json['strokes'] as List? ?? []))
            Stroke.fromJson(s as Map<String, dynamic>),
        ],
        images: [
          for (final i in (json['images'] as List? ?? []))
            NoteImage.fromJson(i as Map<String, dynamic>),
        ],
        backgroundAsset: json['bg'] as String?,
        background: _backgroundFromName(json['paper'] as String?),
      );
}
