'use strict';
// Default multi-screen layout (Stream Deck MK.2 sized: 5 x 3).

let nextId = 0;
const uid = () => `b${Date.now().toString(36)}${(nextId++).toString(36)}`;

function btn(label, icon, color, action, extra = {}) {
  return { id: uid(), label, icon, color, action, ...extra };
}

function defaultConfig() {
  const cols = 5;
  const rows = 3;
  const O = (extra) => ({ type: 'obs', ...extra });
  const hk = (keys) => ({ type: 'hotkey', keys });
  const page = (id, name, icon, list) => {
    const buttons = new Array(cols * rows).fill(null);
    list.forEach((b, i) => (buttons[i] = b));
    return { id, name, icon, pinned: true, buttons };
  };
  // Appearance while the button is "active" (OBS state or a toggle being on).
  const on = (iconOn, labelOn, colorOn) => ({ iconOn, labelOn, colorOn });
  const widget = (label, color, kind) => btn(label, '', color, { type: 'widget', kind });

  const streaming = page('streaming', 'Stream', '🔴', [
    btn('Go Live', '🔴', '#c62828', O({ op: 'toggleStream' }), on('⏹️', 'End Stream', '#8e0000')),
    btn('Record', '⏺️', '#ad1457', O({ op: 'toggleRecord' }), on('⏹️', 'Stop Rec', '#880e4f')),
    widget('Live time', '#37474f', 'streamTimer'),
    btn('Save Replay', '🎞️', '#4527a0', O({ op: 'saveReplay' })),
    btn('Virtual Cam', '📷', '#00695c', O({ op: 'toggleVirtualCam' })),
    btn('Gameplay', '🎮', '#1565c0', O({ op: 'scene', scene: 'Gameplay' })),
    btn('Chatting', '💬', '#00838f', O({ op: 'scene', scene: 'Chatting' })),
    btn('BRB', '☕', '#6a1b9a', O({ op: 'scene', scene: 'BRB' })),
    btn('Starting', '⏳', '#283593', O({ op: 'scene', scene: 'Starting Soon' })),
    btn('Transition', '🔀', '#37474f', O({ op: 'studioTransition' })),
    btn('Mic', '🎙️', '#ef6c00', O({ op: 'toggleMute', input: 'Mic/Aux' }), on('🔇', 'Mic muted', '#b71c1c')),
    btn('Desktop', '🔊', '#f9a825', O({ op: 'toggleMute', input: 'Desktop Audio' }), on('🔇', 'Muted', '#b71c1c')),
    btn('Clip it', '✂️', '#2e7d32', { type: 'text', text: '!clip', enter: true }),
    btn('Screenshot', '📸', '#283593', { type: 'system', op: 'screenshot' }),
    btn('Chat', '💭', '#5d4037', { type: 'open', target: 'https://www.twitch.tv/popout/' }),
  ]);

  // Discord shortcuts must be bound in Discord: Settings > Keybinds.
  const discord = page('discord', 'Discord', '💬', [
    btn('Mute', '🎙️', '#5865f2', { type: 'toggle', on: hk('ctrl+shift+m'), off: hk('ctrl+shift+m') }, on('🔇', 'Muted', '#b71c1c')),
    btn('Deafen', '🎧', '#4752c4', { type: 'toggle', on: hk('ctrl+shift+d'), off: hk('ctrl+shift+d') }, on('🔇', 'Deafened', '#b71c1c')),
    btn('Answer', '📞', '#2e7d32', hk('ctrl+enter')),
    btn('Decline', '📵', '#c62828', hk('esc')),
    btn('Overlay', '🖼️', '#37474f', hk('shift+`')),
    btn('Quick Switch', '🔎', '#455a64', hk('ctrl+k')),
    btn('Prev Server', '⬆️', '#455a64', hk('ctrl+alt+up')),
    btn('Next Server', '⬇️', '#455a64', hk('ctrl+alt+down')),
    btn('Unread', '🔔', '#6a1b9a', hk('alt+shift+down')),
    btn('Discord', '💬', '#5865f2', { type: 'open', target: 'discord://' }),
  ]);

  const desktop = page('desktop', 'Desktop', '🖥️', [
    btn('Show Desktop', '🖥️', '#37474f', { type: 'system', op: 'showDesktop' }),
    btn('Task Manager', '📊', '#455a64', { type: 'system', op: 'taskManager' }),
    btn('Lock PC', '🔒', '#c62828', { type: 'system', op: 'lock' }),
    btn('Screen Off', '🌙', '#283593', { type: 'system', op: 'monitorOff' }),
    btn('Sleep', '😴', '#4527a0', { type: 'system', op: 'sleep' }),
    widget('Clock', '#212121', 'clock'),
    widget('CPU', '#00695c', 'cpu'),
    widget('RAM', '#1565c0', 'ram'),
    btn('Alt-Tab', '↔️', '#455a64', hk('alt+tab')),
    btn('Explorer', '📂', '#f9a825', { type: 'open', target: 'explorer.exe' }),
    btn('Browser', '🌐', '#1565c0', { type: 'open', target: 'https://www.google.com' }),
    btn('Calculator', '🧮', '#546e7a', { type: 'open', target: 'calc.exe' }),
    btn('Notepad', '📝', '#546e7a', { type: 'open', target: 'notepad.exe' }),
    btn('Spotify', '🎵', '#1db954', { type: 'open', target: 'spotify:' }),
    btn('OBS', '🎬', '#263238', { type: 'open', target: 'obs64.exe' }),
  ]);

  const audio = page('audio', 'Audio', '🔊', [
    btn('Vol +', '🔊', '#2e7d32', { type: 'volume', op: 'up', value: 5 }),
    btn('Vol -', '🔉', '#388e3c', { type: 'volume', op: 'down', value: 5 }),
    btn('Mute', '🔈', '#455a64', { type: 'volume', op: 'toggleMute' }, on('🔇', 'Muted', '#b71c1c')),
    widget('Volume', '#00695c', 'volume'),
    btn('Play/Pause', '⏯️', '#1565c0', { type: 'media', key: 'playpause' }),
    btn('Prev', '⏮️', '#1976d2', { type: 'media', key: 'prev' }),
    btn('Next', '⏭️', '#1976d2', { type: 'media', key: 'next' }),
    btn('25%', '🔈', '#37474f', { type: 'volume', op: 'set', value: 25 }),
    btn('50%', '🔉', '#37474f', { type: 'volume', op: 'set', value: 50 }),
    btn('75%', '🔊', '#37474f', { type: 'volume', op: 'set', value: 75 }),
    btn('Fade down', '📉', '#6a1b9a', {
      type: 'multi',
      actions: [
        { type: 'volume', op: 'down', value: 10 },
        { type: 'delay', ms: 300 },
        { type: 'volume', op: 'down', value: 10 },
        { type: 'delay', ms: 300 },
        { type: 'volume', op: 'down', value: 10 },
      ],
    }),
  ]);

  // Set each button's sound file path in the editor (wav/mp3 on the PC).
  const sounds = page('sounds', 'Sounds', '📯', [
    btn('Airhorn', '📯', '#c62828', { type: 'sound', file: '' }),
    btn('Applause', '👏', '#2e7d32', { type: 'sound', file: '' }),
    btn('Sad trombone', '🎺', '#6a1b9a', { type: 'sound', file: '' }),
    btn('Drumroll', '🥁', '#ef6c00', { type: 'sound', file: '' }),
    btn('Ding', '🔔', '#f9a825', { type: 'sound', file: '' }),
  ]);

  return {
    version: 2,
    name: 'DeckPad',
    cols,
    rows,
    rootPage: 'streaming',
    pages: { streaming, discord, desktop, audio, sounds },
  };
}

module.exports = { defaultConfig, uid, btn };
