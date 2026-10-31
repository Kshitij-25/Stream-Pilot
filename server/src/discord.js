'use strict';
// Discord via the local RPC (IPC) socket: real mute/deafen control and state. Needs a Discord application
// (discord.com/developers) with redirect URI http://localhost; its Client ID + secret go in the app.
// Discord shows an "Authorize" prompt in your desktop client the first time.
const net = require('net');
const { EventEmitter } = require('events');
const { addEvent } = require('./core');

const OP = { HANDSHAKE: 0, FRAME: 1, CLOSE: 2, PING: 3, PONG: 4 };
const API = process.env.DECKPAD_DISCORD_API_URL || 'https://discord.com/api';

function pipePath(i) {
  if (process.env.DECKPAD_DISCORD_PIPE) return `${process.env.DECKPAD_DISCORD_PIPE}${i}`;
  if (process.platform === 'win32') return `\\\\?\\pipe\\discord-ipc-${i}`;
  const base = process.env.XDG_RUNTIME_DIR || process.env.TMPDIR || '/tmp';
  return `${base}/discord-ipc-${i}`;
}

function encode(op, payload) {
  const data = Buffer.from(JSON.stringify(payload));
  const head = Buffer.alloc(8);
  head.writeInt32LE(op, 0);
  head.writeInt32LE(data.length, 4);
  return Buffer.concat([head, data]);
}

class DiscordService extends EventEmitter {
  constructor(store) {
    super();
    this.store = store;
    this.sock = null;
    this.buf = Buffer.alloc(0);
    this.nonce = 0;
    this.waiting = new Map();
    this.timer = null;
    this.stopped = true;
    this.ready = false;
    this.voice = { mute: false, deaf: false, inputVolume: null, outputVolume: null };
    this.error = null;
  }

  get cfg() {
    return this.store.settings.integrations.discord;
  }

  status() {
    return {
      configured: !!(this.cfg.clientId && this.cfg.clientSecret),
      connected: this.ready,
      error: this.error,
      ...this.voice,
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

  start() {
    this.stopped = false;
    if (!this.cfg.clientId || !this.cfg.clientSecret) return;
    this._connect(0);
  }

  stop() {
    this.stopped = true;
    clearTimeout(this.timer);
    this.ready = false;
    if (this.sock) {
      this.sock.removeAllListeners();
      this.sock.destroy();
      this.sock = null;
    }
  }

  logout() {
    this.stop();
    this.cfg.token = null;
    this.store.saveSettings();
    this._changed();
  }

  _retry() {
    if (this.stopped) return;
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this._connect(0), 6000);
    this.timer.unref();
  }

  _connect(i) {
    if (this.stopped) return;
    if (i > 9) {
      this.error = 'Discord is not running (or RPC is unavailable)';
      this._changed();
      return this._retry();
    }
    const sock = net.createConnection(pipePath(i));
    let opened = false;
    sock.on('connect', () => {
      opened = true;
      this.sock = sock;
      this.buf = Buffer.alloc(0);
      sock.write(encode(OP.HANDSHAKE, { v: 1, client_id: this.cfg.clientId }));
    });
    sock.on('data', (d) => this._onData(sock, d));
    sock.on('error', () => {
      if (!opened) this._connect(i + 1);
    });
    sock.on('close', () => {
      if (this.sock !== sock) return;
      this.sock = null;
      this.ready = false;
      for (const w of this.waiting.values()) w.reject(new Error('Discord disconnected'));
      this.waiting.clear();
      this._changed();
      this._retry();
    });
  }

  _onData(sock, d) {
    this.buf = Buffer.concat([this.buf, d]);
    while (this.buf.length >= 8) {
      const op = this.buf.readInt32LE(0);
      const len = this.buf.readInt32LE(4);
      if (this.buf.length < 8 + len) return;
      const body = this.buf.subarray(8, 8 + len).toString('utf8');
      this.buf = this.buf.subarray(8 + len);
      let msg = {};
      try { msg = JSON.parse(body); } catch {}
      if (op === OP.PING) sock.write(encode(OP.PONG, msg));
      else if (op === OP.CLOSE) {
        this.error = msg.message || 'Discord closed the connection';
        this._changed();
      } else this._onMessage(msg);
    }
  }

  async _onMessage(msg) {
    if (msg.nonce && this.waiting.has(msg.nonce)) {
      const w = this.waiting.get(msg.nonce);
      this.waiting.delete(msg.nonce);
      return msg.evt === 'ERROR' ? w.reject(new Error((msg.data && msg.data.message) || 'Discord error')) : w.resolve(msg.data);
    }
    if (msg.cmd === 'DISPATCH' && msg.evt === 'READY') {
      try {
        await this._authenticate();
      } catch (e) {
        this.error = e.message;
        this._changed();
      }
    } else if (msg.cmd === 'DISPATCH' && msg.evt === 'VOICE_SETTINGS_UPDATE') {
      this._voice(msg.data);
    }
  }

  _voice(d) {
    if (!d) return;
    this.voice = {
      mute: !!d.mute,
      deaf: !!d.deaf,
      inputVolume: d.input ? d.input.volume : this.voice.inputVolume,
      outputVolume: d.output ? d.output.volume : this.voice.outputVolume,
    };
    this._changed();
  }

  _call(cmd, args = {}, evt) {
    if (!this.sock) return Promise.reject(new Error('Discord is not connected'));
    const nonce = String(++this.nonce);
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => {
        this.waiting.delete(nonce);
        reject(new Error(cmd === 'AUTHORIZE' ? 'Authorization timed out: accept the prompt in Discord' : 'Discord did not answer'));
      }, cmd === 'AUTHORIZE' ? 120000 : 8000);
      this.waiting.set(nonce, {
        resolve: (v) => { clearTimeout(t); resolve(v); },
        reject: (e) => { clearTimeout(t); reject(e); },
      });
      this.sock.write(encode(OP.FRAME, { cmd, args, nonce, ...(evt ? { evt } : {}) }));
    });
  }

  async _token(params) {
    const res = await fetch(`${API}/oauth2/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: this.cfg.clientId, client_secret: this.cfg.clientSecret, redirect_uri: 'http://localhost', ...params }).toString(),
      signal: AbortSignal.timeout(15000),
    });
    const j = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(j.error_description || j.error || `Discord token error ${res.status}`);
    return j;
  }

  async _authenticate() {
    let token = this.cfg.token;
    if (token && Date.now() > token.expiresAt - 60000 && token.refresh) {
      try {
        const j = await this._token({ grant_type: 'refresh_token', refresh_token: token.refresh });
        token = this.cfg.token = { access: j.access_token, refresh: j.refresh_token, expiresAt: Date.now() + j.expires_in * 1000 };
        this.store.saveSettings();
      } catch {
        token = null;
      }
    }
    if (!token) {
      const { code } = await this._call('AUTHORIZE', { client_id: this.cfg.clientId, scopes: ['rpc', 'rpc.voice.read', 'rpc.voice.write'] });
      const j = await this._token({ grant_type: 'authorization_code', code });
      token = this.cfg.token = { access: j.access_token, refresh: j.refresh_token, expiresAt: Date.now() + j.expires_in * 1000 };
      this.store.saveSettings();
    }
    await this._call('AUTHENTICATE', { access_token: token.access });
    this.ready = true;
    this.error = null;
    this._voice(await this._call('GET_VOICE_SETTINGS'));
    await this._call('SUBSCRIBE', {}, 'VOICE_SETTINGS_UPDATE');
    addEvent({ type: 'discord.connected', platform: 'discord', title: 'Discord connected', detail: '' });
    this._changed();
  }

  async perform(a) {
    if (!this.ready) throw new Error('Discord is not connected (Integrations → Discord)');
    const set = (args) => this._call('SET_VOICE_SETTINGS', args).then((d) => this._voice(d));
    switch (a.op) {
      case 'toggleMute': return set({ mute: !this.voice.mute });
      case 'mute': return set({ mute: true });
      case 'unmute': return set({ mute: false });
      case 'toggleDeafen': return set({ deaf: !this.voice.deaf });
      case 'deafen': return set({ deaf: true });
      case 'undeafen': return set({ deaf: false });
      case 'inputVolume': return set({ input: { volume: Math.max(0, Math.min(100, Number(a.value) || 0)) } });
      case 'outputVolume': return set({ output: { volume: Math.max(0, Math.min(200, Number(a.value) || 0)) } });
      case 'leave': return this._call('SELECT_VOICE_CHANNEL', { channel_id: null });
      default: throw new Error(`Unknown Discord operation "${a.op}"`);
    }
  }
}

module.exports = { DiscordService, encode, OP };
