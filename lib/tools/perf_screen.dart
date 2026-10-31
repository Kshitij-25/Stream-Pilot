import 'package:flutter/material.dart';

import '../connection.dart';

/// Live sparkline charts of PC and OBS performance (last ~3 minutes).
class PerfScreen extends StatelessWidget {
  const PerfScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final conn = ConnScope.of(context);
    final h = conn.perfHistory;
    List<double?> series(String k, [double scale = 1]) =>
        [for (final e in h) (e[k] is num) ? (e[k] as num).toDouble() * scale : null];

    final charts = <Widget>[
      _Chart('CPU', series('cpu'), '%', Colors.tealAccent, fixedMax: 100),
      _Chart('Memory', series('mem'), '%', Colors.lightBlueAccent, fixedMax: 100),
      _Chart('GPU (NVIDIA)', series('gpu'), '%', Colors.greenAccent, fixedMax: 100, emptyText: 'No NVIDIA GPU data'),
      _Chart('Download', series('netDown', 8 / 1e6), 'Mb/s', Colors.amberAccent, emptyText: 'Windows only'),
      _Chart('Upload', series('netUp', 8 / 1e6), 'Mb/s', Colors.orangeAccent, emptyText: 'Windows only'),
      _Chart('OBS FPS', series('obsFps'), 'fps', Colors.purpleAccent, emptyText: 'OBS not connected'),
      _Chart('Dropped frames', series('dropped'), '', Colors.redAccent, emptyText: 'OBS not connected'),
      _Chart('Stream bitrate', series('bitrate'), 'kbps', Colors.pinkAccent, emptyText: 'Not streaming'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Performance')),
      body: LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth > 700 ? 3 : (box.maxWidth > 420 ? 2 : 1);
        return GridView.count(
          crossAxisCount: cols,
          padding: const EdgeInsets.all(12),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.9,
          children: charts,
        );
      }),
    );
  }
}

class _Chart extends StatelessWidget {
  final String title;
  final List<double?> values;
  final String unit;
  final Color color;
  final double? fixedMax;
  final String emptyText;

  const _Chart(this.title, this.values, this.unit, this.color, {this.fixedMax, this.emptyText = 'No data'});

  @override
  Widget build(BuildContext context) {
    final real = values.whereType<double>().toList();
    final last = real.isEmpty ? null : real.last;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.labelLarge)),
            Text(last == null ? '--' : '${last >= 100 ? last.round() : last.toStringAsFixed(1)} $unit',
                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          Expanded(
            child: real.length < 2
                ? Center(child: Text(emptyText, style: const TextStyle(color: Colors.white38, fontSize: 12)))
                : CustomPaint(size: Size.infinite, painter: _Spark(values, color, fixedMax)),
          ),
        ]),
      ),
    );
  }
}

class _Spark extends CustomPainter {
  final List<double?> v;
  final Color color;
  final double? fixedMax;
  _Spark(this.v, this.color, this.fixedMax);

  @override
  void paint(Canvas canvas, Size size) {
    final real = v.whereType<double>();
    final max = fixedMax ?? (real.fold<double>(1, (a, b) => b > a ? b : a) * 1.15);
    final grid = Paint()..color = Colors.white10..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final path = Path();
    final fill = Path();
    var started = false;
    final n = v.length;
    for (var i = 0; i < n; i++) {
      final val = v[i];
      if (val == null) continue;
      final x = n == 1 ? 0.0 : size.width * i / (n - 1);
      final y = size.height - (val / max).clamp(0.0, 1.0) * size.height;
      if (!started) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    if (!started) return;
    fill.lineTo(size.width, size.height);
    fill.close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.15));
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _Spark old) => true;
}
