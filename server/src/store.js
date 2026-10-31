'use strict';
// Persistent storage: layout config + settings (OBS creds, paired device tokens).
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const DIR = process.env.DECKPAD_HOME || path.join(os.homedir(), '.deckpad');
const CONFIG_FILE = path.join(DIR, 'config.json');
const SETTINGS_FILE = path.join(DIR, 'settings.json');

function ensureDir() {
  fs.mkdirSync(DIR, { recursive: true });
}

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return fallback;
  }
}

function writeJson(file, data) {
  ensureDir();
  const tmp = file + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
  fs.renameSync(tmp, file);
}

let nextId = 0;
const uid = () => `b${Date.now().toString(36)}${(nextId++).toString(36)}`;

function btn(label, icon, color, action) {
  return { id: uid(), label, icon, color, action };
}

function defaultConfig() {
  const cols = 4;
  const rows = 4;
  const home = new Array(cols * rows).fill(null);
  home[0] = btn('Start Stream', '🔴', '#c62828', { type: 'obs', op: 'toggleStream' });
  home[1] = btn('Record', '⏺️', '#ad1457', { type: 'obs', op: 'toggleRecord' });
  home[2] = btn('Mute Mic', '🎙️', '#ef6c00', { type: 'obs', op: 'toggleMute', input: 'Mic/Aux' });
  home[3] = btn('Desktop', '🔊', '#f9a825', { type: 'obs', op: 'toggleMute', input: 'Desktop Audio' });
  home[4] = btn('Scene 1', '🎮', '#1565c0', { type: 'obs', op: 'scene', scene: 'Scene' });
  home[5] = btn('Scene 2', '💬', '#00838f', { type: 'obs', op: 'scene', scene: 'Scene 2' });
  home[6] = btn('BRB', '☕', '#6a1b9a', { type: 'obs', op: 'scene', scene: 'BRB' });
  home[7] = btn('Discord Mute', '🔇', '#4527a0', { type: 'hotkey', keys: 'ctrl+shift+m' });
  home[8] = btn('Play/Pause', '⏯️', '#2e7d32', { type: 'media', key: 'playpause' });
  home[9] = btn('Prev', '⏮️', '#388e3c', { type: 'media', key: 'prev' });
  home[10] = btn('Next', '⏭️', '#388e3c', { type: 'media', key: 'next' });
  home[11] = btn('Mute PC', '🔈', '#455a64', { type: 'media', key: 'mute' });
  home[12] = btn('Apps', '📁', '#37474f', { type: 'folder', page: 'apps' });
  home[13] = btn('Chat', '💭', '#5d4037', { type: 'open', target: 'https://www.twitch.tv/popout/' });
  home[14] = btn('Screenshot', '📸', '#283593', { type: 'hotkey', keys: 'win+shift+s' });

  const apps = new Array(cols * rows).fill(null);
  apps[0] = btn('Back', '⬅️', '#424242', { type: 'back' });
  apps[1] = btn('OBS', '🎬', '#263238', { type: 'open', target: 'obs64.exe' });
  apps[2] = btn('Discord', '💬', '#5865f2', { type: 'open', target: 'discord://' });
  apps[3] = btn('Spotify', '🎵', '#1db954', { type: 'open', target: 'spotify:' });
  apps[4] = btn('Notepad', '📝', '#546e7a', { type: 'open', target: 'notepad.exe' });
  apps[5] = btn('GG', '👏', '#00897b', { type: 'text', text: 'GG!', enter: true });

  return {
    version: 1,
    name: 'DeckPad',
    cols,
    rows,
    rootPage: 'home',
    pages: {
      home: { id: 'home', name: 'Home', buttons: home },
      apps: { id: 'apps', name: 'Apps', buttons: apps },
    },
  };
}

function defaultSettings() {
  return {
    obs: { host: '127.0.0.1', port: 4455, password: '' },
    tokens: [], // [{ hash, name, createdAt }]
  };
}

const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');

function normalizeConfig(cfg) {
  if (!cfg || typeof cfg !== 'object' || !cfg.pages || typeof cfg.pages !== 'object') {
    throw new Error('invalid config');
  }
  const cols = Math.min(10, Math.max(1, parseInt(cfg.cols, 10) || 4));
  const rows = Math.min(10, Math.max(1, parseInt(cfg.rows, 10) || 4));
  const pages = {};
  for (const [id, p] of Object.entries(cfg.pages)) {
    const buttons = new Array(cols * rows).fill(null);
    (p.buttons || []).slice(0, cols * rows).forEach((b, i) => {
      if (b && typeof b === 'object') buttons[i] = { ...b, id: b.id || uid() };
    });
    pages[id] = { id, name: String(p.name || id), buttons };
  }
  if (!Object.keys(pages).length) throw new Error('config needs at least one page');
  const rootPage = pages[cfg.rootPage] ? cfg.rootPage : Object.keys(pages)[0];
  return { version: 1, name: String(cfg.name || 'DeckPad'), cols, rows, rootPage, pages };
}

class Store {
  constructor() {
    ensureDir();
    this.config = readJson(CONFIG_FILE, null);
    try {
      this.config = this.config ? normalizeConfig(this.config) : defaultConfig();
    } catch {
      this.config = defaultConfig();
    }
    this.settings = { ...defaultSettings(), ...readJson(SETTINGS_FILE, {}) };
    this.saveConfig(this.config);
    this.saveSettings();
  }

  saveConfig(cfg) {
    this.config = normalizeConfig(cfg);
    writeJson(CONFIG_FILE, this.config);
    return this.config;
  }

  saveSettings() {
    writeJson(SETTINGS_FILE, this.settings);
  }

  findButton(id) {
    for (const page of Object.values(this.config.pages)) {
      const b = page.buttons.find((x) => x && x.id === id);
      if (b) return b;
    }
    return null;
  }

  addToken(name) {
    const token = crypto.randomBytes(24).toString('hex');
    this.settings.tokens.push({ hash: sha(token), name: String(name || 'device').slice(0, 60), createdAt: Date.now() });
    this.saveSettings();
    return token;
  }

  checkToken(token) {
    if (!token || typeof token !== 'string') return false;
    const h = sha(token);
    return this.settings.tokens.some((t) => t.hash === h);
  }
}

module.exports = { Store, DIR, uid };
