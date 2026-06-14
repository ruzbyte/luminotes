import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../models/canvas_page.dart';
import '../models/note.dart';
import '../models/note_image.dart';
import '../models/note_text.dart';
import '../models/stroke.dart';
import '../services/storage_service.dart';
import 'library_provider.dart';

enum EditorTool { pen, highlighter, eraser, text, pan, select }

/// A reversible edit: [undo] restores the previous state, [redo] re-applies it.
class _UndoEntry {
  _UndoEntry(this.undo, this.redo);
  final VoidCallback undo;
  final VoidCallback redo;
}

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

  /// Currently selected / freshly created text box.
  String? _selectedTextId;
  String? get selectedTextId => _selectedTextId;

  /// Text box that should grab keyboard focus (just created).
  String? _editingTextId;
  String? get editingTextId => _editingTextId;

  // --- Undo / redo ---------------------------------------------------------
  final List<_UndoEntry> _undoStack = [];
  final List<_UndoEntry> _redoStack = [];
  static const int _maxUndo = 200;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void _pushUndo(VoidCallback undo, VoidCallback redo) {
    _undoStack.add(_UndoEntry(undo, redo));
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    entry.undo();
    _redoStack.add(entry);
    _touch();
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();
    entry.redo();
    _undoStack.add(entry);
    _touch();
    notifyListeners();
  }

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
    await _disposePdfDocs();
    _note = await _storage.loadNote(noteId);
    _selectedImageId = null;
    _selectedTextId = null;
    _editingTextId = null;
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  void setTool(EditorTool tool) {
    // Drop any in-progress stroke so it can't leak across a tool change.
    if (_drawing) cancelStroke();
    _tool = tool;
    if (tool != EditorTool.select) _selectedImageId = null;
    if (tool != EditorTool.select && tool != EditorTool.text) {
      _selectedTextId = null;
      _editingTextId = null;
    }
    notifyListeners();
  }

  void setPenColor(int color) {
    // While a text box is selected, recolor it instead of the pen.
    if (_selectedTextId != null &&
        (_tool == EditorTool.text || _tool == EditorTool.select)) {
      final t = _findText(_selectedTextId!);
      if (t != null) {
        t.color = color;
        _touch();
        notifyListeners();
        return;
      }
    }
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
      final page = note.pages[_activeStrokePage];
      page.strokes.add(stroke);
      _pushUndo(
        () => page.strokes.remove(stroke),
        () => page.strokes.add(stroke),
      );
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

  // Snapshot of a page's strokes taken at the start of an eraser gesture, so
  // the whole gesture collapses into a single undo step.
  List<Stroke>? _eraseSnapshot;
  int _erasePage = -1;

  /// Object-eraser: removes whole strokes within [radius] of [logicalPoint].
  void eraseAt(int pageIndex, Offset logicalPoint, {double radius = 12}) {
    if (_note == null) return;
    final strokes = _note!.pages[pageIndex].strokes;
    _eraseSnapshot ??= List<Stroke>.from(strokes);
    _erasePage = pageIndex;
    final before = strokes.length;
    strokes.removeWhere((s) => _strokeHit(s, logicalPoint, radius));
    if (strokes.length != before) {
      _touch();
      notifyListeners();
    }
  }

  /// Finalizes an eraser gesture, pushing one undo step for everything erased.
  void endErase() {
    final snapshot = _eraseSnapshot;
    if (snapshot == null || _note == null) {
      _eraseSnapshot = null;
      return;
    }
    final page = _note!.pages[_erasePage];
    final after = List<Stroke>.from(page.strokes);
    _eraseSnapshot = null;
    if (snapshot.length != after.length) {
      _pushUndo(
        () => page.strokes
          ..clear()
          ..addAll(snapshot),
        () => page.strokes
          ..clear()
          ..addAll(after),
      );
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
    final image = NoteImage(id: id, assetFile: fileName, rect: rect);
    page.images.add(image);
    _pushUndo(
      () => page.images.remove(image),
      () => page.images.add(image),
    );
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
    final images = _note!.pages[pageIndex].images;
    final index = images.indexWhere((i) => i.id == imageId);
    if (index < 0) return;
    final image = images.removeAt(index);
    _pushUndo(
      () => images.insert(index.clamp(0, images.length), image),
      () => images.remove(image),
    );
    if (_selectedImageId == imageId) _selectedImageId = null;
    _touch();
    notifyListeners();
  }

  // --- Text ----------------------------------------------------------------

  NoteText? _findText(String id) {
    if (_note == null) return null;
    for (final page in _note!.pages) {
      for (final t in page.texts) {
        if (t.id == id) return t;
      }
    }
    return null;
  }

  /// Creates a text box at [logicalPoint] and marks it for editing/focus,
  /// switching to the select tool so it can be typed in and moved immediately.
  void addText(int pageIndex, Offset logicalPoint) {
    if (_note == null) return;
    final page = _note!.pages[pageIndex];
    // Keep the box within the page and ensure a sane minimum width.
    final maxAvail = (page.width - logicalPoint.dx).clamp(60.0, page.width);
    final width = (page.width * 0.5).clamp(60.0, maxAvail);
    final text = NoteText(
      id: _uuid.v4(),
      position: logicalPoint,
      width: width,
      fontSize: 28,
      color: _penColor,
    );
    page.texts.add(text);
    _pushUndo(
      () => page.texts.remove(text),
      () => page.texts.add(text),
    );
    _selectedTextId = text.id;
    _editingTextId = text.id;
    _tool = EditorTool.select;
    _touch();
    notifyListeners();
  }

  void selectText(String? id, {bool edit = false}) {
    _selectedTextId = id;
    _editingTextId = edit ? id : null;
    notifyListeners();
  }

  /// Called once focus has been granted so the box isn't re-focused on rebuild.
  void clearEditingText() {
    _editingTextId = null;
  }

  void updateTextContent(String id, String content) {
    final t = _findText(id);
    if (t == null) return;
    t.text = content;
    _touch();
    // No notifyListeners: the TextField owns its own display while editing.
  }

  void moveText(String id, Offset delta) {
    final t = _findText(id);
    if (t == null) return;
    t.position += delta;
    _touch();
    notifyListeners();
  }

  void setTextWidth(String id, double width) {
    final t = _findText(id);
    if (t == null) return;
    t.width = width.clamp(60.0, 100000.0);
    _touch();
    notifyListeners();
  }

  void setTextFontSize(String id, double fontSize) {
    final t = _findText(id);
    if (t == null) return;
    t.fontSize = fontSize.clamp(8.0, 200.0);
    _touch();
    notifyListeners();
  }

  void removeText(int pageIndex, String id) {
    if (_note == null) return;
    final texts = _note!.pages[pageIndex].texts;
    final index = texts.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final text = texts.removeAt(index);
    _pushUndo(
      () => texts.insert(index.clamp(0, texts.length), text),
      () => texts.remove(text),
    );
    if (_selectedTextId == id) _selectedTextId = null;
    if (_editingTextId == id) _editingTextId = null;
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
    final pages = _note!.pages;
    final page = CanvasPage(id: _uuid.v4(), background: _defaultBackground);
    final at = (afterIndex == null || afterIndex >= pages.length - 1)
        ? pages.length
        : afterIndex + 1;
    pages.insert(at, page);
    _pushUndo(
      () => pages.remove(page),
      () => pages.insert(at.clamp(0, pages.length), page),
    );
    _touch();
    notifyListeners();
  }

  void deletePage(int index) {
    if (_note == null || _note!.pages.length <= 1) return;
    final pages = _note!.pages;
    final page = pages.removeAt(index);
    _pushUndo(
      () => pages.insert(index.clamp(0, pages.length), page),
      () => pages.remove(page),
    );
    _touch();
    notifyListeners();
  }

  // --- PDF (on-demand rendering) -------------------------------------------

  /// Opened PDF documents, cached per asset file so [PdfPageView] can render
  /// pages lazily without re-opening. Disposed when the note closes.
  final Map<String, Future<PdfDocument>> _pdfDocs = {};

  Future<PdfDocument> pdfDocument(String assetFile) {
    return _pdfDocs.putIfAbsent(
      assetFile,
      () => PdfDocument.openFile(_storage.assetPath(_note!.id, assetFile)),
    );
  }

  Future<void> _disposePdfDocs() async {
    final docs = _pdfDocs.values.toList();
    _pdfDocs.clear();
    for (final f in docs) {
      try {
        (await f).dispose();
      } catch (_) {/* ignore */}
    }
  }

  /// Imports a PDF by copying it into the note's assets and creating one
  /// canvas page per PDF page. Pages render on demand (no upfront
  /// rasterization), so even very large PDFs import quickly and stay light on
  /// memory. With [afterIndex] the pages are inserted right after it.
  Future<int> importPdf(String filePath, {int? afterIndex}) async {
    if (_note == null) return 0;
    // Copy the PDF into the note's assets once (streamed, not loaded to RAM).
    final assetName = '${_uuid.v4()}.pdf';
    await _storage.copyAsset(_note!.id, assetName, filePath);

    // Read page sizes only (fast, no rendering).
    final doc = await PdfDocument.openFile(filePath);
    var insertAt = (afterIndex ?? _note!.pages.length - 1) + 1;
    final startedAt = insertAt;
    try {
      for (final p in doc.pages) {
        final w = kA4LogicalWidth;
        final h = w * (p.height / p.width);
        final page = CanvasPage(
          id: _uuid.v4(),
          width: w,
          height: h,
          background: PageBackground.blank,
          pdfAsset: assetName,
          pdfPage: p.pageNumber,
        );
        _note!.pages.insert(insertAt.clamp(0, _note!.pages.length), page);
        insertAt++;
      }
    } finally {
      await doc.dispose();
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
    _disposePdfDocs();
    super.dispose();
  }
}
