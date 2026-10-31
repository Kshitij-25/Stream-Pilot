import 'dart:async';

import 'package:flutter/material.dart';

import '../connection.dart';
import '../models.dart';
import '../theme.dart';

/// Faders for the PC master volume, each app playing audio, and OBS audio inputs.
class MixerScreen extends StatefulWidget {
  const MixerScreen({super.key});

  @override
  State<MixerScreen> createState() => _MixerScreenState();
}

class _MixerScreenState extends State<MixerScreen> {
  Json? _data;
  String? _error;
  Timer? _poll;
  final Map<String, double> _dragging = {}; // fader key -> value while the finger is down
  final Map<String, int> _lastSent = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _load());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_dragging.isNotEmpty || !mounted) return;
    try {
      final d = await ConnScope.of(context).rpc('mixer.get') as Map;
      if (mounted && _dragging.isEmpty) setState(() { _data = Map<String, dynamic>.from(d); _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _set(String target, String? name, {double? volume, bool? muted}) async {
    try {
      await ConnScope.of(context).rpc('mixer.set', {'target': target, 'name': name, 'volume': ?volume, 'muted': ?muted});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _fader(String key, String label, double value, double max, bool muted, String target, String? name, {String? unit}) {
    final v = (_dragging[key] ?? value).clamp(0.0, max);
    final pct = max == 100 ? '${v.round()}%' : '${(v * 100).round()}%';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(children: [
          IconButton(
            icon: Icon(muted ? Icons.volume_off : Icons.volume_up, color: muted ? Colors.redAccent : null),
            tooltip: muted ? 'Unmute' : 'Mute',
            onPressed: () async {
              await _set(target, name, muted: !muted);
              _load();
            },
          ),
          SizedBox(width: 110, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(
            child: Slider(
              value: v,
              max: max,
              onChangeStart: (_) => _dragging[key] = v,
              onChanged: (x) {
                setState(() => _dragging[key] = x);
                final now = DateTime.now().millisecondsSinceEpoch;
                if (now - (_lastSent[key] ?? 0) > 120) {
                  _lastSent[key] = now;
                  _set(target, name, volume: x);
                }
              },
              onChangeEnd: (x) async {
                await _set(target, name, volume: x);
                _dragging.remove(key);
                _load();
              },
            ),
          ),
          SizedBox(width: 44, child: Text(unit ?? pct, textAlign: TextAlign.end)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final master = (d?['master'] ?? {}) as Map;
    final apps = [for (final a in (d?['apps'] ?? const []) as List) Map<String, dynamic>.from(a as Map)];
    final obs = [for (final a in (d?['obs'] ?? const []) as List) Map<String, dynamic>.from(a as Map)];
    return Scaffold(
      appBar: AppBar(title: const Text('Audio mixer')),
      body: d == null
          ? Center(child: _error != null ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!)) : const CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: [
              const _Section('PC'),
              _fader('master', 'Master', ((master['volume'] ?? 0) as num).toDouble(), 100, master['muted'] == true, 'master', null),
              const _Section('Apps playing audio'),
              if (d['appsError'] != null) Padding(padding: const EdgeInsets.all(8), child: Text('${d['appsError']}')),
              if (apps.isEmpty && d['appsError'] == null) const Padding(padding: EdgeInsets.all(8), child: Text('No app is producing audio right now.')),
              for (final a in apps) _fader('app:${a['name']}', a['name'] as String, (a['volume'] as num).toDouble(), 100, a['muted'] == true, 'app', a['name'] as String),
              const _Section('OBS inputs'),
              if (d['obsError'] != null) Padding(padding: const EdgeInsets.all(8), child: Text('${d['obsError']}')),
              for (final a in obs) _fader('obs:${a['name']}', a['name'] as String, (a['volume'] as num).toDouble(), 1, a['muted'] == true, 'obs', a['name'] as String),
            ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
        child: Text(text.toUpperCase(), style: sectionStyle()),
      );
}
