import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/canvas_page.dart';
import 'canvas_page_view.dart';

/// Scrollable / zoomable viewport hosting the column of canvas pages.
///
/// Zoom is applied by resizing the pages (crisp vector rendering), not by a
/// scaling transform, so ink and ruling stay sharp at any zoom. Panning uses a
/// translation-only transform.
///
/// Input: touch & trackpad pinch -> zoom; one finger / trackpad drag -> pan;
/// mouse wheel -> scroll. Pen & mouse are deliberately not captured here so
/// they reach the per-page drawing layer.
class CanvasViewport extends StatefulWidget {
  const CanvasViewport({
    super.key,
    required this.pages,
    this.onPageChanged,
  });

  final List<CanvasPage> pages;
  final ValueChanged<int>? onPageChanged;

  @override
  State<CanvasViewport> createState() => _CanvasViewportState();
}

class _CanvasViewportState extends State<CanvasViewport> {
  static const double _minZoom = 0.4;
  static const double _maxZoom = 5.0;
  static const double _basePad = 16;
  static const double _baseGap = 24;

  double _zoom = 1.0;
  Offset _offset = Offset.zero; // top-left scroll offset, in display pixels

  // Gesture anchors.
  double _startZoom = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  int _reportedPage = -1;

  /// Base (zoom-1) content size for the current viewport width.
  double _baseWidth(double viewportWidth) =>
      (viewportWidth - 2 * _basePad).clamp(280.0, 900.0);

  /// Total content size in display pixels at the given [zoom], computed the
  /// same way the page column lays out (so clamping/positioning stay exact).
  ({double w, double h}) _contentSize(double viewportWidth, double zoom) {
    final pw = _baseWidth(viewportWidth) * zoom;
    final pad = _basePad * zoom;
    final gap = _baseGap * zoom;
    var h = 2 * pad;
    for (var i = 0; i < widget.pages.length; i++) {
      final p = widget.pages[i];
      h += pw * (p.height / p.width);
      if (i != widget.pages.length - 1) h += gap;
    }
    return (w: pw + 2 * pad, h: h);
  }

  void _clampOffset(Size viewport, double zoom) {
    final size = _contentSize(viewport.width, zoom);
    final maxX = (size.w - viewport.width).clamp(0.0, double.infinity);
    final maxY = (size.h - viewport.height).clamp(0.0, double.infinity);
    _offset = Offset(
      _offset.dx.clamp(0.0, maxX),
      _offset.dy.clamp(0.0, maxY),
    );
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startZoom = _zoom;
    _startOffset = _offset;
    _startFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size viewport) {
    final newZoom = (_startZoom * d.scale).clamp(_minZoom, _maxZoom);
    // Keep the content point under the initial focal anchored while zooming,
    // and pan as the focal moves.
    final sceneFocal = (_startOffset + _startFocal) / _startZoom;
    setState(() {
      _zoom = newZoom;
      _offset = sceneFocal * newZoom - d.localFocalPoint;
      _clampOffset(viewport, newZoom);
    });
    _maybeReportPage(viewport);
  }

  void _onPointerSignal(PointerSignalEvent e, Size viewport) {
    if (e is! PointerScrollEvent) return;
    setState(() {
      _offset += e.scrollDelta;
      _clampOffset(viewport, _zoom);
    });
    _maybeReportPage(viewport);
  }

  void _setZoom(double zoom, Size viewport) {
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    // Zoom around the viewport center.
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final sceneCenter = (_offset + center) / _zoom;
    setState(() {
      _zoom = clamped;
      _offset = sceneCenter * clamped - center;
      _clampOffset(viewport, clamped);
    });
    _maybeReportPage(viewport);
  }

  void _maybeReportPage(Size viewport) {
    if (widget.onPageChanged == null || widget.pages.isEmpty) return;
    final pw = _baseWidth(viewport.width) * _zoom;
    final pad = _basePad * _zoom;
    final gap = _baseGap * _zoom;
    // Display-space y of the viewport center, in content coordinates.
    final centerY = _offset.dy + viewport.height / 2;
    var y = pad;
    var index = 0;
    for (var i = 0; i < widget.pages.length; i++) {
      final ph = pw * (widget.pages[i].height / widget.pages[i].width);
      if (centerY <= y + ph + gap / 2) {
        index = i;
        break;
      }
      y += ph + gap;
      index = i;
    }
    if (index != _reportedPage) {
      _reportedPage = index;
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => widget.onPageChanged?.call(index));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final pageWidth = _baseWidth(viewport.width) * _zoom;
        final pad = _basePad * _zoom;
        final gap = _baseGap * _zoom;
        final size = _contentSize(viewport.width, _zoom);
        final contentW = size.w;
        final contentH = size.h;

        // Center when smaller than the viewport, otherwise translate by offset.
        final dx = contentW <= viewport.width
            ? (viewport.width - contentW) / 2
            : -_offset.dx;
        final dy = contentH <= viewport.height
            ? (viewport.height - contentH) / 2
            : -_offset.dy;

        // OverflowBox lets the (taller-than-viewport) column take its intrinsic
        // height without a RenderFlex overflow; the outer ClipRect clips it.
        final content = OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: contentW,
          maxWidth: contentW,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.pages.length; i++) ...[
                  CanvasPageView(
                    pageIndex: i,
                    page: widget.pages[i],
                    displayWidth: pageWidth,
                  ),
                  if (i != widget.pages.length - 1) SizedBox(height: gap),
                ],
              ],
            ),
          ),
        );

        return Listener(
          onPointerSignal: (e) => _onPointerSignal(e, viewport),
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              ScaleGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
                () => ScaleGestureRecognizer(
                  // Pen & mouse are reserved for drawing; only fingers and the
                  // trackpad pan/zoom the canvas.
                  supportedDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.trackpad,
                  },
                ),
                (instance) {
                  instance
                    ..onStart = _onScaleStart
                    ..onUpdate = (d) => _onScaleUpdate(d, viewport);
                },
              ),
            },
            child: ClipRect(
              child: Stack(
                children: [
                  // Absolute placement with an explicit size so the (often
                  // taller-than-viewport) content escapes viewport constraints
                  // and is simply clipped; dx/dy may be negative when scrolled.
                  Positioned(
                    left: dx,
                    top: dy,
                    width: contentW,
                    height: contentH,
                    child: content,
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: _ZoomPill(
                      zoom: _zoom,
                      onZoomOut: () => _setZoom(_zoom - 0.1, viewport),
                      onZoomIn: () => _setZoom(_zoom + 0.1, viewport),
                      onReset: () => _setZoom(1.0, viewport),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ZoomPill extends StatelessWidget {
  const _ZoomPill({
    required this.zoom,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onReset,
  });

  final double zoom;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(24),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              icon: const Icon(Icons.remove),
              onPressed: onZoomOut,
            ),
            InkWell(
              onTap: onReset,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text('${(zoom * 100).round()}%',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              icon: const Icon(Icons.add),
              onPressed: onZoomIn,
            ),
          ],
        ),
      ),
    );
  }
}
