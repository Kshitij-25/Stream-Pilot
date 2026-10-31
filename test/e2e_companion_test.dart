// End-to-end: the real Node companion driven through the app's own DeckConnection.
@TestOn('windows || mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_deck/connection.dart';
import 'package:stream_deck/models.dart';

const port = 18800;

Future<(Process, String)> startCompanion(String home) async {
  final p = await Process.start(
    'node',
    ['server/src/index.js'],
    environment: {'DECKPAD_PORT': '$port', 'DECKPAD_HOME': home, 'DECKPAD_NO_ICONS': '1', 'DECKPAD_DISCOVERY_PORT': '${port + 1}'},
  );
  final out = StringBuffer();
  final ready = Completer<String>();
  p.stdout.transform(utf8.decoder).listen((d) {
    out.write(d);
    final m = RegExp(r'Pairing PIN : (\d{6})').firstMatch(out.toString());
    if (m != null && !ready.isCompleted) ready.complete(m.group(1));
  });
  p.stderr.drain<void>();
  final pin = await ready.future.timeout(const Duration(seconds: 15));
  return (p, pin);
}

Future<void> until(bool Function() cond, {int seconds = 15, String what = 'condition'}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  test('app <-> companion: pairing, presses, long press, profiles, stats, discovery, reconnect', () async {
    SharedPreferences.setMockInitialValues({});
    final home = Directory.systemTemp.createTempSync('deckpad-e2e-').path;
    var (server, pin) = await startCompanion(home);
    addTearDown(() => server.kill());

    final conn = DeckConnection();
    await conn.init();
    conn.keepAwake = false;

    // --- pairing with the PIN
    await conn.connect(host: '127.0.0.1', port: port, pin: pin);
    await until(() => conn.connected, what: 'connected');
    expect(conn.protocol, requiredProtocol);
    expect(conn.outdatedCompanion, isFalse);
    expect(conn.config!.screens.map((p) => p.name), containsAll(['Stream', 'Audio', 'Twitch', 'YouTube', 'Discord', 'Desktop', 'Macros', 'Sounds', 'Monitor']));
    expect(conn.profiles.map((p) => p['id']), containsAll(['streaming', 'desktop']));
    expect(conn.following, isTrue);
    expect(conn.token, isNotNull);

    // --- Vol + / Vol - from the default Audio page, through the app code path
    if (Platform.isWindows) {
      final audio = conn.config!.pages['audio']!;
      final up = audio.buttons.firstWhere((b) => b?.label == 'Vol +')!;
      final down = audio.buttons.firstWhere((b) => b?.label == 'Vol -')!;
      await until(() => conn.stats.vol != null, what: 'volume readback');
      final before = conn.stats.vol!;
      expect(await conn.press(down), isNull);
      await until(() => conn.stats.vol != before, what: 'volume to change after Vol -');
      final lowered = conn.stats.vol!;
      expect(lowered, lessThan(before));
      expect(await conn.press(up), isNull);
      await until(() => conn.stats.vol != lowered, what: 'volume to change after Vol +');
      expect(conn.stats.vol, greaterThan(lowered));
      expect(await conn.runAction({'type': 'volume', 'op': 'set', 'value': before}), isNull); // restore
    }

    // --- editing syncs and persists; tap / long press / double tap / missing button
    conn.updateConfig((c) {
      c.pages['stream']!.buttons[0] = DeckButton(
        id: 'e2e',
        label: 'E2E',
        action: {'type': 'command', 'command': 'echo tap'},
        longAction: {'type': 'command', 'command': 'echo long'},
        doubleAction: {'type': 'command', 'command': 'exit 4'},
      );
    });
    final e2e = conn.config!.pages['stream']!.buttons[0]!;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(await conn.press(e2e), isNull);
    expect(await conn.press(e2e, kind: 'long'), isNull);
    expect(await conn.press(e2e, kind: 'double'), isNotNull);
    expect(await conn.press(DeckButton(id: 'nope')), contains('no longer exists'));
    final hist = (await conn.rpc('history') as Map)['history'] as List;
    expect(hist.where((h) => (h as Map)['label'] == 'E2E').length, 3);

    // --- live stats feed the dashboard
    await until(() => conn.perfHistory.length >= 2, what: 'stats', seconds: 8);
    expect(conn.stats.mem, greaterThan(0));
    expect(conn.isActive(DeckButton(action: {'type': 'obs', 'op': 'toggleStream'})), isFalse); // OBS not connected here

    // --- profiles: pin this phone, then follow the PC again
    conn.selectProfile('desktop');
    await until(() => conn.profileId == 'desktop', what: 'desktop profile');
    expect(conn.following, isFalse);
    expect(conn.config!.pages.containsKey('stream'), isFalse);
    conn.selectProfile(null);
    await until(() => conn.following && conn.profileId == 'streaming', what: 'follow PC');

    // --- device list, mixer rpc, unknown rpc
    final devices = await conn.rpc('devices') as List;
    expect(devices.length, 1);
    expect((devices.first as Map)['current'], isTrue);
    await expectLater(conn.rpc('definitely.not.a.method'), throwsA(contains('update the companion')));
    if (Platform.isWindows) {
      final mix = await conn.rpc('mixer.get') as Map;
      expect(mix['master'], isNotNull);
    }

    // --- LAN discovery
    final found = await DeckConnection.discover(port: port + 1);
    expect(found.any((f) => f.port == port), isTrue);

    // --- reconnection: kill the companion, then bring it back
    server.kill();
    await until(() => conn.status == LinkStatus.reconnecting, what: 'reconnecting state');
    final restarted = await startCompanion(home);
    server = restarted.$1;
    await until(() => conn.connected, seconds: 30, what: 'automatic reconnect with the saved token');
    expect(conn.config!.pages.containsKey('stream'), isTrue);
    expect(conn.config!.pages['stream']!.buttons[0]!.id, 'e2e', reason: 'edits persisted across the restart');
    conn.stop();
    server.kill();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
