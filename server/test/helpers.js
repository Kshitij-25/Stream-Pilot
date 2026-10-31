'use strict';
// Shared helpers: start a companion in a temp home, connect test clients.
const { spawn } = require('child_process');
const path = require('path');
const os = require('os');
const fs = require('fs');
const WebSocket = require('ws');

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

async function startServer({ port, home, env = {} }) {
  home = home || fs.mkdtempSync(path.join(os.tmpdir(), 'deckpad-test-'));
  const srv = spawn('node', [path.join(__dirname, '..', 'src', 'index.js')], {
    env: { ...process.env, DECKPAD_PORT: String(port), DECKPAD_HOME: home, DECKPAD_NO_ICONS: '1', DECKPAD_DISCOVERY_PORT: String(port + 1), ...env },
  });
  const t = { out: '' };
  srv.stdout.on('data', (d) => (t.out += d));
  srv.stderr.on('data', (d) => (t.out += d));
  for (let i = 0; i < 80 && !/Pairing PIN/.test(t.out); i++) await wait(100);
  const m = /Pairing PIN : (\d{6})/.exec(t.out);
  if (!m) throw new Error('server did not start: ' + t.out);
  return { srv, home, pin: m[1], log: t, stop: () => srv.kill() };
}

function client(port) {
  const ws = new WebSocket(`ws://127.0.0.1:${port}`);
  const q = [];
  const waiters = [];
  ws.on('message', (d) => {
    const m = JSON.parse(d.toString());
    const w = waiters.findIndex((f) => f.pred(m));
    if (w >= 0) waiters.splice(w, 1)[0].res(m);
    else q.push(m);
  });
  ws.next = (pred = () => true, ms = 5000) =>
    new Promise((res, rej) => {
      const i = q.findIndex(pred);
      if (i >= 0) return res(q.splice(i, 1)[0]);
      const t = setTimeout(() => rej(new Error('timeout waiting for message')), ms);
      waiters.push({ pred, res: (m) => { clearTimeout(t); res(m); } });
    });
  let rid = 1000;
  ws.sendj = (o) => ws.send(JSON.stringify(o));
  ws.rpc = async (method, params) => {
    const id = ++rid;
    ws.sendj({ t: 'rpc', rid: id, method, params });
    const m = await ws.next((x) => x.t === 'rpcResult' && x.rid === id);
    if (!m.ok) throw new Error(m.error);
    return m.data;
  };
  return new Promise((res, rej) => { ws.on('open', () => res(ws)); ws.on('error', rej); });
}

async function pair(port, pin, extra = {}) {
  const c = await client(port);
  c.sendj({ t: 'hello', pin, name: 'test phone', ...extra });
  const w = await c.next((m) => m.t === 'welcome' || m.t === 'authFail');
  if (w.t !== 'welcome') throw new Error('pairing failed: ' + w.reason);
  return { c, welcome: w };
}

module.exports = { startServer, client, pair, wait };
