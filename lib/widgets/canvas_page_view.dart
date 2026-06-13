import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/canvas_page.dart';
import '../models/note_image.dart';
import '../providers/note_provider.dart';
import 'stroke_painter.dart';

/// Renders a single canvas page at [displayWidth] and routes pointer input to
/// the [NoteProvider].
///
/// Input model (Samsung-Notes style):
///  * stylus / mouse with a drawing tool selected -> draws (or erases);
///  * inverted stylus (eraser end) -> erases regardless of tool;
///  * finger / touch -> ignored here so the page scrolls instead.
class CanvasPageView extends StatelessWidget {
  const CanvasPageView({
    super.key,
    required this.pageIndex,
    required this.page,
    required this.displayWidth,
  });

  final int pageIndex;
  final CanvasPage page;
  final double displayWidth;

  double get _displayHeight => displayWidth * (page.height / page.width);
  double get _scale => displayWidth / page.width;

  Offset _toLogical(Offset local) => local / _scale;

  bool _isDrawDevice(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus ||
      kind == PointerDeviceKind.mouse;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NoteProvider>();
    final read = context.read<NoteProvider>();
    final tool = provider.tool;
    final isInk =
        tool == EditorTool.pen || tool == EditorTool.highlighter;
    final isEraser = tool == EditorTool.eraser;
    final interactive = isInk || isEraser;

    void handle(PointerEvent e, {required bool isDown}) {
      // Touch is reserved for navigation; only pen/mouse interact with ink.
      if (!_isDrawDevice(e.kind)) return;
      final inverted = e.kind == PointerDeviceKind.invertedStylus;
      final p = _toLogical(e.localPosition);
      if (isEraser || inverted) {
        read.eraseAt(pageIndex, p);
      } else if (isDown) {
        read.startStroke(pageIndex, p);
      } else {
        read.extendStroke(p);
      }
    }

    return RepaintBoundary(
      child: Center(
        child: Container(
          width: displayWidth,
          height: _displayHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: ClipRect(
            child: Stack(
              children: [
                // PDF background, if this page was imported from a PDF.
                if (page.backgroundAsset != null)
                  Positioned.fill(
                    child: Image.file(
                      File(provider.assetPath(page.backgroundAsset!)),
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    ),
                  ),

                // Paper template + committed ink (repaints only on change).
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: PageContentPainter(
                        strokes: page.strokes,
                        background: page.background,
                        hasPdfBackground: page.backgroundAsset != null,
                        logicalWidth: page.width,
                        logicalHeight: page.height,
                      ),
                    ),
                  ),
                ),

                // Embedded images.
                for (final img in page.images)
                  _ImageLayer(
                    pageIndex: pageIndex,
                    image: img,
                    scale: _scale,
                    selectable: tool == EditorTool.select,
                    selected: provider.selectedImageId == img.id,
                  ),

                // Live (in-progress) stroke — repaints via the tick notifier.
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: ActiveStrokePainter(
                        repaint: read.strokeTick,
                        logicalWidth: page.width,
                        getStroke: () => read.activeStrokePage == pageIndex
                            ? read.activeStroke
                            : null,
                      ),
                    ),
                  ),
                ),

                // Pointer capture for drawing / erasing.
                if (interactive)
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (e) => handle(e, isDown: true),
                      onPointerMove: (e) => handle(e, isDown: false),
                      onPointerUp: (_) => read.endStroke(),
                      onPointerCancel: (_) => read.endStroke(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A movable / resizable embedded image shown when the select tool is active.
class _ImageLayer extends StatelessWidget {
  const _ImageLayer({
    required this.pageIndex,
    required this.image,
    required this.scale,
    required this.selectable,
    required this.selected,
  });

  final int pageIndex;
  final NoteImage image;
  final double scale;
  final bool selectable;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<NoteProvider>();
    final rect = image.rect;
    final left = rect.left * scale;
    final top = rect.top * scale;
    final width = rect.width * scale;
    final height = rect.height * scale;
    const minLogical = 40.0;

    final imageWidget = Image.file(
      File(provider.assetPath(image.assetFile)),
      width: width,
      height: height,
      fit: BoxFit.fill,
      gaplessPlayback: true,
    );

    if (!selectable) {
      return Positioned(left: left, top: top, child: imageWidget);
    }

    return Positioned(
      left: left,
      top: top,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: () => provider.selectImage(image.id),
            onPanStart: (_) => provider.selectImage(image.id),
            onPanUpdate: (d) {
              final dx = d.delta.dx / scale;
              final dy = d.delta.dy / scale;
              provider.updateImageRect(
                pageIndex,
                image.id,
                image.rect.translate(dx, dy),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: selected
                      ? Colors.blue
                      : Colors.blue.withValues(alpha: 0.4),
                  width: selected ? 2 : 1,
                ),
              ),
              child: imageWidget,
            ),
          ),
          if (selected) ...[
            // Delete handle (top-right).
            Positioned(
              right: -14,
              top: -14,
              child: _Handle(
                icon: Icons.close,
                color: Colors.red,
                onTap: () => provider.removeImage(pageIndex, image.id),
              ),
            ),
            // Resize handle (bottom-right).
            Positioned(
              right: -14,
              bottom: -14,
              child: GestureDetector(
                onPanUpdate: (d) {
                  final newW = (image.rect.width + d.delta.dx / scale)
                      .clamp(minLogical, 100000.0);
                  final newH = (image.rect.height + d.delta.dy / scale)
                      .clamp(minLogical, 100000.0);
                  provider.updateImageRect(
                    pageIndex,
                    image.id,
                    Rect.fromLTWH(
                        image.rect.left, image.rect.top, newW, newH),
                  );
                },
                child: const _Handle(
                    icon: Icons.open_in_full, color: Colors.blue),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({required this.icon, required this.color, this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
