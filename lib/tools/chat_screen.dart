import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../connection.dart';
import '../models.dart';

/// Live Twitch + YouTube chat with one-tap moderation.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Json> _msgs = [];
  final _scroll = ScrollController();
  final _input = TextEditingController();
  StreamSubscription? _sub;
  String _send = 'twitch';
  DeckConnection? _conn;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    final conn = _conn = ConnScope.of(context);
    _sub = conn.chatStream.listen((m) {
      setState(() {
        _msgs.add(m);
        if (_msgs.length > 300) _msgs.removeAt(0);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && _scroll.position.maxScrollExtent - _scroll.offset < 200) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    });
    () async {
      try {
        await conn.rpc('chat.subscribe', {'on': true});
        final recent = await conn.rpc('chat.recent') as List;
        if (mounted) setState(() => _msgs.insertAll(0, [for (final m in recent) Map<String, dynamic>.from(m as Map)]));
      } catch (_) {}
    }();
    if ((conn.integrations['twitch'] as Map?)?['connected'] != true && (conn.integrations['youtube'] as Map?)?['connected'] == true) _send = 'youtube';
  }

  @override
  void dispose() {
    _sub?.cancel();
    final c = _conn;
    if (c != null && c.connected) c.rpc('chat.subscribe', {'on': false}).catchError((_) {});
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _run(Json action) async {
    final err = await ConnScope.of(context).runAction(action);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(err ?? 'Done'), backgroundColor: err == null ? null : Colors.red.shade800));
  }

  void _modMenu(Json m) {
    final p = m['platform'] as String;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(title: Text('${m['user']}', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('${m['text']}', maxLines: 2)),
          for (final t in const [(60, '1 minute'), (600, '10 minutes'), (3600, '1 hour')])
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text('Timeout ${t.$2}'),
              onTap: () {
                Navigator.pop(ctx);
                _run({'type': p, 'op': 'timeout', 'userId': m['userId'], 'seconds': t.$1});
              },
            ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.redAccent),
            title: const Text('Ban'),
            onTap: () {
              Navigator.pop(ctx);
              _run({'type': p, 'op': 'ban', 'userId': m['userId']});
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete message'),
            onTap: () {
              Navigator.pop(ctx);
              _run({'type': p, 'op': 'deleteMessage', 'messageId': m['id']});
            },
          ),
          if (p == 'twitch')
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: const Text('Shoutout'),
              onTap: () {
                Navigator.pop(ctx);
                _run({'type': 'twitch', 'op': 'shoutout', 'userId': m['userId']});
              },
            ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy message'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: '${m['text']}'));
              Navigator.pop(ctx);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conn = ConnScope.of(context);
    final tw = (conn.integrations['twitch'] as Map?) ?? {};
    final yt = (conn.integrations['youtube'] as Map?) ?? {};
    final modes = (conn.stats.twitch['modes'] ?? {}) as Map;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat & moderation'),
        actions: [
          if (tw['connected'] == true)
            PopupMenuButton<String>(
              icon: const Icon(Icons.shield_outlined),
              tooltip: 'Chat modes',
              onSelected: (mode) => _run({'type': 'twitch', 'op': 'chatMode', 'mode': mode, 'state': 'toggle', 'value': mode == 'slow' ? 10 : 0}),
              itemBuilder: (_) => [
                for (final e in const {'slow': 'Slow mode', 'subs': 'Subscribers only', 'emote': 'Emote only', 'followers': 'Followers only', 'unique': 'Unique chat'}.entries)
                  CheckedPopupMenuItem(value: e.key, checked: modes[e.key] == true, child: Text(e.value)),
              ],
            ),
          if (tw['connected'] == true)
            IconButton(icon: const Icon(Icons.cleaning_services_outlined), tooltip: 'Clear chat', onPressed: () => _run({'type': 'twitch', 'op': 'clearChat'})),
        ],
      ),
      body: Column(children: [
        if (tw['connected'] != true && yt['connected'] != true)
          Container(
            width: double.infinity,
            color: Colors.orange.shade900,
            padding: const EdgeInsets.all(10),
            child: const Text('Connect Twitch or YouTube under Integrations to see chat.'),
          ),
        Expanded(
          child: _msgs.isEmpty
              ? const Center(child: Text('Waiting for chat messages…'))
              : ListView.builder(
                  controller: _scroll,
                  itemCount: _msgs.length,
                  itemBuilder: (_, i) {
                    final m = _msgs[i];
                    final color = m['color'] is String ? parseColor(m['color'] as String, Colors.lightBlueAccent) : Colors.lightBlueAccent;
                    return InkWell(
                      onTap: () => _modMenu(m),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        child: Text.rich(TextSpan(children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(m['platform'] == 'twitch' ? Icons.circle : Icons.play_circle_fill, size: 10, color: m['platform'] == 'twitch' ? const Color(0xFF9146FF) : Colors.redAccent),
                            ),
                          ),
                          if (m['isMod'] == true) const WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.gavel, size: 12, color: Colors.greenAccent))),
                          if (m['isSub'] == true) const WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.star, size: 12, color: Colors.amber))),
                          TextSpan(text: '${m['user']}: ', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                          TextSpan(text: '${m['text']}'),
                        ])),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(children: [
              if (tw['connected'] == true && yt['connected'] == true)
                IconButton(
                  icon: Icon(_send == 'twitch' ? Icons.circle : Icons.play_circle_fill, color: _send == 'twitch' ? const Color(0xFF9146FF) : Colors.redAccent),
                  tooltip: 'Sending to $_send',
                  onPressed: () => setState(() => _send = _send == 'twitch' ? 'youtube' : 'twitch'),
                ),
              Expanded(child: TextField(controller: _input, decoration: const InputDecoration(hintText: 'Send a chat message', isDense: true), onSubmitted: (_) => _submit())),
              IconButton(icon: const Icon(Icons.send), onPressed: _submit),
            ]),
          ),
        ),
      ]),
    );
  }

  void _submit() {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    _input.clear();
    _run({'type': _send, 'op': 'say', 'text': t});
  }
}
