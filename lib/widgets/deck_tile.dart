import 'package:flutter/material.dart';

import '../models.dart';

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
        onTap: widget.editing ? widget.onTap : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: widget.editing ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
            border: Border.all(color: widget.editing ? Colors.white24 : Colors.white10),
          ),
          child: widget.editing ? const Center(child: Icon(Icons.add, color: Colors.white38)) : null,
        ),
      );
    }

    final base = parseColor(b.color);
    final hsl = HSLColor.fromColor(base);
    final top = hsl.withLightness((hsl.lightness + 0.08).clamp(0, 1)).toColor();
    final bottom = hsl.withLightness((hsl.lightness - 0.08).clamp(0, 1)).toColor();

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: const Duration(milliseconds: 80),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]),
            border: Border.all(
              color: widget.error
                  ? Colors.redAccent
                  : widget.active
                      ? Colors.white
                      : widget.editing
                          ? Colors.white54
                          : Colors.white12,
              width: widget.active || widget.error ? 3 : 1,
            ),
            boxShadow: widget.active ? [BoxShadow(color: base.withValues(alpha: 0.8), blurRadius: 14)] : null,
          ),
          padding: const EdgeInsets.all(6),
          child: Stack(
            children: [
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (b.icon.isNotEmpty) Text(b.icon, style: const TextStyle(fontSize: 34)),
                      if (b.label.isNotEmpty)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 110),
                          child: Text(
                            b.label,
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
