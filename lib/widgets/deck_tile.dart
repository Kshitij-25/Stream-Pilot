import 'dart:async';

import 'package:flutter/material.dart';

import '../connection.dart';
import '../models.dart';
import '../theme.dart';
import 'deck_icon.dart';

class DeckTile extends StatefulWidget {
  final DeckButton? button;
  final bool editing;
  final bool active;
  final bool busy;
  final bool error;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;

  const DeckTile({
    super.key,
    required this.button,
    required this.editing,
    required this.active,
    required this.busy,
    required this.error,
    required this.onTap,
    this.onLongPress,
    this.onDoubleTap,
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
            borderRadius: BorderRadius.circular(16),
            color: widget.editing ? kSurface : Colors.transparent,
            border: Border.all(color: widget.editing ? kBorder2 : const Color(0xFF17171A)),
          ),
          child: widget.editing ? const Center(child: Icon(Icons.add, color: kMuted, size: 20)) : null,
        ),
      );
    }

    final active = widget.active && !widget.editing;
    final isWidget = b.action['type'] == 'widget';
    final colorHex = active && (b.colorOn ?? '').isNotEmpty ? b.colorOn! : b.color;
    final label = active && (b.labelOn ?? '').isNotEmpty ? b.labelOn! : b.label;
    final icon = active && (b.iconOn ?? '').isNotEmpty ? b.iconOn! : b.icon;
    final showImage = !(active && (b.iconOn ?? '').isNotEmpty);
    final hue = accentFor(parseColor(colorHex));

    final borderColor = widget.error
        ? kLive
        : active
            ? hue.withValues(alpha: 0.6)
            : widget.editing
                ? Colors.white30
                : kBorder;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.editing ? null : widget.onLongPress,
      onDoubleTap: widget.editing ? null : widget.onDoubleTap,
      // A raised key: gradient face, hard bottom lip, soft drop shadow. Pressing sinks it ~3px and flattens the shadow.
      child: AnimatedSlide(
        offset: Offset(0, _down ? 0.03 : 0),
        duration: const Duration(milliseconds: 70),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: active
                  ? [hue.withValues(alpha: 0.23), hue.withValues(alpha: 0.09)]
                  : const [Color(0xFF202025), Color(0xFF131316)],
            ),
            border: Border.all(color: active || widget.error || widget.editing ? borderColor : const Color(0xFF2A2A30), width: widget.error ? 1.5 : 1),
            boxShadow: _down
                ? const [BoxShadow(color: Color(0xFF040405), offset: Offset(0, 1), blurRadius: 2)]
                : [
                    const BoxShadow(color: Color(0xFF040405), offset: Offset(0, 3)),
                    if (active)
                      BoxShadow(color: hue.withValues(alpha: 0.25), blurRadius: 16)
                    else
                      const BoxShadow(color: Color(0x73000000), offset: Offset(0, 7), blurRadius: 12),
                  ],
          ),
          padding: const EdgeInsets.all(6),
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
                            if (icon.isNotEmpty || (showImage && (b.image ?? '').isNotEmpty)) DeckIcon(icon: icon, image: showImage ? b.image : null, size: 28, color: hue),
                            if (label.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 96),
                                child: Text(
                                  label,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, height: 1.15, fontWeight: FontWeight.w500, letterSpacing: 0.1, color: active ? kText : const Color(0xFFA6A6AF)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
              if (widget.busy)
                const Positioned(
                  top: 2,
                  right: 2,
                  child: SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.6, color: kMuted)),
                ),
              if (widget.editing)
                const Positioned(top: 1, right: 1, child: Icon(Icons.drag_indicator, size: 13, color: kMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

String _rate(int? bytesPerSec) {
  if (bytesPerSec == null) return '--';
  final bits = bytesPerSec * 8;
  if (bits >= 1000000) return '${(bits / 1000000).toStringAsFixed(1)} Mb/s';
  if (bits >= 1000) return '${(bits / 1000).round()} kb/s';
  return '$bits b/s';
}

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
      case 'gpu':
        value = conn.stats.gpu == null ? 'n/a' : '${conn.stats.gpu}%';
        if (caption.isEmpty) caption = 'GPU';
        break;
      case 'netDown':
        value = _rate(conn.stats.netDown);
        if (caption.isEmpty) caption = 'Download';
        break;
      case 'netUp':
        value = _rate(conn.stats.netUp);
        if (caption.isEmpty) caption = 'Upload';
        break;
      case 'obsFps':
        value = conn.stats.obsFps == null ? '--' : '${conn.stats.obsFps}';
        if (caption.isEmpty) caption = 'OBS FPS';
        break;
      case 'dropped':
        value = conn.stats.dropped == null ? '--' : '${conn.stats.dropped}';
        if (caption.isEmpty) caption = 'Dropped';
        break;
      case 'bitrate':
        value = conn.stats.bitrate == null ? '--' : '${conn.stats.bitrate}';
        if (caption.isEmpty) caption = 'kbps';
        break;
      case 'twitchViewers':
        value = '${conn.stats.twitch['viewers'] ?? '--'}';
        if (caption.isEmpty) caption = 'Twitch viewers';
        break;
      case 'twitchFollowers':
        value = '${conn.stats.twitch['followers'] ?? '--'}';
        if (caption.isEmpty) caption = 'Followers';
        break;
      case 'ytViewers':
        value = '${conn.stats.youtube['viewers'] ?? '--'}';
        if (caption.isEmpty) caption = 'YouTube viewers';
        break;
      default:
        value = '?';
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500, letterSpacing: -0.5, color: kText, fontFeatures: [FontFeature.tabularFigures()])),
          if (caption.isNotEmpty)
            Text(caption, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: kMuted)),
        ],
      ),
    );
  }
}
