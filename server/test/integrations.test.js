'use strict';
// Integration tests against LOCAL MOCKS of Twitch / YouTube / Discord (no real accounts are contacted).
// They verify our protocol handling: OAuth device flow, token refresh, EventSub, chat, moderation, IPC framing.
const assert = require('assert');
const http = require('http');
const net = require('net');
const fs = require('fs');
const os = require('os');
const path = require('path');
const WebSocket = require('ws');
const { startServer, pair, wait } = require('./helpers');

const MOCK = 18790;
const PORT = 18780;
const PIPE = `\\\\.\\pipe\\deckpad-test-${process.pid}-ipc-`;
const log = []; // every request the mocks saw
let twitchPolls = 0;
let ytPolls = 0;
let ytChatCalls = 0;
let expireTwitch = false;
let twitchWs = null;

function readBody(req) {
  return new Promise((res) => { let b = ''; req.on('data', (d) => (b += d)); req.on('end', () => res(b)); });
}

const mock = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${MOCK}`);
  const raw = await readBody(req);
  const form = req.headers['content-type'] === 'application/x-www-form-urlencoded' ? Object.fromEntries(new URLSearchParams(raw)) : null;
  const body = !form && raw ? JSON.parse(raw) : form;
  log.push({ method: req.method, path: url.pathname, query: Object.fromEntries(url.searchParams), body, auth: req.headers.authorization });
  const json = (status, obj) => { res.writeHead(status, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };
  const p = url.pathname;

  // ----- control channel for the test
  if (p === '/_emit') { twitchWs.send(JSON.stringify(body)); return json(200, {}); }
  if (p === '/_expire') { expireTwitch = true; return json(200, {}); }

  // ----- Twitch
  if (p === '/id/oauth2/device') return json(200, { device_code: 'dc', user_code: 'ABCD-EFGH', verification_uri: 'https://www.twitch.tv/activate', expires_in: 600, interval: 1 });
  if (p === '/id/oauth2/token') {
    if (form.grant_type === 'refresh_token') return json(200, { access_token: 'tok2', refresh_token: 'ref2', expires_in: 3600 });
    return ++twitchPolls < 2 ? json(400, { message: 'authorization_pending' }) : json(200, { access_token: 'tok1', refresh_token: 'ref1', expires_in: 3600 });
  }
  if (p.startsWith('/helix')) {
    if (expireTwitch && req.headers.authorization === 'Bearer tok1') return json(401, { message: 'Invalid OAuth token' });
    const h = p.slice('/helix'.length);
    if (h === '/users') return json(200, { data: [{ id: url.searchParams.get('login') ? '99' : '42', login: url.searchParams.get('login') || 'streamer', display_name: 'Streamer' }] });
    if (h === '/streams') return json(200, { data: [{ viewer_count: 123 }] });
    if (h === '/channels/followers') return json(200, { total: 456 });
    if (h === '/chat/settings' && req.method === 'GET') return json(200, { data: [{ slow_mode: false, subscriber_mode: false, emote_mode: false, follower_mode: false, unique_chat_mode: false }] });
    if (h === '/clips') return json(200, { data: [{ id: 'ClipXYZ' }] });
    return json(204 === 0 ? 204 : 200, { data: [] });
  }

  // ----- Google / YouTube
  if (p === '/g/device/code') return json(200, { device_code: 'ydc', user_code: 'YT-CODE', verification_url: 'https://www.google.com/device', expires_in: 600, interval: 1 });
  if (p === '/g/token') return ++ytPolls < 2 ? json(400, { error: 'authorization_pending' }) : json(200, { access_token: 'ytok', refresh_token: 'yref', expires_in: 3600 });
  if (p === '/yt/liveBroadcasts') return json(200, { items: [{ id: 'vid1', snippet: { liveChatId: 'chat1', title: 'My Stream' } }] });
  if (p === '/yt/liveChat/messages' && req.method === 'GET') {
    ytChatCalls++;
    const mk = (id, type, extra = {}) => ({ id, snippet: { type, displayMessage: extra.text || '', publishedAt: new Date().toISOString(), ...extra.snippet }, authorDetails: { channelId: 'UC' + id, displayName: 'viewer' + id, isChatModerator: false } });
    if (ytChatCalls === 1) return json(200, { pollingIntervalMillis: 5000, nextPageToken: 't1', items: [mk('old', 'textMessageEvent', { text: 'old message' })] });
    return json(200, { pollingIntervalMillis: 5000, nextPageToken: 't2', items: [
      mk('sc', 'superChatEvent', { text: 'great stream', snippet: { superChatDetails: { amountMicros: '5000000', amountDisplayString: '$5.00' } } }),
      mk('cmd', 'textMessageEvent', { text: '!yt hello' }),
    ] });
  }
  if (p === '/yt/videos') return json(200, { items: [{ liveStreamingDetails: { concurrentViewers: '77' } }] });
  if (p.startsWith('/yt/')) return json(200, {});

  // ----- Discord OAuth
  if (p === '/discord/oauth2/token') return json(200, { access_token: 'dtok', refresh_token: 'dref', expires_in: 3600 });
  json(404, {});
});

const twitchWss = new WebSocket.Server({ server: mock, path: '/eventsub' });
twitchWss.on('connection', (ws) => {
  twitchWs = ws;
  ws.send(JSON.stringify({ metadata: { message_type: 'session_welcome' }, payload: { session: { id: 'sess1', keepalive_timeout_seconds: 30 } } }));
});

// ----- Discord IPC mock (named pipe)
let dMute = false;
const frame = (op, obj) => { const d = Buffer.from(JSON.stringify(obj)); const h = Buffer.alloc(8); h.writeInt32LE(op, 0); h.writeInt32LE(d.length, 4); return Buffer.concat([h, d]); };
const ipc = net.createServer((sock) => {
  let buf = Buffer.alloc(0);
  const voice = () => ({ mute: dMute, deaf: false, input: { volume: 100 }, output: { volume: 100 } });
  sock.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    while (buf.length >= 8) {
      const op = buf.readInt32LE(0), len = buf.readInt32LE(4);
      if (buf.length < 8 + len) return;
      const msg = JSON.parse(buf.subarray(8, 8 + len).toString());
      buf = buf.subarray(8 + len);
      if (op === 0) { assert.strictEqual(msg.client_id, 'dcid'); return sock.write(frame(1, { cmd: 'DISPATCH', evt: 'READY', data: {} })); }
      const reply = (data) => sock.write(frame(1, { cmd: msg.cmd, data, nonce: msg.nonce }));
      log.push({ ipc: msg.cmd, args: msg.args });
      if (msg.cmd === 'AUTHORIZE') reply({ code: 'authcode' });
      else if (msg.cmd === 'AUTHENTICATE') { assert.strictEqual(msg.args.access_token, 'dtok'); reply({ user: { username: 'me' } }); }
      else if (msg.cmd === 'GET_VOICE_SETTINGS') reply(voice());
      else if (msg.cmd === 'SUBSCRIBE') reply({ evt: msg.evt });
      else if (msg.cmd === 'SET_VOICE_SETTINGS') {
        if (msg.args.mute !== undefined) dMute = msg.args.mute;
        reply(voice());
        sock.write(frame(1, { cmd: 'DISPATCH', evt: 'VOICE_SETTINGS_UPDATE', data: voice() }));
      } else reply({});
    }
  });
});

const cmd = (c) => ({ type: 'command', command: c });
const callsTo = (p, method) => log.filter((l) => l.path === p && (!method || l.method === method));

(async () => {
  await new Promise((r) => mock.listen(MOCK, r));
  await new Promise((r) => ipc.listen(`${PIPE}0`, r));
  const out = fs.mkdtempSync(path.join(os.tmpdir(), 'deckpad-out-'));
  const f = (n) => path.join(out, n).replace(/\\/g, '/');

  const s = await startServer({
    port: PORT,
    env: {
      DECKPAD_TWITCH_ID_URL: `http://127.0.0.1:${MOCK}/id`,
      DECKPAD_TWITCH_API_URL: `http://127.0.0.1:${MOCK}/helix`,
      DECKPAD_TWITCH_WS_URL: `ws://127.0.0.1:${MOCK}/eventsub`,
      DECKPAD_GOOGLE_OAUTH_URL: `http://127.0.0.1:${MOCK}/g`,
      DECKPAD_YT_API_URL: `http://127.0.0.1:${MOCK}/yt`,
      DECKPAD_DISCORD_API_URL: `http://127.0.0.1:${MOCK}/discord`,
      DECKPAD_DISCORD_PIPE: PIPE,
    },
  });
  const { c } = await pair(PORT, s.pin);

  // Automations that react to integration events
  await c.rpc('automations.save', {
    rules: [
      { id: 'a1', name: 'follow', enabled: true, trigger: { type: 'twitch.follow' }, actions: [cmd(`echo {{user}} > "${f('follow.txt')}"`)] },
      { id: 'a2', name: 'hello cmd', enabled: true, trigger: { type: 'twitch.chatCommand', command: '!hello' }, actions: [cmd(`echo {{user}} {{args}} > "${f('cmd.txt')}"`)] },
      { id: 'a3', name: 'bits', enabled: true, trigger: { type: 'twitch.cheer', minBits: 50 }, actions: [cmd(`echo {{bits}} > "${f('bits.txt')}"`)] },
      { id: 'a4', name: 'superchat', enabled: true, trigger: { type: 'youtube.superchat' }, actions: [cmd(`echo {{user}} {{amount}} > "${f('sc.txt')}"`)] },
      { id: 'a5', name: 'yt cmd', enabled: true, trigger: { type: 'youtube.chatCommand', command: '!yt' }, actions: [cmd(`echo ok > "${f('ytcmd.txt')}"`)] },
    ],
  });

  // Discord action falls back to a keyboard shortcut while Discord is not connected
  c.sendj({ t: 'run', rid: 1, action: { type: 'discord', op: 'toggleMute', fallback: cmd(`echo fb > "${f('fallback.txt')}"`) } });
  assert.ok((await c.next((x) => x.t === 'result' && x.rid === 1)).ok);
  assert.ok(fs.existsSync(f('fallback.txt')));
  c.sendj({ t: 'run', rid: 2, action: { type: 'discord', op: 'toggleMute' } });
  assert.match((await c.next((x) => x.t === 'result' && x.rid === 2)).error, /not connected/i);
  console.log('ok discord fallback when not connected');

  // ===== Twitch
  await assert.rejects(c.rpc('integrations.login', { service: 'twitch' }), /Client ID/);
  await c.rpc('integrations.configure', { service: 'twitch', clientId: 'cid' });
  const login = await c.rpc('integrations.login', { service: 'twitch' });
  assert.strictEqual(login.userCode, 'ABCD-EFGH');
  let st = await c.next((x) => x.t === 'integrations' && x.status.twitch.connected, 15000);
  assert.strictEqual(st.status.twitch.user, 'streamer');
  assert.ok(callsTo('/id/oauth2/device')[0].body.scopes.includes('moderator:manage:banned_users'));
  await wait(800);
  const subs = callsTo('/helix/eventsub/subscriptions', 'POST').map((l) => l.body.type);
  for (const t of ['channel.follow', 'channel.subscribe', 'channel.cheer', 'channel.raid', 'channel.chat.message', 'stream.online', 'channel.channel_points_custom_reward_redemption.add']) assert.ok(subs.includes(t), 'subscribed to ' + t);
  const follow = callsTo('/helix/eventsub/subscriptions', 'POST').find((l) => l.body.type === 'channel.follow').body;
  assert.strictEqual(follow.version, '2');
  assert.strictEqual(follow.transport.session_id, 'sess1');
  const stats = await c.next((x) => x.t === 'stats' && x.stats.twitch.viewers === 123, 8000);
  assert.strictEqual(stats.stats.twitch.followers, 456);
  console.log('ok twitch login (device flow) + EventSub subscriptions + viewer/follower stats');

  // events -> notifications + automations
  const emit = (type, event) => fetch(`http://127.0.0.1:${MOCK}/_emit`, { method: 'POST', body: JSON.stringify({ metadata: { message_type: 'notification' }, payload: { subscription: { type }, event } }) });
  await emit('channel.follow', { user_name: 'NewFan' });
  const n = await c.next((x) => x.t === 'notify' && x.event.type === 'twitch.follow');
  assert.match(n.event.title, /NewFan followed/);
  await emit('channel.cheer', { user_name: 'Cheerer', bits: 10, message: 'small' });
  await emit('channel.cheer', { user_name: 'Cheerer', bits: 100, message: 'big' });
  await wait(1200);
  assert.match(fs.readFileSync(f('follow.txt'), 'utf8'), /NewFan/);
  assert.match(fs.readFileSync(f('bits.txt'), 'utf8'), /100/);
  console.log('ok notifications + automations (follow, cheer with minBits filter)');

  // chat + commands
  await c.rpc('chat.subscribe', { on: true });
  await emit('channel.chat.message', { message_id: 'm1', chatter_user_id: '5', chatter_user_login: 'fan', chatter_user_name: 'Fan', message: { text: '!hello world' }, badges: [{ set_id: 'moderator' }], color: '#ff0000' });
  const chat = await c.next((x) => x.t === 'chat');
  assert.strictEqual(chat.msg.user, 'Fan');
  assert.strictEqual(chat.msg.isMod, true);
  await wait(800);
  assert.match(fs.readFileSync(f('cmd.txt'), 'utf8'), /Fan world/);
  assert.strictEqual((await c.rpc('chat.recent')).length, 1);
  console.log('ok chat + chat-command automation');

  // moderation / actions
  const act = async (a) => { const rid = Math.floor(Math.random() * 1e6); c.sendj({ t: 'run', rid, action: a }); const r = await c.next((x) => x.t === 'result' && x.rid === rid); assert.ok(r.ok, JSON.stringify(a) + ' -> ' + r.error); };
  await act({ type: 'twitch', op: 'timeout', userId: '7', seconds: 60, reason: 'spam' });
  let ban = callsTo('/helix/moderation/bans', 'POST').pop();
  assert.deepStrictEqual(ban.body.data, { user_id: '7', duration: 60, reason: 'spam' });
  assert.strictEqual(ban.query.broadcaster_id, '42');
  assert.strictEqual(ban.query.moderator_id, '42');
  await act({ type: 'twitch', op: 'ban', user: 'baduser' }); // resolves login -> id 99
  ban = callsTo('/helix/moderation/bans', 'POST').pop();
  assert.strictEqual(ban.body.data.user_id, '99');
  await act({ type: 'twitch', op: 'deleteMessage', messageId: 'm1' });
  assert.strictEqual(callsTo('/helix/moderation/chat', 'DELETE').pop().query.message_id, 'm1');
  await act({ type: 'twitch', op: 'chatMode', mode: 'slow', state: 'toggle', value: 30 });
  const patch = callsTo('/helix/chat/settings', 'PATCH').pop();
  assert.deepStrictEqual(patch.body, { slow_mode: true, slow_mode_wait_time: 30 });
  await act({ type: 'twitch', op: 'shoutout', user: 'friend' });
  assert.strictEqual(callsTo('/helix/chat/shoutouts', 'POST').pop().query.to_broadcaster_id, '99');
  await act({ type: 'twitch', op: 'clip' });
  assert.strictEqual((await c.next((x) => x.t === 'notify' && x.event.type === 'twitch.clip')).event.detail, 'https://clips.twitch.tv/ClipXYZ');
  await act({ type: 'twitch', op: 'marker', text: 'cool moment' });
  await act({ type: 'twitch', op: 'announce', text: 'hi', color: 'blue' });
  await act({ type: 'twitch', op: 'say', text: 'hello chat' });
  assert.strictEqual(callsTo('/helix/chat/messages', 'POST').pop().body.message, 'hello chat');
  console.log('ok twitch moderation + actions (timeout, ban, delete, slow mode, shoutout, clip, marker, announce, say)');

  // expired token -> automatic refresh + retry
  await fetch(`http://127.0.0.1:${MOCK}/_expire`);
  await act({ type: 'twitch', op: 'say', text: 'after refresh' });
  assert.strictEqual(callsTo('/helix/chat/messages', 'POST').pop().auth, 'Bearer tok2');
  assert.ok(callsTo('/id/oauth2/token').some((l) => l.body.grant_type === 'refresh_token'));
  console.log('ok twitch token refresh on 401');

  // ===== YouTube
  await c.rpc('integrations.configure', { service: 'youtube', clientId: 'ycid', clientSecret: 'ysec' });
  const yl = await c.rpc('integrations.login', { service: 'youtube' });
  assert.strictEqual(yl.userCode, 'YT-CODE');
  await c.next((x) => x.t === 'integrations' && x.status.youtube.connected, 15000);
  const ys = await c.next((x) => x.t === 'integrations' && x.status.youtube.viewers === 77 && x.status.youtube.title === 'My Stream', 15000);
  assert.strictEqual(ys.status.youtube.live, true);
  await wait(7000); // second chat poll (poll interval is 5s)
  assert.match(fs.readFileSync(f('sc.txt'), 'utf8'), /viewersc 5/);
  assert.ok(fs.existsSync(f('ytcmd.txt')));
  await act({ type: 'youtube', op: 'say', text: 'hi youtube' });
  assert.strictEqual(callsTo('/yt/liveChat/messages', 'POST').pop().body.snippet.textMessageDetails.messageText, 'hi youtube');
  await act({ type: 'youtube', op: 'timeout', userId: 'UCx', seconds: 300 });
  const yb = callsTo('/yt/liveChat/bans', 'POST').pop().body.snippet;
  assert.deepStrictEqual([yb.type, yb.banDurationSeconds, yb.bannedUserDetails.channelId, yb.liveChatId], ['temporary', 300, 'UCx', 'chat1']);
  await act({ type: 'youtube', op: 'deleteMessage', messageId: 'msg9' });
  console.log('ok youtube login + chat poll + super chat/command automations + say/timeout/delete');

  // ===== Discord IPC
  await c.rpc('integrations.configure', { service: 'discord', clientId: 'dcid', clientSecret: 'dsec' });
  await c.rpc('integrations.login', { service: 'discord' });
  await c.next((x) => x.t === 'integrations' && x.status.discord.connected, 10000);
  assert.ok(log.some((l) => l.ipc === 'AUTHORIZE' && l.args.scopes.includes('rpc.voice.write')));
  await act({ type: 'discord', op: 'toggleMute' });
  const dm = await c.next((x) => x.t === 'integrations' && x.status.discord.mute === true);
  assert.strictEqual(dm.status.discord.connected, true);
  const dstats = await c.next((x) => x.t === 'stats' && x.stats.discord.mute === true, 5000);
  assert.strictEqual(dstats.stats.discord.connected, true);
  await act({ type: 'discord', op: 'unmute' });
  await c.next((x) => x.t === 'integrations' && x.status.discord.mute === false);
  console.log('ok discord IPC (handshake, authorize, authenticate, mute state sync)');

  s.stop();
  console.log('INTEGRATIONS PASSED');
})().catch((e) => { console.error('FAILED', e); process.exitCode = 1; })
  .finally(() => setTimeout(() => process.exit(), 300));
