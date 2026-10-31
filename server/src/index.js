'use strict';
const http = require('http');
const os = require('os');
const crypto = require('crypto');
const WebSocket = require('ws');
const qrcode = require('qrcode-terminal');

const { Store } = require('./store');
const { createInput } = require('./input');
const { ObsClient } = require('./obs');
const { run } = require('./actions');
const { bus, history, events, addHistory, describe } = require('./core');
const { Mixer } = require('./mixer');
const { Perf } = require('./perf');
const { Automations } = require('./automations');
const { TwitchService } = require('./twitch');
const { YouTubeService } = require('./youtube');
const { DiscordService } = require('./discord');
const { startDiscovery, lanAddresses } = require('./discovery');
const icons = require('./appicons');

const PORT = parseInt(process.env.DECKPAD_PORT, 10) || 8765;
const PROTOCOL = 3; // bumped whenever the app needs a newer companion

const store = new Store();
const input = createInput();
const obs = new ObsClient(() => store.settings.obs);
const mixer = new Mixer();
const perf = new Perf(obs);
const twitch = new TwitchService(store);
const youtube = new YouTubeService(store);
const discord = new DiscordService(store);

const ctx = {
  input, obs, mixer, twitch, youtube, discord,
  state: { toggles: {}, cycles: {} },
  changed: () => pushState(),
  switchProfile: (ref) => switchProfile(ref),
};
const makeCtx = (extra = {}) => ({ ...ctx, ...extra });
const automations = new Automations({ store, makeCtx, run });

// Pairing PIN: new each launch, rotated after every successful pairing.
const newPin = () => String(crypto.randomInt(0, 1000000)).padStart(6, '0');
let pin = newPin();
const failures = new Map(); // ip -> { count, until }

function printPairing() {
  const ips = lanAddresses();
  const host = ips[0] || '127.0.0.1';
  console.log('\n==============  DeckPad companion  ==============');
  console.log(`Listening on: ${ips.map((ip) => `${ip}:${PORT}`).join(', ') || `localhost:${PORT}`}`);
  console.log(`Pairing PIN : ${pin}`);
  console.log('Scan this QR in the app, or tap "Find PCs on Wi-Fi" and enter the PIN:\n');
  qrcode.generate(`deckpad://${host}:${PORT}?pin=${pin}`, { small: true }, (q) => console.log(q));
  if (store.migratedFrom) {
    console.log(`Note: your old v${store.migratedFrom} layout was backed up (config.v${store.migratedFrom}.bak.json) and replaced by the new profiles.`);
  }
  console.log('Same Wi-Fi network required. Allow Node through the Windows firewall on Private networks.\n');
}

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ app: 'deckpad', name: os.hostname(), protocol: PROTOCOL }));
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocket.Server({ server, maxPayload: 32 * 1024 * 1024 });

const send = (ws, msg) => ws.readyState === WebSocket.OPEN && ws.send(JSON.stringify(msg));
const authed = () => [...wss.clients].filter((c) => c.authed);
const broadcast = (msg) => authed().forEach((c) => send(c, msg));

// ---------- state pushed to phones ----------
function integrationsStatus() {
  return { twitch: twitch.status(), youtube: youtube.status(), discord: discord.status() };
}

function obsPublic() {
  const { host, port, password } = store.settings.obs;
  return { host, port, hasPassword: !!password };
}

function statsPayload() {
  const p = perf.last;
  const t = twitch.status();
  const y = youtube.status();
  const d = discord.status();
  return {
    cpu: p.cpu, mem: p.mem, gpu: p.gpu, netDown: p.netDown, netUp: p.netUp,
    obsFps: p.obsFps, dropped: p.dropped, bitrate: p.bitrate,
    vol: input.audio ? input.audio.volume : null,
    muted: input.audio ? input.audio.muted : false,
    twitch: { live: t.live, viewers: t.viewers, followers: t.followers, modes: t.modes },
    youtube: { live: y.live, viewers: y.viewers },
    discord: { connected: d.connected, mute: d.mute, deaf: d.deaf },
  };
}

function pushState() {
  broadcast({ t: 'state', state: obs.state, toggles: ctx.state.toggles, now: Date.now() });
}

function configMessage(ws) {
  const p = store.profile(ws.profileId);
  return {
    t: 'config',
    config: p.config,
    profile: { id: p.id, name: p.name },
    profiles: store.listProfiles(),
    following: ws.follow,
  };
}

function broadcastConfig(profileId) {
  for (const c of authed()) if (c.profileId === profileId) send(c, configMessage(c));
}

function broadcastProfiles() {
  for (const c of authed()) send(c, configMessage(c));
}

/** Switches the PC-wide active profile; phones that follow the PC move with it. */
function switchProfile(ref) {
  const p = store.resolveProfile(ref);
  if (!p) throw new Error(`No profile "${ref}"`);
  store.setActiveProfile(p.id);
  for (const c of authed()) {
    if (c.follow) {
      c.profileId = p.id;
      send(c, configMessage(c));
    }
  }
}

obs.on('state', (state) => {
  const prev = obs.prev || {};
  obs.prev = { ...state };
  if (state.streaming !== prev.streaming && prev.streaming !== undefined) bus.emit('event', { type: state.streaming ? 'obs.streamStarted' : 'obs.streamStopped' });
  if (state.recording !== prev.recording && prev.recording !== undefined) bus.emit('event', { type: state.recording ? 'obs.recordStarted' : 'obs.recordStopped' });
  if (state.scene !== prev.scene && state.scene) bus.emit('event', { type: 'obs.scene', scene: state.scene });
  if (state.connected && !prev.connected) bus.emit('event', { type: 'obs.connected' });
  pushState();
});

twitch.on('status', () => broadcast({ t: 'integrations', status: integrationsStatus() }));
youtube.on('status', () => broadcast({ t: 'integrations', status: integrationsStatus() }));
discord.on('status', () => broadcast({ t: 'integrations', status: integrationsStatus() }));
for (const svc of [twitch, youtube]) {
  svc.on('chat', (msg) => authed().filter((c) => c.chatSub).forEach((c) => send(c, { t: 'chat', msg })));
}
bus.on('notify', (event) => broadcast({ t: 'notify', event }));
bus.on('history', (entry) => authed().filter((c) => c.historySub).forEach((c) => send(c, { t: 'history', entry })));

// ---------- mixer ----------
const OBS_AUDIO_KINDS = /wasapi|audio|pulse|alsa|coreaudio|browser|ffmpeg|vlc|media/i;

async function mixerState() {
  const out = { master: { volume: input.audio ? input.audio.volume : null, muted: input.audio ? input.audio.muted : false }, apps: [], obs: [] };
  input.query();
  try { out.apps = await mixer.apps(); } catch (e) { out.appsError = e.message; }
  if (obs.ready) {
    try {
      const list = (await obs.request('GetInputList')).inputs || [];
      const wanted = list.filter((i) => OBS_AUDIO_KINDS.test(i.inputKind || '')).slice(0, 24);
      out.obs = (await Promise.all(wanted.map(async (i) => {
        try {
          const [v, m] = await Promise.all([obs.request('GetInputVolume', { inputName: i.inputName }), obs.request('GetInputMute', { inputName: i.inputName })]);
          return { name: i.inputName, volume: v.inputVolumeMul, db: v.inputVolumeDb, muted: m.inputMuted };
        } catch {
          return null;
        }
      }))).filter(Boolean);
    } catch (e) { out.obsError = e.message; }
  } else {
    out.obsError = 'OBS is not connected';
  }
  return out;
}

async function mixerSet(p) {
  switch (p.target) {
    case 'master':
      if (p.volume !== undefined) input.setVolume(p.volume);
      if (p.muted !== undefined) input.setMute(!!p.muted);
      return;
    case 'app':
      if (p.volume !== undefined) await mixer.setVolume(p.name, p.volume);
      if (p.muted !== undefined) await mixer.setMute(p.name, !!p.muted);
      return;
    case 'obs':
      if (p.volume !== undefined) await obs.request('SetInputVolume', { inputName: p.name, inputVolumeMul: Math.max(0, Math.min(20, Number(p.volume))) });
      if (p.muted !== undefined) await obs.request('SetInputMute', { inputName: p.name, inputMuted: !!p.muted });
      return;
    default:
      throw new Error('Unknown mixer target');
  }
}

// ---------- RPC ----------
function service(name) {
  const s = { twitch, youtube, discord }[name];
  if (!s) throw new Error('Unknown service');
  return s;
}

const rpc = {
  listApps: () => icons.listApps(),
  appIcon: ({ path }) => icons.iconForPath(path),
  siteIcon: ({ domain }) => icons.faviconFor(domain),
  history: () => ({ history, events }),
  'profiles.create': ({ name, from }) => {
    const p = from ? store.duplicateProfile(from, name) : store.createProfile(name, require('./defaults').defaultConfig('desktop'));
    broadcastProfiles();
    return { id: p.id };
  },
  'profiles.rename': ({ id, name }) => { store.renameProfile(id, name); broadcastProfiles(); },
  'profiles.delete': ({ id }) => {
    store.deleteProfile(id);
    for (const c of authed()) if (c.profileId === id) c.profileId = store.activeProfile;
    broadcastProfiles();
  },
  'profiles.setActive': ({ id }) => switchProfile(id),
  devices: (_, ws) => store.settings.tokens.map((t) => ({
    id: t.id, name: t.name, createdAt: t.createdAt, lastSeen: t.lastSeen,
    online: authed().some((c) => c.deviceId === t.id), current: ws.deviceId === t.id,
  })),
  'devices.revoke': ({ id }) => {
    store.revokeDevice(id);
    for (const c of authed()) if (c.deviceId === id) c.close();
  },
  'devices.rename': ({ id, name }) => store.renameDevice(id, name),
  'automations.get': () => store.automations,
  'automations.save': ({ rules }) => store.saveAutomations(rules),
  'automations.test': async ({ id }) => {
    const rule = store.automations.find((r) => r.id === id);
    if (!rule) throw new Error('No such rule');
    await automations.fire(rule, { type: 'manual', user: 'TestUser', amount: 5, bits: 100, viewers: 10, message: 'test message' });
  },
  'integrations.status': () => integrationsStatus(),
  'integrations.configure': (p) => { service(p.service).configure(p); },
  'integrations.login': (p) => {
    if (p.service === 'discord') {
      discord.stop();
      discord.start();
      return {};
    }
    return service(p.service).login();
  },
  'integrations.logout': ({ service: s }) => service(s).logout(),
  'mixer.get': () => mixerState(),
  'mixer.set': (p) => mixerSet(p),
  'perf.history': () => perf.history,
  'chat.recent': () => [...twitch.chat, ...youtube.chat].sort((a, b) => a.ts - b.ts).slice(-200),
  'chat.subscribe': ({ on }, ws) => { ws.chatSub = !!on; },
  'history.subscribe': ({ on }, ws) => { ws.historySub = !!on; },
};

// ---------- connections ----------
wss.on('connection', (ws, req) => {
  const ip = req.socket.remoteAddress || '?';
  ws.authed = false;
  ws.isAlive = true;
  ws.on('pong', () => (ws.isAlive = true));
  const authTimeout = setTimeout(() => !ws.authed && ws.close(), 15000);
  ws.on('close', () => clearTimeout(authTimeout));
  ws.on('error', () => {});

  function welcome(device, token, m) {
    ws.authed = true;
    ws.deviceId = device.id;
    ws.deviceName = device.name;
    device.lastSeen = Date.now();
    if (m.name && m.name !== device.name && !m.token) device.name = String(m.name).slice(0, 60);
    store.saveSettings();
    // A phone either follows the PC's active profile or pins one of its own.
    const pinned = m.profile && store.profiles[m.profile] ? m.profile : null;
    ws.follow = !pinned;
    ws.profileId = pinned || store.activeProfile;
    send(ws, {
      ...configMessage(ws),
      t: 'welcome',
      token,
      protocol: PROTOCOL,
      state: obs.state,
      toggles: ctx.state.toggles,
      stats: statsPayload(),
      integrations: integrationsStatus(),
      now: Date.now(),
      obs: obsPublic(),
      host: { name: os.hostname(), platform: process.platform },
    });
    bus.emit('event', { type: 'device.connected', device: device.name });
  }

  function hello(m) {
    const device = store.deviceForToken(m.token);
    if (device) return welcome(device, undefined, m);
    if (m.pin !== undefined) {
      const f = failures.get(ip);
      if (f && f.until > Date.now()) return send(ws, { t: 'authFail', reason: 'Too many attempts, wait a minute' });
      if (String(m.pin) === pin) {
        failures.delete(ip);
        const token = store.addToken(m.name);
        pin = newPin();
        console.log(`Paired "${m.name || 'device'}". New PIN for next device: ${pin}`);
        return welcome(store.deviceForToken(token), token, m);
      }
      const count = (f ? f.count : 0) + 1;
      failures.set(ip, { count, until: count >= 5 ? Date.now() + 60000 : 0 });
      return send(ws, { t: 'authFail', reason: 'Wrong PIN' });
    }
    send(ws, { t: 'authFail', reason: 'Not paired', needPin: true });
  }

  async function execute(m, kind) {
    const b = store.findButton(ws.profileId, m.id);
    if (!b) throw new Error('Button no longer exists');
    const action = kind === 'long' ? b.longAction : kind === 'double' ? b.doubleAction : b.action;
    if (!action) return;
    let error = null;
    try {
      await run(action, makeCtx({ buttonId: kind === 'tap' ? b.id : `${b.id}:${kind}` }));
    } catch (e) {
      error = e.message;
    }
    if (!['widget', 'screen', 'folder', 'back', 'home'].includes(action.type)) {
      addHistory({ source: 'button', label: b.label || describe(action), kind, action: describe(action), ok: !error, error, device: ws.deviceName });
    }
    if (error) throw new Error(error);
  }

  ws.on('message', async (raw) => {
    let m;
    try { m = JSON.parse(raw.toString()); } catch { return; }
    if (!ws.authed) {
      if (m.t === 'hello') hello(m);
      return;
    }
    try {
      switch (m.t) {
        case 'ping':
          return send(ws, { t: 'pong' });
        case 'press':
          await execute(m, m.kind === 'long' || m.kind === 'double' ? m.kind : 'tap');
          return send(ws, { t: 'result', rid: m.rid, ok: true });
        case 'run': { // test an unsaved action from the editor
          let error = null;
          try { await run(m.action, makeCtx()); } catch (e) { error = e.message; }
          addHistory({ source: 'test', label: 'Editor test', action: describe(m.action), ok: !error, error, device: ws.deviceName });
          if (error) throw new Error(error);
          return send(ws, { t: 'result', rid: m.rid, ok: true });
        }
        case 'saveConfig': {
          store.saveConfig(ws.profileId, m.config);
          return broadcastConfig(ws.profileId);
        }
        case 'selectProfile': { // phone picks its own profile ("follow PC" when id is null)
          if (m.id && store.profiles[m.id]) {
            ws.follow = false;
            ws.profileId = m.id;
          } else {
            ws.follow = true;
            ws.profileId = store.activeProfile;
          }
          return send(ws, configMessage(ws));
        }
        case 'saveSettings': {
          const o = m.obs || {};
          const cur = store.settings.obs;
          store.settings.obs = {
            host: String(o.host || cur.host),
            port: parseInt(o.port, 10) || cur.port,
            password: o.password === undefined ? cur.password : String(o.password),
          };
          store.saveSettings();
          obs.reconnect();
          return broadcast({ t: 'obsSettings', obs: obsPublic() });
        }
        case 'obsList': {
          const list = await obs.listScenesAndInputs();
          return send(ws, { t: 'obsList', ...list });
        }
        case 'rpc': {
          const fn = rpc[m.method];
          if (!fn) return send(ws, { t: 'rpcResult', rid: m.rid, ok: false, error: `Unknown method ${m.method} (update the companion?)` });
          try {
            const data = await fn(m.params || {}, ws);
            return send(ws, { t: 'rpcResult', rid: m.rid, ok: true, data: data === undefined ? null : data });
          } catch (e) {
            return send(ws, { t: 'rpcResult', rid: m.rid, ok: false, error: e.message });
          }
        }
        default:
          return;
      }
    } catch (e) {
      send(ws, { t: 'result', rid: m.rid, ok: false, error: e.message });
    }
  });
});

// Drop dead sockets (phone went to sleep, Wi-Fi roamed).
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    try { ws.ping(); } catch {}
  }
}, 15000).unref();

// ---------- periodic stats, foreground app, background services ----------
let lastFg = '';
input.onForeground = (name) => {
  if (name && name !== lastFg) {
    lastFg = name;
    bus.emit('event', { type: 'app.foreground', process: name });
  }
};

setInterval(async () => {
  if (automations.usesForeground()) input.queryForeground();
  if (!authed().length && !store.automations.some((r) => r.enabled && r.trigger && r.trigger.type === 'system.cpu')) return;
  input.query();
  await perf.sample();
  bus.emit('event', { type: 'system.cpu', cpu: perf.last.cpu });
  broadcast({ t: 'stats', stats: statsPayload(), now: Date.now() });
}, 2000).unref();

server.listen(PORT, '0.0.0.0', () => {
  obs.start();
  automations.start();
  twitch.start();
  youtube.start();
  discord.start();
  startDiscovery(PORT);
  printPairing();
  // Replace vector placeholders with the real icon of each app / website, in the background.
  if (!process.env.DECKPAD_NO_ICONS) icons.resolveDefaultIcons(store, broadcastConfig).catch(() => {});
});
server.on('error', (e) => {
  console.error(e.code === 'EADDRINUSE' ? `Port ${PORT} is busy. Set DECKPAD_PORT to another port.` : e);
  process.exit(1);
});

function shutdown() {
  input.close();
  mixer.close();
  obs.stop();
  twitch.stop();
  youtube.stop();
  discord.stop();
  process.exit(0);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

module.exports = { server, store };
