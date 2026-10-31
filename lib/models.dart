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
  String icon; // emoji / short text, or "mi:<name>" for a built-in Material icon
  String? image; // base64 PNG of a custom picture; overrides [icon]
  String color;
  Json action;

  // Appearance while the button is "active" (OBS state, toggle on, muted ...).
  String? iconOn;
  String? labelOn;
  String? colorOn;

  DeckButton({
    String? id,
    this.label = '',
    this.icon = '⭐',
    this.image,
    this.color = '#37474f',
    this.iconOn,
    this.labelOn,
    this.colorOn,
    Json? action,
  })  : id = id ?? newId(),
        action = action ?? {'type': 'hotkey', 'keys': ''};

  factory DeckButton.fromJson(Json j) => DeckButton(
        id: j['id'] as String?,
        label: (j['label'] ?? '') as String,
        icon: (j['icon'] ?? '') as String,
        image: j['image'] as String?,
        color: (j['color'] ?? '#37474f') as String,
        iconOn: j['iconOn'] as String?,
        labelOn: j['labelOn'] as String?,
        colorOn: j['colorOn'] as String?,
        action: Map<String, dynamic>.from((j['action'] ?? {'type': 'none'}) as Map),
      );

  Json toJson() => {
        'id': id,
        'label': label,
        'icon': icon,
        'image': ?image,
        'color': color,
        'iconOn': ?iconOn,
        'labelOn': ?labelOn,
        'colorOn': ?colorOn,
        'action': action,
      };

  DeckButton copy() => DeckButton.fromJson(jsonDecode(jsonEncode(toJson())) as Json);

  bool get hasActiveLook => (iconOn ?? '').isNotEmpty || (labelOn ?? '').isNotEmpty || (colorOn ?? '').isNotEmpty;
}

class DeckPage {
  String id;
  String name;
  String icon;
  bool pinned; // shown in the screen switcher (rail / tab bar)
  List<DeckButton?> buttons;
  DeckPage(this.id, this.name, this.buttons, {this.icon = '', this.pinned = false});

  factory DeckPage.fromJson(Json j, int slots) {
    final list = <DeckButton?>[];
    for (final b in (j['buttons'] as List? ?? const [])) {
      list.add(b == null ? null : DeckButton.fromJson(Map<String, dynamic>.from(b as Map)));
    }
    while (list.length < slots) {
      list.add(null);
    }
    return DeckPage(
      j['id'] as String,
      (j['name'] ?? j['id']) as String,
      list.sublist(0, slots),
      icon: (j['icon'] ?? '') as String,
      pinned: j['pinned'] == true,
    );
  }

  Json toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'pinned': pinned,
        'buttons': buttons.map((b) => b?.toJson()).toList(),
      };
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

  String addPage(String name, {String icon = '', bool pinned = false}) {
    final id = 'p${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    pages[id] = DeckPage(id, name, List<DeckButton?>.filled(cols * rows, null), icon: icon, pinned: pinned);
    return id;
  }

  /// Pages shown in the screen switcher; always at least the start page.
  List<DeckPage> get screens {
    final list = pages.values.where((p) => p.pinned).toList();
    return list.isEmpty ? [pages[rootPage] ?? pages.values.first] : list;
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
  int? streamStart; // server epoch ms
  int? recordStart;

  ObsState();
  factory ObsState.fromJson(Json? j) {
    final s = ObsState();
    if (j == null) return s;
    s.connected = j['connected'] == true;
    s.streaming = j['streaming'] == true;
    s.recording = j['recording'] == true;
    s.scene = j['scene'] as String?;
    s.streamStart = (j['streamStart'] as num?)?.toInt();
    s.recordStart = (j['recordStart'] as num?)?.toInt();
    s.muted = {for (final e in ((j['muted'] ?? {}) as Map).entries) e.key as String: e.value == true};
    return s;
  }
}

class SystemStats {
  int cpu = 0;
  int mem = 0;
  int? vol;
  bool muted = false;
  SystemStats();
  factory SystemStats.fromJson(Json? j) {
    final s = SystemStats();
    if (j == null) return s;
    s.cpu = (j['cpu'] as num?)?.toInt() ?? 0;
    s.mem = (j['mem'] as num?)?.toInt() ?? 0;
    s.vol = (j['vol'] as num?)?.toInt();
    s.muted = j['muted'] == true;
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
  ActionKind('multi', 'Macro', 'Run several actions in order (can repeat)'),
  ActionKind('toggle', 'Toggle', 'Two states: alternates ON / OFF actions'),
  ActionKind('cycle', 'Cycle', 'Each press runs the next action in the list'),
  ActionKind('volume', 'PC volume', 'Set, raise, lower or mute system volume'),
  ActionKind('sound', 'Play sound', 'Play an audio file on the PC (soundboard)'),
  ActionKind('system', 'System', 'Lock, sleep, screenshot, task manager…'),
  ActionKind('widget', 'Live widget', 'Clock, CPU, RAM, volume, stream timer'),
  ActionKind('command', 'Shell command', 'Run a command on the PC'),
  ActionKind('http', 'Web request', 'Call a webhook or API'),
  ActionKind('folder', 'Folder', 'Open another page of buttons'),
  ActionKind('back', 'Back', 'Return to the previous page'),
  ActionKind('home', 'Home', 'Jump to the first page'),
];

/// Kinds that can't be used as a step inside a macro/toggle/cycle.
const notNestable = {'multi', 'folder', 'back', 'home', 'toggle', 'cycle', 'widget'};

const widgetKinds = {
  'clock': 'Clock',
  'date': 'Date',
  'cpu': 'CPU usage',
  'ram': 'RAM usage',
  'volume': 'PC volume',
  'streamTimer': 'Stream timer',
  'recordTimer': 'Recording timer',
};

const volumeOps = {
  'up': 'Volume up',
  'down': 'Volume down',
  'set': 'Set volume to…',
  'toggleMute': 'Toggle mute',
  'mute': 'Mute',
  'unmute': 'Unmute',
};

const systemOps = {
  'showDesktop': 'Show desktop',
  'screenshot': 'Screenshot (snip)',
  'taskManager': 'Task manager',
  'lock': 'Lock PC',
  'sleep': 'Sleep',
  'monitorOff': 'Turn screen off',
  'emptyRecycleBin': 'Empty recycle bin',
};

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
  'toggleFilter': 'Toggle source filter',
  'setVolume': 'Set input volume (dB)',
  'saveReplay': 'Save replay buffer',
  'toggleReplayBuffer': 'Start / stop replay buffer',
  'toggleVirtualCam': 'Toggle virtual camera',
  'pauseRecord': 'Pause / resume recording',
  'toggleStudioMode': 'Toggle studio mode',
  'studioTransition': 'Studio-mode transition',
  'hotkey': 'Trigger OBS hotkey by name',
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
      final r = int.tryParse('${a['repeat'] ?? 1}') ?? 1;
      return 'Macro (${(a['actions'] as List?)?.length ?? 0} steps${r > 1 ? ' ×$r' : ''})';
    case 'toggle':
      return 'Toggle: ${describeAction(Map<String, dynamic>.from((a['on'] ?? {'type': 'none'}) as Map))}';
    case 'cycle':
      return 'Cycle (${(a['actions'] as List?)?.length ?? 0} steps)';
    case 'volume':
      return '${volumeOps[a['op']] ?? 'Volume'}${a['op'] == 'set' || a['op'] == 'up' || a['op'] == 'down' ? ' ${a['value'] ?? ''}' : ''}';
    case 'sound':
      return 'Play ${a['file'] ?? ''}';
    case 'system':
      return systemOps[a['op']] ?? 'System';
    case 'widget':
      return 'Widget: ${widgetKinds[a['kind']] ?? a['kind']}';
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
      return {'type': 'multi', 'repeat': 1, 'actions': <Json>[]};
    case 'toggle':
      return {
        'type': 'toggle',
        'on': {'type': 'hotkey', 'keys': ''},
        'off': {'type': 'hotkey', 'keys': ''},
      };
    case 'cycle':
      return {'type': 'cycle', 'actions': <Json>[]};
    case 'volume':
      return {'type': 'volume', 'op': 'up', 'value': 5};
    case 'sound':
      return {'type': 'sound', 'file': ''};
    case 'system':
      return {'type': 'system', 'op': 'showDesktop'};
    case 'widget':
      return {'type': 'widget', 'kind': 'clock'};
    case 'delay':
      return {'type': 'delay', 'ms': 500};
    case 'folder':
      return {'type': 'folder', 'page': ''};
    default:
      return {'type': type};
  }
}
