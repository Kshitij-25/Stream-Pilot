import 'package:flutter/material.dart';

import '../connection.dart';

/// Create ([pageId] null) or edit a screen: name, icon, whether it appears in the switcher.
Future<void> showPageEditor(BuildContext context, DeckConnection conn, {String? pageId}) async {
  final existing = pageId == null ? null : conn.config!.pages[pageId];
  final name = TextEditingController(text: existing?.name ?? '');
  final icon = TextEditingController(text: existing?.icon ?? '');
  var pinned = existing?.pinned ?? true;

  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'New screen' : 'Edit screen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, autofocus: existing == null, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(controller: icon, decoration: const InputDecoration(labelText: 'Icon (emoji)')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show in screen switcher'),
              subtitle: const Text('Off = only reachable through a Folder button'),
              value: pinned,
              onChanged: (v) => setState(() => pinned = v),
            ),
          ],
        ),
        actions: [
          if (existing != null && conn.config!.pages.length > 1)
            TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        ],
      ),
    ),
  );

  if (action == 'save' && name.text.trim().isNotEmpty) {
    conn.updateConfig((c) {
      if (existing == null) {
        c.addPage(name.text.trim(), icon: icon.text.trim(), pinned: pinned);
      } else {
        final p = c.pages[existing.id]!;
        p.name = name.text.trim();
        p.icon = icon.text.trim();
        p.pinned = pinned;
        // The start page must stay reachable.
        if (c.rootPage == p.id) p.pinned = true;
      }
    });
  } else if (action == 'delete' && existing != null) {
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${existing.name}"?'),
        content: const Text('Its buttons, and folder buttons pointing to it, are removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) conn.updateConfig((c) => c.deletePage(existing.id));
  }
  name.dispose();
  icon.dispose();
}
