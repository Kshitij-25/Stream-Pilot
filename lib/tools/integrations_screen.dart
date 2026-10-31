import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../connection.dart';
import '../models.dart';

/// Connect Twitch, YouTube and Discord. Each needs an app registration of your own (free).
class IntegrationsScreen extends StatelessWidget {
  const IntegrationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final conn = ConnScope.of(context);
    Json st(String k) => Map<String, dynamic>.from((conn.integrations[k] ?? {}) as Map);
    return Scaffold(
      appBar: AppBar(title: const Text('Integrations')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        _Card(
          service: 'twitch',
          title: 'Twitch',
          color: const Color(0xFF6441A5),
          status: st('twitch'),
          help: 'Create an app at dev.twitch.tv/console (OAuth redirect URL: http://localhost, Client Type: Public) and paste its Client ID. '
              'Then press Connect and enter the shown code on the Twitch page. Gives you events, chat, moderation, clips, markers, ads and chat modes.',
          fields: const [('clientId', 'Client ID', false)],
          summary: (s) => s['connected'] == true ? 'Logged in as ${s['user']}${s['live'] == true ? ' · LIVE ${s['viewers'] ?? ''} viewers' : ''}' : null,
        ),
        _Card(
          service: 'youtube',
          title: 'YouTube',
          color: const Color(0xFFC62828),
          status: st('youtube'),
          help: 'In Google Cloud Console enable "YouTube Data API v3" and create an OAuth client of type "TV and Limited Input devices". '
              'Paste the Client ID and secret, then Connect. Gives you live chat, Super Chat events, moderation and go-live / end. '
              'Note: the API has a daily quota.',
          fields: const [('clientId', 'Client ID', false), ('clientSecret', 'Client secret', true)],
          summary: (s) => s['connected'] == true ? (s['title'] != null ? 'Live: ${s['title']} · ${s['viewers'] ?? '?'} viewers' : 'Connected · no active broadcast') : null,
        ),
        _Card(
          service: 'discord',
          title: 'Discord',
          color: const Color(0xFF5865F2),
          status: st('discord'),
          help: 'Create an application at discord.com/developers, add the redirect http://localhost, and paste its Client ID and secret. '
              'Discord must be running on your PC: press Connect and click "Authorize" in the Discord window. Gives real mute / deafen state on your buttons. '
              'Discord only lets your own account authorize unapproved apps (add yourself as a tester under App Testers if asked).',
          fields: const [('clientId', 'Client ID', false), ('clientSecret', 'Client secret', true)],
          summary: (s) => s['connected'] == true ? 'Connected · mic ${s['mute'] == true ? 'muted' : 'live'}${s['deaf'] == true ? ' · deafened' : ''}' : null,
          loginLabel: 'Connect',
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Credentials are stored on your PC in ~/.deckpad/settings.json (plain text). Anyone with access to that file can use them.', style: TextStyle(fontSize: 12, color: Colors.white54)),
        ),
      ]),
    );
  }
}

class _Card extends StatefulWidget {
  final String service;
  final String title;
  final Color color;
  final Json status;
  final String help;
  final List<(String, String, bool)> fields;
  final String? Function(Json) summary;
  final String loginLabel;

  const _Card({
    required this.service,
    required this.title,
    required this.color,
    required this.status,
    required this.help,
    required this.fields,
    required this.summary,
    this.loginLabel = 'Log in',
  });

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  final _ctrl = <String, TextEditingController>{};
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _connect() async {
    final conn = ConnScope.of(context);
    setState(() { _busy = true; _msg = null; });
    try {
      final vals = {for (final f in widget.fields) f.$1: (_ctrl[f.$1]?.text ?? '').trim()};
      if (vals.values.any((v) => v.isNotEmpty)) {
        await conn.rpc('integrations.configure', {'service': widget.service, ...vals});
      }
      final r = await conn.rpc('integrations.login', {'service': widget.service});
      final uri = (r is Map ? r['verificationUri'] : null) as String?;
      if (uri != null) {
        await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
      } else if (widget.service == 'discord') {
        _msg = 'Look for the Authorize prompt in the Discord window on your PC.';
      }
    } catch (e) {
      _msg = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    final conn = ConnScope.of(context);
    final connected = s['connected'] == true;
    final pending = s['pending'] as Map?;
    final summary = widget.summary(s);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 6, backgroundColor: connected ? Colors.greenAccent : widget.color),
            const SizedBox(width: 8),
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (connected) TextButton(onPressed: () => conn.rpc('integrations.logout', {'service': widget.service}), child: const Text('Disconnect')),
          ]),
          if (summary != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(summary)),
          if (!connected) ...[
            const SizedBox(height: 8),
            Text(widget.help, style: const TextStyle(fontSize: 12, color: Colors.white60)),
            const SizedBox(height: 8),
            for (final f in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _ctrl.putIfAbsent(f.$1, () => TextEditingController()),
                  obscureText: f.$3,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: f.$2, hintText: s['configured'] == true ? 'saved: leave blank to keep' : null, isDense: true),
                ),
              ),
            if (pending != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                child: Column(children: [
                  const Text('Enter this code on the page that opened:'),
                  const SizedBox(height: 4),
                  SelectableText('${pending['userCode']}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  Wrap(spacing: 8, children: [
                    TextButton.icon(
                      onPressed: () => Clipboard.setData(ClipboardData(text: '${pending['userCode']}')),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                    ),
                    TextButton.icon(
                      onPressed: () => launchUrl(Uri.parse('${pending['verificationUri']}'), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open page'),
                    ),
                  ]),
                  const Text('Waiting for you to approve…', style: TextStyle(fontSize: 12, color: Colors.white54)),
                ]),
              ),
            if ((s['error'] ?? _msg) != null)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text('${s['error'] ?? _msg}', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12))),
            const SizedBox(height: 6),
            FilledButton(onPressed: _busy || !conn.connected ? null : _connect, child: Text(widget.loginLabel)),
          ] else if (s['error'] != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('${s['error']}', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12))),
        ]),
      ),
    );
  }
}
