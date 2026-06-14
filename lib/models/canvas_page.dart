import 'note_image.dart';
import 'note_text.dart';
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
    List<NoteText>? texts,
    this.backgroundAsset,
    this.pdfAsset,
    this.pdfPage,
    this.background = PageBackground.grid,
  })  : strokes = strokes ?? [],
        images = images ?? [],
        texts = texts ?? [];

  final String id;

  /// Logical page dimensions in pixels (may differ from A4 for PDF pages).
  double width;
  double height;

  final List<Stroke> strokes;
  final List<NoteImage> images;
  final List<NoteText> texts;

  /// Legacy: pre-rasterized PDF page background (PNG file name in `assets/`).
  /// New imports use [pdfAsset]/[pdfPage] and render on demand instead.
  String? backgroundAsset;

  /// On-demand PDF background: the copied PDF file name in `assets/` and the
  /// 1-based page number to render. Rendered lazily at display resolution.
  String? pdfAsset;
  int? pdfPage;

  bool get hasPdfBackground => backgroundAsset != null || pdfAsset != null;

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
        'texts': [for (final t in texts) t.toJson()],
        'bg': backgroundAsset,
        'pdf': pdfAsset,
        'pdfPage': pdfPage,
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
        texts: [
          for (final t in (json['texts'] as List? ?? []))
            NoteText.fromJson(t as Map<String, dynamic>),
        ],
        backgroundAsset: json['bg'] as String?,
        pdfAsset: json['pdf'] as String?,
        pdfPage: json['pdfPage'] as int?,
        background: _backgroundFromName(json['paper'] as String?),
      );
}
