import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/canvas_page.dart';
import '../models/note.dart';
import '../models/note_image.dart';
import '../models/stroke.dart';
import '../services/pdf_import_service.dart';
import '../services/storage_service.dart';
import 'library_provider.dart';

enum EditorTool { pen, highlighter, eraser, pan, select }

/// Holds the note currently being edited plus the live tool/color state and
/// all mutating operations. Persists changes back to disk (debounced).
class NoteProvider extends ChangeNotifier {
  NoteProvider(this._storage, this._library);

  final StorageService _storage;
  final LibraryProvider _library;
  static const _uuid = Uuid();

  Note? _note;
  Note? get note => _note;

  // --- Tool state ----------------------------------------------------------
  EditorTool _tool = EditorTool.pen;
  EditorTool get tool => _tool;

  int _penColor = 0xFF1A1A1A;
  int get penColor => _penColor;

  double _penWidth = 3.0;
  double get penWidth => _penWidth;

  int _highlighterColor = 0x66FFEB3B;
  int get highlighterColor => _highlighterColor;

  /// Currently selected image (in select mode), if any.
  String? _selectedImageId;
  String? get selectedImageId => _selectedImageId;

  Stroke? _activeStroke;
  Stroke? get activeStroke => _activeStroke;
  int _activeStrokePage = -1;
  int get activeStrokePage => _activeStrokePage;
  bool _drawing = false;

  /// Repaint signal for the live (in-progress) stroke layer only. Bumped on
  /// every pointer move so the active-stroke painter repaints WITHOUT
  /// rebuilding the whole editor tree (which is what made drawing laggy).
  final ValueNotifier<int> strokeTick = ValueNotifier<int>(0);

  Timer? _saveTimer;

  // --- Lifecycle -----------------------------------------------------------

  Future<void> open(String noteId) async {
    _note = await _storage.loadNote(noteId);
    _selectedImageId = null;
    notifyListeners();
  }

  void setTool(EditorTool tool) {
    // Drop any in-progress stroke so it can't leak across a tool change.
    if (_drawing) cancelStroke();
    _tool = tool;
    if (tool != EditorTool.select) _selectedImageId = null;
    notifyListeners();
  }

  void setPenColor(int color) {
    if (_tool == EditorTool.highlighter) {
      _highlighterColor = (color & 0x00FFFFFF) | 0x66000000;
    } else {
      _penColor = color;
    }
    notifyListeners();
  }

  void setPenWidth(double width) {
    _penWidth = width;
    notifyListeners();
  }

  String assetPath(String fileName) =>
      _storage.assetPath(_note!.id, fileName);

  // --- Drawing -------------------------------------------------------------

  bool get _isInk => _tool == EditorTool.pen || _tool == EditorTool.highlighter;

  void startStroke(int pageIndex, Offset logicalPoint) {
    if (!_isInk || _note == null) return;
    final highlighter = _tool == EditorTool.highlighter;
    _activeStroke = Stroke(
      points: [logicalPoint],
      color: highlighter ? _highlighterColor : _penColor,
      width: highlighter ? _penWidth * 6 : _penWidth,
      isHighlighter: highlighter,
    );
    _activeStrokePage = pageIndex;
    _drawing = true;
    strokeTick.value++; // repaint active layer only
  }

  void extendStroke(Offset logicalPoint) {
    if (!_drawing) return;
    final stroke = _activeStroke;
    if (stroke == null) return;
    // Skip points that are sub-pixel close to reduce jitter / point count.
    final last = stroke.points.last;
    if ((logicalPoint - last).distanceSquared < 1.0) return;
    stroke.points.add(logicalPoint);
    strokeTick.value++; // repaint active layer only (no tree rebuild)
  }

  void endStroke() {
    if (!_drawing) return;
    _drawing = false;
    final stroke = _activeStroke;
    final note = _note;
    if (stroke != null && stroke.points.length >= 2 && note != null) {
      note.pages[_activeStrokePage].strokes.add(stroke);
      _touch();
    }
    _activeStroke = null;
    _activeStrokePage = -1;
    // One rebuild to fold the finished stroke into the committed layer.
    notifyListeners();
    strokeTick.value++;
  }

  void cancelStroke() {
    if (!_drawing && _activeStroke == null) return;
    _drawing = false;
    _activeStroke = null;
    _activeStrokePage = -1;
    strokeTick.value++;
  }

  /// Object-eraser: removes whole strokes within [radius] of [logicalPoint].
  void eraseAt(int pageIndex, Offset logicalPoint, {double radius = 12}) {
    if (_note == null) return;
    final strokes = _note!.pages[pageIndex].strokes;
    final before = strokes.length;
    strokes.removeWhere((s) => _strokeHit(s, logicalPoint, radius));
    if (strokes.length != before) {
      _touch();
      notifyListeners();
    }
  }

  bool _strokeHit(Stroke stroke, Offset p, double radius) {
    final r = radius + stroke.width / 2;
    final pts = stroke.points;
    if (pts.length == 1) return (pts.first - p).distance <= r;
    for (var i = 0; i + 1 < pts.length; i++) {
      if (_distanceToSegment(p, pts[i], pts[i + 1]) <= r) return true;
    }
    return false;
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0) return (p - a).distance;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq;
    t = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }

  // --- Images --------------------------------------------------------------

  Future<void> addImage(int pageIndex, Uint8List bytes, String extension) async {
    if (_note == null) return;
    final id = _uuid.v4();
    final fileName = '$id.$extension';
    await _storage.saveAsset(_note!.id, fileName, bytes);

    final page = _note!.pages[pageIndex];
    // Decode to honor the image's aspect ratio, capped to half the page width.
    final codec = await instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final decoded = frame.image;
    final maxW = page.width * 0.5;
    final ar = decoded.height == 0 ? 1.0 : decoded.width / decoded.height;
    decoded.dispose();
    codec.dispose();
    final w = maxW;
    final h = w / ar;
    final rect = Rect.fromLTWH(
      (page.width - w) / 2,
      (page.height - h) / 2,
      w,
      h,
    );
    page.images.add(NoteImage(id: id, assetFile: fileName, rect: rect));
    _selectedImageId = id;
    _tool = EditorTool.select;
    _touch();
    notifyListeners();
  }

  void updateImageRect(int pageIndex, String imageId, Rect rect) {
    if (_note == null) return;
    NoteImage? img;
    for (final i in _note!.pages[pageIndex].images) {
      if (i.id == imageId) {
        img = i;
        break;
      }
    }
    if (img == null) return;
    img.rect = rect;
    _touch();
    notifyListeners();
  }

  void selectImage(String? imageId) {
    _selectedImageId = imageId;
    notifyListeners();
  }

  void removeImage(int pageIndex, String imageId) {
    if (_note == null) return;
    _note!.pages[pageIndex].images.removeWhere((i) => i.id == imageId);
    if (_selectedImageId == imageId) _selectedImageId = null;
    _touch();
    notifyListeners();
  }

  // --- Pages ---------------------------------------------------------------

  /// Paper template applied to newly created blank pages.
  PageBackground _defaultBackground = PageBackground.grid;
  PageBackground get defaultBackground => _defaultBackground;

  /// Sets the paper template for every non-PDF page and for future pages.
  void setBackground(PageBackground bg) {
    _defaultBackground = bg;
    if (_note != null) {
      for (final p in _note!.pages) {
        if (p.backgroundAsset == null) p.background = bg;
      }
    }
    _touch();
    notifyListeners();
  }

  void addBlankPage({int? afterIndex}) {
    if (_note == null) return;
    final page = CanvasPage(id: _uuid.v4(), background: _defaultBackground);
    if (afterIndex == null || afterIndex >= _note!.pages.length - 1) {
      _note!.pages.add(page);
    } else {
      _note!.pages.insert(afterIndex + 1, page);
    }
    _touch();
    notifyListeners();
  }

  void deletePage(int index) {
    if (_note == null || _note!.pages.length <= 1) return;
    _note!.pages.removeAt(index);
    _touch();
    notifyListeners();
  }

  /// Imports a PDF, rasterizing each page into a new background canvas page.
  /// When [afterIndex] is provided the pages are inserted right after it,
  /// enabling "insert between PDF pages" workflows.
  Future<int> importPdf(String filePath, {int? afterIndex}) async {
    if (_note == null) return 0;
    final pages = await PdfImportService.rasterize(filePath);
    var insertAt = (afterIndex ?? _note!.pages.length - 1) + 1;
    final startedAt = insertAt;
    for (final raster in pages) {
      final id = _uuid.v4();
      final fileName = '$id.png';
      await _storage.saveAsset(_note!.id, fileName, raster.png);
      // Normalize page width to A4 width, preserving the PDF aspect ratio.
      final w = kA4LogicalWidth;
      final h = w * (raster.height / raster.width);
      final page = CanvasPage(
        id: id,
        width: w,
        height: h,
        backgroundAsset: fileName,
        background: PageBackground.blank,
      );
      _note!.pages.insert(insertAt.clamp(0, _note!.pages.length), page);
      insertAt++;
    }
    _touch();
    notifyListeners();
    return startedAt;
  }

  // --- Persistence ---------------------------------------------------------

  void _touch() {
    _note?.updatedAt = DateTime.now();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), saveNow);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    final note = _note;
    if (note == null) return;
    await _storage.saveNote(note);
    await _library.syncSummary(note);
  }

  void renameTitle(String title) {
    if (_note == null) return;
    _note!.title = title.trim().isEmpty ? _note!.title : title.trim();
    _touch();
    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    strokeTick.dispose();
    super.dispose();
  }
}
