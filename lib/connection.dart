import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';

enum LinkStatus { idle, connecting, connected, reconnecting, failed }

/// Owns the WebSocket link to the PC companion, plus the synced deck config and OBS state.
class DeckConnection extends ChangeNotifier {
  late final SharedPreferences _prefs;

  LinkStatus status = LinkStatus.idle;
  String? error;
  String host = '';
  int port = 8765;
  String? token;
  String hostName = '';
  DeckConfig? config;
  ObsState obs = ObsState();
  ObsSettings obsSettings = ObsSettings();
  SystemStats stats = SystemStats();
  Map<String, bool> toggles = {};
  int _clockOffset = 0; // server ms minus phone ms

  /// 'landscape' | 'portrait' | 'auto'
  String orientation = 'landscape';

  bool haptics = true;
  bool keepAwake = true;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _retryTimer;
  Timer? _pingTimer;
  DateTime _lastRx = DateTime.now();
  bool _want = false; // user wants to be connected
  bool _persist = false; // keep retrying forever (we hold a valid token)
  int _attempt = 0;
  int _rid = 0;
  String? _pin;
  final _pending = <int, Completer<String?>>{};
  Completer<Map<String, List<String>>>? _listing;

  bool get connected => status == LinkStatus.connected;
  bool get hasSavedServer => host.isNotEmpty && token != null;

  String get _deviceName => Platform.isIOS ? 'iPhone / iPad' : 'Android device';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    host = _prefs.getString('host') ?? '';
    port = _prefs.getInt('port') ?? 8765;
    token = _prefs.getString('token');
    haptics = _prefs.getBool('haptics') ?? true;
    orientation = _prefs.getString('orientation') ?? 'landscape';
    keepAwake = _prefs.getBool('keepAwake') ?? true;
    final cached = _prefs.getString('config');
    if (cached != null) {
      try {
        config = DeckConfig.fromJson(jsonDecode(cached) as Json);
      } catch (_) {}
    }
    if (hasSavedServer) {
      unawaited(connect(host: host, port: port));
    }
  }

  void setHaptics(bool v) {
    haptics = v;
    _prefs.setBool('haptics', v);
    notifyListeners();
  }

  void setOrientation(String v) {
    orientation = v;
    _prefs.setString('orientation', v);
    notifyListeners();
  }

  /// Current time on the PC (for stream timers that must not drift with phone clock).
  int get serverNow => DateTime.now().millisecondsSinceEpoch + _clockOffset;

  void _syncClock(dynamic now) {
    if (now is num) _clockOffset = now.toInt() - DateTime.now().millisecondsSinceEpoch;
  }

  /// Whether a button should currently show its "active" look.
  bool isActive(DeckButton b) {
    final a = b.action;
    if (toggles[b.id] == true) return true;
    switch (a['type']) {
      case 'obs':
        if (!obs.connected) return false;
        switch (a['op']) {
          case 'toggleStream':
          case 'startStream':
            return obs.streaming;
          case 'toggleRecord':
            return obs.recording;
          case 'scene':
            return obs.scene != null && obs.scene == a['scene'];
          case 'toggleMute':
          case 'mute':
            return obs.muted[a['input']] == true;
        }
        return false;
      case 'volume':
        return (a['op'] == 'toggleMute' || a['op'] == 'mute') && stats.muted;
    }
    return false;
  }

  void setKeepAwake(bool v) {
    keepAwake = v;
    _prefs.setBool('keepAwake', v);
    _applyWakelock();
    notifyListeners();
  }

  void _applyWakelock() {
    try {
      if (keepAwake && connected) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    } catch (_) {}
  }

  Future<void> connect({required String host, required int port, String? pin}) async {
    if (host != this.host || port != this.port) {
      // A different PC: the old token is useless for it.
      token = host == this.host ? token : null;
    }
    this.host = host;
    this.port = port;
    _pin = pin;
    _want = true;
    _persist = token != null;
    _attempt = 0;
    error = null;
    status = _persist && config != null ? LinkStatus.reconnecting : LinkStatus.connecting;
    notifyListeners();
    await _open();
  }

  Future<void> _open() async {
    _teardown();
    if (!_want) return;
    try {
      final ch = WebSocketChannel.connect(Uri.parse('ws://$host:$port'));
      await ch.ready.timeout(const Duration(seconds: 5));
      if (!_want) {
        ch.sink.close();
        return;
      }
      _ch = ch;
      _lastRx = DateTime.now();
      _sub = ch.stream.listen(_onData, onDone: () => _onClosed(ch), onError: (_) => _onClosed(ch));
      _send({
        't': 'hello',
        'name': _deviceName,
        if (token != null) 'token': token,
        if (_pin != null) 'pin': _pin,
      });
      _pingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        if (DateTime.now().difference(_lastRx) > const Duration(seconds: 22)) {
          _onClosed(ch);
        } else {
          _send({'t': 'ping'});
        }
      });
    } catch (_) {
      _onClosed(null);
    }
  }

  void _teardown() {
    _pingTimer?.cancel();
    _retryTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete('Disconnected');
    }
    _pending.clear();
  }

  void _onClosed(WebSocketChannel? ch) {
    if (ch != null && ch != _ch) return; // stale socket
    _teardown();
    if (!_want) return;
    if (_persist) {
      status = LinkStatus.reconnecting;
      error = 'Can\'t reach $host — is the companion running on your PC?';
      notifyListeners();
      final wait = Duration(seconds: (1 << _attempt.clamp(0, 3)));
      _attempt++;
      _retryTimer = Timer(wait, _open);
    } else {
      status = LinkStatus.failed;
      error = 'Could not connect to $host:$port. Check the address and that you are on the same Wi-Fi.';
      _want = false;
      notifyListeners();
    }
    _applyWakelock();
  }

  void _onData(dynamic raw) {
    _lastRx = DateTime.now();
    final Json m;
    try {
      m = jsonDecode(raw as String) as Json;
    } catch (_) {
      return;
    }
    switch (m['t']) {
      case 'welcome':
        if (m['token'] != null) {
          token = m['token'] as String;
          _prefs.setString('token', token!);
        }
        _prefs.setString('host', host);
        _prefs.setInt('port', port);
        _pin = null;
        _persist = true;
        _attempt = 0;
        error = null;
        hostName = (m['host']?['name'] ?? host) as String;
        _setConfig(m['config'] as Json);
        _syncClock(m['now']);
        obs = ObsState.fromJson(m['state'] as Json?);
        toggles = _toggles(m['toggles']);
        stats = SystemStats.fromJson(m['stats'] as Json?);
        obsSettings = ObsSettings.fromJson(m['obs'] as Json?);
        status = LinkStatus.connected;
        _applyWakelock();
        notifyListeners();
        break;
      case 'authFail':
        error = (m['reason'] ?? 'Authentication failed') as String;
        if (m['needPin'] == true) {
          // Server no longer knows this device (e.g. its settings were reset).
          token = null;
          _prefs.remove('token');
          error = 'This PC no longer recognises the app. Enter the new PIN to pair again.';
        }
        _want = false;
        _persist = false;
        status = LinkStatus.failed;
        _teardown();
        notifyListeners();
        break;
      case 'config':
        _setConfig(m['config'] as Json);
        notifyListeners();
        break;
      case 'state':
        _syncClock(m['now']);
        obs = ObsState.fromJson(m['state'] as Json?);
        toggles = _toggles(m['toggles']);
        notifyListeners();
        break;
      case 'stats':
        _syncClock(m['now']);
        stats = SystemStats.fromJson(m['stats'] as Json?);
        notifyListeners();
        break;
      case 'obsSettings':
        obsSettings = ObsSettings.fromJson(m['obs'] as Json?);
        notifyListeners();
        break;
      case 'obsList':
        _listing?.complete({
          'scenes': List<String>.from(m['scenes'] as List),
          'inputs': List<String>.from(m['inputs'] as List),
        });
        _listing = null;
        break;
      case 'result':
        final rid = m['rid'] as int?;
        final err = m['ok'] == true ? null : (m['error'] ?? 'Failed') as String;
        if (rid == null) {
          _listing?.completeError(err ?? 'Failed');
          _listing = null;
        } else {
          _pending.remove(rid)?.complete(err);
        }
        break;
    }
  }

  Map<String, bool> _toggles(dynamic j) =>
      {for (final e in ((j ?? {}) as Map).entries) e.key as String: e.value == true};

  void _setConfig(Json j) {
    config = DeckConfig.fromJson(j);
    _prefs.setString('config', jsonEncode(j));
  }

  void _send(Json m) {
    try {
      _ch?.sink.add(jsonEncode(m));
    } catch (_) {}
  }

  Future<String?> _request(Json m) {
    if (!connected) return Future.value('Not connected to your PC');
    final rid = ++_rid;
    final c = Completer<String?>();
    _pending[rid] = c;
    _send({...m, 'rid': rid});
    return c.future.timeout(const Duration(seconds: 40), onTimeout: () => 'Timed out');
  }

  /// Returns null on success, or an error message.
  Future<String?> press(DeckButton b) => _request({'t': 'press', 'id': b.id});
  Future<String?> runAction(Json action) => _request({'t': 'run', 'action': action});

  /// Edits a copy of the config, applies it immediately, and syncs it to the PC.
  void updateConfig(void Function(DeckConfig cfg) mutate) {
    final cfg = config?.copy();
    if (cfg == null) return;
    mutate(cfg);
    config = cfg;
    _prefs.setString('config', jsonEncode(cfg.toJson()));
    notifyListeners();
    _send({'t': 'saveConfig', 'config': cfg.toJson()});
  }

  void saveObsSettings({required String host, required int port, String? password}) {
    _send({
      't': 'saveSettings',
      'obs': {'host': host, 'port': port, 'password': ?password},
    });
  }

  Future<Map<String, List<String>>> listObs() {
    if (!connected) return Future.error('Not connected to your PC');
    _listing ??= Completer<Map<String, List<String>>>();
    _send({'t': 'obsList'});
    return _listing!.future.timeout(const Duration(seconds: 10), onTimeout: () {
      _listing = null;
      throw 'OBS did not answer';
    });
  }

  /// Stop connecting/reconnecting (keeps the pairing).
  void stop() {
    _want = false;
    _persist = false;
    _teardown();
    status = LinkStatus.idle;
    _applyWakelock();
    notifyListeners();
  }

  /// Disconnect and forget this PC entirely.
  Future<void> forget() async {
    stop();
    token = null;
    config = null;
    error = null;
    await _prefs.remove('token');
    await _prefs.remove('config');
    notifyListeners();
  }
}

class ConnScope extends InheritedNotifier<DeckConnection> {
  const ConnScope({super.key, required DeckConnection conn, required super.child}) : super(notifier: conn);

  static DeckConnection of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConnScope>()!.notifier!;
}
