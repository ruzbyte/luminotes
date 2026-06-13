import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:luminotes/models/canvas_page.dart';
import 'package:luminotes/models/note.dart';
import 'package:luminotes/models/note_image.dart';
import 'package:luminotes/models/stroke.dart';

void main() {
  test('Stroke round-trips through JSON', () {
    final stroke = Stroke(
      points: const [Offset(1, 2), Offset(3, 4), Offset(5, 6)],
      color: 0xFF112233,
      width: 4.5,
      isHighlighter: true,
    );
    final restored = Stroke.fromJson(stroke.toJson());

    expect(restored.points, stroke.points);
    expect(restored.color, stroke.color);
    expect(restored.width, stroke.width);
    expect(restored.isHighlighter, isTrue);
  });

  test('NoteImage preserves its rect', () {
    final img = NoteImage(
      id: 'img1',
      assetFile: 'img1.png',
      rect: const Rect.fromLTWH(10, 20, 100, 200),
    );
    final restored = NoteImage.fromJson(img.toJson());

    expect(restored.id, 'img1');
    expect(restored.assetFile, 'img1.png');
    expect(restored.rect, const Rect.fromLTWH(10, 20, 100, 200));
  });

  test('Note with pages round-trips and keeps page geometry', () {
    final note = Note(
      id: 'n1',
      title: 'Test',
      folderId: 'f1',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
      pages: [
        CanvasPage(id: 'p1')
          ..strokes.add(Stroke(
              points: const [Offset(0, 0), Offset(1, 1)],
              color: 0xFF000000,
              width: 2)),
        CanvasPage(id: 'p2', width: 794, height: 500, backgroundAsset: 'p2.png'),
      ],
    );

    final restored = Note.fromJson(note.toJson());

    expect(restored.id, 'n1');
    expect(restored.title, 'Test');
    expect(restored.folderId, 'f1');
    expect(restored.pages.length, 2);
    expect(restored.pages[0].strokes.length, 1);
    expect(restored.pages[1].backgroundAsset, 'p2.png');
    expect(restored.pages[1].height, 500);
  });

  test('NoteSummary derives from a Note', () {
    final note = Note(
      id: 'n2',
      title: 'Summary',
      folderId: null,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 5),
      pages: [CanvasPage(id: 'p1'), CanvasPage(id: 'p2')],
    );
    final summary = NoteSummary.fromNote(note);

    expect(summary.pageCount, 2);
    expect(summary.folderId, isNull);
    final restored = NoteSummary.fromJson(summary.toJson());
    expect(restored.title, 'Summary');
    expect(restored.pageCount, 2);
  });
}
