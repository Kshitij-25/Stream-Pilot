import 'package:flutter/material.dart';

import '../connection.dart';
import '../models.dart';

/// Edits one action map in place and reports every change through [onChanged].
/// With [nested] true it hides the actions that make no sense inside a macro (folders, nested macros...).
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
        onChanged: (v) {
          if (type == TextInputType.number || type == const TextInputType.numberWithOptions(decimal: true, signed: true)) {
            _set(key, num.tryParse(v) ?? 0);
          } else {
            _set(key, v);
          }
        },
      ),
    );
  }

  Widget _dropdown(String key, String label, Map<String, String> items, String fallback) {
    final cur = widget.action[key];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DropdownButtonFormField<String>(
        initialValue: items.containsKey(cur) ? cur as String : fallback,
        decoration: InputDecoration(labelText: label),
        isExpanded: true,
        items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
        onChanged: (v) => setState(() => _set(key, v)),
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

    final kinds = actionKinds.where((k) => !widget.nested || !notNestable.contains(k.type)).toList();
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

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.white60)),
      );

  List<Widget> _fields(String type, Json a) {
    switch (type) {
      case 'hotkey':
        return [
          _field('keys', 'Keys', hint: 'ctrl+shift+m'),
          _note('Join keys with +. Names: ctrl, shift, alt, win, enter, esc, tab, space, f1–f24, up/down/left/right, a–z, 0–9.'),
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
          _dropdown('method', 'Method', const {'GET': 'GET', 'POST': 'POST', 'PUT': 'PUT'}, 'GET'),
          _field('url', 'URL', type: TextInputType.url),
          if (a['method'] != null && a['method'] != 'GET') _field('body', 'JSON body (optional)', maxLines: 3),
        ];
      case 'delay':
        return [_field('ms', 'Milliseconds', type: TextInputType.number)];
      case 'media':
        return [_dropdown('key', 'Key', mediaKeys, 'playpause')];
      case 'volume':
        final op = (a['op'] ?? 'up') as String;
        return [
          _field('app', 'App (blank = whole PC)', hint: 'e.g. spotify, chrome, discord'),
          _dropdown('op', 'Operation', volumeOps, 'up'),
          if (op == 'set') _field('value', 'Volume (0–100)', type: TextInputType.number),
          if (op == 'up' || op == 'down') _field('value', 'Step (% per press)', type: TextInputType.number),
        ];
      case 'system':
        return [_dropdown('op', 'Operation', systemOps, 'showDesktop')];
      case 'screen':
        return [_dropdown('screen', 'Opens', toolScreens, 'mixer'), _note('A shortcut to a full-screen tool inside the app.')];
      case 'profile':
        final conn = ConnScope.of(context);
        return [
          _dropdown('profile', 'Switch to profile', {for (final p in conn.profiles) p['name'] as String: p['name'] as String}, conn.profiles.isEmpty ? '' : conn.profiles.first['name'] as String),
          _note('Switches the PC-wide profile. Phones set to "Follow PC" change layout instantly.'),
        ];
      case 'twitch':
        final op = (a['op'] ?? 'marker') as String;
        return [
          _dropdown('op', 'Twitch action', twitchOps, 'marker'),
          if (const {'say', 'announce', 'title', 'category'}.contains(op)) _field('text', op == 'title' ? 'Title' : op == 'category' ? 'Category' : 'Message', maxLines: 2),
          if (op == 'announce') _dropdown('color', 'Color', const {'primary': 'Primary', 'blue': 'Blue', 'green': 'Green', 'orange': 'Orange', 'purple': 'Purple'}, 'primary'),
          if (const {'timeout', 'ban', 'unban', 'shoutout', 'raid'}.contains(op)) _field('user', 'Username', hint: 'blank = chosen at runtime is not supported; enter a login'),
          if (op == 'timeout') _field('seconds', 'Seconds', type: TextInputType.number),
          if (op == 'timeout' || op == 'ban') _field('reason', 'Reason (optional)'),
          if (op == 'ad') _field('length', 'Seconds (30/60/90/120/150/180)', type: TextInputType.number),
          if (op == 'chatMode') ...[
            _dropdown('mode', 'Mode', const {'slow': 'Slow mode', 'subs': 'Subscribers only', 'emote': 'Emote only', 'followers': 'Followers only', 'unique': 'Unique chat'}, 'slow'),
            _dropdown('state', 'State', const {'toggle': 'Toggle', 'on': 'Turn on', 'off': 'Turn off'}, 'toggle'),
            if (a['mode'] == 'slow' || a['mode'] == 'followers') _field('value', a['mode'] == 'slow' ? 'Slow mode seconds' : 'Follow time (minutes, 0 = any)', type: TextInputType.number),
          ],
          _note('Connect Twitch under Integrations first.'),
        ];
      case 'youtube':
        final op = (a['op'] ?? 'say') as String;
        return [
          _dropdown('op', 'YouTube action', youtubeOps, 'say'),
          if (op == 'say') _field('text', 'Message', maxLines: 2),
          _note('Connect YouTube under Integrations first. Go live needs a broadcast created in YouTube Studio.'),
        ];
      case 'discord':
        final op = (a['op'] ?? 'toggleMute') as String;
        return [
          _dropdown('op', 'Discord action', discordOps, 'toggleMute'),
          if (op == 'inputVolume' || op == 'outputVolume') _field('value', 'Volume (0–100 mic, 0–200 speakers)', type: TextInputType.number),
          _note('Uses Discord\'s local API for real state. Without setup (Integrations → Discord) the button falls back to its keyboard shortcut if it has one.'),
        ];
      case 'sound':
        return [
          _field('file', 'Sound file path on the PC', hint: r'C:\Sounds\airhorn.mp3'),
          _note('Supports mp3 / wav / wma. Plays through the PC\'s default output, so OBS picks it up from Desktop Audio.'),
        ];
      case 'widget':
        return [_dropdown('kind', 'Shows', widgetKinds, 'clock'), _note('A live display. Pressing it does nothing.')];
      case 'obs':
        final op = (a['op'] ?? 'toggleStream') as String;
        return [
          _dropdown('op', 'OBS operation', obsOps, 'toggleStream'),
          if (op == 'scene') _obsPicker('scene', 'scenes', 'Scene name'),
          if (op == 'toggleMute' || op == 'mute' || op == 'unmute') _obsPicker('input', 'inputs', 'Audio input name'),
          if (op == 'setVolume') ...[_obsPicker('input', 'inputs', 'Audio input name'), _field('db', 'Volume in dB (-100 to 26)', type: const TextInputType.numberWithOptions(decimal: true, signed: true))],
          if (op == 'toggleSource') ...[
            _obsPicker('scene', 'scenes', 'Scene (blank = current)'),
            _field('source', 'Source name'),
          ],
          if (op == 'toggleFilter') ...[_field('source', 'Source name'), _field('filter', 'Filter name')],
          if (op == 'hotkey') _field('name', 'OBS hotkey name', hint: 'ReplayBuffer.Save'),
          _note('Needs OBS 28+ with the WebSocket server enabled (Settings → OBS).'),
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
        return [
          _field('repeat', 'Repeat the whole sequence (times)', type: TextInputType.number),
          StepList(action: a, listKey: 'actions', onChanged: () => setState(() => widget.onChanged(a))),
        ];
      case 'cycle':
        return [
          _note('Each press runs the next step, then loops back to the first.'),
          StepList(action: a, listKey: 'actions', onChanged: () => setState(() => widget.onChanged(a))),
        ];
      case 'toggle':
        return [
          const SizedBox(height: 16),
          Text('When switching ON', style: Theme.of(context).textTheme.titleSmall),
          _nestedForm('on', a),
          const SizedBox(height: 16),
          Text('When switching OFF', style: Theme.of(context).textTheme.titleSmall),
          _nestedForm('off', a),
          _note('The button shows its "active look" while ON. State resets if the companion restarts.'),
        ];
      case 'back':
        return [const Padding(padding: EdgeInsets.only(top: 12), child: Text('Returns to the previous page.'))];
      case 'home':
        return [const Padding(padding: EdgeInsets.only(top: 12), child: Text('Jumps to the start screen.'))];
    }
    return const [];
  }

  Widget _nestedForm(String key, Json a) {
    final sub = Map<String, dynamic>.from((a[key] ?? defaultAction('hotkey')) as Map);
    a[key] = sub;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ActionForm(
        key: ValueKey('$key-${sub['type']}'),
        action: sub,
        nested: true,
        onChanged: (updated) {
          a[key] = updated;
          widget.onChanged(a);
          setState(() {});
        },
      ),
    );
  }
}

/// Reorderable list of nested actions (macro / cycle steps, automation actions).
class StepList extends StatelessWidget {
  final Json action;
  final String listKey;
  final VoidCallback onChanged;
  const StepList({super.key, required this.action, required this.listKey, required this.onChanged});

  List<Json> get steps => ((action[listKey] ??= <Json>[]) as List).cast<Json>();

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
                    IconButton(icon: const Icon(Icons.copy), tooltip: 'Duplicate', onPressed: () { list.insert(i + 1, Map<String, dynamic>.from(list[i])); onChanged(); }),
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
              isScrollControlled: true,
              builder: (_) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
                  for (final k in actionKinds.where((k) => !notNestable.contains(k.type)))
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
