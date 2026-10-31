import 'package:flutter/material.dart';

import '../connection.dart';
import 'scan_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '8765');
  final _pin = TextEditingController();
  bool _seeded = false;
  bool _searching = false;
  List<FoundPc>? _found;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    final c = ConnScope.of(context);
    _host.text = c.host;
    _port.text = c.port.toString();
  }

  Future<void> _find() async {
    setState(() { _searching = true; _found = null; });
    final r = await DeckConnection.discover();
    if (!mounted) return;
    setState(() { _searching = false; _found = r; });
    if (r.length == 1) _pick(r.first);
  }

  void _pick(FoundPc pc) {
    _host.text = pc.host;
    _port.text = '${pc.port}';
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (raw == null) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'deckpad' || uri.host.isEmpty) {
      _toast('That QR code is not from the DeckPad companion.');
      return;
    }
    _host.text = uri.host;
    _port.text = (uri.hasPort ? uri.port : 8765).toString();
    _pin.text = uri.queryParameters['pin'] ?? '';
    _connect();
  }

  void _connect() {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty || port == null) {
      _toast('Enter the PC address and port.');
      return;
    }
    final pin = _pin.text.trim();
    final c = ConnScope.of(context);
    if (pin.isEmpty && !(c.token != null && c.host == host)) {
      _toast('Enter the 6-digit PIN shown in the companion window.');
      return;
    }
    FocusScope.of(context).unfocus();
    c.connect(host: host, port: port, pin: pin.isEmpty ? null : pin);
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final c = ConnScope.of(context);
    final busy = c.status == LinkStatus.connecting || c.status == LinkStatus.reconnecting;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.grid_view_rounded, size: 64),
                  const SizedBox(height: 12),
                  Text('DeckPad', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Run the companion on your PC, then scan its QR code.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: busy ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Scan QR code')),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: busy || _searching ? null : _find,
                    icon: _searching ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find),
                    label: Text(_searching ? 'Searching…' : 'Find PCs on Wi-Fi'),
                  ),
                  if (_found != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _found!.isEmpty
                          ? const Text('No PC found. Is the companion running on this Wi-Fi?', textAlign: TextAlign.center)
                          : Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
                              for (final pc in _found!) ActionChip(avatar: const Icon(Icons.computer, size: 16), label: Text('${pc.name} (${pc.host})'), onPressed: () => _pick(pc)),
                            ]),
                    ),
                  const SizedBox(height: 20),
                  Text('or enter manually', textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _host,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: const InputDecoration(labelText: 'PC address', hintText: '192.168.1.20'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _port,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Port'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pin,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(labelText: 'PIN', counterText: ''),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: busy ? null : _connect,
                    child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Connect')),
                  ),
                  const SizedBox(height: 16),
                  if (busy) ...[
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 8),
                    Text('Connecting to ${c.host}…', textAlign: TextAlign.center),
                    TextButton(onPressed: c.stop, child: const Text('Cancel')),
                  ],
                  if (c.error != null && !busy)
                    Text(c.error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
