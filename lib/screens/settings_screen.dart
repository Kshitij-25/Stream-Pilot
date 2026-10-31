import 'package:flutter/material.dart';

import '../connection.dart';
import '../widgets/page_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _obsHost = TextEditingController();
  final _obsPort = TextEditingController();
  final _obsPass = TextEditingController();
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    final o = ConnScope.of(context).obsSettings;
    _obsHost.text = o.host;
    _obsPort.text = o.port.toString();
  }

  @override
  void dispose() {
    _obsHost.dispose();
    _obsPort.dispose();
    _obsPass.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    return r == true;
  }

  Widget _stepper(String label, int value, int min, int max, ValueChanged<int> onChanged) => ListTile(
        title: Text(label),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: value > min ? () => onChanged(value - 1) : null),
          Text('$value', style: Theme.of(context).textTheme.titleMedium),
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: value < max ? () => onChanged(value + 1) : null),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final conn = ConnScope.of(context);
    final cfg = conn.config!;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.circle, size: 14, color: conn.connected ? Colors.greenAccent : Colors.orange),
            title: Text(conn.hostName.isEmpty ? conn.host : conn.hostName),
            subtitle: Text(conn.connected ? 'Connected · ${conn.host}:${conn.port}' : 'Reconnecting…'),
          ),
          const Divider(),
          const _Header('Layout'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              for (final g in const [('Mini 3×2', 3, 2), ('Classic 5×3', 5, 3), ('XL 8×4', 8, 4), ('Tall 4×5', 4, 5)])
                ChoiceChip(
                  label: Text(g.$1),
                  selected: cfg.cols == g.$2 && cfg.rows == g.$3,
                  onSelected: (_) => conn.updateConfig((c) => c.resize(g.$2, g.$3)),
                ),
            ]),
          ),
          _stepper('Columns', cfg.cols, 1, 10, (v) => conn.updateConfig((c) => c.resize(v, c.rows))),
          _stepper('Rows', cfg.rows, 1, 10, (v) => conn.updateConfig((c) => c.resize(c.cols, v))),
          ListTile(
            title: const Text('Screen orientation'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'landscape', label: Text('Landscape'), icon: Icon(Icons.stay_current_landscape)),
                  ButtonSegment(value: 'portrait', label: Text('Portrait'), icon: Icon(Icons.stay_current_portrait)),
                  ButtonSegment(value: 'auto', label: Text('Auto')),
                ],
                selected: {conn.orientation},
                onSelectionChanged: (v) => conn.setOrientation(v.first),
              ),
            ),
          ),
          const Divider(),
          const _Header('Screens & pages'),
          for (final p in cfg.pages.values)
            ListTile(
              leading: p.icon.isEmpty ? Icon(p.id == cfg.rootPage ? Icons.home : Icons.folder_outlined) : Text(p.icon, style: const TextStyle(fontSize: 22)),
              title: Text(p.name),
              subtitle: Text([
                if (p.id == cfg.rootPage) 'Start screen',
                p.pinned ? 'In switcher' : 'Folder page',
              ].join(' · ')),
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') {
                    showPageEditor(context, conn, pageId: p.id);
                  } else if (v == 'root') {
                    conn.updateConfig((c) {
                      c.rootPage = p.id;
                      c.pages[p.id]!.pinned = true;
                    });
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit / delete')),
                  if (p.id != cfg.rootPage) const PopupMenuItem(value: 'root', child: Text('Make start screen')),
                ],
              ),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add screen'),
            subtitle: const Text('e.g. Streaming, Discord, Desktop, Audio'),
            onTap: () => showPageEditor(context, conn),
          ),
          const Divider(),
          const _Header('OBS Studio'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              Row(children: [
                Icon(Icons.circle, size: 12, color: conn.obs.connected ? Colors.greenAccent : Colors.grey),
                const SizedBox(width: 8),
                Text(conn.obs.connected ? 'OBS connected' : 'OBS not connected'),
              ]),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'In OBS: Tools → WebSocket Server Settings → enable. Use the same port and password here. Host is relative to your PC (usually 127.0.0.1).',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(flex: 3, child: TextField(controller: _obsHost, decoration: const InputDecoration(labelText: 'Host'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _obsPort, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port'))),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _obsPass,
                obscureText: true,
                decoration: InputDecoration(labelText: 'Password', hintText: conn.obsSettings.hasPassword ? 'unchanged' : 'none'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    conn.saveObsSettings(
                      host: _obsHost.text.trim(),
                      port: int.tryParse(_obsPort.text.trim()) ?? 4455,
                      password: _obsPass.text.isEmpty ? null : _obsPass.text,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved. Reconnecting to OBS…')));
                  },
                  child: const Text('Save & reconnect'),
                ),
              ),
            ]),
          ),
          const Divider(),
          const _Header('App'),
          SwitchListTile(title: const Text('Haptic feedback'), value: conn.haptics, onChanged: conn.setHaptics),
          SwitchListTile(
            title: const Text('Keep screen on'),
            subtitle: const Text('Stops the phone sleeping while the deck is open'),
            value: conn.keepAwake,
            onChanged: conn.setKeepAwake,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.link_off),
            title: const Text('Disconnect'),
            subtitle: const Text('Stay paired, stop connecting'),
            onTap: () {
              conn.stop();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
            title: const Text('Forget this PC'),
            subtitle: const Text('You will need a new PIN to pair again'),
            onTap: () async {
              if (await _confirm('Forget this PC?', 'The app will unpair. Your buttons stay saved on the PC.')) {
                await conn.forget();
                if (!context.mounted) return;
                Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
