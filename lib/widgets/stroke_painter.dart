import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../models/canvas_page.dart';
import '../models/stroke.dart';

/// Draws the paper template (grid / lines / dots) plus the committed ink.
/// Repaints only when the page content actually changes (stroke committed,
/// erased, background switched), not on every pointer move.
class PageContentPainter extends CustomPainter {
  PageContentPainter({
    required this.strokes,
    required this.background,
    required this.hasPdfBackground,
    required this.logicalWidth,
    required this.logicalHeight,
  }) : _strokeCount = strokes.length;

  final List<Stroke> strokes;

  // Snapshotted at build time: comparing strokes.length in shouldRepaint is
  // useless because old & new painters share the same list reference.
  final int _strokeCount;
  final PageBackground background;
  final bool hasPdfBackground;
  final double logicalWidth;
  final double logicalHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / logicalWidth;
    canvas.save();
    canvas.scale(scale);

    if (!hasPdfBackground) {
      _paintTemplate(canvas, scale);
    }

    // Highlighter under ink.
    for (final s in strokes) {
      if (s.isHighlighter) paintStroke(canvas, s);
    }
    for (final s in strokes) {
      if (!s.isHighlighter) paintStroke(canvas, s);
    }
    canvas.restore();
  }

  void _paintTemplate(Canvas canvas, double scale) {
    if (background == PageBackground.blank) return;
    // Keep ~1 device px regardless of zoom and anti-alias on, so the ruling
    // stays put relative to the ink instead of snapping/drifting at each zoom.
    final line = Paint()
      ..color = const Color(0xFFD6E0F0)
      ..strokeWidth = 1 / scale
      ..isAntiAlias = true;

    switch (background) {
      case PageBackground.grid:
        for (double x = kRuleSpacing; x < logicalWidth; x += kRuleSpacing) {
          canvas.drawLine(Offset(x, 0), Offset(x, logicalHeight), line);
        }
        for (double y = kRuleSpacing; y < logicalHeight; y += kRuleSpacing) {
          canvas.drawLine(Offset(0, y), Offset(logicalWidth, y), line);
        }
      case PageBackground.lines:
        for (double y = kRuleSpacing; y < logicalHeight; y += kRuleSpacing) {
          canvas.drawLine(Offset(0, y), Offset(logicalWidth, y), line);
        }
      case PageBackground.dots:
        final dot = Paint()..color = const Color(0xFFBFCBE0);
        for (double x = kRuleSpacing; x < logicalWidth; x += kRuleSpacing) {
          for (double y = kRuleSpacing; y < logicalHeight; y += kRuleSpacing) {
            canvas.drawCircle(Offset(x, y), 1.2, dot);
          }
        }
      case PageBackground.blank:
        break;
    }
  }

  @override
  bool shouldRepaint(PageContentPainter old) =>
      old._strokeCount != _strokeCount ||
      old.background != background ||
      old.hasPdfBackground != hasPdfBackground;
}

/// Draws only the in-progress stroke. Wired with `repaint:` to a tick notifier
/// so it repaints on pointer move without rebuilding any widgets.
class ActiveStrokePainter extends CustomPainter {
  ActiveStrokePainter({
    required this.getStroke,
    required this.logicalWidth,
    required Listenable repaint,
  }) : super(repaint: repaint);

  /// Returns the live stroke for this page, or null when none is active.
  final Stroke? Function() getStroke;
  final double logicalWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = getStroke();
    if (stroke == null) return;
    final scale = size.width / logicalWidth;
    canvas.save();
    canvas.scale(scale);
    paintStroke(canvas, stroke);
    canvas.restore();
  }

  // Always repaint: the tick notifier already gates when this fires.
  @override
  bool shouldRepaint(ActiveStrokePainter old) => true;
}

/// Shared stroke rendering: a single quadratic-smoothed path through point
/// midpoints. One draw call per stroke keeps the live layer cheap and smooth.
void paintStroke(Canvas canvas, Stroke stroke) {
  final pts = stroke.points;
  if (pts.isEmpty) return;

  final paint = Paint()
    ..color = Color(stroke.color)
    ..strokeWidth = stroke.width
    ..style = PaintingStyle.stroke
    ..strokeCap = stroke.isHighlighter ? StrokeCap.square : StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  if (pts.length == 1) {
    canvas.drawPoints(PointMode.points, pts, paint);
    return;
  }

  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length - 1; i++) {
    final mid = Offset(
      (pts[i].dx + pts[i + 1].dx) / 2,
      (pts[i].dy + pts[i + 1].dy) / 2,
    );
    path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  canvas.drawPath(path, paint);
}
