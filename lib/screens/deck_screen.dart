import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../connection.dart';
import '../models.dart';
import '../widgets/deck_icon.dart';
import '../widgets/deck_tile.dart';
import '../widgets/page_dialog.dart';
import 'button_editor.dart';
import 'settings_screen.dart';

class DeckScreen extends StatefulWidget {
  const DeckScreen({super.key});

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  String? _screenId; // selected top-level screen (switcher)
  final List<String> _stack = []; // folders opened on top of the screen
  bool _editing = false;
  final Map<String, String> _errors = {};
  String? _flashId;
  String? _appliedOrientation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final o = ConnScope.of(context).orientation;
    if (o == _appliedOrientation) return;
    _appliedOrientation = o;
    SystemChrome.setPreferredOrientations(switch (o) {
      'landscape' => [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      'portrait' => [DeviceOrientation.portraitUp],
      _ => DeviceOrientation.values,
    });
    SystemChrome.setEnabledSystemUIMode(o == 'portrait' ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _screen(DeckConfig cfg) =>
      _screenId != null && cfg.pages.containsKey(_screenId) ? _screenId! : (cfg.pages.containsKey(cfg.rootPage) ? cfg.rootPage : cfg.pages.keys.first);

  String _current(DeckConfig cfg) {
    while (_stack.isNotEmpty && !cfg.pages.containsKey(_stack.last)) {
      _stack.removeLast();
    }
    return _stack.isNotEmpty ? _stack.last : _screen(cfg);
  }

  void _selectScreen(String id) => setState(() {
        _screenId = id;
        _stack.clear();
      });

  Future<void> _tap(DeckConnection conn, DeckConfig cfg, String pageId, int slot) async {
    final b = cfg.pages[pageId]!.buttons[slot];
    if (_editing) {
      await _edit(conn, cfg, pageId, slot);
      return;
    }
    if (b == null) return;
    if (conn.haptics) HapticFeedback.lightImpact();
    switch (b.action['type']) {
      case 'folder':
        final target = b.action['page'] as String?;
        if (target != null && cfg.pages.containsKey(target)) setState(() => _stack.add(target));
        return;
      case 'back':
        if (_stack.isNotEmpty) setState(() => _stack.removeLast());
        return;
      case 'home':
        _selectScreen(cfg.rootPage);
        return;
      case 'widget':
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
        c.pages[id]!.buttons[0] = DeckButton(label: 'Back', icon: '⬅️', color: '#424242', action: {'type': 'back'});
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

  void _openSettings() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    final conn = ConnScope.of(context);
    final cfg = conn.config!;
    final pageId = _current(cfg);
    final page = cfg.pages[pageId]!;
    final screenId = _screen(cfg);
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    final grid = _Grid(
      cfg: cfg,
      cell: (slot) => _cell(conn, cfg, pageId, slot),
    );

    final hint = _editing
        ? Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Text(
              'Edit mode: tap a slot to edit, long-press to drag. Long-press a screen to rename or delete it.',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
          )
        : null;
    final offline = !conn.connected
        ? Container(
            width: double.infinity,
            color: Colors.orange.shade900,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Text('Reconnecting to ${conn.host}…', style: const TextStyle(fontSize: 11)),
          )
        : null;

    final tabs = [
      for (final s in cfg.screens)
        _Tab(
          page: s,
          selected: s.id == screenId,
          vertical: landscape,
          onTap: () => _selectScreen(s.id),
          onLongPress: _editing ? () => showPageEditor(context, conn, pageId: s.id) : null,
        ),
      if (_editing)
        _Tab.add(vertical: landscape, onTap: () => showPageEditor(context, conn)),
    ];

    return PopScope(
      canPop: _stack.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _stack.isNotEmpty) setState(() => _stack.removeLast());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF08080B),
        body: SafeArea(
          child: landscape
              ? Row(children: [
                  _Rail(
                    tabs: tabs,
                    inFolder: _stack.isNotEmpty,
                    onBack: () => setState(() => _stack.removeLast()),
                    editing: _editing,
                    onToggleEdit: () => setState(() => _editing = !_editing),
                    onSettings: _openSettings,
                    obs: conn.obs,
                    offline: !conn.connected,
                  ),
                  Expanded(child: Column(children: [?offline, ?hint, Expanded(child: grid)])),
                ])
              : Column(children: [
                  _TopBar(
                    title: page.name,
                    canGoBack: _stack.isNotEmpty,
                    onBack: () => setState(() => _stack.removeLast()),
                    editing: _editing,
                    onToggleEdit: () => setState(() => _editing = !_editing),
                    onSettings: _openSettings,
                    obs: conn.obs,
                    offline: !conn.connected,
                  ),
                  SizedBox(height: 54, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: tabs)),
                  ?offline,
                  ?hint,
                  Expanded(child: grid),
                ]),
        ),
      ),
    );
  }

  Widget _cell(DeckConnection conn, DeckConfig cfg, String pageId, int slot) {
    final b = cfg.pages[pageId]!.buttons[slot];
    final tile = DeckTile(
      button: b,
      editing: _editing,
      active: b != null && conn.isActive(b),
      busy: b != null && _flashId == b.id,
      error: b != null && _errors.containsKey(b.id),
      onTap: () => _tap(conn, cfg, pageId, slot),
    );
    if (!_editing) return tile;

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != slot,
      onAcceptWithDetails: (d) => _swap(conn, pageId, d.data, slot),
      builder: (context, candidates, _) {
        final body = candidates.isNotEmpty ? Opacity(opacity: 0.5, child: tile) : tile;
        if (b == null) return body;
        return LongPressDraggable<int>(
          data: slot,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(width: 80, height: 80, child: DeckTile(button: b, editing: false, active: false, busy: false, error: false, onTap: () {})),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: tile),
          child: body,
        );
      },
    );
  }
}

/// Hardware-style key matrix: square keys, centred, as large as the space allows.
class _Grid extends StatelessWidget {
  final DeckConfig cfg;
  final Widget Function(int slot) cell;
  const _Grid({required this.cfg, required this.cell});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const gap = 8.0;
      final w = (box.maxWidth - 16 - gap * (cfg.cols - 1)) / cfg.cols;
      final h = (box.maxHeight - 16 - gap * (cfg.rows - 1)) / cfg.rows;
      final size = w < h ? w : h;
      if (size <= 0) return const SizedBox.shrink();
      return Center(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFF15151B), borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < cfg.rows; r++)
                Padding(
                  padding: EdgeInsets.only(top: r == 0 ? 0 : gap),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var c = 0; c < cfg.cols; c++)
                        Padding(
                          padding: EdgeInsets.only(left: c == 0 ? 0 : gap),
                          child: SizedBox(width: size, height: size, child: cell(r * cfg.cols + c)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _Tab extends StatelessWidget {
  final DeckPage? page;
  final bool selected;
  final bool vertical;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _Tab({required this.page, required this.selected, required this.vertical, required this.onTap, this.onLongPress});
  const _Tab.add({required this.vertical, required this.onTap})
      : page = null,
        selected = false,
        onLongPress = null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = page;
    final icon = p == null ? const Icon(Icons.add, size: 22) : (p.icon.isEmpty ? const Icon(Icons.dashboard, size: 22) : DeckIcon(icon: p.icon, size: 22));
    final label = p?.name ?? 'Add';
    final decoration = BoxDecoration(
      color: selected ? cs.primaryContainer : Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: selected ? cs.primary : Colors.transparent),
    );
    final child = vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: [
            icon,
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
          ])
        : Row(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 13))]);
    return Padding(
      padding: vertical ? const EdgeInsets.symmetric(vertical: 2, horizontal: 6) : const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: vertical ? double.infinity : null,
          padding: vertical ? const EdgeInsets.symmetric(vertical: 5, horizontal: 2) : const EdgeInsets.symmetric(horizontal: 12),
          decoration: decoration,
          child: child,
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  final List<Widget> tabs;
  final bool inFolder;
  final VoidCallback onBack;
  final bool editing;
  final VoidCallback onToggleEdit;
  final VoidCallback onSettings;
  final ObsState obs;
  final bool offline;

  const _Rail({
    required this.tabs,
    required this.inFolder,
    required this.onBack,
    required this.editing,
    required this.onToggleEdit,
    required this.onSettings,
    required this.obs,
    required this.offline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      color: const Color(0xFF101015),
      child: Column(
        children: [
          const SizedBox(height: 6),
          Icon(Icons.circle, size: 9, color: offline ? Colors.orange : Colors.greenAccent),
          if (inFolder)
            IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', visualDensity: VisualDensity.compact, onPressed: onBack)
          else
            const SizedBox(height: 4),
          Expanded(child: ListView(padding: EdgeInsets.zero, children: tabs)),
          if (obs.streaming) const _Badge('LIVE', Colors.red),
          if (obs.recording) const _Badge('REC', Colors.pink),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              icon: Icon(editing ? Icons.check_circle : Icons.edit_outlined),
              tooltip: editing ? 'Done editing' : 'Edit buttons',
              visualDensity: VisualDensity.compact,
              onPressed: onToggleEdit,
            ),
            IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', visualDensity: VisualDensity.compact, onPressed: onSettings),
          ]),
        ],
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
      margin: const EdgeInsets.only(right: 6, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
