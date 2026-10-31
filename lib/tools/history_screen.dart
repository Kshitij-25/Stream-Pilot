import 'dart:async';

import 'package:flutter/material.dart';

import '../connection.dart';
import '../models.dart';

String _clock(dynamic ts) {
  final d = DateTime.fromMillisecondsSinceEpoch((ts as num).toInt());
  String t(int n) => n.toString().padLeft(2, '0');
  return '${t(d.hour)}:${t(d.minute)}:${t(d.second)}';
}

/// Everything the deck / automations did: what ran, from which device, and whether it worked.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Json> _items = [];
  String? _error;
  bool _onlyErrors = false;
  StreamSubscription? _sub;
  late final DeckConnection _conn;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    _conn = ConnScope.of(context);
    _sub = _conn.historyStream.listen((e) => setState(() => _items.insert(0, e)));
    () async {
      try {
        await _conn.rpc('history.subscribe', {'on': true});
        final d = await _conn.rpc('history') as Map;
        if (mounted) setState(() => _items = [for (final h in d['history'] as List) Map<String, dynamic>.from(h as Map)]);
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      }
    }();
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_conn.connected) _conn.rpc('history.subscribe', {'on': false}).catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _onlyErrors ? _items.where((e) => e['ok'] == false).toList() : _items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Action history'),
        actions: [
          FilterChip(label: const Text('Errors only'), selected: _onlyErrors, onSelected: (v) => setState(() => _onlyErrors = v)),
          const SizedBox(width: 12),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : list.isEmpty
              ? const Center(child: Text('Nothing yet. Press a button.'))
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = list[i];
                    final ok = e['ok'] == true;
                    return ListTile(
                      dense: true,
                      leading: Icon(ok ? Icons.check_circle : Icons.error, color: ok ? Colors.greenAccent : Colors.redAccent, size: 20),
                      title: Text('${e['label'] ?? ''}${e['kind'] != null && e['kind'] != 'tap' ? ' (${e['kind']})' : ''}'),
                      subtitle: Text([e['action'], if (!ok && e['error'] != null) '⚠ ${e['error']}'].join('\n')),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(_clock(e['ts']), style: const TextStyle(fontSize: 12)),
                        Text('${e['source'] ?? ''}${e['device'] != null ? ' · ${e['device']}' : ''}', style: const TextStyle(fontSize: 10, color: Colors.white54)),
                      ]),
                    );
                  },
                ),
    );
  }
}

/// Follows, subs, raids, super chats, clips ... as they happen.
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  List<Json> _items = [];
  StreamSubscription? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    final conn = ConnScope.of(context);
    _sub = conn.eventStream.listen((e) => setState(() => _items.insert(0, e)));
    conn.rpc('history').then((d) {
      if (mounted) setState(() => _items = [for (final h in (d as Map)['events'] as List) Map<String, dynamic>.from(h as Map)]);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  static IconData _icon(String t) {
    if (t.contains('follow')) return Icons.person_add;
    if (t.contains('sub') || t.contains('member') || t.contains('gift')) return Icons.star;
    if (t.contains('cheer') || t.contains('superchat')) return Icons.diamond;
    if (t.contains('raid')) return Icons.groups;
    if (t.contains('redeem')) return Icons.redeem;
    if (t.contains('clip')) return Icons.content_cut;
    if (t.contains('online')) return Icons.sensors;
    if (t.contains('offline')) return Icons.sensors_off;
    return Icons.notifications;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: _items.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Follows, subs, raids and other events show up here once Twitch / YouTube is connected.', textAlign: TextAlign.center)))
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = _items[i];
                return ListTile(
                  leading: Icon(_icon('${e['type']}')),
                  title: Text('${e['title'] ?? e['type']}'),
                  subtitle: (e['detail'] ?? '') == '' ? null : Text('${e['detail']}'),
                  trailing: Text(_clock(e['ts']), style: const TextStyle(fontSize: 12)),
                );
              },
            ),
    );
  }
}
