import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_deck/connection.dart';
import 'package:stream_deck/models.dart';
import 'package:stream_deck/screens/deck_screen.dart';
import 'package:stream_deck/widgets/deck_tile.dart';
import 'package:stream_deck/widgets/deck_icon.dart';

Future<DeckConnection> _conn() async {
  SharedPreferences.setMockInitialValues({});
  final c = DeckConnection();
  await c.init();
  // The real default layout produced by the companion server.
  final json = jsonDecode(File('test/fixtures/default_config.json').readAsStringSync()) as Json;
  c.config = DeckConfig.fromJson(json);
  c.status = LinkStatus.reconnecting;
  c.obs = ObsState()..connected = true..streaming = true..streamStart = DateTime.now().millisecondsSinceEpoch - 65000;
  c.stats = SystemStats()..cpu = 42..mem = 61..vol = 35;
  return c;
}

/// Rails / tab strips scroll when there are many screens: bring the tab into view, then tap it.
Future<void> tapTab(WidgetTester tester, String name, Axis axis) async {
  final f = find.text(name);
  if (f.evaluate().isEmpty) {
    await tester.dragUntilVisible(f, find.byType(ListView).first, axis == Axis.vertical ? const Offset(0, -80) : const Offset(-120, 0));
  }
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first, warnIfMissed: true);
  await tester.pump();
}

Widget _app(DeckConnection c) => ConnScope(conn: c, child: const MaterialApp(home: DeckScreen()));

void main() {
  testWidgets('landscape: rail with screens + square key grid, no overflow', (tester) async {
    tester.view.physicalSize = const Size(2400, 1080); // 800x360 dp
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = await _conn();
    await tester.pumpWidget(_app(c));
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final name in ['Stream', 'Audio', 'Twitch', 'YouTube', 'Discord', 'Desktop', 'Macros', 'Sounds', 'Monitor']) {
      expect(find.text(name, skipOffstage: false), findsWidgets, reason: 'rail tab $name');
    }
    // Dynamic: streaming button shows its active look (End Stream), live timer ticks.
    expect(find.text('End Stream'), findsOneWidget);
    expect(find.text('00:01:05'), findsOneWidget);
    expect(find.text('Live'), findsWidgets);

    // Keys are square and fit the screen height.
    final size = tester.getSize(find.byType(DeckScreen));
    final tile = tester.getSize(find.byType(DeckTile).first);
    expect(tile.width, tile.height);
    expect(tile.height, lessThanOrEqualTo(size.height / 3));

    await tapTab(tester, 'Audio', Axis.vertical);
    expect(find.text('35%'), findsOneWidget); // volume widget from live stats
    await tapTab(tester, 'Monitor', Axis.vertical);
    expect(find.text('42%'), findsOneWidget); // CPU widget
    expect(find.text('61%'), findsOneWidget); // RAM widget
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait: top bar + tab strip, no overflow', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = await _conn();
    await tester.pumpWidget(_app(c));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tapTab(tester, 'Discord', Axis.horizontal);
    expect(find.text('Deafen'), findsOneWidget);
    // Discord toggle shows its normal look until Discord reports muted.
    expect(find.text('Muted'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('every vector icon used by the default layout exists in the app icon set', () {
    final json = jsonDecode(File('test/fixtures/default_config.json').readAsStringSync()) as Map;
    final missing = <String>{};
    void check(String? icon) {
      if (icon != null && icon.startsWith('mi:') && !materialIconSet.containsKey(icon.substring(3))) missing.add(icon);
    }
    for (final p in (json['pages'] as Map).values) {
      for (final b in (p as Map)['buttons'] as List) {
        if (b == null) continue;
        check(b['icon'] as String?);
        check(b['iconOn'] as String?);
      }
    }
    expect(missing, isEmpty);
  });

  test('default layout round-trips through the app model without losing companion fields', () {
    final json = jsonDecode(File('test/fixtures/default_config.json').readAsStringSync()) as Json;
    final cfg = DeckConfig.fromJson(json);
    final again = jsonEncode(cfg.toJson());
    expect(again.contains('iconHint'), isTrue); // real-icon hints survive a phone-side save
    expect(cfg.screens.length, 9);
    expect(cfg.pages['stream']!.buttons[10]!.hasActiveLook, isTrue);
  });

  testWidgets('edit mode shows add-screen tab', (tester) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = await _conn();
    await tester.pumpWidget(_app(c));
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    await tester.dragUntilVisible(find.text('Add'), find.byType(ListView).first, const Offset(0, -80));
    expect(find.text('Add'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
