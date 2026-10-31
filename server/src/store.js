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

const { defaultConfig, uid } = require('./defaults');

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
    pages[id] = { id, name: String(p.name || id), icon: p.icon ? String(p.icon) : '', pinned: !!p.pinned, buttons };
  }
  if (!Object.keys(pages).length) throw new Error('config needs at least one page');
  const rootPage = pages[cfg.rootPage] ? cfg.rootPage : Object.keys(pages)[0];
  return { version: 2, name: String(cfg.name || 'DeckPad'), cols, rows, rootPage, pages };
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
