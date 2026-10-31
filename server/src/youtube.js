'use strict';
// YouTube Live: OAuth device flow (Google "TV and limited-input" client), live chat read/send, moderation, go live / end.
// Needs a Google Cloud OAuth client ID + secret (type "TV and Limited Input devices") with the YouTube Data API enabled.
const { EventEmitter } = require('events');
const { bus, addEvent } = require('./core');

const OAUTH = process.env.DECKPAD_GOOGLE_OAUTH_URL || 'https://oauth2.googleapis.com';
const API = process.env.DECKPAD_YT_API_URL || 'https://www.googleapis.com/youtube/v3';
const SCOPE = 'https://www.googleapis.com/auth/youtube';

class YouTubeService extends EventEmitter {
  constructor(store) {
    super();
    this.store = store;
    this.pending = null;
    this.pollTimer = null;
    this.loopTimer = null;
    this.broadcast = null; // { id, videoId, liveChatId, title }
    this.pageToken = null;
    this.first = true;
    this.chat = [];
    this.info = { live: false, viewers: null };
    this.error = null;
    this.stopped = true;
  }

  get cfg() {
    return this.store.settings.integrations.youtube;
  }

  status() {
    const c = this.cfg;
    return {
      configured: !!(c.clientId && c.clientSecret),
      connected: !!c.token,
      pending: this.pending ? { userCode: this.pending.userCode, verificationUri: this.pending.verificationUri } : null,
      error: this.error,
      title: this.broadcast ? this.broadcast.title : null,
      ...this.info,
    };
  }

  _changed() {
    this.emit('status', this.status());
  }

  configure({ clientId, clientSecret }) {
    this.cfg.clientId = String(clientId || '').trim();
    if (clientSecret) this.cfg.clientSecret = String(clientSecret).trim();
    this.store.saveSettings();
    this._changed();
  }

  async _form(path, params) {
    const res = await fetch(`${OAUTH}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(params).toString(),
      signal: AbortSignal.timeout(15000),
    });
    return { ok: res.ok, status: res.status, body: await res.json().catch(() => ({})) };
  }

  async login() {
    if (!this.cfg.clientId || !this.cfg.clientSecret) throw new Error('Enter your Google Client ID and secret first');
    this.error = null;
    const r = await this._form('/device/code', { client_id: this.cfg.clientId, scope: SCOPE });
    if (!r.ok) throw new Error(r.body.error_description || r.body.error || `Google rejected the client (${r.status})`);
    const d = r.body;
    this.pending = { userCode: d.user_code, verificationUri: d.verification_url || d.verification_uri, expiresAt: Date.now() + d.expires_in * 1000 };
    this._poll(d.device_code, Math.max(1, d.interval || 5));
    this._changed();
    return { userCode: d.user_code, verificationUri: this.pending.verificationUri, expiresIn: d.expires_in };
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
        const r = await this._form('/token', {
          client_id: this.cfg.clientId,
          client_secret: this.cfg.clientSecret,
          device_code: deviceCode,
          grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
        });
        if (r.ok) {
          this._setToken(r.body);
          this.pending = null;
          this.start();
          return this._changed();
        }
        if (!/authorization_pending|slow_down/i.test(r.body.error || '')) {
          this.pending = null;
          this.error = r.body.error_description || r.body.error || 'Login failed';
          return this._changed();
        }
      } catch {}
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
    if (!t || !t.refresh) throw new Error('YouTube login expired. Log in again.');
    const r = await this._form('/token', {
      client_id: this.cfg.clientId,
      client_secret: this.cfg.clientSecret,
      grant_type: 'refresh_token',
      refresh_token: t.refresh,
    });
    if (!r.ok) {
      this.cfg.token = null;
      this.store.saveSettings();
      this._changed();
      throw new Error('YouTube login expired. Log in again.');
    }
    this._setToken(r.body);
  }

  logout() {
    this.stop();
    clearTimeout(this.pollTimer);
    this.pending = null;
    this.cfg.token = null;
    this.broadcast = null;
    this.info = { live: false, viewers: null };
    this.store.saveSettings();
    this._changed();
  }

  async api(method, path, { query, body } = {}, retry = true) {
    const t = this.cfg.token;
    if (!t) throw new Error('YouTube is not connected (Integrations → YouTube)');
    if (Date.now() > t.expiresAt - 60000) await this._refresh();
    const url = new URL(API + path);
    for (const [k, v] of Object.entries(query || {})) if (v !== undefined && v !== null) url.searchParams.set(k, v);
    const res = await fetch(url, {
      method,
      headers: { Authorization: `Bearer ${this.cfg.token.access}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(15000),
    });
    if (res.status === 401 && retry) {
      await this._refresh();
      return this.api(method, path, { query, body }, false);
    }
    const text = await res.text();
    const json = text ? JSON.parse(text) : {};
    if (!res.ok) throw new Error((json.error && json.error.message) || `YouTube error ${res.status}`);
    return json;
  }

  async _findBroadcast(status = 'active') {
    const d = await this.api('GET', '/liveBroadcasts', { query: { part: 'snippet,status', broadcastStatus: status, mine: 'true' } });
    const b = d.items && d.items[0];
    return b ? { id: b.id, videoId: b.id, liveChatId: b.snippet.liveChatId, title: b.snippet.title } : null;
  }

  // ---------- actions ----------
  async perform(a) {
    switch (a.op) {
      case 'say': {
        const b = await this._need();
        return this.api('POST', '/liveChat/messages', {
          query: { part: 'snippet' },
          body: { snippet: { liveChatId: b.liveChatId, type: 'textMessageEvent', textMessageDetails: { messageText: String(a.text || '') } } },
        });
      }
      case 'goLive': {
        const b = await this._findBroadcast('upcoming');
        if (!b) throw new Error('No upcoming broadcast. Create one in YouTube Studio first.');
        return this.api('POST', '/liveBroadcasts/transition', { query: { part: 'status', broadcastStatus: 'live', id: b.id } });
      }
      case 'endStream': {
        const b = await this._need();
        return this.api('POST', '/liveBroadcasts/transition', { query: { part: 'status', broadcastStatus: 'complete', id: b.id } });
      }
      case 'timeout':
      case 'ban': {
        const b = await this._need();
        const snippet = { liveChatId: b.liveChatId, type: a.op === 'ban' ? 'permanent' : 'temporary', bannedUserDetails: { channelId: a.userId } };
        if (a.op === 'timeout') snippet.banDurationSeconds = Number(a.seconds) || 600;
        return this.api('POST', '/liveChat/bans', { query: { part: 'snippet' }, body: { snippet } });
      }
      case 'deleteMessage':
        return this.api('DELETE', '/liveChat/messages', { query: { id: a.messageId } });
      default:
        throw new Error(`Unknown YouTube operation "${a.op}"`);
    }
  }

  async _need() {
    if (!this.broadcast) this.broadcast = await this._findBroadcast('active');
    if (!this.broadcast) throw new Error('No active YouTube live broadcast');
    return this.broadcast;
  }

  // ---------- chat polling ----------
  start() {
    this.stopped = false;
    if (!this.cfg.token) return;
    clearTimeout(this.loopTimer);
    this._loop();
  }

  stop() {
    this.stopped = true;
    clearTimeout(this.loopTimer);
  }

  async _loop() {
    if (this.stopped) return;
    let wait = 30000;
    try {
      if (!this.broadcast) {
        this.broadcast = await this._findBroadcast('active');
        this.pageToken = null;
        this.first = true;
        if (this.broadcast) bus.emit('event', { type: 'youtube.online', platform: 'youtube' });
      }
      if (this.broadcast) {
        const d = await this.api('GET', '/liveChat/messages', {
          query: { liveChatId: this.broadcast.liveChatId, part: 'snippet,authorDetails', pageToken: this.pageToken },
        });
        this.pageToken = d.nextPageToken;
        this._ingest(d.items || []);
        this.first = false;
        wait = Math.max(5000, d.pollingIntervalMillis || 6000);
        const v = await this.api('GET', '/videos', { query: { part: 'liveStreamingDetails', id: this.broadcast.videoId } });
        const det = v.items && v.items[0] && v.items[0].liveStreamingDetails;
        this.info = { live: !(det && det.actualEndTime), viewers: det && det.concurrentViewers ? Number(det.concurrentViewers) : null };
        if (det && det.actualEndTime) {
          this.broadcast = null;
          bus.emit('event', { type: 'youtube.offline', platform: 'youtube' });
        }
        this.error = null;
      } else {
        this.info = { live: false, viewers: null };
      }
      this._changed();
    } catch (e) {
      this.error = e.message;
      this.broadcast = null; // chat ended / quota / auth: re-detect next round
      this._changed();
    }
    this.loopTimer = setTimeout(() => this._loop(), wait);
    this.loopTimer.unref();
  }

  _ingest(items) {
    for (const it of items) {
      const s = it.snippet || {};
      const a = it.authorDetails || {};
      const text = s.displayMessage || (s.textMessageDetails && s.textMessageDetails.messageText) || '';
      const msg = {
        platform: 'youtube', id: it.id, userId: a.channelId, user: a.displayName, text,
        isMod: !!(a.isChatModerator || a.isChatOwner), isSub: !!a.isChatSponsor, ts: Date.parse(s.publishedAt) || Date.now(),
      };
      this.chat.push(msg);
      if (this.chat.length > 200) this.chat.shift();
      this.emit('chat', msg);
      if (this.first) continue; // history from before we started watching: don't fire events
      if (s.type === 'superChatEvent' && s.superChatDetails) {
        const amount = Number(s.superChatDetails.amountMicros) / 1e6;
        addEvent({ type: 'youtube.superchat', platform: 'youtube', title: `${a.displayName} sent ${s.superChatDetails.amountDisplayString}`, detail: text });
        bus.emit('event', { type: 'youtube.superchat', platform: 'youtube', user: a.displayName, amount, message: text });
      } else if (s.type === 'newSponsorEvent') {
        addEvent({ type: 'youtube.member', platform: 'youtube', title: `${a.displayName} became a member`, detail: '' });
        bus.emit('event', { type: 'youtube.member', platform: 'youtube', user: a.displayName });
      } else if (text.startsWith('!')) {
        const [command, ...args] = text.split(/\s+/);
        bus.emit('event', { type: 'youtube.chatCommand', platform: 'youtube', command, args: args.join(' '), user: a.displayName, message: text, isMod: msg.isMod });
      }
    }
  }
}

module.exports = { YouTubeService };
