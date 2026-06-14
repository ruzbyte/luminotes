import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/canvas_page.dart';
import '../providers/note_provider.dart';
import '../widgets/canvas_viewport.dart';
import '../widgets/editor_toolbar.dart';

/// Full-screen canvas editor: a zoomable column of A4 pages plus the tool
/// toolbar. Pen/mouse draw; finger & trackpad pan/zoom (Samsung-Notes style).
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, required this.noteId});

  final String noteId;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final CanvasViewportController _viewportController =
      CanvasViewportController();
  int _currentPage = 0;
  bool _busy = false;
  NoteProvider? _provider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NoteProvider>().open(widget.noteId);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = context.read<NoteProvider>();
  }

  @override
  void dispose() {
    _provider?.saveNow(); // flush pending edits
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NoteProvider>();
    final note = provider.note;

    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          dark ? const Color(0xFF1F1F23) : const Color(0xFFE8E8EC),
      appBar: AppBar(
        title: note == null
            ? const Text('Loading…')
            : _TitleField(title: note.title, onChanged: provider.renameTitle),
        actions: note == null
            ? null
            : [
                Center(
                  child: TextButton(
                    onPressed: () => _jumpToPage(note.pages.length),
                    child: Text('${_currentPage + 1} / ${note.pages.length}'),
                  ),
                ),
                IconButton(
                  tooltip: 'Insert image',
                  icon: const Icon(Icons.image_outlined),
                  onPressed: _busy ? null : () => _insertImage(provider),
                ),
                IconButton(
                  tooltip: 'Import PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: _busy ? null : () => _importPdf(provider),
                ),
                // Page operations.
                PopupMenuButton<String>(
                  tooltip: 'Pages',
                  icon: const Icon(Icons.note_add_outlined),
                  onSelected: (v) => _onPageMenu(v, provider),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'before', child: Text('Insert page before')),
                    PopupMenuItem(
                        value: 'after', child: Text('Insert page after')),
                    PopupMenuDivider(),
                    PopupMenuItem(
                        value: 'delete', child: Text('Delete this page')),
                  ],
                ),
                // Paper background.
                PopupMenuButton<PageBackground>(
                  tooltip: 'Paper',
                  icon: const Icon(Icons.grid_on),
                  onSelected: provider.setBackground,
                  itemBuilder: (_) => [
                    _paperItem(PageBackground.grid, 'Grid paper',
                        provider.defaultBackground),
                    _paperItem(PageBackground.lines, 'Lined paper',
                        provider.defaultBackground),
                    _paperItem(PageBackground.dots, 'Dotted paper',
                        provider.defaultBackground),
                    _paperItem(PageBackground.blank, 'Blank paper',
                        provider.defaultBackground),
                  ],
                ),
              ],
      ),
      body: note == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                CanvasViewport(
                  pages: note.pages,
                  controller: _viewportController,
                  // In select/text tools, disable touch pan/zoom so taps & drags
                  // reach the text/image overlays.
                  allowTouchPanZoom: provider.tool != EditorTool.select &&
                      provider.tool != EditorTool.text,
                  onPageChanged: (i) {
                    if (i != _currentPage) setState(() => _currentPage = i);
                  },
                ),
                if (_busy)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x66000000),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: note == null ? null : const EditorToolbar(),
    );
  }

  Future<void> _jumpToPage(int pageCount) async {
    final controller = TextEditingController(text: '${_currentPage + 1}');
    final target = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Page (1–$pageCount)'),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    if (target == null) return;
    _viewportController.jumpToPage(target.clamp(1, pageCount) - 1);
  }

  void _onPageMenu(String value, NoteProvider provider) {
    switch (value) {
      case 'before':
        provider.addBlankPage(afterIndex: _currentPage - 1);
      case 'after':
        provider.addBlankPage(afterIndex: _currentPage);
      case 'delete':
        provider.deletePage(_currentPage);
    }
  }

  PopupMenuItem<PageBackground> _paperItem(
    PageBackground bg,
    String label,
    PageBackground current,
  ) {
    return PopupMenuItem(
      value: bg,
      child: Row(
        children: [
          Icon(bg == current ? Icons.check : Icons.crop_square_outlined,
              size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Future<void> _insertImage(NoteProvider provider) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) return;
    final ext = (file.extension ?? 'png').toLowerCase();
    await provider.addImage(_currentPage, bytes, ext);
  }

  Future<void> _importPdf(NoteProvider provider) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = result?.files.first.path;
    if (path == null) return;
    setState(() => _busy = true);
    try {
      await provider.importPdf(path, afterIndex: _currentPage);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF import failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _TitleField extends StatefulWidget {
  const _TitleField({required this.title, required this.onChanged});
  final String title;
  final ValueChanged<String> onChanged;

  @override
  State<_TitleField> createState() => _TitleFieldState();
}

class _TitleFieldState extends State<_TitleField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.title);

  @override
  void didUpdateWidget(_TitleField old) {
    super.didUpdateWidget(old);
    if (old.title != widget.title && _controller.text != widget.title) {
      _controller.text = widget.title;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      style: Theme.of(context).textTheme.titleLarge,
      decoration: const InputDecoration(
        border: InputBorder.none,
        hintText: 'Untitled',
      ),
    );
  }
}
