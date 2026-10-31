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

const PORT = parseInt(process.env.DECKPAD_PORT, 10) || 8765;

const store = new Store();
const input = createInput();
const obs = new ObsClient(() => store.settings.obs);
const ctx = {
  input,
  obs,
  state: { toggles: {}, cycles: {} },
  changed: () => pushState(),
};

let stats = { cpu: 0, mem: 0, vol: null, muted: false };
let lastCpu = os.cpus().map((c) => ({ ...c.times }));
function sampleStats() {
  const now = os.cpus().map((c) => ({ ...c.times }));
  let idle = 0;
  let total = 0;
  now.forEach((t, i) => {
    const p = lastCpu[i] || t;
    total += Object.keys(t).reduce((a, k) => a + (t[k] - (p[k] || 0)), 0);
    idle += t.idle - (p.idle || 0);
  });
  lastCpu = now;
  stats = {
    cpu: total ? Math.round((1 - idle / total) * 100) : 0,
    mem: Math.round((1 - os.freemem() / os.totalmem()) * 100),
    vol: input.audio ? input.audio.volume : null,
    muted: input.audio ? input.audio.muted : false,
  };
}

// Pairing PIN: new each launch, reusable until a device pairs successfully, then rotated.
let pin = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
const failures = new Map(); // ip -> { count, until }

function lanAddresses() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const i of list || []) if (i.family === 'IPv4' && !i.internal) out.push(i.address);
  }
  // Prefer typical home LAN ranges first.
  return out.sort((a, b) => Number(/^(192\.168|10\.)/.test(b)) - Number(/^(192\.168|10\.)/.test(a)));
}

function printPairing() {
  const ips = lanAddresses();
  const host = ips[0] || '127.0.0.1';
  const url = `deckpad://${host}:${PORT}?pin=${pin}`;
  console.log('\n==============  DeckPad companion  ==============');
  console.log(`Listening on: ${ips.map((ip) => `${ip}:${PORT}`).join(', ') || `localhost:${PORT}`}`);
  console.log(`Pairing PIN : ${pin}`);
  console.log('Scan this QR in the app (or type the address + PIN):\n');
  qrcode.generate(url, { small: true }, (q) => console.log(q));
  console.log('Same Wi-Fi network required. Windows may ask to allow Node through the firewall: allow Private networks.\n');
}

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ app: 'deckpad', name: os.hostname() }));
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocket.Server({ server, maxPayload: 32 * 1024 * 1024 });

const send = (ws, msg) => ws.readyState === WebSocket.OPEN && ws.send(JSON.stringify(msg));
const broadcast = (msg) => {
  for (const c of wss.clients) if (c.authed) send(c, msg);
};

function obsPublic() {
  const { host, port, password } = store.settings.obs;
  return { host, port, hasPassword: !!password };
}

function pushState() {
  broadcast({ t: 'state', state: obs.state, toggles: ctx.state.toggles, now: Date.now() });
}
obs.on('state', pushState);

setInterval(() => {
  if (![...wss.clients].some((c) => c.authed)) return;
  input.query();
  sampleStats();
  broadcast({ t: 'stats', stats, now: Date.now() });
}, 2000).unref();

wss.on('connection', (ws, req) => {
  const ip = req.socket.remoteAddress || '?';
  ws.authed = false;
  ws.isAlive = true;
  ws.on('pong', () => (ws.isAlive = true));
  const authTimeout = setTimeout(() => !ws.authed && ws.close(), 15000);
  ws.on('close', () => clearTimeout(authTimeout));
  ws.on('error', () => {});

  function welcome(token) {
    ws.authed = true;
    send(ws, {
      t: 'welcome',
      token,
      config: store.config,
      state: obs.state,
      toggles: ctx.state.toggles,
      stats,
      now: Date.now(),
      obs: obsPublic(),
      host: { name: os.hostname(), platform: process.platform },
    });
  }

  function hello(m) {
    if (store.checkToken(m.token)) return welcome(undefined);
    if (m.pin !== undefined) {
      const f = failures.get(ip);
      if (f && f.until > Date.now()) return send(ws, { t: 'authFail', reason: 'Too many attempts, wait a minute' });
      if (String(m.pin) === pin) {
        failures.delete(ip);
        const token = store.addToken(m.name);
        pin = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
        console.log(`Paired "${m.name || 'device'}". New PIN for next device: ${pin}`);
        return welcome(token);
      }
      const count = (f ? f.count : 0) + 1;
      failures.set(ip, { count, until: count >= 5 ? Date.now() + 60000 : 0 });
      return send(ws, { t: 'authFail', reason: 'Wrong PIN' });
    }
    send(ws, { t: 'authFail', reason: 'Not paired', needPin: true });
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
        case 'press': {
          const b = store.findButton(m.id);
          if (!b) throw new Error('Button no longer exists');
          await run(b.action, { ...ctx, buttonId: b.id });
          return send(ws, { t: 'result', rid: m.rid, ok: true });
        }
        case 'run': // test an unsaved action from the editor
          await run(m.action, ctx);
          return send(ws, { t: 'result', rid: m.rid, ok: true });
        case 'saveConfig': {
          const cfg = store.saveConfig(m.config);
          return broadcast({ t: 'config', config: cfg });
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

server.listen(PORT, '0.0.0.0', () => {
  obs.start();
  printPairing();
});
server.on('error', (e) => {
  console.error(e.code === 'EADDRINUSE' ? `Port ${PORT} is busy. Set DECKPAD_PORT to another port.` : e);
  process.exit(1);
});

process.on('SIGINT', () => {
  input.close();
  obs.stop();
  process.exit(0);
});

module.exports = { server, store };
