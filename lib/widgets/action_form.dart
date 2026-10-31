import 'package:flutter/material.dart';

import '../connection.dart';
import '../models.dart';

/// Edits one action map in place and reports every change through [onChanged].
/// With [nested] true it hides the actions that make no sense inside a macro (folders, nested macros).
class ActionForm extends StatefulWidget {
  final Json action;
  final ValueChanged<Json> onChanged;
  final bool nested;
  final String currentPageId;

  const ActionForm({
    super.key,
    required this.action,
    required this.onChanged,
    this.nested = false,
    this.currentPageId = '',
  });

  @override
  State<ActionForm> createState() => _ActionFormState();
}

class _ActionFormState extends State<ActionForm> {
  final _ctrls = <String, TextEditingController>{};
  String? _lastType;

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _c(String key) =>
      _ctrls.putIfAbsent(key, () => TextEditingController(text: '${widget.action[key] ?? ''}'));

  void _set(String key, dynamic value) {
    widget.action[key] = value;
    widget.onChanged(widget.action);
  }

  Widget _field(String key, String label, {String? hint, int maxLines = 1, TextInputType? type, Widget? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: _c(key),
        maxLines: maxLines,
        keyboardType: type,
        autocorrect: false,
        decoration: InputDecoration(labelText: label, hintText: hint, suffixIcon: suffix),
        onChanged: (v) => key == 'ms' ? _set(key, int.tryParse(v) ?? 0) : _set(key, v),
      ),
    );
  }

  Future<void> _pickFromObs(String key, String listKey) async {
    final conn = ConnScope.of(context);
    try {
      final data = await conn.listObs();
      if (!mounted) return;
      final items = data[listKey] ?? [];
      final picked = await showModalBottomSheet<String>(
        context: context,
        builder: (_) => SafeArea(
          child: items.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Text('OBS returned nothing.'))
              : ListView(children: [for (final s in items) ListTile(title: Text(s), onTap: () => Navigator.pop(context, s))]),
        ),
      );
      if (picked != null) {
        _c(key).text = picked;
        _set(key, picked);
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _obsPicker(String key, String listKey, String label) => _field(
        key,
        label,
        suffix: IconButton(icon: const Icon(Icons.list), tooltip: 'Pick from OBS', onPressed: () => _pickFromObs(key, listKey)),
      );

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final type = (a['type'] ?? 'hotkey') as String;
    if (_lastType != null && _lastType != type) {
      for (final c in _ctrls.values) {
        c.dispose();
      }
      _ctrls.clear();
    }
    _lastType = type;

    final kinds = actionKinds.where((k) => !widget.nested || !{'multi', 'folder', 'back', 'home'}.contains(k.type)).toList();
    final typeItems = [
      for (final k in kinds) DropdownMenuItem(value: k.type, child: Text(k.label)),
      if (widget.nested) const DropdownMenuItem(value: 'delay', child: Text('Wait')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: typeItems.any((i) => i.value == type) ? type : null,
          decoration: const InputDecoration(labelText: 'Action'),
          items: typeItems,
          onChanged: (v) {
            if (v == null || v == type) return;
            widget.onChanged(defaultAction(v));
          },
        ),
        ..._fields(type, a),
      ],
    );
  }

  List<Widget> _fields(String type, Json a) {
    switch (type) {
      case 'hotkey':
        return [
          _field('keys', 'Keys', hint: 'ctrl+shift+m'),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Join keys with +. Names: ctrl, shift, alt, win, enter, esc, tab, space, f1–f24, up/down/left/right, a–z, 0–9.',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ),
        ];
      case 'text':
        return [
          _field('text', 'Text to type', maxLines: 3),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Press Enter afterwards'),
            value: a['enter'] == true,
            onChanged: (v) => setState(() => _set('enter', v)),
          ),
        ];
      case 'open':
        return [
          _field('target', 'App, file or URL', hint: 'notepad.exe  or  https://…'),
          _field('args', 'Arguments (optional)'),
        ];
      case 'command':
        return [_field('command', 'Command', hint: 'e.g. shutdown /s /t 60', maxLines: 2)];
      case 'http':
        return [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DropdownButtonFormField<String>(
              initialValue: (a['method'] ?? 'GET') as String,
              decoration: const InputDecoration(labelText: 'Method'),
              items: const [
                DropdownMenuItem(value: 'GET', child: Text('GET')),
                DropdownMenuItem(value: 'POST', child: Text('POST')),
                DropdownMenuItem(value: 'PUT', child: Text('PUT')),
              ],
              onChanged: (v) => setState(() => _set('method', v)),
            ),
          ),
          _field('url', 'URL', type: TextInputType.url),
          if (a['method'] != 'GET') _field('body', 'JSON body (optional)', maxLines: 3),
        ];
      case 'delay':
        return [_field('ms', 'Milliseconds', type: TextInputType.number)];
      case 'media':
        return [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DropdownButtonFormField<String>(
              initialValue: mediaKeys.containsKey(a['key']) ? a['key'] as String : 'playpause',
              decoration: const InputDecoration(labelText: 'Key'),
              items: [for (final e in mediaKeys.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _set('key', v)),
            ),
          ),
        ];
      case 'obs':
        final op = (a['op'] ?? 'toggleStream') as String;
        return [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DropdownButtonFormField<String>(
              initialValue: obsOps.containsKey(op) ? op : 'toggleStream',
              decoration: const InputDecoration(labelText: 'OBS operation'),
              items: [for (final e in obsOps.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _set('op', v)),
            ),
          ),
          if (op == 'scene') _obsPicker('scene', 'scenes', 'Scene name'),
          if (op == 'toggleMute' || op == 'mute' || op == 'unmute') _obsPicker('input', 'inputs', 'Audio input name'),
          if (op == 'toggleSource') ...[
            _obsPicker('scene', 'scenes', 'Scene (blank = current)'),
            _field('source', 'Source name'),
          ],
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Needs OBS 28+ with WebSocket server enabled (see Settings → OBS).', style: TextStyle(fontSize: 12, color: Colors.white60)),
          ),
        ];
      case 'folder':
        final conn = ConnScope.of(context);
        final pages = conn.config!.pages.values.where((p) => p.id != widget.currentPageId).toList();
        final cur = a['page'] as String?;
        return [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DropdownButtonFormField<String>(
              initialValue: (cur == '__new__' || pages.any((p) => p.id == cur)) ? cur : null,
              decoration: const InputDecoration(labelText: 'Opens page'),
              items: [
                for (final p in pages) DropdownMenuItem(value: p.id, child: Text(p.name)),
                const DropdownMenuItem(value: '__new__', child: Text('+ Create new page')),
              ],
              onChanged: (v) => setState(() => _set('page', v)),
            ),
          ),
          if (cur == '__new__') _field('newName', 'New page name'),
        ];
      case 'multi':
        return [_MacroSteps(action: a, onChanged: () => setState(() => widget.onChanged(a)))];
      case 'back':
        return [const Padding(padding: EdgeInsets.only(top: 12), child: Text('Returns to the previous page.'))];
      case 'home':
        return [const Padding(padding: EdgeInsets.only(top: 12), child: Text('Jumps to the first page.'))];
    }
    return const [];
  }
}

class _MacroSteps extends StatelessWidget {
  final Json action;
  final VoidCallback onChanged;
  const _MacroSteps({required this.action, required this.onChanged});

  List<Json> get steps => (action['actions'] as List).cast<Json>();

  @override
  Widget build(BuildContext context) {
    final list = steps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        for (var i = 0; i < list.length; i++)
          Card(
            key: ObjectKey(list[i]),
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              title: Text('${i + 1}. ${describeAction(list[i])}', maxLines: 1, overflow: TextOverflow.ellipsis),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                ActionForm(
                  action: list[i],
                  nested: true,
                  onChanged: (updated) {
                    list[i] = updated;
                    onChanged();
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: i == 0 ? null : () { list.insert(i - 1, list.removeAt(i)); onChanged(); },
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_downward),
                      onPressed: i == list.length - 1 ? null : () { list.insert(i + 1, list.removeAt(i)); onChanged(); },
                    ),
                    IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { list.removeAt(i); onChanged(); }),
                  ],
                ),
              ],
            ),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add step'),
          onPressed: () async {
            final t = await showModalBottomSheet<String>(
              context: context,
              builder: (_) => SafeArea(
                child: ListView(children: [
                  for (final k in actionKinds.where((k) => !{'multi', 'folder', 'back', 'home'}.contains(k.type)))
                    ListTile(title: Text(k.label), subtitle: Text(k.hint), onTap: () => Navigator.pop(context, k.type)),
                  ListTile(title: const Text('Wait'), subtitle: const Text('Pause before the next step'), onTap: () => Navigator.pop(context, 'delay')),
                ]),
              ),
            );
            if (t != null) {
              list.add(defaultAction(t));
              onChanged();
            }
          },
        ),
      ],
    );
  }
}
