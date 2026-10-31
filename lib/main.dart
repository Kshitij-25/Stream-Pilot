import 'package:flutter/material.dart';

import 'connection.dart';
import 'screens/connect_screen.dart';
import 'screens/deck_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final conn = DeckConnection();
  await conn.init();
  runApp(DeckPadApp(conn));
}

class DeckPadApp extends StatelessWidget {
  final DeckConnection conn;
  const DeckPadApp(this.conn, {super.key});

  @override
  Widget build(BuildContext context) {
    return ConnScope(
      conn: conn,
      child: MaterialApp(
        title: 'DeckPad',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF), brightness: Brightness.dark),
          scaffoldBackgroundColor: const Color(0xFF0E0E12),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final conn = ConnScope.of(context);
    if (conn.config != null && conn.status != LinkStatus.failed && conn.status != LinkStatus.idle) {
      return const DeckScreen();
    }
    return const ConnectScreen();
  }
}
