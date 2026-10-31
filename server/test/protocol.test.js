'use strict';
// End-to-end protocol test: launches the server, pairs, presses buttons, edits config.
const { spawn } = require('child_process');
const path = require('path');
const os = require('os');
const fs = require('fs');
const assert = require('assert');
const WebSocket = require('ws');

const PORT = 18765;
const home = fs.mkdtempSync(path.join(os.tmpdir(), 'deckpad-test-'));
const srv = spawn('node', [path.join(__dirname, '..', 'src', 'index.js')], {
  env: { ...process.env, DECKPAD_PORT: String(PORT), DECKPAD_HOME: home },
});
let out = '';
srv.stdout.on('data', (d) => (out += d));
srv.stderr.on('data', (d) => (out += d));

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

function client() {
  const ws = new WebSocket(`ws://127.0.0.1:${PORT}`);
  const q = [];
  const waiters = [];
  ws.on('message', (d) => {
    const m = JSON.parse(d.toString());
    const w = waiters.findIndex((f) => f.pred(m));
    if (w >= 0) waiters.splice(w, 1)[0].res(m);
    else q.push(m);
  });
  ws.next = (pred = () => true) =>
    new Promise((res, rej) => {
      const i = q.findIndex(pred);
      if (i >= 0) return res(q.splice(i, 1)[0]);
      const t = setTimeout(() => rej(new Error('timeout waiting for message')), 4000);
      waiters.push({ pred, res: (m) => { clearTimeout(t); res(m); } });
    });
  ws.sendj = (o) => ws.send(JSON.stringify(o));
  return new Promise((res, rej) => { ws.on('open', () => res(ws)); ws.on('error', rej); });
}

(async () => {
  for (let i = 0; i < 50 && !/Pairing PIN/.test(out); i++) await wait(100);
  const pin = /Pairing PIN : (\d{6})/.exec(out)[1];

  // unauthenticated
  let c = await client();
  c.sendj({ t: 'hello', name: 'x' });
  assert.strictEqual((await c.next()).t, 'authFail');
  c.sendj({ t: 'hello', pin: '000000', name: 'x' });
  let m = await c.next();
  assert.strictEqual(m.t, 'authFail'); assert.strictEqual(m.reason, 'Wrong PIN');

  // pair
  c.sendj({ t: 'hello', pin, name: 'test phone' });
  m = await c.next();
  assert.strictEqual(m.t, 'welcome'); assert.ok(m.token);
  assert.ok(m.config.pages.home.buttons[0]);
  const token = m.token;
  console.log('ok pairing');

  // old PIN rotated, token reconnect works
  const c2 = await client();
  c2.sendj({ t: 'hello', pin, name: 'again' });
  assert.strictEqual((await c2.next()).t, 'authFail');
  c2.close();
  const c3 = await client();
  c3.sendj({ t: 'hello', token });
  m = await c3.next();
  assert.strictEqual(m.t, 'welcome'); assert.strictEqual(m.token, undefined);
  console.log('ok token reconnect');

  // edit config: add a command button, broadcast to other client
  const cfg = m.config;
  cfg.pages.home.buttons[15] = { id: 'testbtn', label: 'T', icon: 'x', color: '#000', action: { type: 'command', command: 'echo hi' } };
  cfg.pages.home.buttons[14] = { id: 'bad', label: 'B', icon: 'x', color: '#000', action: { type: 'command', command: 'exit 3' } };
  cfg.pages.home.buttons[13] = { id: 'macro', label: 'M', icon: 'x', color: '#000', action: { type: 'multi', actions: [{ type: 'delay', ms: 50 }, { type: 'command', command: 'echo a' }] } };
  c.sendj({ t: 'saveConfig', config: cfg });
  m = await c3.next((x) => x.t === 'config');
  assert.strictEqual(m.config.pages.home.buttons[15].id, 'testbtn');
  console.log('ok config broadcast');

  c3.sendj({ t: 'press', id: 'testbtn', rid: 1 });
  m = await c3.next((x) => x.t === 'result'); assert.ok(m.ok && m.rid === 1);
  c3.sendj({ t: 'press', id: 'bad', rid: 2 });
  m = await c3.next((x) => x.t === 'result'); assert.ok(!m.ok && m.rid === 2);
  c3.sendj({ t: 'press', id: 'macro', rid: 3 });
  m = await c3.next((x) => x.t === 'result'); assert.ok(m.ok);
  c3.sendj({ t: 'press', id: 'nope', rid: 4 });
  m = await c3.next((x) => x.t === 'result'); assert.ok(!m.ok);
  c3.sendj({ t: 'run', rid: 5, action: { type: 'hotkey', keys: 'ctrl+bogus' } });
  m = await c3.next((x) => x.t === 'result'); assert.ok(!m.ok && /Unknown key/.test(m.error));
  if (process.platform === 'win32') {
    c3.sendj({ t: 'run', rid: 6, action: { type: 'hotkey', keys: 'f24' } }); // harmless key
    m = await c3.next((x) => x.t === 'result'); assert.ok(m.ok);
  }
  c3.sendj({ t: 'press', id: 'testbtn', rid: 7 });
  c3.sendj({ t: 'run', rid: 8, action: { type: 'obs', op: 'toggleStream' } });
  m = await c3.next((x) => x.t === 'result' && x.rid === 8); assert.ok(!m.ok && /OBS/.test(m.error));
  console.log('ok actions');

  // persisted
  const saved = JSON.parse(fs.readFileSync(path.join(home, 'config.json'), 'utf8'));
  assert.strictEqual(saved.pages.home.buttons[15].id, 'testbtn');
  console.log('ok persistence');
  console.log('ALL PASSED');
})()
  .catch((e) => { console.error('FAILED', e); process.exitCode = 1; })
  .finally(() => { srv.kill(); setTimeout(() => process.exit(), 200); });
