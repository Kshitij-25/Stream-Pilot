import 'package:flutter/material.dart';

import '../connection.dart';
import '../models.dart';
import '../presets.dart';
import '../widgets/action_form.dart';
import '../widgets/deck_icon.dart';
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
  late final _icon = TextEditingController(text: b.icon.startsWith('mi:') ? '' : b.icon);
  late final _iconOn = TextEditingController(text: b.iconOn ?? '');
  late final _labelOn = TextEditingController(text: b.labelOn ?? '');
  int _previewActive = 0; // 0 = normal look, 1 = active look

  @override
  void dispose() {
    _label.dispose();
    _icon.dispose();
    _iconOn.dispose();
    _labelOn.dispose();
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

  Future<void> _pickPreset() async {
    final picked = await showModalBottomSheet<Preset>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PresetSheet(),
    );
    if (picked == null) return;
    final p = picked.toButton();
    setState(() {
      b.label = p.label;
      b.icon = p.icon;
      b.image = null;
      b.color = p.color;
      b.action = p.action;
      b.iconOn = p.iconOn;
      b.labelOn = p.labelOn;
      b.colorOn = p.colorOn;
      _label.text = b.label;
      _icon.text = b.icon;
      _iconOn.text = b.iconOn ?? '';
      _labelOn.text = b.labelOn ?? '';
    });
  }

  bool _fetchingIcon = false;

  /// Pick an installed app on the PC: sets the launch target, label and the app's REAL icon.
  Future<void> _pickApp() async {
    final conn = ConnScope.of(context);
    final app = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AppPicker(),
    );
    if (app == null || !mounted) return;
    setState(() {
      _fetchingIcon = true;
      b.action = {'type': 'open', 'target': app['path'] as String};
      if (b.label.isEmpty) {
        b.label = app['name'] as String;
        _label.text = b.label;
      }
    });
    try {
      final png = await conn.rpc('appIcon', {'path': app['path']}) as String;
      if (mounted) setState(() => b.image = png);
    } catch (e) {
      _toast('Could not read that app\'s icon: $e');
    } finally {
      if (mounted) setState(() => _fetchingIcon = false);
    }
  }

  /// Fetch the favicon of the website this button opens.
  Future<void> _siteIcon() async {
    final target = (b.action['target'] ?? '') as String;
    final domain = Uri.tryParse(target)?.host ?? '';
    if (domain.isEmpty) {
      _toast('Set the action to "Open app / link" with a web address first.');
      return;
    }
    setState(() => _fetchingIcon = true);
    try {
      final png = await ConnScope.of(context).rpc('siteIcon', {'domain': domain}) as String;
      if (mounted) setState(() => b.image = png);
    } catch (e) {
      _toast('Could not fetch the site icon: $e');
    } finally {
      if (mounted) setState(() => _fetchingIcon = false);
    }
  }

  Widget _extraAction(String title, String subtitle, Json? value, ValueChanged<Json?> onChanged) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: value != null,
        title: Text(title),
        subtitle: Text(subtitle),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enabled'),
            value: value != null,
            onChanged: (v) => setState(() => onChanged(v ? defaultAction('hotkey') : null)),
          ),
          if (value != null)
            ActionForm(
              key: ValueKey('$title-${value['type']}'),
              action: value,
              nested: true,
              onChanged: (a) => setState(() => onChanged(a)),
            ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final img = await pickIconImage();
      if (img != null) setState(() => b.image = img);
    } catch (e) {
      _toast('Could not load that picture: $e');
    }
  }

  Future<void> _pickMaterialIcon() async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.6,
          child: GridView.count(
            crossAxisCount: 6,
            padding: const EdgeInsets.all(12),
            children: [
              for (final e in materialIconSet.entries)
                IconButton(icon: Icon(e.value, size: 30), tooltip: e.key, onPressed: () => Navigator.pop(ctx, e.key)),
            ],
          ),
        ),
      ),
    );
    if (name != null) {
      setState(() {
        b.icon = 'mi:$name';
        b.image = null;
        _icon.text = '';
      });
    }
  }

  Widget _colorRow(String? selected, ValueChanged<String?> onPick, {bool allowNone = false}) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (allowNone)
          GestureDetector(
            onTap: () => onPick(null),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected == null ? Colors.white : Colors.white30, width: selected == null ? 3 : 1),
              ),
              child: const Icon(Icons.block, size: 18, color: Colors.white54),
            ),
          ),
        for (final c in _palette)
          GestureDetector(
            onTap: () => onPick(c),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: parseColor(c),
                shape: BoxShape.circle,
                border: Border.all(color: selected == c ? Colors.white : Colors.transparent, width: 3),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isClientOnly = {'folder', 'back', 'home', 'widget', 'screen'}.contains(b.action['type']);
    final preview = _previewActive == 1;
    final isWidget = b.action['type'] == 'widget';
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
              child: DeckTile(button: b, editing: false, active: preview, busy: false, error: false, onTap: () {}),
            ),
          ),
          if (b.hasActiveLook)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: 0, label: Text('Normal')), ButtonSegment(value: 1, label: Text('Active'))],
                  selected: {_previewActive},
                  onSelectionChanged: (s) => setState(() => _previewActive = s.first),
                ),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _pickPreset, icon: const Icon(Icons.auto_awesome), label: const Text('Start from a preset (macros, Discord, OBS, audio…)')),
          const SizedBox(height: 16),
          TextField(
            controller: _label,
            decoration: const InputDecoration(labelText: 'Label'),
            onChanged: (v) => setState(() => b.label = v),
          ),
          if (!isWidget) ...[
            const SizedBox(height: 16),
            Text('Icon', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                onPressed: _fetchingIcon ? null : _pickApp,
                icon: _fetchingIcon
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.apps),
                label: const Text('App icon from PC'),
              ),
              OutlinedButton.icon(onPressed: _fetchingIcon ? null : _siteIcon, icon: const Icon(Icons.language), label: const Text('Website icon')),
              OutlinedButton.icon(onPressed: _pickMaterialIcon, icon: const Icon(Icons.category_outlined), label: const Text('Icon library')),
              if (b.image != null) TextButton(onPressed: () => setState(() => b.image = null), child: const Text('Remove picture')),
            ]),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('More: your own picture, emoji'),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.image_outlined), label: const Text('Picture from gallery')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _icon,
                    decoration: const InputDecoration(labelText: 'Emoji / short text'),
                    onChanged: (v) => setState(() {
                      b.icon = v;
                      b.image = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    children: [
                      for (final e in _emoji)
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(() {
                            b.icon = e;
                            b.image = null;
                            _icon.text = e;
                          }),
                          child: Padding(padding: const EdgeInsets.all(6), child: Text(e, style: const TextStyle(fontSize: 26))),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text('Color', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _colorRow(b.color, (c) => setState(() => b.color = c!)),
          if (!isWidget)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: b.hasActiveLook,
                title: const Text('Dynamic look (when active)'),
                subtitle: const Text('Changes while OBS is live/recording/muted, a toggle is ON, etc.'),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  TextField(
                    controller: _iconOn,
                    decoration: const InputDecoration(labelText: 'Active icon (emoji, blank = same)'),
                    onChanged: (v) => setState(() => b.iconOn = v.isEmpty ? null : v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _labelOn,
                    decoration: const InputDecoration(labelText: 'Active label (blank = same)'),
                    onChanged: (v) => setState(() => b.labelOn = v.isEmpty ? null : v),
                  ),
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: Text('Active color', style: Theme.of(context).textTheme.labelLarge)),
                  const SizedBox(height: 8),
                  _colorRow(b.colorOn, (c) => setState(() => b.colorOn = c), allowNone: true),
                ],
              ),
            ),
          const Divider(height: 40),
          ActionForm(
            action: b.action,
            currentPageId: widget.currentPageId,
            onChanged: (a) => setState(() => b.action = a),
          ),
          if (!isClientOnly) ...[
            const Divider(height: 32),
            _extraAction('Long press', 'Runs instead when you hold the button', b.longAction, (a) => b.longAction = a),
            _extraAction('Double tap', 'Runs when you tap twice quickly (adds a short delay to single taps)', b.doubleAction, (a) => b.doubleAction = a),
          ],
          const SizedBox(height: 20),
          if (!isClientOnly)
            OutlinedButton.icon(onPressed: _test, icon: const Icon(Icons.play_arrow), label: const Text('Test on PC now')),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _PresetSheet extends StatefulWidget {
  const _PresetSheet();

  @override
  State<_PresetSheet> createState() => _PresetSheetState();
}

class _PresetSheetState extends State<_PresetSheet> {
  String _cat = presetCategories.first;

  @override
  Widget build(BuildContext context) {
    final items = presets.where((p) => p.category == _cat).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                children: [
                  for (final c in presetCategories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(c), selected: c == _cat, onSelected: (_) => setState(() => _cat = c)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final p in items)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: parseColor(p.color),
                        child: p.icon.isEmpty ? const Icon(Icons.widgets, size: 18, color: Colors.white) : Text(p.icon, style: const TextStyle(fontSize: 18)),
                      ),
                      title: Text(p.label),
                      subtitle: Text(describeAction(p.action), maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, p),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppPicker extends StatefulWidget {
  const _AppPicker();

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  List<Json>? _apps;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final l = await ConnScope.of(context).rpc('listApps') as List;
        if (mounted) setState(() => _apps = [for (final a in l) Map<String, dynamic>.from(a as Map)]);
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final apps = (_apps ?? const <Json>[]).where((a) => (a['name'] as String).toLowerCase().contains(_q.toLowerCase())).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search apps installed on your PC'),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                : _apps == null
                    ? const Center(child: CircularProgressIndicator())
                    : apps.isEmpty
                        ? const Center(child: Text('No apps found'))
                        : ListView.builder(
                            itemCount: apps.length,
                            itemBuilder: (_, i) => ListTile(
                              leading: const Icon(Icons.apps),
                              title: Text(apps[i]['name'] as String),
                              onTap: () => Navigator.pop(context, apps[i]),
                            ),
                          ),
          ),
        ]),
      ),
    );
  }
}
