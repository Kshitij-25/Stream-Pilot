'use strict';
// Feature tests: migration, profiles, long/double press, history, devices, automations, discovery, mixer, icons.
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const dgram = require('dgram');
const { startServer, pair, client, wait } = require('./helpers');

const PORT = 18770;
const cmd = (c) => ({ type: 'command', command: c });

(async () => {
  // --- legacy v1 config is backed up and replaced by the multi-screen defaults
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'deckpad-feat-'));
  fs.writeFileSync(path.join(home, 'config.json'), JSON.stringify({ version: 1, cols: 4, rows: 4, rootPage: 'home', pages: { home: { id: 'home', name: 'Home', buttons: [] } } }));
  const s = await startServer({ port: PORT, home });
  assert.ok(fs.existsSync(path.join(home, 'config.v1.bak.json')), 'backup written');
  assert.ok(!fs.existsSync(path.join(home, 'config.json')));
  const { c, welcome } = await pair(PORT, s.pin, { name: 'phone A' });
  assert.strictEqual(welcome.protocol, 3);
  const names = Object.values(welcome.config.pages).map((p) => p.name);
  for (const want of ['Stream', 'Audio', 'Twitch', 'YouTube', 'Discord', 'Desktop', 'Macros', 'Sounds', 'Monitor']) assert.ok(names.includes(want), 'default page ' + want);
  assert.ok(Object.values(welcome.config.pages).every((p) => p.pinned), 'all default pages are in the switcher');
  assert.deepStrictEqual(welcome.profiles.map((p) => p.id).sort(), ['desktop', 'streaming']);
  const volBtns = welcome.config.pages.audio.buttons.filter((b) => b && b.action.type === 'volume').map((b) => b.label);
  assert.ok(volBtns.includes('Vol +') && volBtns.includes('Vol -'));
  console.log('ok migration + default pages');

  // --- Vol + / Vol - really change the system volume (Windows)
  if (process.platform === 'win32') {
    const audio = welcome.config.pages.audio.buttons;
    const volUp = audio.find((b) => b && b.label === 'Vol +');
    const volDown = audio.find((b) => b && b.label === 'Vol -');
    const readVol = async () => { for (let i = 0; i < 6; i++) { const m = await c.next((x) => x.t === 'stats' && x.stats.vol !== null, 6000); return m.stats.vol; } };
    const before = await readVol();
    c.sendj({ t: 'press', id: volDown.id, rid: 1 });
    await c.next((x) => x.t === 'result' && x.rid === 1 && x.ok);
    await wait(2500);
    const down = await readVol();
    c.sendj({ t: 'press', id: volUp.id, rid: 2 });
    await c.next((x) => x.t === 'result' && x.rid === 2 && x.ok);
    await wait(2500);
    const up = await readVol();
    console.log(`   volume ${before} -> ${down} -> ${up}`);
    assert.ok(before === 0 || down < before, 'Vol - lowers volume');
    assert.ok(before === 100 && down === 95 ? up === 100 : up > down, 'Vol + raises volume');
    c.sendj({ t: 'run', rid: 3, action: { type: 'volume', op: 'set', value: before } });
    await c.next((x) => x.t === 'result' && x.rid === 3);
    console.log('ok Vol+ / Vol- via the default buttons');
  }

  // --- long press / double tap / history
  const cfg = JSON.parse(JSON.stringify(welcome.config));
  cfg.pages.stream.buttons[0] = { id: 'ld', label: 'LD', icon: 'mi:star', color: '#000', action: cmd('echo tap'), longAction: cmd('echo long'), doubleAction: cmd('exit 5') };
  c.sendj({ t: 'saveConfig', config: cfg });
  await c.next((x) => x.t === 'config');
  c.sendj({ t: 'press', id: 'ld', rid: 10 });
  assert.ok((await c.next((x) => x.t === 'result' && x.rid === 10)).ok);
  c.sendj({ t: 'press', id: 'ld', kind: 'long', rid: 11 });
  assert.ok((await c.next((x) => x.t === 'result' && x.rid === 11)).ok);
  c.sendj({ t: 'press', id: 'ld', kind: 'double', rid: 12 });
  assert.ok(!(await c.next((x) => x.t === 'result' && x.rid === 12)).ok);
  const hist = (await c.rpc('history')).history;
  const mine = hist.filter((h) => h.label === 'LD');
  assert.deepStrictEqual(mine.map((h) => h.kind).reverse(), ['tap', 'long', 'double']);
  assert.strictEqual(mine[0].ok, false);
  assert.strictEqual(mine[0].device, 'phone A');
  console.log('ok long/double press + history');

  // --- profiles: per-device selection, follow PC, global switch
  const { c: c2 } = await pair(PORT, (await (async () => { const m = /New PIN for next device: (\d{6})/.exec(s.log.out); return { x: m[1] }; })()).x, { name: 'tablet', profile: 'desktop' });
  const m2 = await c2.rpc('devices');
  assert.ok(m2.length === 2 && m2.every((d) => d.online));
  c.sendj({ t: 'selectProfile', id: 'desktop' });
  let pm = await c.next((x) => x.t === 'config');
  assert.strictEqual(pm.profile.id, 'desktop');
  assert.ok(pm.config.pages.audio && !pm.config.pages.stream, 'desktop profile has fewer pages');
  c.sendj({ t: 'selectProfile', id: null });
  pm = await c.next((x) => x.t === 'config');
  assert.strictEqual(pm.profile.id, 'streaming');
  assert.strictEqual(pm.following, true);
  await c.rpc('profiles.setActive', { id: 'desktop' }); // PC-wide switch moves followers only
  pm = await c.next((x) => x.t === 'config');
  assert.strictEqual(pm.profile.id, 'desktop');
  const nid = (await c.rpc('profiles.create', { name: 'Gaming', from: 'streaming' })).id;
  assert.strictEqual(nid, 'gaming');
  await c.rpc('profiles.rename', { id: 'gaming', name: 'Gaming PC' });
  await c.rpc('profiles.delete', { id: 'gaming' });
  console.log('ok profiles (per-device, follow, global, create/rename/delete)');

  // --- automations: save rule, fire it manually, template variables, history
  const out = path.join(home, 'auto.txt').replace(/\\/g, '/');
  await c.rpc('automations.save', { rules: [{ id: 'r1', name: 'Test rule', enabled: true, trigger: { type: 'twitch.follow' }, cooldown: 0, actions: [cmd(`echo {{user}} {{amount}} > "${out}"`)] }] });
  await c.rpc('automations.test', { id: 'r1' });
  assert.match(fs.readFileSync(out, 'utf8'), /TestUser 5/);
  const h2 = (await c.rpc('history')).history.find((h) => h.source === 'automation');
  assert.ok(h2 && h2.ok);
  console.log('ok automations');

  // --- device management
  const devs = await c.rpc('devices');
  const tablet = devs.find((d) => d.name === 'tablet');
  await c.rpc('devices.revoke', { id: tablet.id });
  await wait(200);
  assert.ok(!(await c.rpc('devices')).some((d) => d.name === 'tablet'));
  console.log('ok devices');

  // --- unknown rpc gives a helpful error
  await assert.rejects(c.rpc('nope'), /update the companion/);

  // --- LAN discovery
  const found = await new Promise((resolve, reject) => {
    const sock = dgram.createSocket('udp4');
    const t = setTimeout(() => reject(new Error('no discovery reply')), 3000);
    sock.on('message', (m) => { clearTimeout(t); sock.close(); resolve(JSON.parse(m.toString())); });
    sock.send('DECKPAD?', PORT + 1, '127.0.0.1');
  });
  assert.strictEqual(found.app, 'deckpad');
  assert.strictEqual(found.port, PORT);
  console.log('ok discovery');

  // --- real icons (Windows): installed app list + extraction
  if (process.platform === 'win32') {
    const apps = await c.rpc('listApps');
    assert.ok(apps.length > 5);
    const png = await c.rpc('appIcon', { path: 'notepad.exe' });
    assert.ok(Buffer.from(png, 'base64').subarray(0, 4).toString('hex') === '89504e47', 'PNG header');
    const mix = await c.rpc('mixer.get');
    assert.ok(Array.isArray(mix.apps) && mix.master);
    console.log(`ok real icons (${apps.length} apps) + mixer (${mix.apps.length} audio sessions)`);
  }

  s.stop();
  console.log('FEATURES PASSED');
})().catch((e) => { console.error('FAILED', e); process.exitCode = 1; })
  .finally(() => setTimeout(() => process.exit(), 300));
