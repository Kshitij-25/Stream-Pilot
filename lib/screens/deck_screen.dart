import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../connection.dart';
import '../models.dart';
import '../widgets/deck_tile.dart';
import 'button_editor.dart';
import 'settings_screen.dart';

class DeckScreen extends StatefulWidget {
  const DeckScreen({super.key});

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  final List<String> _stack = [];
  bool _editing = false;
  final Map<String, String> _errors = {}; // button id -> last error (cleared on next press)
  String? _flashId;

  String _currentPageId(DeckConfig cfg) {
    while (_stack.isNotEmpty && !cfg.pages.containsKey(_stack.last)) {
      _stack.removeLast();
    }
    return _stack.isNotEmpty ? _stack.last : (cfg.pages.containsKey(cfg.rootPage) ? cfg.rootPage : cfg.pages.keys.first);
  }

  bool _isActive(DeckButton b, ObsState obs) {
    final a = b.action;
    if (a['type'] != 'obs' || !obs.connected) return false;
    switch (a['op']) {
      case 'toggleStream':
      case 'startStream':
        return obs.streaming;
      case 'toggleRecord':
        return obs.recording;
      case 'scene':
        return obs.scene != null && obs.scene == a['scene'];
      case 'toggleMute':
      case 'mute':
        return obs.muted[a['input']] == true;
      default:
        return false;
    }
  }

  Future<void> _tap(DeckConnection conn, DeckConfig cfg, String pageId, int slot) async {
    final b = cfg.pages[pageId]!.buttons[slot];
    if (_editing) {
      await _edit(conn, cfg, pageId, slot);
      return;
    }
    if (b == null) return;
    if (conn.haptics) HapticFeedback.lightImpact();
    final type = b.action['type'];
    if (type == 'folder') {
      final target = b.action['page'] as String?;
      if (target != null && cfg.pages.containsKey(target)) setState(() => _stack.add(target));
      return;
    }
    if (type == 'back') {
      if (_stack.isNotEmpty) setState(() => _stack.removeLast());
      return;
    }
    if (type == 'home') {
      setState(_stack.clear);
      return;
    }
    setState(() {
      _errors.remove(b.id);
      _flashId = b.id;
    });
    final err = await conn.press(b);
    if (!mounted) return;
    setState(() => _flashId = null);
    if (err != null) {
      if (conn.haptics) HapticFeedback.heavyImpact();
      setState(() => _errors[b.id] = err);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('${b.label.isEmpty ? 'Button' : b.label}: $err'), backgroundColor: Colors.red.shade800));
    }
  }

  Future<void> _edit(DeckConnection conn, DeckConfig cfg, String pageId, int slot) async {
    final existing = cfg.pages[pageId]!.buttons[slot];
    final result = await Navigator.of(context).push<EditResult>(
      MaterialPageRoute(builder: (_) => ButtonEditor(button: existing?.copy(), currentPageId: pageId)),
    );
    if (result == null) return;
    conn.updateConfig((c) {
      if (result.newPageName != null) {
        // Folder pointing at a page created from inside the editor.
        final id = c.addPage(result.newPageName!);
        result.button?.action['page'] = id;
        final back = DeckButton(label: 'Back', icon: '⬅️', color: '#424242', action: {'type': 'back'});
        c.pages[id]!.buttons[0] = back;
      }
      c.pages[pageId]!.buttons[slot] = result.button;
    });
  }

  void _swap(DeckConnection conn, String pageId, int from, int to) {
    if (from == to) return;
    conn.updateConfig((c) {
      final list = c.pages[pageId]!.buttons;
      final tmp = list[from];
      list[from] = list[to];
      list[to] = tmp;
    });
  }

  @override
  Widget build(BuildContext context) {
    final conn = ConnScope.of(context);
    final cfg = conn.config!;
    final pageId = _currentPageId(cfg);
    final page = cfg.pages[pageId]!;
    final offline = !conn.connected;

    return PopScope(
      canPop: _stack.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _stack.isNotEmpty) setState(() => _stack.removeLast());
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(
                title: page.name,
                canGoBack: _stack.isNotEmpty,
                onBack: () => setState(() => _stack.removeLast()),
                editing: _editing,
                onToggleEdit: () => setState(() => _editing = !_editing),
                onSettings: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                obs: conn.obs,
                offline: offline,
              ),
              if (offline)
                Container(
                  width: double.infinity,
                  color: Colors.orange.shade900,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Text('Reconnecting to ${conn.host}…', style: const TextStyle(fontSize: 12)),
                ),
              if (_editing)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Text(
                    'Edit mode: tap a slot to edit it, long-press and drag to rearrange.',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      for (var r = 0; r < cfg.rows; r++)
                        Expanded(
                          child: Row(
                            children: [
                              for (var col = 0; col < cfg.cols; col++)
                                Expanded(
                                  child: _cell(conn, cfg, pageId, r * cfg.cols + col),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(DeckConnection conn, DeckConfig cfg, String pageId, int slot) {
    final b = cfg.pages[pageId]!.buttons[slot];
    final tile = DeckTile(
      button: b,
      editing: _editing,
      active: b != null && _isActive(b, conn.obs),
      busy: b != null && _flashId == b.id,
      error: b != null && _errors.containsKey(b.id),
      onTap: () => _tap(conn, cfg, pageId, slot),
    );
    if (!_editing) return Padding(padding: const EdgeInsets.all(4), child: tile);

    return Padding(
      padding: const EdgeInsets.all(4),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (d) => d.data != slot,
        onAcceptWithDetails: (d) => _swap(conn, pageId, d.data, slot),
        builder: (context, candidates, _) {
          final hovering = candidates.isNotEmpty;
          final body = hovering ? Opacity(opacity: 0.5, child: tile) : tile;
          if (b == null) return body;
          return LongPressDraggable<int>(
            data: slot,
            feedback: Material(
              color: Colors.transparent,
              child: SizedBox(width: 90, height: 90, child: DeckTile(button: b, editing: false, active: false, busy: false, error: false, onTap: () {})),
            ),
            childWhenDragging: Opacity(opacity: 0.25, child: tile),
            child: body,
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final bool canGoBack;
  final VoidCallback onBack;
  final bool editing;
  final VoidCallback onToggleEdit;
  final VoidCallback onSettings;
  final ObsState obs;
  final bool offline;

  const _TopBar({
    required this.title,
    required this.canGoBack,
    required this.onBack,
    required this.editing,
    required this.onToggleEdit,
    required this.onSettings,
    required this.obs,
    required this.offline,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          if (canGoBack)
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack, visualDensity: VisualDensity.compact)
          else
            const SizedBox(width: 12),
          Icon(Icons.circle, size: 10, color: offline ? Colors.orange : Colors.greenAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(title, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium)),
          if (obs.streaming) const _Badge('LIVE', Colors.red),
          if (obs.recording) const _Badge('REC', Colors.pink),
          if (!obs.connected && !offline) const _Badge('OBS offline', Colors.grey),
          IconButton(
            icon: Icon(editing ? Icons.check_circle : Icons.edit_outlined),
            tooltip: editing ? 'Done editing' : 'Edit buttons',
            onPressed: onToggleEdit,
          ),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: onSettings),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
