'use strict';
// Starter profiles. Every button uses a vector icon ("mi:<name>"); buttons with an `iconHint`
// get the REAL icon of the app / website resolved by the companion at startup (see appicons.js).

let nextId = 0;
const uid = () => `b${Date.now().toString(36)}${(nextId++).toString(36)}`;

function btn(label, icon, color, action, extra = {}) {
  return { id: uid(), label, icon, color, action, ...extra };
}

const COLS = 5;
const ROWS = 3;

const O = (op, extra = {}) => ({ type: 'obs', op, ...extra });
const hk = (keys) => ({ type: 'hotkey', keys });
const T = (op, extra = {}) => ({ type: 'twitch', op, ...extra });
const Y = (op, extra = {}) => ({ type: 'youtube', op, ...extra });
const D = (op, fallbackKeys) => ({ type: 'discord', op, fallback: fallbackKeys ? hk(fallbackKeys) : undefined });
const on = (iconOn, labelOn, colorOn) => ({ iconOn, labelOn, colorOn });
const widget = (label, color, kind) => btn(label, '', color, { type: 'widget', kind });
const screen = (label, icon, color, name) => btn(label, icon, color, { type: 'screen', screen: name });
const app = (label, icon, color, target, hint) => btn(label, icon, color, { type: 'open', target }, { iconHint: hint });
const site = (label, icon, color, url, domain) => btn(label, icon, color, { type: 'open', target: url }, { iconHint: { site: domain } });

function page(id, name, icon, list) {
  const buttons = new Array(COLS * ROWS).fill(null);
  list.forEach((b, i) => (buttons[i] = b));
  return { id, name, icon, pinned: true, buttons };
}

function streamingPages() {
  const stream = page('stream', 'Stream', 'mi:live', [
    btn('Go Live', 'mi:live', '#c62828', O('toggleStream'), on('mi:stop', 'End Stream', '#8e0000')),
    btn('Record', 'mi:record', '#ad1457', O('toggleRecord'), on('mi:stop', 'Stop Rec', '#880e4f')),
    widget('Live time', '#37474f', 'streamTimer'),
    btn('Save Replay', 'mi:replay', '#4527a0', O('saveReplay')),
    btn('Virtual Cam', 'mi:videocam', '#00695c', O('toggleVirtualCam')),
    btn('Gameplay', 'mi:gamepad', '#1565c0', O('scene', { scene: 'Gameplay' })),
    btn('Chatting', 'mi:chat', '#00838f', O('scene', { scene: 'Chatting' })),
    btn('BRB', 'mi:coffee', '#6a1b9a', O('scene', { scene: 'BRB' })),
    btn('Starting', 'mi:hourglass', '#283593', O('scene', { scene: 'Starting Soon' })),
    btn('Transition', 'mi:swap', '#37474f', O('studioTransition')),
    btn('Mic', 'mi:mic', '#ef6c00', O('toggleMute', { input: 'Mic/Aux' }), on('mi:mic_off', 'Mic muted', '#b71c1c')),
    btn('Desktop', 'mi:volume_up', '#f9a825', O('toggleMute', { input: 'Desktop Audio' }), on('mi:volume_off', 'Muted', '#b71c1c')),
    btn('Marker', 'mi:flag', '#2e7d32', T('marker')),
    btn('Clip', 'mi:cut', '#388e3c', T('clip')),
    screen('Mixer', 'mi:tune', '#455a64', 'mixer'),
  ]);

  const audio = page('audio', 'Audio', 'mi:volume_up', [
    btn('Vol +', 'mi:volume_up', '#2e7d32', { type: 'volume', op: 'up', value: 5 }),
    btn('Vol -', 'mi:volume_down', '#388e3c', { type: 'volume', op: 'down', value: 5 }),
    btn('Mute', 'mi:volume_mute', '#455a64', { type: 'volume', op: 'toggleMute' }, on('mi:volume_off', 'Muted', '#b71c1c')),
    widget('Volume', '#00695c', 'volume'),
    screen('Mixer', 'mi:tune', '#455a64', 'mixer'),
    btn('Play/Pause', 'mi:play_pause', '#1565c0', { type: 'media', key: 'playpause' }),
    btn('Prev', 'mi:skip_prev', '#1976d2', { type: 'media', key: 'prev' }),
    btn('Next', 'mi:skip_next', '#1976d2', { type: 'media', key: 'next' }),
    btn('Spotify +', 'mi:volume_up', '#1db954', { type: 'volume', op: 'up', value: 10, app: 'spotify' }, { iconHint: { app: 'Spotify' } }),
    btn('Spotify -', 'mi:volume_down', '#1db954', { type: 'volume', op: 'down', value: 10, app: 'spotify' }, { iconHint: { app: 'Spotify' } }),
    btn('Discord +', 'mi:volume_up', '#5865f2', { type: 'volume', op: 'up', value: 10, app: 'discord' }, { iconHint: { app: 'Discord' } }),
    btn('Discord -', 'mi:volume_down', '#5865f2', { type: 'volume', op: 'down', value: 10, app: 'discord' }, { iconHint: { app: 'Discord' } }),
    btn('25%', 'mi:volume_mute', '#37474f', { type: 'volume', op: 'set', value: 25 }),
    btn('50%', 'mi:volume_down', '#37474f', { type: 'volume', op: 'set', value: 50 }),
    btn('100%', 'mi:volume_up', '#37474f', { type: 'volume', op: 'set', value: 100 }),
  ]);

  const twitch = page('twitch', 'Twitch', 'mi:forum', [
    widget('Viewers', '#6441a5', 'twitchViewers'),
    widget('Followers', '#6441a5', 'twitchFollowers'),
    btn('Marker', 'mi:flag', '#2e7d32', T('marker')),
    btn('Clip', 'mi:cut', '#388e3c', T('clip')),
    btn('Run Ad', 'mi:campaign', '#ef6c00', T('ad', { length: 60 })),
    btn('Slow', 'mi:hourglass', '#455a64', T('chatMode', { mode: 'slow', state: 'toggle', value: 10 }), on('mi:hourglass', 'Slow ON', '#00897b')),
    btn('Subs only', 'mi:star', '#455a64', T('chatMode', { mode: 'subs', state: 'toggle' }), on('mi:star', 'Subs ON', '#00897b')),
    btn('Emote only', 'mi:emoji', '#455a64', T('chatMode', { mode: 'emote', state: 'toggle' }), on('mi:emoji', 'Emote ON', '#00897b')),
    btn('Followers', 'mi:person', '#455a64', T('chatMode', { mode: 'followers', state: 'toggle', value: 0 }), on('mi:person', 'Fol. ON', '#00897b')),
    btn('Clear chat', 'mi:block', '#c62828', T('clearChat')),
    screen('Chat & Mod', 'mi:gavel', '#6441a5', 'chat'),
    screen('Events', 'mi:notifications', '#6441a5', 'events'),
    btn('Say hi', 'mi:chat', '#37474f', T('say', { text: 'Welcome to the stream!' })),
    btn('Announce', 'mi:campaign', '#37474f', T('announce', { text: 'Remember to follow!', color: 'primary' })),
    btn('Twitch', 'mi:web', '#6441a5', { type: 'open', target: 'https://dashboard.twitch.tv' }, { iconHint: { site: 'twitch.tv' } }),
  ]);

  const youtube = page('youtube', 'YouTube', 'mi:movie', [
    widget('Viewers', '#c62828', 'ytViewers'),
    btn('Go Live', 'mi:live', '#c62828', Y('goLive')),
    btn('End Stream', 'mi:stop', '#8e0000', Y('endStream')),
    screen('Chat & Mod', 'mi:gavel', '#c62828', 'chat'),
    screen('Events', 'mi:notifications', '#c62828', 'events'),
    btn('Say hi', 'mi:chat', '#37474f', Y('say', { text: 'Welcome to the stream!' })),
    site('Studio', 'mi:movie', '#c62828', 'https://studio.youtube.com', 'youtube.com'),
    site('YouTube', 'mi:movie', '#c62828', 'https://www.youtube.com', 'youtube.com'),
  ]);

  const discord = page('discord', 'Discord', 'mi:headset', [
    btn('Mute', 'mi:mic', '#5865f2', D('toggleMute', 'ctrl+shift+m'), on('mi:mic_off', 'Muted', '#b71c1c')),
    btn('Deafen', 'mi:headset', '#4752c4', D('toggleDeafen', 'ctrl+shift+d'), on('mi:headset_off', 'Deafened', '#b71c1c')),
    btn('Leave VC', 'mi:power', '#c62828', D('leave')),
    btn('Answer', 'mi:check', '#2e7d32', hk('ctrl+enter')),
    btn('Decline', 'mi:close', '#c62828', hk('esc')),
    btn('Overlay', 'mi:layers', '#37474f', hk('shift+`')),
    btn('Quick Switch', 'mi:search', '#455a64', hk('ctrl+k')),
    btn('Prev Server', 'mi:remove', '#455a64', hk('ctrl+alt+up')),
    btn('Next Server', 'mi:add', '#455a64', hk('ctrl+alt+down')),
    app('Discord', 'mi:chat', '#5865f2', 'discord://', { app: 'Discord' }),
  ]);

  const desktop = page('desktop', 'Desktop', 'mi:screen', [
    app('Explorer', 'mi:folder', '#f9a825', 'explorer.exe', { exe: 'explorer.exe' }),
    app('Chrome', 'mi:web', '#1565c0', 'chrome.exe', { app: 'Google Chrome' }),
    app('Spotify', 'mi:music', '#1db954', 'spotify:', { app: 'Spotify' }),
    app('OBS', 'mi:videocam', '#263238', 'obs64.exe', { app: 'OBS Studio' }),
    app('Discord', 'mi:chat', '#5865f2', 'discord://', { app: 'Discord' }),
    app('Notepad', 'mi:edit', '#546e7a', 'notepad.exe', { exe: 'notepad.exe' }),
    app('Calculator', 'mi:dashboard', '#546e7a', 'calc.exe', { exe: 'calc.exe' }),
    btn('Task Manager', 'mi:analytics', '#455a64', { type: 'system', op: 'taskManager' }),
    btn('Show Desktop', 'mi:screen', '#37474f', { type: 'system', op: 'showDesktop' }),
    btn('Screenshot', 'mi:photo_camera', '#283593', { type: 'system', op: 'screenshot' }),
    btn('Alt-Tab', 'mi:swap', '#455a64', hk('alt+tab')),
    btn('Lock PC', 'mi:lock', '#c62828', { type: 'system', op: 'lock' }),
    btn('Screen Off', 'mi:moon', '#283593', { type: 'system', op: 'monitorOff' }),
    btn('Sleep', 'mi:sleep', '#4527a0', { type: 'system', op: 'sleep' }),
    btn('Emoji', 'mi:emoji', '#f9a825', hk('win+.')),
  ]);

  const sounds = page('sounds', 'Sounds', 'mi:music', [
    btn('Airhorn', 'mi:campaign', '#c62828', { type: 'sound', file: '' }),
    btn('Applause', 'mi:thumb_up', '#2e7d32', { type: 'sound', file: '' }),
    btn('Sad trombone', 'mi:music', '#6a1b9a', { type: 'sound', file: '' }),
    btn('Drumroll', 'mi:graphic_eq', '#ef6c00', { type: 'sound', file: '' }),
    btn('Ding', 'mi:notifications', '#f9a825', { type: 'sound', file: '' }),
  ]);

  const macros = page('macros', 'Macros', 'mi:bolt', [
    btn('Starting Soon', 'mi:hourglass', '#283593', {
      type: 'multi', repeat: 1,
      actions: [O('scene', { scene: 'Starting Soon' }), O('unmute', { input: 'Mic/Aux' }), O('startStream')],
    }),
    btn('BRB mode', 'mi:coffee', '#6a1b9a', {
      type: 'multi', repeat: 1,
      actions: [O('scene', { scene: 'BRB' }), O('mute', { input: 'Mic/Aux' })],
    }),
    btn('Back', 'mi:check', '#2e7d32', {
      type: 'multi', repeat: 1,
      actions: [O('unmute', { input: 'Mic/Aux' }), O('scene', { scene: 'Gameplay' })],
    }),
    btn('End Stream', 'mi:flag', '#c62828', {
      type: 'multi', repeat: 1,
      actions: [O('scene', { scene: 'Ending' }), { type: 'delay', ms: 15000 }, O('stopStream'), O('toggleRecord')],
    }, { longAction: O('stopStream') }),
    btn('Panic', 'mi:visibility_off', '#212121', {
      type: 'multi', repeat: 1,
      actions: [O('scene', { scene: 'BRB' }), O('mute', { input: 'Mic/Aux' }), O('mute', { input: 'Desktop Audio' })],
    }),
    btn('Scene cycle', 'mi:repeat', '#1565c0', {
      type: 'cycle',
      actions: [O('scene', { scene: 'Gameplay' }), O('scene', { scene: 'Chatting' }), O('scene', { scene: 'BRB' })],
    }),
  ]);

  const monitor = page('monitor', 'Monitor', 'mi:speed', [
    widget('Clock', '#212121', 'clock'),
    widget('CPU', '#00695c', 'cpu'),
    widget('RAM', '#1565c0', 'ram'),
    widget('GPU', '#2e7d32', 'gpu'),
    widget('Net down', '#37474f', 'netDown'),
    widget('Net up', '#37474f', 'netUp'),
    widget('OBS FPS', '#455a64', 'obsFps'),
    widget('Dropped', '#455a64', 'dropped'),
    widget('Bitrate', '#455a64', 'bitrate'),
    widget('Live time', '#37474f', 'streamTimer'),
    widget('Rec time', '#37474f', 'recordTimer'),
    screen('Performance', 'mi:analytics', '#00695c', 'perf'),
    screen('History', 'mi:history', '#455a64', 'history'),
    screen('Automations', 'mi:smart_toy', '#6a1b9a', 'automations'),
    screen('Integrations', 'mi:link', '#37474f', 'integrations'),
  ]);

  return [stream, audio, twitch, youtube, discord, desktop, macros, sounds, monitor];
}

function desktopPages() {
  const p = streamingPages().filter((x) => ['audio', 'desktop', 'sounds', 'monitor', 'discord'].includes(x.id));
  p[0].pinned = true;
  return p;
}

function defaultConfig(kind = 'streaming') {
  const pages = kind === 'desktop' ? desktopPages() : streamingPages();
  return {
    version: 3,
    name: 'DeckPad',
    cols: COLS,
    rows: ROWS,
    rootPage: pages[0].id,
    pages: Object.fromEntries(pages.map((p) => [p.id, p])),
  };
}

module.exports = { defaultConfig, uid, btn };
