import 'models.dart';

class Preset {
  final String category;
  final String label;
  final String icon;
  final String color;
  final Json action;
  final String? iconOn;
  final String? labelOn;
  final String? colorOn;
  const Preset(this.category, this.label, this.icon, this.color, this.action, {this.iconOn, this.labelOn, this.colorOn});

  DeckButton toButton() => DeckButton(
        label: label,
        icon: icon,
        color: color,
        iconOn: iconOn,
        labelOn: labelOn,
        colorOn: colorOn,
        // Deep copy: presets are const-like and must never be mutated by the editor.
        action: _clone(action),
      );
}

Json _clone(Json j) => {
      for (final e in j.entries)
        e.key: e.value is Map
            ? _clone(Map<String, dynamic>.from(e.value as Map))
            : e.value is List
                ? [for (final x in e.value as List) x is Map ? _clone(Map<String, dynamic>.from(x)) : x]
                : e.value,
    };

Json _obs(String op, [Json extra = const {}]) => {'type': 'obs', 'op': op, ...extra};
Json _hk(String keys) => {'type': 'hotkey', 'keys': keys};

final presetCategories = <String>['Streaming', 'Macros', 'Discord', 'Audio', 'Desktop', 'Editing', 'Widgets'];

final presets = <Preset>[
  // ---- Streaming
  Preset('Streaming', 'Go Live', '🔴', '#c62828', _obs('toggleStream'), iconOn: '⏹️', labelOn: 'End Stream', colorOn: '#8e0000'),
  Preset('Streaming', 'Record', '⏺️', '#ad1457', _obs('toggleRecord'), iconOn: '⏹️', labelOn: 'Stop Rec', colorOn: '#880e4f'),
  Preset('Streaming', 'Pause Rec', '⏸️', '#6a1b9a', _obs('pauseRecord')),
  Preset('Streaming', 'Save Replay', '🎞️', '#4527a0', _obs('saveReplay')),
  Preset('Streaming', 'Replay Buffer', '🔁', '#4527a0', _obs('toggleReplayBuffer')),
  Preset('Streaming', 'Virtual Cam', '📷', '#00695c', _obs('toggleVirtualCam')),
  Preset('Streaming', 'Studio Mode', '🎛️', '#37474f', _obs('toggleStudioMode')),
  Preset('Streaming', 'Transition', '🔀', '#37474f', _obs('studioTransition')),
  Preset('Streaming', 'Scene', '🎮', '#1565c0', _obs('scene', {'scene': 'Scene'})),
  Preset('Streaming', 'Mic', '🎙️', '#ef6c00', _obs('toggleMute', {'input': 'Mic/Aux'}), iconOn: '🔇', labelOn: 'Mic muted', colorOn: '#b71c1c'),
  Preset('Streaming', 'Desktop Audio', '🔊', '#f9a825', _obs('toggleMute', {'input': 'Desktop Audio'}), iconOn: '🔇', labelOn: 'Muted', colorOn: '#b71c1c'),
  Preset('Streaming', 'Source on/off', '👁️', '#00838f', _obs('toggleSource', {'source': 'Webcam'})),
  Preset('Streaming', 'Filter on/off', '🪄', '#00838f', _obs('toggleFilter', {'source': 'Webcam', 'filter': 'Color Correction'})),
  Preset('Streaming', 'Clip it', '✂️', '#2e7d32', {'type': 'text', 'text': '!clip', 'enter': true}),

  // ---- Macros
  Preset('Macros', 'Starting Soon', '⏳', '#283593', {
    'type': 'multi',
    'repeat': 1,
    'actions': [
      _obs('scene', {'scene': 'Starting Soon'}),
      _obs('unmute', {'input': 'Mic/Aux'}),
      _obs('startStream'),
    ],
  }),
  Preset('Macros', 'BRB mode', '☕', '#6a1b9a', {
    'type': 'multi',
    'repeat': 1,
    'actions': [
      _obs('scene', {'scene': 'BRB'}),
      _obs('mute', {'input': 'Mic/Aux'}),
      {'type': 'text', 'text': 'Be right back!', 'enter': true},
    ],
  }),
  Preset('Macros', 'Back from BRB', '👋', '#2e7d32', {
    'type': 'multi',
    'repeat': 1,
    'actions': [
      _obs('unmute', {'input': 'Mic/Aux'}),
      _obs('scene', {'scene': 'Gameplay'}),
      {'type': 'text', 'text': 'I am back!', 'enter': true},
    ],
  }),
  Preset('Macros', 'End Stream', '🏁', '#c62828', {
    'type': 'multi',
    'repeat': 1,
    'actions': [
      _obs('scene', {'scene': 'Ending'}),
      {'type': 'text', 'text': 'Thanks for watching, see you next time!', 'enter': true},
      {'type': 'delay', 'ms': 15000},
      _obs('stopStream'),
      _obs('toggleRecord'),
    ],
  }),
  Preset('Macros', 'Panic / Privacy', '🙈', '#212121', {
    'type': 'multi',
    'repeat': 1,
    'actions': [
      _obs('scene', {'scene': 'BRB'}),
      _obs('mute', {'input': 'Mic/Aux'}),
      _obs('mute', {'input': 'Desktop Audio'}),
    ],
  }),
  Preset('Macros', 'Scene cycle', '🔄', '#1565c0', {
    'type': 'cycle',
    'actions': [
      _obs('scene', {'scene': 'Gameplay'}),
      _obs('scene', {'scene': 'Chatting'}),
      _obs('scene', {'scene': 'BRB'}),
    ],
  }),
  Preset('Macros', 'Cam toggle', '📹', '#00838f', {
    'type': 'toggle',
    'on': _obs('toggleSource', {'source': 'Webcam'}),
    'off': _obs('toggleSource', {'source': 'Webcam'}),
  }, iconOn: '📹', labelOn: 'Cam ON', colorOn: '#00bfa5'),
  Preset('Macros', 'Spam ×5', '💥', '#ef6c00', {
    'type': 'multi',
    'repeat': 5,
    'actions': [
      {'type': 'text', 'text': 'PogChamp', 'enter': true},
      {'type': 'delay', 'ms': 1500},
    ],
  }),
  Preset('Macros', 'Webhook', '🌐', '#455a64', {'type': 'http', 'method': 'POST', 'url': 'https://', 'body': '{}'}),

  // ---- Discord (bind these in Discord > Settings > Keybinds)
  Preset('Discord', 'Mute', '🎙️', '#5865f2', {'type': 'toggle', 'on': _hk('ctrl+shift+m'), 'off': _hk('ctrl+shift+m')},
      iconOn: '🔇', labelOn: 'Muted', colorOn: '#b71c1c'),
  Preset('Discord', 'Deafen', '🎧', '#4752c4', {'type': 'toggle', 'on': _hk('ctrl+shift+d'), 'off': _hk('ctrl+shift+d')},
      iconOn: '🔇', labelOn: 'Deafened', colorOn: '#b71c1c'),
  Preset('Discord', 'Answer call', '📞', '#2e7d32', _hk('ctrl+enter')),
  Preset('Discord', 'Decline call', '📵', '#c62828', _hk('esc')),
  Preset('Discord', 'Overlay', '🖼️', '#37474f', _hk('shift+`')),
  Preset('Discord', 'Quick switcher', '🔎', '#455a64', _hk('ctrl+k')),
  Preset('Discord', 'Prev server', '⬆️', '#455a64', _hk('ctrl+alt+up')),
  Preset('Discord', 'Next server', '⬇️', '#455a64', _hk('ctrl+alt+down')),
  Preset('Discord', 'Launch', '💬', '#5865f2', {'type': 'open', 'target': 'discord://'}),

  // ---- Audio
  Preset('Audio', 'Vol +', '🔊', '#2e7d32', {'type': 'volume', 'op': 'up', 'value': 5}),
  Preset('Audio', 'Vol −', '🔉', '#388e3c', {'type': 'volume', 'op': 'down', 'value': 5}),
  Preset('Audio', 'Mute PC', '🔈', '#455a64', {'type': 'volume', 'op': 'toggleMute'}, iconOn: '🔇', labelOn: 'Muted', colorOn: '#b71c1c'),
  Preset('Audio', 'Volume 25%', '🔈', '#37474f', {'type': 'volume', 'op': 'set', 'value': 25}),
  Preset('Audio', 'Volume 50%', '🔉', '#37474f', {'type': 'volume', 'op': 'set', 'value': 50}),
  Preset('Audio', 'Volume 100%', '🔊', '#37474f', {'type': 'volume', 'op': 'set', 'value': 100}),
  Preset('Audio', 'Play / Pause', '⏯️', '#1565c0', {'type': 'media', 'key': 'playpause'}),
  Preset('Audio', 'Next track', '⏭️', '#1976d2', {'type': 'media', 'key': 'next'}),
  Preset('Audio', 'Prev track', '⏮️', '#1976d2', {'type': 'media', 'key': 'prev'}),
  Preset('Audio', 'Sound clip', '📯', '#c62828', {'type': 'sound', 'file': ''}),
  Preset('Audio', 'Fade out', '📉', '#6a1b9a', {
    'type': 'multi',
    'repeat': 5,
    'actions': [
      {'type': 'volume', 'op': 'down', 'value': 5},
      {'type': 'delay', 'ms': 250},
    ],
  }),

  // ---- Desktop
  Preset('Desktop', 'Show desktop', '🖥️', '#37474f', {'type': 'system', 'op': 'showDesktop'}),
  Preset('Desktop', 'Task manager', '📊', '#455a64', {'type': 'system', 'op': 'taskManager'}),
  Preset('Desktop', 'Lock PC', '🔒', '#c62828', {'type': 'system', 'op': 'lock'}),
  Preset('Desktop', 'Screen off', '🌙', '#283593', {'type': 'system', 'op': 'monitorOff'}),
  Preset('Desktop', 'Sleep', '😴', '#4527a0', {'type': 'system', 'op': 'sleep'}),
  Preset('Desktop', 'Screenshot', '📸', '#283593', {'type': 'system', 'op': 'screenshot'}),
  Preset('Desktop', 'Alt-Tab', '↔️', '#455a64', _hk('alt+tab')),
  Preset('Desktop', 'Open app', '🚀', '#1565c0', {'type': 'open', 'target': ''}),
  Preset('Desktop', 'Open website', '🌐', '#00838f', {'type': 'open', 'target': 'https://'}),
  Preset('Desktop', 'Folder', '📁', '#37474f', {'type': 'folder', 'page': ''}),

  // ---- Editing
  Preset('Editing', 'Copy', '📄', '#455a64', _hk('ctrl+c')),
  Preset('Editing', 'Paste', '📋', '#455a64', _hk('ctrl+v')),
  Preset('Editing', 'Cut', '✂️', '#455a64', _hk('ctrl+x')),
  Preset('Editing', 'Undo', '↩️', '#546e7a', _hk('ctrl+z')),
  Preset('Editing', 'Redo', '↪️', '#546e7a', _hk('ctrl+y')),
  Preset('Editing', 'Save', '💾', '#2e7d32', _hk('ctrl+s')),
  Preset('Editing', 'Select all', '🔲', '#546e7a', _hk('ctrl+a')),
  Preset('Editing', 'Emoji panel', '😀', '#f9a825', _hk('win+.')),
  Preset('Editing', 'Clipboard', '📎', '#00838f', _hk('win+v')),

  // ---- Widgets
  Preset('Widgets', 'Clock', '', '#212121', {'type': 'widget', 'kind': 'clock'}),
  Preset('Widgets', 'Date', '', '#212121', {'type': 'widget', 'kind': 'date'}),
  Preset('Widgets', 'CPU', '', '#00695c', {'type': 'widget', 'kind': 'cpu'}),
  Preset('Widgets', 'RAM', '', '#1565c0', {'type': 'widget', 'kind': 'ram'}),
  Preset('Widgets', 'Volume', '', '#00695c', {'type': 'widget', 'kind': 'volume'}),
  Preset('Widgets', 'Stream timer', '', '#37474f', {'type': 'widget', 'kind': 'streamTimer'}),
  Preset('Widgets', 'Record timer', '', '#37474f', {'type': 'widget', 'kind': 'recordTimer'}),
];
