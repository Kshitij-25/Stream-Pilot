import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';

enum LinkStatus { idle, connecting, connected, reconnecting, failed }

/// Protocol version this app needs from the PC companion (older companions lack features).
const requiredProtocol = 3;

class FoundPc {
  final String name;
  final String host;
  final int port;
  FoundPc(this.name, this.host, this.port);
}

/// Owns the WebSocket link to the PC companion, plus the synced deck config and live state.
class DeckConnection extends ChangeNotifier {
  late final SharedPreferences _prefs;

  LinkStatus status = LinkStatus.idle;
  String? error;
  String host = '';
  int port = 8765;
  String? token;
  String hostName = '';
  int protocol = 0;
  DeckConfig? config;
  ObsState obs = ObsState();
  ObsSettings obsSettings = ObsSettings();
  SystemStats stats = SystemStats();
  Map<String, bool> toggles = {};
  Json integrations = {};
  final List<Json> perfHistory = [];

  // Profiles
  String profileId = '';
  String profileName = '';
  List<Json> profiles = [];
  bool following = true; // follow the PC's active profile (auto-switching) vs. pinned to one
  String? pinnedProfile;

  int _clockOffset = 0; // server ms minus phone ms

  /// 'landscape' | 'portrait' | 'auto'
  String orientation = 'landscape';
  bool haptics = true;
  bool keepAwake = true;
  bool notifications = true;

  final _events = StreamController<Json>.broadcast();
  final _chat = StreamController<Json>.broadcast();
  final _history = StreamController<Json>.broadcast();
  Stream<Json> get eventStream => _events.stream;
  Stream<Json> get chatStream => _chat.stream;
  Stream<Json> get historyStream => _history.stream;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _retryTimer;
  Timer? _pingTimer;
  DateTime _lastRx = DateTime.now();
  bool _want = false;
  bool _persist = false;
  int _attempt = 0;
  int _rid = 0;
  String? _pin;
  final _pending = <int, Completer<String?>>{};
  final _rpc = <int, Completer<dynamic>>{};
  Completer<Map<String, List<String>>>? _listing;

  bool get connected => status == LinkStatus.connected;
  bool get hasSavedServer => host.isNotEmpty && token != null;
  bool get outdatedCompanion => connected && protocol < requiredProtocol;

  String get _deviceName => Platform.isIOS ? 'iPhone / iPad' : 'Android device';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    host = _prefs.getString('host') ?? '';
    port = _prefs.getInt('port') ?? 8765;
    token = _prefs.getString('token');
    haptics = _prefs.getBool('haptics') ?? true;
    keepAwake = _prefs.getBool('keepAwake') ?? true;
    notifications = _prefs.getBool('notifications') ?? true;
    orientation = _prefs.getString('orientation') ?? 'landscape';
    pinnedProfile = _prefs.getString('profile');
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

  // ---------- preferences ----------
  void setHaptics(bool v) {
    haptics = v;
    _prefs.setBool('haptics', v);
    notifyListeners();
  }

  void setNotifications(bool v) {
    notifications = v;
    _prefs.setBool('notifications', v);
    notifyListeners();
  }

  void setOrientation(String v) {
    orientation = v;
    _prefs.setString('orientation', v);
    notifyListeners();
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
        unawaited(WakelockPlus.enable().catchError((_) {}));
      } else {
        unawaited(WakelockPlus.disable().catchError((_) {}));
      }
    } catch (_) {}
  }

  /// Current time on the PC (for timers that must not drift with the phone clock).
  int get serverNow => DateTime.now().millisecondsSinceEpoch + _clockOffset;

  void _syncClock(dynamic now) {
    if (now is num) _clockOffset = now.toInt() - DateTime.now().millisecondsSinceEpoch;
  }

  // ---------- dynamic state ----------
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
        return a['app'] == null && (a['op'] == 'toggleMute' || a['op'] == 'mute') && stats.muted;
      case 'discord':
        if (stats.discord['connected'] != true) return false;
        switch (a['op']) {
          case 'toggleMute':
          case 'mute':
            return stats.discord['mute'] == true;
          case 'toggleDeafen':
          case 'deafen':
            return stats.discord['deaf'] == true;
        }
        return false;
      case 'twitch':
        if (a['op'] == 'chatMode') return ((stats.twitch['modes'] ?? {}) as Map)[a['mode']] == true;
        return false;
    }
    return false;
  }

  // ---------- connecting ----------
  Future<void> connect({required String host, required int port, String? pin}) async {
    if (host != this.host) token = null; // a different PC: the old token is useless for it
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
        'token': ?token,
        'pin': ?_pin,
        'profile': pinnedProfile,
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
    for (final c in _rpc.values) {
      if (!c.isCompleted) c.completeError('Disconnected');
    }
    _rpc.clear();
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
        protocol = (m['protocol'] as num?)?.toInt() ?? 1;
        hostName = (m['host']?['name'] ?? host) as String;
        _applyConfigMessage(m);
        _syncClock(m['now']);
        obs = ObsState.fromJson(m['state'] as Json?);
        toggles = _toggles(m['toggles']);
        stats = SystemStats.fromJson(m['stats'] as Json?);
        integrations = Map<String, dynamic>.from((m['integrations'] ?? {}) as Map);
        obsSettings = ObsSettings.fromJson(m['obs'] as Json?);
        status = LinkStatus.connected;
        _applyWakelock();
        notifyListeners();
        unawaited(rpc('perf.history').then((h) {
          perfHistory
            ..clear()
            ..addAll((h as List).map((e) => Map<String, dynamic>.from(e as Map)));
          notifyListeners();
        }).catchError((_) {}));
        break;
      case 'authFail':
        error = (m['reason'] ?? 'Authentication failed') as String;
        if (m['needPin'] == true) {
          // Server no longer knows this device (e.g. it was revoked or settings were reset).
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
        _applyConfigMessage(m);
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
        perfHistory.add({'t': m['now'], ...Map<String, dynamic>.from(m['stats'] as Map)});
        if (perfHistory.length > 90) perfHistory.removeAt(0);
        notifyListeners();
        break;
      case 'integrations':
        integrations = Map<String, dynamic>.from(m['status'] as Map);
        notifyListeners();
        break;
      case 'notify':
        _events.add(Map<String, dynamic>.from(m['event'] as Map));
        break;
      case 'chat':
        _chat.add(Map<String, dynamic>.from(m['msg'] as Map));
        break;
      case 'history':
        _history.add(Map<String, dynamic>.from(m['entry'] as Map));
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
      case 'rpcResult':
        final c = _rpc.remove(m['rid'] as int?);
        if (c != null) {
          if (m['ok'] == true) {
            c.complete(m['data']);
          } else {
            c.completeError((m['error'] ?? 'Failed') as String);
          }
        }
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

  void _applyConfigMessage(Json m) {
    final j = m['config'] as Json;
    config = DeckConfig.fromJson(j);
    _prefs.setString('config', jsonEncode(j));
    final p = m['profile'] as Map?;
    if (p != null) {
      profileId = p['id'] as String;
      profileName = p['name'] as String;
    }
    profiles = [for (final x in (m['profiles'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    following = m['following'] != false;
  }

  Map<String, bool> _toggles(dynamic j) =>
      {for (final e in ((j ?? {}) as Map).entries) e.key as String: e.value == true};

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

  /// Generic request/response call to the companion. Throws a String message on failure.
  Future<dynamic> rpc(String method, [Json params = const {}]) {
    if (!connected) return Future.error('Not connected to your PC');
    final rid = ++_rid;
    final c = Completer<dynamic>();
    _rpc[rid] = c;
    _send({'t': 'rpc', 'rid': rid, 'method': method, 'params': params});
    return c.future.timeout(const Duration(seconds: 60), onTimeout: () {
      _rpc.remove(rid);
      throw 'Timed out';
    });
  }

  /// [kind] is 'tap', 'long' or 'double'. Returns null on success, or an error message.
  Future<String?> press(DeckButton b, {String kind = 'tap'}) => _request({'t': 'press', 'id': b.id, 'kind': kind});
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

  /// Pin this phone to a profile, or pass null to follow the PC's active profile (auto-switching).
  void selectProfile(String? id) {
    pinnedProfile = id;
    if (id == null) {
      _prefs.remove('profile');
    } else {
      _prefs.setString('profile', id);
    }
    _send({'t': 'selectProfile', 'id': id});
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

  /// Finds companions on the local network (UDP broadcast on port 8766).
  static Future<List<FoundPc>> discover({Duration timeout = const Duration(milliseconds: 1800), int port = 8766}) async {
    final found = <String, FoundPc>{};
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.broadcastEnabled = true;
      sock.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = sock!.receive();
        if (d == null) return;
        try {
          final j = jsonDecode(utf8.decode(d.data)) as Map;
          if (j['app'] != 'deckpad') return;
          final addrs = [for (final a in (j['addresses'] as List? ?? const [])) a as String];
          final h = addrs.contains(d.address.address) || addrs.isEmpty ? d.address.address : addrs.first;
          found['$h:${j['port']}'] = FoundPc((j['name'] ?? h) as String, h, (j['port'] as num).toInt());
        } catch (_) {}
      });
      final msg = utf8.encode('DECKPAD?');
      final targets = <InternetAddress>{InternetAddress('255.255.255.255'), InternetAddress.loopbackIPv4};
      try {
        for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
          for (final a in i.addresses) {
            final p = a.address.split('.');
            if (p.length == 4) targets.add(InternetAddress('${p[0]}.${p[1]}.${p[2]}.255'));
          }
        }
      } catch (_) {}
      for (final t in targets) {
        try {
          sock.send(msg, t, port);
        } catch (_) {}
      }
      await Future.delayed(timeout);
    } catch (_) {
      // discovery is best-effort
    } finally {
      sock?.close();
    }
    return found.values.toList();
  }
}

class ConnScope extends InheritedNotifier<DeckConnection> {
  const ConnScope({super.key, required DeckConnection conn, required super.child}) : super(notifier: conn);

  static DeckConnection of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConnScope>()!.notifier!;
}
