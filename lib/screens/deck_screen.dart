import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../connection.dart';
import '../theme.dart';
import '../models.dart';
import '../widgets/deck_icon.dart';
import '../widgets/deck_tile.dart';
import '../widgets/page_dialog.dart';
import '../tools/tools.dart';
import 'dart:async';
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
  StreamSubscription? _eventSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final conn0 = ConnScope.of(context);
    _eventSub ??= conn0.eventStream.listen((e) {
      if (!mounted || !conn0.notifications) return;
      if (conn0.haptics) HapticFeedback.mediumImpact();
      final detail = (e['detail'] ?? '') as String;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          content: Row(children: [
            const Icon(Icons.notifications_active, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text('${e['title']}${detail.isEmpty ? '' : '\n$detail'}', maxLines: 3, overflow: TextOverflow.ellipsis)),
          ]),
          action: SnackBarAction(label: 'Events', onPressed: () => openTool(context, 'events')),
        ));
    });
    final o = conn0.orientation;
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
    _eventSub?.cancel();
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
      case 'screen':
        openTool(context, '${b.action['screen']}');
        return;
    }
    await _fire(conn, b, 'tap');
  }

  Future<void> _fire(DeckConnection conn, DeckButton b, String kind) async {
    if (kind != 'tap' && conn.haptics) HapticFeedback.mediumImpact();
    setState(() {
      _errors.remove(b.id);
      _flashId = b.id;
    });
    final err = await conn.press(b, kind: kind);
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

    final hint = _editing ? const _Strip('Edit mode: tap a slot to edit, long-press to drag. Long-press a screen to rename it.', kAccent) : null;
    final outdated = conn.outdatedCompanion
        ? const _Strip('Your PC companion is outdated. Close it, update the server folder and restart it (npm start).', kLive)
        : null;
    final offline = !conn.connected ? _Strip('Reconnecting to ${conn.host}…', const Color(0xFFFFB86B)) : null;

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
        backgroundColor: kBg,
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
                  Expanded(child: Column(children: [?outdated, ?offline, ?hint, _PageHeader(title: page.name, obs: conn.obs, conn: conn), Expanded(child: grid)])),
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
                    subtitle: conn.hostName.isEmpty ? conn.host : conn.hostName,
                    conn: conn,
                  ),
                  Container(height: 42, margin: const EdgeInsets.only(top: 14), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF1C1C20)))), child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: tabs)),
                  ?outdated,
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
      onLongPress: b?.longAction == null ? null : () => _fire(conn, b!, 'long'),
      onDoubleTap: b?.doubleAction == null ? null : () => _fire(conn, b!, 'double'),
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

/// Key matrix: square keys, centred, as large as the space allows.
class _Grid extends StatelessWidget {
  final DeckConfig cfg;
  final Widget Function(int slot) cell;
  const _Grid({required this.cfg, required this.cell});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const gap = 10.0;
      const rowGap = 13.0; // room for each key's bottom lip
      const pad = 12.0;
      final w = (box.maxWidth - pad * 2 - gap * (cfg.cols - 1)) / cfg.cols;
      final h = (box.maxHeight - pad * 2 - rowGap * (cfg.rows - 1)) / cfg.rows;
      final size = w < h ? w : h;
      if (size <= 0) return const SizedBox.shrink();
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < cfg.rows; r++)
              Padding(
                padding: EdgeInsets.only(top: r == 0 ? 0 : rowGap),
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
      );
    });
  }
}

class _Strip extends StatelessWidget {
  final String text;
  final Color color;
  const _Strip(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        color: color.withValues(alpha: 0.12),
        child: Text(text, style: TextStyle(fontSize: 11.5, color: color)),
      );
}

/// One screen in the switcher: icon + label in the landscape rail, text with underline in portrait.
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
    final p = page;
    final label = p?.name ?? 'Add';
    final color = selected ? kAccent : const Color(0xFF7D7D86);

    if (!vertical) {
      return InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: selected ? kAccent : Colors.transparent, width: 2))),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: selected ? kText : const Color(0xFF7D7D86))),
        ),
      );
    }

    final icon = p == null ? Icon(Icons.add, size: 20, color: color) : (p.icon.isEmpty ? Icon(Icons.dashboard_outlined, size: 20, color: color) : DeckIcon(icon: p.icon, size: 20, color: color));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Material(
        color: selected ? kSurface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              icon,
              const SizedBox(height: 3),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, letterSpacing: 0.2, color: color)),
            ]),
          ),
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
    Widget tool(IconData i, String tip, VoidCallback f, {Color color = kMuted}) =>
        IconButton(icon: Icon(i, size: 19, color: color), tooltip: tip, visualDensity: VisualDensity.compact, onPressed: f);
    final conn = ConnScope.of(context);
    return Container(
      width: 68,
      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFF1C1C20)))),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: offline ? const Color(0xFFFFB86B) : kOk)),
          if (inFolder) tool(Icons.arrow_back, 'Back', onBack) else const SizedBox(height: 10),
          Expanded(child: ListView(padding: EdgeInsets.zero, children: tabs)),
          tool(conn.following ? Icons.layers_outlined : Icons.push_pin_outlined, 'Profile: ${conn.profileName}', () => showProfileSheet(context)),
          tool(editing ? Icons.check_circle_outline : Icons.edit_outlined, editing ? 'Done editing' : 'Edit buttons', onToggleEdit, color: editing ? kAccent : kMuted),
          tool(Icons.tune, 'Settings', onSettings),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// Landscape: slim title line above the keys with live status pills.
class _PageHeader extends StatelessWidget {
  final String title;
  final ObsState obs;
  final DeckConnection conn;
  const _PageHeader({required this.title, required this.obs, required this.conn});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: SizedBox(
        height: 26,
        child: Row(children: [
          Expanded(child: Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: -0.1))),
          if (obs.streaming) const _Pill('Live', kLive, dot: true),
          if (obs.recording) const _Pill('Rec', Color(0xFFFF7AA8), dot: true),
          if (!obs.connected && conn.connected) const _Pill('OBS offline', kMuted),
          _Pill(conn.profileName, kMuted),
        ]),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool canGoBack;
  final VoidCallback onBack;
  final bool editing;
  final VoidCallback onToggleEdit;
  final VoidCallback onSettings;
  final ObsState obs;
  final bool offline;
  final DeckConnection conn;

  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.canGoBack,
    required this.onBack,
    required this.editing,
    required this.onToggleEdit,
    required this.onSettings,
    required this.obs,
    required this.offline,
    required this.conn,
  });

  @override
  Widget build(BuildContext context) {
    Widget tool(IconData i, String tip, VoidCallback f, {Color color = kMuted}) => IconButton(icon: Icon(i, size: 20, color: color), tooltip: tip, onPressed: f);
    return Padding(
      padding: EdgeInsets.fromLTRB(canGoBack ? 8 : 20, 14, 8, 0),
      child: Row(children: [
        if (canGoBack) IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: offline ? const Color(0xFFFFB86B) : kOk)),
              const SizedBox(width: 7),
              Flexible(child: Text(subtitle, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kMuted))),
            ]),
            const SizedBox(height: 2),
            Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.8)),
          ]),
        ),
        if (obs.streaming) const _Pill('Live', kLive, dot: true),
        if (obs.recording) const _Pill('Rec', Color(0xFFFF7AA8), dot: true),
        tool(Icons.layers_outlined, 'Profile: ${conn.profileName}', () => showProfileSheet(context)),
        tool(editing ? Icons.check_circle_outline : Icons.edit_outlined, editing ? 'Done editing' : 'Edit buttons', onToggleEdit, color: editing ? kAccent : kMuted),
        tool(Icons.tune, 'Settings', onSettings),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final bool dot;
  const _Pill(this.text, this.color, {this.dot = false});

  @override
  Widget build(BuildContext context) {
    final strong = dot;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: strong ? color.withValues(alpha: 0.14) : kSurface2, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)), const SizedBox(width: 6)],
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: strong ? color : kMuted)),
      ]),
    );
  }
}
