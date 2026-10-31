import 'package:flutter/material.dart';

import '../connection.dart';
import '../models.dart';
import 'automations_screen.dart';
import 'chat_screen.dart';
import 'history_screen.dart';
import 'integrations_screen.dart';
import 'mixer_screen.dart';
import 'perf_screen.dart';

const _icons = {
  'mixer': Icons.tune,
  'perf': Icons.analytics_outlined,
  'history': Icons.history,
  'automations': Icons.smart_toy_outlined,
  'integrations': Icons.link,
  'chat': Icons.forum_outlined,
  'events': Icons.notifications_outlined,
};

Widget? toolScreen(String name) => switch (name) {
      'mixer' => const MixerScreen(),
      'perf' => const PerfScreen(),
      'history' => const HistoryScreen(),
      'automations' => const AutomationsScreen(),
      'integrations' => const IntegrationsScreen(),
      'chat' => const ChatScreen(),
      'events' => const EventsScreen(),
      _ => null,
    };

void openTool(BuildContext context, String name) {
  final w = toolScreen(name);
  if (w != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
}

IconData toolIcon(String name) => _icons[name] ?? Icons.apps;

/// Bottom sheet to choose which deck profile this phone shows.
Future<void> showProfileSheet(BuildContext context) {
  final conn = ConnScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Deck profile', style: TextStyle(fontWeight: FontWeight.bold))),
        ListTile(
          leading: Icon(conn.following ? Icons.radio_button_checked : Icons.radio_button_off),
          title: const Text('Follow the PC'),
          subtitle: const Text('Changes automatically, e.g. when you switch apps (see Automations)'),
          onTap: () {
            conn.selectProfile(null);
            Navigator.pop(ctx);
          },
        ),
        for (final p in conn.profiles)
          ListTile(
            leading: Icon(!conn.following && conn.profileId == p['id'] ? Icons.radio_button_checked : Icons.radio_button_off),
            title: Text(p['name'] as String),
            subtitle: const Text('Pinned to this phone'),
            onTap: () {
              conn.selectProfile(p['id'] as String);
              Navigator.pop(ctx);
            },
          ),
      ]),
    ),
  );
}

Future<String?> promptText(BuildContext context, String title, {String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

/// Lists every tool screen (used from Settings).
List<Widget> toolTiles(BuildContext context) => [
      for (final e in toolScreens.entries)
        ListTile(leading: Icon(toolIcon(e.key)), title: Text(e.value), trailing: const Icon(Icons.chevron_right), onTap: () => openTool(context, e.key)),
    ];
