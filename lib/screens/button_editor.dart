import 'package:flutter/material.dart';

import '../connection.dart';
import '../models.dart';
import '../widgets/action_form.dart';
import '../widgets/deck_tile.dart';

class EditResult {
  /// null means "clear this slot".
  final DeckButton? button;
  final String? newPageName;
  EditResult(this.button, {this.newPageName});
}

const _palette = [
  '#c62828', '#ad1457', '#6a1b9a', '#4527a0', '#283593', '#1565c0', '#00838f', '#00695c',
  '#2e7d32', '#9e9d24', '#f9a825', '#ef6c00', '#d84315', '#5d4037', '#37474f', '#212121',
];

const _emoji = [
  '🔴', '⏺️', '⏯️', '⏭️', '⏮️', '🎙️', '🔇', '🔊', '🔈', '🎧', '🎮', '🕹️', '💬', '💭', '☕', '📸',
  '🎬', '🎥', '📹', '🎵', '🎶', '🎤', '📁', '📝', '🌐', '⭐', '❤️', '🔥', '👏', '👍', '😂', '🎉',
  '🚀', '⚡', '🔔', '💡', '🖥️', '⌨️', '🖱️', '📺', '🔒', '🔓', '⏱️', '🎲', '🧠', '🛑', '▶️', '⏸️',
  '⬅️', '🏠', '➕', '➖', '✅', '❌', '🔄', '📌', '🛠️', '💾', '🗑️', '🙈',
];

class ButtonEditor extends StatefulWidget {
  final DeckButton? button;
  final String currentPageId;
  const ButtonEditor({super.key, this.button, required this.currentPageId});

  @override
  State<ButtonEditor> createState() => _ButtonEditorState();
}

class _ButtonEditorState extends State<ButtonEditor> {
  late DeckButton b = widget.button ?? DeckButton(color: _palette[5], icon: '⭐');
  late final _label = TextEditingController(text: b.label);
  late final _icon = TextEditingController(text: b.icon);

  @override
  void dispose() {
    _label.dispose();
    _icon.dispose();
    super.dispose();
  }

  void _save() {
    final a = b.action;
    String? newPage;
    if (a['type'] == 'folder') {
      if (a['page'] == '__new__') {
        final n = (a['newName'] as String?)?.trim();
        if (n != null && n.isNotEmpty) {
          newPage = n;
        } else {
          newPage = b.label.isEmpty ? 'Folder' : b.label;
        }
      } else if ((a['page'] as String?)?.isEmpty ?? true) {
        _toast('Choose which page this folder opens.');
        return;
      }
      a.remove('newName');
    }
    Navigator.pop(context, EditResult(b, newPageName: newPage));
  }

  Future<void> _test() async {
    final err = await ConnScope.of(context).runAction(b.action);
    if (!mounted) return;
    _toast(err ?? 'Sent to PC');
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final isClientOnly = {'folder', 'back', 'home'}.contains(b.action['type']);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.button == null ? 'New button' : 'Edit button'),
        actions: [
          if (widget.button != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear slot',
              onPressed: () => Navigator.pop(context, EditResult(null)),
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: SizedBox(
              width: 110,
              height: 110,
              child: DeckTile(button: b, editing: false, active: false, busy: false, error: false, onTap: () {}),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _label,
            decoration: const InputDecoration(labelText: 'Label'),
            onChanged: (v) => setState(() => b.label = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _icon,
            decoration: const InputDecoration(labelText: 'Icon (any emoji or short text)'),
            onChanged: (v) => setState(() => b.icon = v),
          ),
          const SizedBox(height: 8),
          Wrap(
            children: [
              for (final e in _emoji)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() {
                    b.icon = e;
                    _icon.text = e;
                  }),
                  child: Padding(padding: const EdgeInsets.all(6), child: Text(e, style: const TextStyle(fontSize: 26))),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Color', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in _palette)
                GestureDetector(
                  onTap: () => setState(() => b.color = c),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: parseColor(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: b.color == c ? Colors.white : Colors.transparent, width: 3),
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 40),
          ActionForm(
            action: b.action,
            currentPageId: widget.currentPageId,
            onChanged: (a) => setState(() => b.action = a),
          ),
          const SizedBox(height: 20),
          if (!isClientOnly)
            OutlinedButton.icon(onPressed: _test, icon: const Icon(Icons.play_arrow), label: const Text('Test on PC now')),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
