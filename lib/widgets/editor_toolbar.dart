import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/note_provider.dart';

/// Bottom toolbar: tool selection, color swatches and stroke width.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key});

  static const _palette = <int>[
    0xFF1A1A1A, // near-black
    0xFFE53935, // red
    0xFF1E88E5, // blue
    0xFF43A047, // green
    0xFFFB8C00, // orange
    0xFF8E24AA, // purple
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NoteProvider>();
    final tool = provider.tool;
    final showWidth =
        tool == EditorTool.pen || tool == EditorTool.highlighter;
    final showColors = showWidth || tool == EditorTool.text;
    final activeColor = tool == EditorTool.highlighter
        ? provider.highlighterColor
        : provider.penColor;

    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _ToolButton(
                    icon: Icons.edit,
                    label: 'Pen',
                    selected: tool == EditorTool.pen,
                    onTap: () => provider.setTool(EditorTool.pen),
                  ),
                  _ToolButton(
                    icon: Icons.brush,
                    label: 'Marker',
                    selected: tool == EditorTool.highlighter,
                    onTap: () => provider.setTool(EditorTool.highlighter),
                  ),
                  _ToolButton(
                    icon: Icons.auto_fix_normal,
                    label: 'Eraser',
                    selected: tool == EditorTool.eraser,
                    onTap: () => provider.setTool(EditorTool.eraser),
                  ),
                  _ToolButton(
                    icon: Icons.title,
                    label: 'Text',
                    selected: tool == EditorTool.text,
                    onTap: () => provider.setTool(EditorTool.text),
                  ),
                  _ToolButton(
                    icon: Icons.open_with,
                    label: 'Select',
                    selected: tool == EditorTool.select,
                    onTap: () => provider.setTool(EditorTool.select),
                  ),
                  _ToolButton(
                    icon: Icons.pan_tool_alt,
                    label: 'Pan',
                    selected: tool == EditorTool.pan,
                    onTap: () => provider.setTool(EditorTool.pan),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Undo',
                    icon: const Icon(Icons.undo),
                    onPressed: provider.canUndo ? provider.undo : null,
                  ),
                  IconButton(
                    tooltip: 'Redo',
                    icon: const Icon(Icons.redo),
                    onPressed: provider.canRedo ? provider.redo : null,
                  ),
                  const Spacer(),
                  if (showWidth)
                    SizedBox(
                      width: 160,
                      child: Slider(
                        min: 1,
                        max: 16,
                        value: provider.penWidth.clamp(1, 16),
                        onChanged: provider.setPenWidth,
                      ),
                    ),
                ],
              ),
              if (showColors)
                Row(
                  children: [
                    for (final c in _palette)
                      _Swatch(
                        color: Color(c),
                        selected: (activeColor & 0x00FFFFFF) ==
                            (c & 0x00FFFFFF),
                        onTap: () => provider.setPenColor(c),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: IconButton(
        isSelected: selected,
        onPressed: onTap,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: selected ? scheme.secondaryContainer : null,
          foregroundColor: selected ? scheme.onSecondaryContainer : null,
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.black : Colors.black26,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
