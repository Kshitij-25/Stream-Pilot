import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_deck/connection.dart';
import 'package:stream_deck/models.dart';
import 'package:stream_deck/screens/deck_screen.dart';
import 'package:stream_deck/widgets/deck_tile.dart';

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
    for (final name in ['Stream', 'Discord', 'Desktop', 'Audio', 'Sounds']) {
      expect(find.text(name, skipOffstage: false), findsWidgets, reason: 'rail tab $name');
    }
    // Dynamic: streaming button shows its active look (End Stream), live timer ticks.
    expect(find.text('End Stream'), findsOneWidget);
    expect(find.text('00:01:05'), findsOneWidget);
    expect(find.text('LIVE'), findsWidgets);

    // Keys are square and fit the screen height.
    final size = tester.getSize(find.byType(DeckScreen));
    final tile = tester.getSize(find.byType(DeckTile).first);
    expect(tile.width, tile.height);
    expect(tile.height, lessThanOrEqualTo(size.height / 3));

    await tester.tap(find.text('Audio').first);
    await tester.pump();
    expect(find.text('35%'), findsOneWidget); // volume widget from live stats
    await tester.tap(find.text('Desktop').first);
    await tester.pump();
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
    expect(find.text('Discord'), findsOneWidget);
    await tester.tap(find.text('Discord'));
    await tester.pump();
    expect(find.text('Deafen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit mode shows add-screen tab', (tester) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = await _conn();
    await tester.pumpWidget(_app(c));
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    expect(find.text('Add', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
