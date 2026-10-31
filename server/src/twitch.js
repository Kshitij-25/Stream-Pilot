'use strict';
// Twitch: OAuth (device code flow, public client), Helix actions + moderation, EventSub over WebSocket.
// You create a Twitch application (client type "Public") at dev.twitch.tv and paste its Client ID in the app.
const { EventEmitter } = require('events');
const WebSocket = require('ws');
const { bus, addEvent } = require('./core');

const ID_URL = process.env.DECKPAD_TWITCH_ID_URL || 'https://id.twitch.tv';
const API_URL = process.env.DECKPAD_TWITCH_API_URL || 'https://api.twitch.tv/helix';
const WS_URL = process.env.DECKPAD_TWITCH_WS_URL || 'wss://eventsub.wss.twitch.tv/ws';

const SCOPES = [
  'channel:manage:broadcast', 'clips:edit', 'channel:edit:commercial', 'channel:manage:raids',
  'moderator:manage:chat_settings', 'moderator:manage:banned_users', 'moderator:manage:chat_messages',
  'moderator:manage:announcements', 'moderator:manage:shoutouts', 'moderator:read:followers',
  'user:write:chat', 'user:read:chat', 'channel:read:subscriptions', 'bits:read', 'channel:read:redemptions',
];

const MODE_FIELDS = {
  slow: 'slow_mode',
  subs: 'subscriber_mode',
  emote: 'emote_mode',
  followers: 'follower_mode',
  unique: 'unique_chat_mode',
};

class TwitchService extends EventEmitter {
  constructor(store) {
    super();
    this.store = store;
    this.ws = null;
    this.wsTimer = null;
    this.pollTimer = null;
    this.pending = null; // { userCode, verificationUri, expiresAt }
    this.chat = []; // recent messages
    this.info = { live: false, viewers: null, followers: null, modes: {} };
    this.error = null;
    this.stopped = false;
  }

  get cfg() {
    return this.store.settings.integrations.twitch;
  }

  status() {
    const c = this.cfg;
    return {
      configured: !!c.clientId,
      connected: !!(c.token && c.user),
      user: c.user ? c.user.login : null,
      pending: this.pending ? { userCode: this.pending.userCode, verificationUri: this.pending.verificationUri } : null,
      error: this.error,
      ...this.info,
    };
  }

  _changed() {
    this.emit('status', this.status());
  }

  configure({ clientId }) {
    this.cfg.clientId = String(clientId || '').trim();
    this.store.saveSettings();
    this._changed();
  }

  // ---------- OAuth ----------
  async _form(url, params) {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(params).toString(),
      signal: AbortSignal.timeout(15000),
    });
    const body = await res.json().catch(() => ({}));
    return { ok: res.ok, status: res.status, body };
  }

  async login() {
    if (!this.cfg.clientId) throw new Error('Enter your Twitch Client ID first');
    this.error = null;
    const r = await this._form(`${ID_URL}/oauth2/device`, { client_id: this.cfg.clientId, scopes: SCOPES.join(' ') });
    if (!r.ok) throw new Error(r.body.message || `Twitch rejected the Client ID (${r.status}). It must be a Public client.`);
    const d = r.body;
    this.pending = { userCode: d.user_code, verificationUri: d.verification_uri, expiresAt: Date.now() + d.expires_in * 1000 };
    this._poll(d.device_code, Math.max(1, d.interval || 5));
    this._changed();
    return { userCode: d.user_code, verificationUri: d.verification_uri, expiresIn: d.expires_in };
  }

  _poll(deviceCode, interval) {
    clearTimeout(this.pollTimer);
    this.pollTimer = setTimeout(async () => {
      if (!this.pending) return;
      if (Date.now() > this.pending.expiresAt) {
        this.pending = null;
        this.error = 'Login code expired. Try again.';
        return this._changed();
      }
      try {
        const r = await this._form(`${ID_URL}/oauth2/token`, {
          client_id: this.cfg.clientId,
          scopes: SCOPES.join(' '),
          device_code: deviceCode,
          grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
        });
        if (r.ok) {
          this._setToken(r.body);
          this.pending = null;
          await this._loadUser();
          this.start();
          return this._changed();
        }
        if (!/authorization_pending|slow_down/i.test(r.body.message || '')) {
          this.pending = null;
          this.error = r.body.message || 'Login failed';
          return this._changed();
        }
      } catch {
        /* transient network error: keep polling */
      }
      this._poll(deviceCode, interval);
    }, interval * 1000);
    this.pollTimer.unref();
  }

  _setToken(t) {
    this.cfg.token = {
      access: t.access_token,
      refresh: t.refresh_token || (this.cfg.token && this.cfg.token.refresh),
      expiresAt: Date.now() + (t.expires_in || 3600) * 1000,
    };
    this.store.saveSettings();
  }

  async _refresh() {
    const t = this.cfg.token;
    if (!t || !t.refresh) throw new Error('Twitch login expired. Log in again.');
    const r = await this._form(`${ID_URL}/oauth2/token`, {
      client_id: this.cfg.clientId,
      grant_type: 'refresh_token',
      refresh_token: t.refresh,
    });
    if (!r.ok) {
      this.cfg.token = null;
      this.store.saveSettings();
      this._changed();
      throw new Error('Twitch login expired. Log in again.');
    }
    this._setToken(r.body);
  }

  logout() {
    this.stop();
    clearTimeout(this.pollTimer);
    this.pending = null;
    this.cfg.token = null;
    this.cfg.user = null;
    this.info = { live: false, viewers: null, followers: null, modes: {} };
    this.store.saveSettings();
    this._changed();
  }

  async _loadUser() {
    const d = await this.helix('GET', '/users');
    const u = d.data && d.data[0];
    if (!u) throw new Error('Could not read the Twitch user');
    this.cfg.user = { id: u.id, login: u.login, name: u.display_name };
    this.store.saveSettings();
  }

  // ---------- Helix ----------
  async helix(method, path, { query, body } = {}, retry = true) {
    const t = this.cfg.token;
    if (!t) throw new Error('Twitch is not connected (Integrations → Twitch)');
    if (Date.now() > t.expiresAt - 60000) await this._refresh();
    const url = new URL(API_URL + path);
    for (const [k, v] of Object.entries(query || {})) if (v !== undefined && v !== null) url.searchParams.set(k, v);
    const res = await fetch(url, {
      method,
      headers: {
        'Client-Id': this.cfg.clientId,
        Authorization: `Bearer ${this.cfg.token.access}`,
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(15000),
    });
    if (res.status === 401 && retry) {
      await this._refresh();
      return this.helix(method, path, { query, body }, false);
    }
    const text = await res.text();
    const json = text ? JSON.parse(text) : {};
    if (!res.ok) throw new Error(json.message || `Twitch error ${res.status}`);
    return json;
  }

  get uid() {
    if (!this.cfg.user) throw new Error('Twitch is not connected (Integrations → Twitch)');
    return this.cfg.user.id;
  }

  async userId(login) {
    const name = String(login || '').replace(/^@/, '').trim();
    if (!name) throw new Error('No user name given');
    const d = await this.helix('GET', '/users', { query: { login: name } });
    if (!d.data || !d.data[0]) throw new Error(`Twitch user "${name}" not found`);
    return d.data[0].id;
  }

  // ---------- actions ----------
  async perform(a) {
    const me = () => ({ broadcaster_id: this.uid, moderator_id: this.uid });
    switch (a.op) {
      case 'marker':
        return this.helix('POST', '/streams/markers', { body: { user_id: this.uid, description: a.text || 'DeckPad marker' } });
      case 'clip': {
        const d = await this.helix('POST', '/clips', { query: { broadcaster_id: this.uid } });
        const id = d.data && d.data[0] && d.data[0].id;
        if (id) addEvent({ type: 'twitch.clip', title: 'Clip created', detail: `https://clips.twitch.tv/${id}` });
        return;
      }
      case 'title':
        return this.helix('PATCH', '/channels', { query: { broadcaster_id: this.uid }, body: { title: String(a.text || '') } });
      case 'category': {
        const d = await this.helix('GET', '/search/categories', { query: { query: a.text, first: 1 } });
        if (!d.data || !d.data[0]) throw new Error(`Category "${a.text}" not found`);
        return this.helix('PATCH', '/channels', { query: { broadcaster_id: this.uid }, body: { game_id: d.data[0].id } });
      }
      case 'say':
        return this.helix('POST', '/chat/messages', { body: { broadcaster_id: this.uid, sender_id: this.uid, message: String(a.text || '') } });
      case 'announce':
        return this.helix('POST', '/chat/announcements', { query: me(), body: { message: String(a.text || ''), color: a.color || 'primary' } });
      case 'clearChat':
        return this.helix('DELETE', '/moderation/chat', { query: me() });
      case 'deleteMessage':
        return this.helix('DELETE', '/moderation/chat', { query: { ...me(), message_id: a.messageId } });
      case 'timeout':
        return this.helix('POST', '/moderation/bans', {
          query: me(),
          body: { data: { user_id: a.userId || (await this.userId(a.user)), duration: Number(a.seconds) || 600, reason: a.reason || '' } },
        });
      case 'ban':
        return this.helix('POST', '/moderation/bans', {
          query: me(),
          body: { data: { user_id: a.userId || (await this.userId(a.user)), reason: a.reason || '' } },
        });
      case 'unban':
        return this.helix('DELETE', '/moderation/bans', { query: { ...me(), user_id: a.userId || (await this.userId(a.user)) } });
      case 'shoutout':
        return this.helix('POST', '/chat/shoutouts', {
          query: { from_broadcaster_id: this.uid, to_broadcaster_id: a.userId || (await this.userId(a.user)), moderator_id: this.uid },
        });
      case 'raid':
        return this.helix('POST', '/raids', { query: { from_broadcaster_id: this.uid, to_broadcaster_id: await this.userId(a.user) } });
      case 'ad':
        return this.helix('POST', '/channels/commercial', { body: { broadcaster_id: this.uid, length: Number(a.length) || 60 } });
      case 'chatMode':
        return this._chatMode(a, me());
      default:
        throw new Error(`Unknown Twitch operation "${a.op}"`);
    }
  }

  async _chatMode(a, ids) {
    const field = MODE_FIELDS[a.mode];
    if (!field) throw new Error(`Unknown chat mode "${a.mode}"`);
    const cur = (await this.helix('GET', '/chat/settings', { query: ids })).data[0];
    const next = a.state === 'on' ? true : a.state === 'off' ? false : !cur[field];
    const body = { [field]: next };
    if (next && a.mode === 'slow') body.slow_mode_wait_time = Number(a.value) || 10;
    if (next && a.mode === 'followers') body.follower_mode_duration = Number(a.value) || 0;
    await this.helix('PATCH', '/chat/settings', { query: ids, body });
    this.info.modes = { ...this.info.modes, [a.mode]: next };
    this._changed();
  }

  // ---------- background: EventSub + stats ----------
  start() {
    this.stopped = false;
    if (!this.cfg.token || !this.cfg.user) return;
    this._connectWs(WS_URL, true);
    this._refreshStats();
    clearInterval(this.statsTimer);
    this.statsTimer = setInterval(() => this._refreshStats(), 30000);
    this.statsTimer.unref();
  }

  stop() {
    this.stopped = true;
    clearTimeout(this.wsTimer);
    clearInterval(this.statsTimer);
    if (this.ws) {
      this.ws.removeAllListeners();
      try { this.ws.close(); } catch {}
      this.ws = null;
    }
  }

  async _refreshStats() {
    try {
      const s = await this.helix('GET', '/streams', { query: { user_id: this.uid } });
      const live = s.data && s.data[0];
      this.info.live = !!live;
      this.info.viewers = live ? live.viewer_count : null;
      const f = await this.helix('GET', '/channels/followers', { query: { broadcaster_id: this.uid, first: 1 } });
      this.info.followers = f.total;
      const c = (await this.helix('GET', '/chat/settings', { query: { broadcaster_id: this.uid, moderator_id: this.uid } })).data[0];
      this.info.modes = { slow: c.slow_mode, subs: c.subscriber_mode, emote: c.emote_mode, followers: c.follower_mode, unique: c.unique_chat_mode };
      this._changed();
    } catch {
      /* stats are best-effort */
    }
  }

  _connectWs(url, subscribe) {
    if (this.stopped) return;
    const ws = new WebSocket(url);
    const old = this.ws;
    this.ws = ws;
    let watchdog = null;
    const arm = (sec) => {
      clearTimeout(watchdog);
      watchdog = setTimeout(() => ws.terminate(), (sec + 10) * 1000);
      watchdog.unref();
    };
    ws.on('message', async (raw) => {
      let m;
      try { m = JSON.parse(raw.toString()); } catch { return; }
      const type = m.metadata && m.metadata.message_type;
      if (type === 'session_welcome') {
        arm(m.payload.session.keepalive_timeout_seconds || 10);
        if (old && old !== ws) {
          old.removeAllListeners();
          try { old.close(); } catch {}
        }
        if (subscribe) {
          try { await this._subscribeAll(m.payload.session.id); } catch (e) { this.error = e.message; this._changed(); }
        }
      } else if (type === 'session_keepalive') {
        arm(10);
      } else if (type === 'notification') {
        arm(10);
        this._onNotification(m.payload.subscription.type, m.payload.event);
      } else if (type === 'session_reconnect') {
        this._connectWs(m.payload.session.reconnect_url, false);
      }
    });
    ws.on('error', () => {});
    ws.on('close', () => {
      clearTimeout(watchdog);
      if (this.ws !== ws || this.stopped) return;
      this.wsTimer = setTimeout(() => this._connectWs(WS_URL, true), 5000);
      this.wsTimer.unref();
    });
  }

  async _subscribeAll(sessionId) {
    const u = this.uid;
    const subs = [
      ['channel.follow', '2', { broadcaster_user_id: u, moderator_user_id: u }],
      ['channel.subscribe', '1', { broadcaster_user_id: u }],
      ['channel.subscription.gift', '1', { broadcaster_user_id: u }],
      ['channel.subscription.message', '1', { broadcaster_user_id: u }],
      ['channel.cheer', '1', { broadcaster_user_id: u }],
      ['channel.raid', '1', { to_broadcaster_user_id: u }],
      ['channel.channel_points_custom_reward_redemption.add', '1', { broadcaster_user_id: u }],
      ['channel.chat.message', '1', { broadcaster_user_id: u, user_id: u }],
      ['stream.online', '1', { broadcaster_user_id: u }],
      ['stream.offline', '1', { broadcaster_user_id: u }],
    ];
    const failed = [];
    for (const [type, version, condition] of subs) {
      try {
        await this.helix('POST', '/eventsub/subscriptions', {
          body: { type, version, condition, transport: { method: 'websocket', session_id: sessionId } },
        });
      } catch (e) {
        failed.push(`${type}: ${e.message}`);
      }
    }
    this.error = failed.length ? `Some event subscriptions failed (${failed.length}). Log in again to grant all permissions.` : null;
    this._changed();
  }

  _onNotification(type, e) {
    const notify = (kind, title, detail, vars) => {
      addEvent({ type: `twitch.${kind}`, platform: 'twitch', title, detail });
      bus.emit('event', { type: `twitch.${kind}`, platform: 'twitch', ...vars });
    };
    switch (type) {
      case 'channel.follow':
        return notify('follow', `${e.user_name} followed`, '', { user: e.user_name });
      case 'channel.subscribe':
        if (e.is_gift) return;
        return notify('sub', `${e.user_name} subscribed`, `Tier ${Number(e.tier) / 1000}`, { user: e.user_name, tier: e.tier });
      case 'channel.subscription.message':
        return notify('sub', `${e.user_name} resubscribed`, e.message ? e.message.text : '', { user: e.user_name, months: e.cumulative_months });
      case 'channel.subscription.gift':
        return notify('gift', `${e.user_name || 'Anonymous'} gifted ${e.total} sub(s)`, '', { user: e.user_name, amount: e.total });
      case 'channel.cheer':
        return notify('cheer', `${e.user_name || 'Anonymous'} cheered ${e.bits} bits`, e.message, { user: e.user_name, bits: e.bits, message: e.message });
      case 'channel.raid':
        return notify('raid', `${e.from_broadcaster_user_name} raided with ${e.viewers}`, '', { user: e.from_broadcaster_user_name, viewers: e.viewers });
      case 'channel.channel_points_custom_reward_redemption.add':
        return notify('redeem', `${e.user_name} redeemed ${e.reward.title}`, e.user_input || '', { user: e.user_name, reward: e.reward.title, message: e.user_input });
      case 'stream.online':
        this.info.live = true;
        this._changed();
        return notify('online', 'Stream went live', '', {});
      case 'stream.offline':
        this.info.live = false;
        this._changed();
        return notify('offline', 'Stream ended', '', {});
      case 'channel.chat.message':
        return this._onChat(e);
    }
  }

  _onChat(e) {
    const badges = (e.badges || []).map((b) => b.set_id);
    const msg = {
      platform: 'twitch',
      id: e.message_id,
      userId: e.chatter_user_id,
      user: e.chatter_user_name,
      login: e.chatter_user_login,
      text: e.message && e.message.text,
      color: e.color || null,
      isMod: badges.includes('moderator') || badges.includes('broadcaster'),
      isSub: badges.includes('subscriber'),
      ts: Date.now(),
    };
    this.chat.push(msg);
    if (this.chat.length > 200) this.chat.shift();
    this.emit('chat', msg);
    const text = String(msg.text || '');
    if (text.startsWith('!')) {
      const [command, ...args] = text.split(/\s+/);
      bus.emit('event', { type: 'twitch.chatCommand', platform: 'twitch', command, args: args.join(' '), user: msg.user, message: text, isMod: msg.isMod });
    }
  }
}

module.exports = { TwitchService, SCOPES };
