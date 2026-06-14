import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/folder.dart';
import '../models/note.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import 'note_editor_screen.dart';

/// Browses folders and notes. Tapping a folder descends into it; tapping a
/// note opens the editor. New folders/notes are created via the FAB.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _folderId;

  List<Folder> _breadcrumb(LibraryProvider lib) {
    final path = <Folder>[];
    var current = lib.folderById(_folderId);
    while (current != null) {
      path.insert(0, current);
      current = lib.folderById(current.parentId);
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryProvider>();
    final folders = lib.foldersIn(_folderId);
    final notes = lib.notesIn(_folderId);
    final crumbs = _breadcrumb(lib);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Luminotes'),
        leading: _folderId == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Up',
                onPressed: () => setState(
                  () => _folderId = crumbs.length >= 2
                      ? crumbs[crumbs.length - 2].id
                      : null,
                ),
              ),
        actions: const [_ThemeToggle()],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Breadcrumb(
            crumbs: crumbs,
            onTapRoot: () => setState(() => _folderId = null),
            onTap: (f) => setState(() => _folderId = f.id),
          ),
          Expanded(
            child: folders.isEmpty && notes.isEmpty
                ? const _EmptyState()
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (folders.isNotEmpty) ...[
                        const _SectionLabel('Folders'),
                        _FolderGrid(
                          folders: folders,
                          onOpen: (f) => setState(() => _folderId = f.id),
                          onRename: (f) => _renameFolder(context, lib, f),
                          onDelete: (f) => _deleteFolder(context, lib, f),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (notes.isNotEmpty) ...[
                        const _SectionLabel('Notes'),
                        _NoteGrid(
                          notes: notes,
                          onOpen: _openNote,
                          onRename: (n) => _renameNote(context, lib, n),
                          onDelete: (n) => _deleteNote(context, lib, n),
                          onMove: (n) => _moveNote(context, lib, n),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: _CreateFab(
        onNewNote: () => _createNote(context, lib),
        onNewFolder: () => _createFolder(context, lib),
      ),
    );
  }

  Future<void> _openNote(NoteSummary n) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: n.id)),
    );
  }

  Future<void> _createNote(BuildContext context, LibraryProvider lib) async {
    final note = await lib.createNote(folderId: _folderId);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: note.id)),
    );
  }

  Future<void> _createFolder(BuildContext context, LibraryProvider lib) async {
    final name = await _promptText(context, 'New folder', 'Folder name');
    if (name == null) return;
    await lib.createFolder(name, parentId: _folderId);
  }

  Future<void> _renameFolder(
      BuildContext context, LibraryProvider lib, Folder f) async {
    final name = await _promptText(context, 'Rename folder', 'Folder name',
        initial: f.name);
    if (name == null) return;
    await lib.renameFolder(f.id, name);
  }

  Future<void> _deleteFolder(
      BuildContext context, LibraryProvider lib, Folder f) async {
    final ok = await _confirm(context, 'Delete folder?',
        'This deletes "${f.name}" and everything inside it.');
    if (ok) await lib.deleteFolder(f.id);
  }

  Future<void> _renameNote(
      BuildContext context, LibraryProvider lib, NoteSummary n) async {
    final name =
        await _promptText(context, 'Rename note', 'Title', initial: n.title);
    if (name == null) return;
    await lib.renameNote(n.id, name);
  }

  Future<void> _deleteNote(
      BuildContext context, LibraryProvider lib, NoteSummary n) async {
    final ok =
        await _confirm(context, 'Delete note?', 'Delete "${n.title}"?');
    if (ok) await lib.deleteNote(n.id);
  }

  Future<void> _moveNote(
      BuildContext context, LibraryProvider lib, NoteSummary n) async {
    final target = await showDialog<({bool root, String? id})>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: const Text('Move to'),
          children: [
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(ctx, (root: true, id: null)),
              child: const Text('Library root'),
            ),
            for (final f in lib.folders)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(ctx, (root: false, id: f.id)),
                child: Text(f.name),
              ),
          ],
        );
      },
    );
    if (target == null) return;
    await lib.moveNote(n.id, target.id);
  }
}

Future<String?> _promptText(
  BuildContext context,
  String title,
  String label, {
  String? initial,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<bool> _confirm(BuildContext context, String title, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.crumbs,
    required this.onTapRoot,
    required this.onTap,
  });

  final List<Folder> crumbs;
  final VoidCallback onTapRoot;
  final ValueChanged<Folder> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton(onPressed: onTapRoot, child: const Text('Library')),
          for (final f in crumbs) ...[
            const Icon(Icons.chevron_right, size: 18),
            TextButton(onPressed: () => onTap(f), child: Text(f.name)),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _FolderGrid extends StatelessWidget {
  const _FolderGrid({
    required this.folders,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final List<Folder> folders;
  final ValueChanged<Folder> onOpen;
  final ValueChanged<Folder> onRename;
  final ValueChanged<Folder> onDelete;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final f in folders)
          SizedBox(
            width: 200,
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.folder, color: Color(0xFFFFC107)),
                title: Text(f.name, overflow: TextOverflow.ellipsis),
                onTap: () => onOpen(f),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) =>
                      v == 'rename' ? onRename(f) : onDelete(f),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NoteGrid extends StatelessWidget {
  const _NoteGrid({
    required this.notes,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
  });

  final List<NoteSummary> notes;
  final ValueChanged<NoteSummary> onOpen;
  final ValueChanged<NoteSummary> onRename;
  final ValueChanged<NoteSummary> onDelete;
  final ValueChanged<NoteSummary> onMove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final n in notes)
          SizedBox(
            width: 160,
            height: 200,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onOpen(n),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        color: const Color(0xFFF5F5F5),
                        alignment: Alignment.center,
                        child: const Icon(Icons.description_outlined,
                            size: 48, color: Colors.black26),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall),
                                Text('${n.pageCount} page'
                                    '${n.pageCount == 1 ? '' : 's'}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              switch (v) {
                                case 'rename':
                                  onRename(n);
                                case 'move':
                                  onMove(n);
                                case 'delete':
                                  onDelete(n);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'rename', child: Text('Rename')),
                              PopupMenuItem(
                                  value: 'move', child: Text('Move to…')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CreateFab extends StatelessWidget {
  const _CreateFab({required this.onNewNote, required this.onNewFolder});

  final VoidCallback onNewNote;
  final VoidCallback onNewFolder;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: 'newFolder',
          tooltip: 'New folder',
          onPressed: onNewFolder,
          child: const Icon(Icons.create_new_folder_outlined),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'newNote',
          onPressed: onNewNote,
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('New note'),
        ),
      ],
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () =>
          settings.toggle(MediaQuery.platformBrightnessOf(context)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.edit_note, size: 72, color: Colors.black26),
          const SizedBox(height: 12),
          Text('Nothing here yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Create a note or folder to get started.'),
        ],
      ),
    );
  }
}
