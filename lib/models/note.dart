import 'canvas_page.dart';

/// A note is an ordered list of canvas pages plus metadata. The full content
/// (pages, strokes, images) lives in `notes/<id>/note.json`; lightweight
/// metadata is mirrored in the top-level library index.
class Note {
  Note({
    required this.id,
    required this.title,
    required this.folderId,
    required this.createdAt,
    required this.updatedAt,
    List<CanvasPage>? pages,
  }) : pages = pages ?? [];

  final String id;
  String title;

  /// Owning folder id, or null when the note lives at the library root.
  String? folderId;

  final DateTime createdAt;
  DateTime updatedAt;

  final List<CanvasPage> pages;

  /// Metadata-only view persisted in the library index.
  Map<String, dynamic> toMetaJson() => {
        'id': id,
        'title': title,
        'folderId': folderId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'pageCount': pages.length,
      };

  Map<String, dynamic> toJson() => {
        ...toMetaJson(),
        'pages': [for (final p in pages) p.toJson()],
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Untitled',
        folderId: json['folderId'] as String?,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
                DateTime.now(),
        pages: [
          for (final p in (json['pages'] as List? ?? []))
            CanvasPage.fromJson(p as Map<String, dynamic>),
        ],
      );
}

/// Lightweight summary used by the library browser without loading full pages.
class NoteSummary {
  NoteSummary({
    required this.id,
    required this.title,
    required this.folderId,
    required this.updatedAt,
    required this.pageCount,
  });

  final String id;
  String title;
  String? folderId;
  DateTime updatedAt;
  int pageCount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'folderId': folderId,
        'updatedAt': updatedAt.toIso8601String(),
        'pageCount': pageCount,
      };

  factory NoteSummary.fromJson(Map<String, dynamic> json) => NoteSummary(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Untitled',
        folderId: json['folderId'] as String?,
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
                DateTime.now(),
        pageCount: json['pageCount'] as int? ?? 0,
      );

  factory NoteSummary.fromNote(Note note) => NoteSummary(
        id: note.id,
        title: note.title,
        folderId: note.folderId,
        updatedAt: note.updatedAt,
        pageCount: note.pages.length,
      );
}
