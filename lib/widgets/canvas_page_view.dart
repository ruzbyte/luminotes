import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../models/canvas_page.dart';
import '../models/note_image.dart';
import '../models/note_text.dart';
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
    final isText = tool == EditorTool.text;
    final textEditable = isText || tool == EditorTool.select;

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
                // PDF background. New imports render on demand via pdfrx;
                // legacy notes keep their pre-rasterized PNG.
                if (page.pdfAsset != null)
                  Positioned.fill(
                    child: _PdfBackground(
                      assetFile: page.pdfAsset!,
                      pageNumber: page.pdfPage ?? 1,
                    ),
                  )
                else if (page.backgroundAsset != null)
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
                        hasPdfBackground: page.hasPdfBackground,
                        logicalWidth: page.width,
                        logicalHeight: page.height,
                      ),
                    ),
                  ),
                ),

                // Live (in-progress) stroke — repaints via the tick notifier.
                // Kept below the image/text overlays so those receive taps.
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

                // Embedded images (on top, so they're selectable/movable).
                for (final img in page.images)
                  _ImageLayer(
                    pageIndex: pageIndex,
                    image: img,
                    scale: _scale,
                    selectable: tool == EditorTool.select,
                    selected: provider.selectedImageId == img.id,
                  ),

                // Text boxes (on top).
                for (final txt in page.texts)
                  _TextItem(
                    key: ValueKey(txt.id),
                    pageIndex: pageIndex,
                    text: txt,
                    scale: _scale,
                    interactive: textEditable,
                    selected: provider.selectedTextId == txt.id,
                    autofocus: provider.editingTextId == txt.id,
                  ),

                // Pointer capture for drawing / erasing.
                if (interactive)
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (e) => handle(e, isDown: true),
                      onPointerMove: (e) => handle(e, isDown: false),
                      onPointerUp: (_) {
                        read.endStroke();
                        read.endErase();
                      },
                      onPointerCancel: (_) {
                        read.endStroke();
                        read.endErase();
                      },
                    ),
                  ),

                // Tap-to-place layer for the text tool. A raw Listener is used
                // (not a GestureDetector) so the tap isn't swallowed by the
                // viewport's pan/zoom scale recognizer on touch devices.
                if (isText)
                  Positioned.fill(
                    child: _TextCreateLayer(
                      onCreate: (local) =>
                          read.addText(pageIndex, _toLogical(local)),
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

    // Expand the hit area by [pad] on all sides so the corner handles, which
    // sit on the box edges, stay inside the parent's bounds and are tappable.
    const pad = _kHandlePad;
    return Positioned(
      left: left - pad,
      top: top - pad,
      width: width + 2 * pad,
      height: height + 2 * pad,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: pad,
            top: pad,
            width: width,
            height: height,
            child: GestureDetector(
              onTap: () => provider.selectImage(image.id),
              onPanStart: (_) => provider.selectImage(image.id),
              onPanUpdate: (d) {
                provider.updateImageRect(
                  pageIndex,
                  image.id,
                  image.rect.translate(d.delta.dx / scale, d.delta.dy / scale),
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
          ),
          if (selected) ...[
            // Delete handle (top-right corner).
            Positioned(
              left: pad + width - 14,
              top: pad - 14,
              child: _Handle(
                icon: Icons.close,
                color: Colors.red,
                onTap: () => provider.removeImage(pageIndex, image.id),
              ),
            ),
            // Resize handle (bottom-right corner).
            Positioned(
              left: pad + width - 14,
              top: pad + height - 14,
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

/// Margin (px) added around selectable overlays so their corner handles remain
/// inside the parent bounds and therefore receive pointer events.
const double _kHandlePad = 16;

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

/// On-demand PDF page background. pdfrx's [PdfPageView] renders the page at the
/// widget's size and caches it, so only visible pages consume memory.
class _PdfBackground extends StatelessWidget {
  const _PdfBackground({required this.assetFile, required this.pageNumber});

  final String assetFile;
  final int pageNumber;

  @override
  Widget build(BuildContext context) {
    final future = context.read<NoteProvider>().pdfDocument(assetFile);
    return FutureBuilder<PdfDocument>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.data == null) {
          return const ColoredBox(color: Colors.white);
        }
        return PdfPageView(
          document: snapshot.data,
          pageNumber: pageNumber,
          backgroundColor: Colors.white,
        );
      },
    );
  }
}

/// Raw-pointer tap detector for placing text. Bypasses the gesture arena so a
/// tap isn't stolen by the viewport's pan/zoom recognizer on touch screens.
class _TextCreateLayer extends StatefulWidget {
  const _TextCreateLayer({required this.onCreate});
  final ValueChanged<Offset> onCreate;

  @override
  State<_TextCreateLayer> createState() => _TextCreateLayerState();
}

class _TextCreateLayerState extends State<_TextCreateLayer> {
  Offset? _down;
  bool _moved = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _down = e.localPosition;
        _moved = false;
      },
      onPointerMove: (e) {
        if (_down != null && (e.localPosition - _down!).distance > 10) {
          _moved = true;
        }
      },
      onPointerUp: (e) {
        if (_down != null && !_moved) widget.onCreate(e.localPosition);
        _down = null;
      },
      onPointerCancel: (_) => _down = null,
    );
  }
}

/// A placed text box. Read-only when a drawing tool is active (so the pen can
/// draw over it); editable / movable under the text & select tools.
class _TextItem extends StatefulWidget {
  const _TextItem({
    super.key,
    required this.pageIndex,
    required this.text,
    required this.scale,
    required this.interactive,
    required this.selected,
    required this.autofocus,
  });

  final int pageIndex;
  final NoteText text;
  final double scale;
  final bool interactive;
  final bool selected;
  final bool autofocus;

  @override
  State<_TextItem> createState() => _TextItemState();
}

class _TextItemState extends State<_TextItem> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.text.text);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) _grabFocus();
  }

  @override
  void didUpdateWidget(_TextItem old) {
    super.didUpdateWidget(old);
    // Sync external (e.g. undo) changes when we're not actively editing.
    if (!_focus.hasFocus && _controller.text != widget.text.text) {
      _controller.text = widget.text.text;
    }
    if (widget.autofocus && !old.autofocus) _grabFocus();
  }

  void _grabFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      context.read<NoteProvider>().clearEditingText();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final read = context.read<NoteProvider>();
    final t = widget.text;
    final scale = widget.scale;
    final left = t.position.dx * scale;
    final top = t.position.dy * scale;
    final width = t.width * scale;
    final style = TextStyle(
      color: Color(t.color),
      fontSize: t.fontSize * scale,
      height: 1.2,
    );

    if (!widget.interactive) {
      // Read-only: a bare Text doesn't absorb pointers, so the pen draws over it.
      return Positioned(
        left: left,
        top: top,
        width: width,
        child: IgnorePointer(
          child: Text(t.text.isEmpty ? ' ' : t.text, style: style),
        ),
      );
    }

    // Pad the hit area so the corner handles stay inside the parent's bounds
    // (and thus receive taps/drags); the box itself is inset by [pad].
    const pad = _kHandlePad;
    return Positioned(
      left: left - pad,
      top: top - pad,
      width: width + 2 * pad,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.all(pad),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: widget.selected
                      ? Colors.blue
                      : Colors.blue.withValues(alpha: 0.35),
                  width: widget.selected ? 1.5 : 1,
                ),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                style: style,
                maxLines: null,
                cursorColor: Color(t.color),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(4),
                  hintText: 'Text…',
                ),
                onTap: () => read.selectText(t.id),
                onChanged: (v) => read.updateTextContent(t.id, v),
              ),
            ),
          ),
          if (widget.selected) ...[
            // Move handle (near the top-left corner).
            Positioned(
              left: 0,
              top: 0,
              child: GestureDetector(
                onPanUpdate: (d) => read.moveText(t.id, d.delta / scale),
                child: const _Handle(
                    icon: Icons.open_with, color: Colors.blue),
              ),
            ),
            // Delete handle (near the top-right corner).
            Positioned(
              right: 0,
              top: 0,
              child: _Handle(
                icon: Icons.close,
                color: Colors.red,
                onTap: () => read.removeText(widget.pageIndex, t.id),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
