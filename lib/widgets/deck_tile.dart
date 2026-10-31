import 'dart:async';

import 'package:flutter/material.dart';

import '../connection.dart';
import '../models.dart';
import 'deck_icon.dart';

class DeckTile extends StatefulWidget {
  final DeckButton? button;
  final bool editing;
  final bool active;
  final bool busy;
  final bool error;
  final VoidCallback onTap;

  const DeckTile({
    super.key,
    required this.button,
    required this.editing,
    required this.active,
    required this.busy,
    required this.error,
    required this.onTap,
  });

  @override
  State<DeckTile> createState() => _DeckTileState();
}

class _DeckTileState extends State<DeckTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.button;
    if (b == null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.editing ? widget.onTap : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: widget.editing ? Colors.white.withValues(alpha: 0.04) : Colors.black26,
            border: Border.all(color: widget.editing ? Colors.white24 : Colors.white10),
          ),
          child: widget.editing ? const Center(child: Icon(Icons.add, color: Colors.white38)) : null,
        ),
      );
    }

    final active = widget.active && !widget.editing;
    final isWidget = b.action['type'] == 'widget';
    final colorHex = active && (b.colorOn ?? '').isNotEmpty ? b.colorOn! : b.color;
    final label = active && (b.labelOn ?? '').isNotEmpty ? b.labelOn! : b.label;
    final icon = active && (b.iconOn ?? '').isNotEmpty ? b.iconOn! : b.icon;
    final showImage = !(active && (b.iconOn ?? '').isNotEmpty);

    final base = parseColor(colorHex);
    final hsl = HSLColor.fromColor(base);
    final top = hsl.withLightness((hsl.lightness + 0.08).clamp(0, 1)).toColor();
    final bottom = hsl.withLightness((hsl.lightness - 0.08).clamp(0, 1)).toColor();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: const Duration(milliseconds: 80),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]),
            border: Border.all(
              color: widget.error
                  ? Colors.redAccent
                  : active
                      ? Colors.white
                      : widget.editing
                          ? Colors.white54
                          : Colors.white12,
              width: active || widget.error ? 3 : 1,
            ),
            boxShadow: active ? [BoxShadow(color: base.withValues(alpha: 0.8), blurRadius: 14)] : null,
          ),
          padding: const EdgeInsets.all(5),
          child: Stack(
            children: [
              Center(
                child: isWidget
                    ? LiveWidget(kind: (b.action['kind'] ?? 'clock') as String, label: label, icon: icon)
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icon.isNotEmpty || (showImage && (b.image ?? '').isNotEmpty))
                              DeckIcon(icon: icon, image: showImage ? b.image : null, size: 34),
                            if (label.isNotEmpty)
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 110),
                                child: Text(
                                  label,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
              if (widget.busy)
                const Positioned(
                  top: 0,
                  right: 0,
                  child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                ),
              if (widget.editing)
                const Positioned(top: 0, right: 0, child: Icon(Icons.drag_indicator, size: 14, color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

String formatElapsed(int ms) {
  final s = (ms ~/ 1000).clamp(0, 359999);
  return '${_two(s ~/ 3600)}:${_two((s % 3600) ~/ 60)}:${_two(s % 60)}';
}

/// Self-updating tile content: clock, system stats, volume, stream/record timers.
class LiveWidget extends StatefulWidget {
  final String kind;
  final String label;
  final String icon;
  const LiveWidget({super.key, required this.kind, required this.label, required this.icon});

  @override
  State<LiveWidget> createState() => _LiveWidgetState();
}

class _LiveWidgetState extends State<LiveWidget> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (const {'clock', 'date', 'streamTimer', 'recordTimer'}.contains(widget.kind)) {
      _t = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = ConnScope.of(context);
    String value;
    String caption = widget.label;
    switch (widget.kind) {
      case 'clock':
        final n = DateTime.now();
        value = '${_two(n.hour)}:${_two(n.minute)}';
        break;
      case 'date':
        final n = DateTime.now();
        const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        value = '${n.day} ${m[n.month - 1]}';
        break;
      case 'cpu':
        value = '${conn.stats.cpu}%';
        if (caption.isEmpty) caption = 'CPU';
        break;
      case 'ram':
        value = '${conn.stats.mem}%';
        if (caption.isEmpty) caption = 'RAM';
        break;
      case 'volume':
        value = conn.stats.muted ? 'Muted' : (conn.stats.vol == null ? '--' : '${conn.stats.vol}%');
        if (caption.isEmpty) caption = 'Volume';
        break;
      case 'streamTimer':
        final s = conn.obs.streamStart;
        value = s == null ? '--:--:--' : formatElapsed(conn.serverNow - s);
        if (caption.isEmpty) caption = conn.obs.streaming ? 'LIVE' : 'Offline';
        break;
      case 'recordTimer':
        final s = conn.obs.recordStart;
        value = s == null ? '--:--:--' : formatElapsed(conn.serverNow - s);
        if (caption.isEmpty) caption = conn.obs.recording ? 'REC' : 'Not recording';
        break;
      default:
        value = '?';
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
          if (caption.isNotEmpty)
            Text(caption, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }
}
