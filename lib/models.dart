import 'dart:convert';
import 'package:flutter/painting.dart';

typedef Json = Map<String, dynamic>;

Color parseColor(String? hex, [Color fallback = const Color(0xFF37474F)]) {
  if (hex == null) return fallback;
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'ff$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

String colorToHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

String newId() => 'c${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

class DeckButton {
  String id;
  String label;
  String icon;
  String color;
  Json action;

  DeckButton({
    String? id,
    this.label = '',
    this.icon = '⭐',
    this.color = '#37474f',
    Json? action,
  })  : id = id ?? newId(),
        action = action ?? {'type': 'hotkey', 'keys': ''};

  factory DeckButton.fromJson(Json j) => DeckButton(
        id: j['id'] as String?,
        label: (j['label'] ?? '') as String,
        icon: (j['icon'] ?? '') as String,
        color: (j['color'] ?? '#37474f') as String,
        action: Map<String, dynamic>.from((j['action'] ?? {'type': 'none'}) as Map),
      );

  Json toJson() => {'id': id, 'label': label, 'icon': icon, 'color': color, 'action': action};

  DeckButton copy() => DeckButton.fromJson(jsonDecode(jsonEncode(toJson())) as Json);
}

class DeckPage {
  String id;
  String name;
  List<DeckButton?> buttons;
  DeckPage(this.id, this.name, this.buttons);

  factory DeckPage.fromJson(Json j, int slots) {
    final list = <DeckButton?>[];
    for (final b in (j['buttons'] as List? ?? const [])) {
      list.add(b == null ? null : DeckButton.fromJson(Map<String, dynamic>.from(b as Map)));
    }
    while (list.length < slots) {
      list.add(null);
    }
    return DeckPage(j['id'] as String, (j['name'] ?? j['id']) as String, list.sublist(0, slots));
  }

  Json toJson() => {'id': id, 'name': name, 'buttons': buttons.map((b) => b?.toJson()).toList()};
}

class DeckConfig {
  String name;
  int cols;
  int rows;
  String rootPage;
  Map<String, DeckPage> pages;

  DeckConfig({required this.name, required this.cols, required this.rows, required this.rootPage, required this.pages});

  factory DeckConfig.fromJson(Json j) {
    final cols = (j['cols'] as num?)?.toInt() ?? 4;
    final rows = (j['rows'] as num?)?.toInt() ?? 4;
    final pages = <String, DeckPage>{};
    (j['pages'] as Map).forEach((k, v) {
      pages[k as String] = DeckPage.fromJson(Map<String, dynamic>.from(v as Map), cols * rows);
    });
    return DeckConfig(
      name: (j['name'] ?? 'DeckPad') as String,
      cols: cols,
      rows: rows,
      rootPage: (j['rootPage'] ?? pages.keys.first) as String,
      pages: pages,
    );
  }

  Json toJson() => {
        'version': 1,
        'name': name,
        'cols': cols,
        'rows': rows,
        'rootPage': rootPage,
        'pages': pages.map((k, v) => MapEntry(k, v.toJson())),
      };

  DeckConfig copy() => DeckConfig.fromJson(jsonDecode(jsonEncode(toJson())) as Json);

  /// Re-lays out every page on a new grid, keeping each button at its (row, col) where it still fits.
  void resize(int newCols, int newRows) {
    for (final p in pages.values) {
      final next = List<DeckButton?>.filled(newCols * newRows, null);
      final overflow = <DeckButton>[];
      for (var i = 0; i < p.buttons.length; i++) {
        final b = p.buttons[i];
        if (b == null) continue;
        final r = i ~/ cols, c = i % cols;
        if (r < newRows && c < newCols) {
          next[r * newCols + c] = b;
        } else {
          overflow.add(b);
        }
      }
      // Buttons that fell off the grid fill any free slots rather than vanish.
      for (final b in overflow) {
        final free = next.indexOf(null);
        if (free >= 0) next[free] = b;
      }
      p.buttons = next;
    }
    cols = newCols;
    rows = newRows;
  }

  String addPage(String name) {
    final id = 'p${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    pages[id] = DeckPage(id, name, List<DeckButton?>.filled(cols * rows, null));
    return id;
  }

  void deletePage(String id) {
    if (pages.length <= 1) return;
    pages.remove(id);
    if (rootPage == id) rootPage = pages.keys.first;
    // Folder buttons pointing at the deleted page become inert.
    for (final p in pages.values) {
      for (var i = 0; i < p.buttons.length; i++) {
        final b = p.buttons[i];
        if (b != null && b.action['type'] == 'folder' && b.action['page'] == id) p.buttons[i] = null;
      }
    }
  }
}

class ObsState {
  bool connected = false;
  bool streaming = false;
  bool recording = false;
  String? scene;
  Map<String, bool> muted = {};

  ObsState();
  factory ObsState.fromJson(Json? j) {
    final s = ObsState();
    if (j == null) return s;
    s.connected = j['connected'] == true;
    s.streaming = j['streaming'] == true;
    s.recording = j['recording'] == true;
    s.scene = j['scene'] as String?;
    s.muted = {for (final e in ((j['muted'] ?? {}) as Map).entries) e.key as String: e.value == true};
    return s;
  }
}

class ObsSettings {
  String host;
  int port;
  bool hasPassword;
  ObsSettings({this.host = '127.0.0.1', this.port = 4455, this.hasPassword = false});
  factory ObsSettings.fromJson(Json? j) => j == null
      ? ObsSettings()
      : ObsSettings(
          host: (j['host'] ?? '127.0.0.1') as String,
          port: (j['port'] as num?)?.toInt() ?? 4455,
          hasPassword: j['hasPassword'] == true,
        );
}

// ---- Action metadata ------------------------------------------------------

class ActionKind {
  final String type;
  final String label;
  final String hint;
  const ActionKind(this.type, this.label, this.hint);
}

const actionKinds = <ActionKind>[
  ActionKind('hotkey', 'Hotkey', 'Press a key combination'),
  ActionKind('text', 'Type text', 'Type a message into the focused window'),
  ActionKind('open', 'Open app / link', 'Launch a program, file or URL'),
  ActionKind('obs', 'OBS', 'Scenes, stream, record, mute'),
  ActionKind('media', 'Media key', 'Play/pause, volume, next track'),
  ActionKind('multi', 'Multi-action', 'Run several actions in order'),
  ActionKind('command', 'Shell command', 'Run a command on the PC'),
  ActionKind('http', 'Web request', 'Call a webhook or API'),
  ActionKind('folder', 'Folder', 'Open another page of buttons'),
  ActionKind('back', 'Back', 'Return to the previous page'),
  ActionKind('home', 'Home', 'Jump to the first page'),
];

const mediaKeys = {
  'playpause': 'Play / Pause',
  'next': 'Next track',
  'prev': 'Previous track',
  'stop': 'Stop',
  'volup': 'Volume up',
  'voldown': 'Volume down',
  'mute': 'Mute PC audio',
};

const obsOps = {
  'scene': 'Switch scene',
  'toggleStream': 'Toggle stream',
  'startStream': 'Start stream',
  'stopStream': 'Stop stream',
  'toggleRecord': 'Toggle recording',
  'toggleMute': 'Toggle mute (audio input)',
  'mute': 'Mute input',
  'unmute': 'Unmute input',
  'toggleSource': 'Show / hide source',
  'saveReplay': 'Save replay buffer',
};

String describeAction(Json a) {
  switch (a['type']) {
    case 'hotkey':
      return 'Hotkey ${a['keys'] ?? ''}';
    case 'text':
      return 'Type "${a['text'] ?? ''}"';
    case 'open':
      return 'Open ${a['target'] ?? ''}';
    case 'command':
      return 'Run ${a['command'] ?? ''}';
    case 'media':
      return mediaKeys[a['key']] ?? 'Media';
    case 'http':
      return '${a['method'] ?? 'GET'} ${a['url'] ?? ''}';
    case 'obs':
      return 'OBS: ${obsOps[a['op']] ?? a['op']}${a['scene'] != null && a['op'] == 'scene' ? ' → ${a['scene']}' : ''}';
    case 'multi':
      return 'Macro (${(a['actions'] as List?)?.length ?? 0} steps)';
    case 'delay':
      return 'Wait ${a['ms'] ?? 0} ms';
    case 'folder':
      return 'Folder';
    case 'back':
      return 'Back';
    case 'home':
      return 'Home';
    default:
      return 'No action';
  }
}

Json defaultAction(String type) {
  switch (type) {
    case 'hotkey':
      return {'type': 'hotkey', 'keys': ''};
    case 'text':
      return {'type': 'text', 'text': '', 'enter': false};
    case 'open':
      return {'type': 'open', 'target': ''};
    case 'command':
      return {'type': 'command', 'command': ''};
    case 'media':
      return {'type': 'media', 'key': 'playpause'};
    case 'http':
      return {'type': 'http', 'method': 'GET', 'url': ''};
    case 'obs':
      return {'type': 'obs', 'op': 'toggleStream'};
    case 'multi':
      return {'type': 'multi', 'actions': <Json>[]};
    case 'delay':
      return {'type': 'delay', 'ms': 500};
    case 'folder':
      return {'type': 'folder', 'page': ''};
    default:
      return {'type': type};
  }
}
