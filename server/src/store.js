'use strict';
// Persistent storage under ~/.deckpad:
//   profiles/<id>.json   one deck layout per profile ({ id, name, config })
//   settings.json        OBS credentials, paired devices, integrations, active profile
//   automations.json     trigger rules
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { defaultConfig, uid } = require('./defaults');

const DIR = process.env.DECKPAD_HOME || path.join(os.homedir(), '.deckpad');
const PROFILES_DIR = path.join(DIR, 'profiles');
const SETTINGS_FILE = path.join(DIR, 'settings.json');
const AUTOMATIONS_FILE = path.join(DIR, 'automations.json');
const LEGACY_CONFIG = path.join(DIR, 'config.json');
const CONFIG_VERSION = 3;

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return fallback;
  }
}

function writeJson(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = file + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
  fs.renameSync(tmp, file);
}

const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const slug = (s) => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'profile';

function defaultSettings() {
  return {
    obs: { host: '127.0.0.1', port: 4455, password: '' },
    tokens: [], // [{ id, hash, name, createdAt, lastSeen }]
    activeProfile: null,
    integrations: { twitch: {}, youtube: {}, discord: {} },
  };
}

function normalizeConfig(cfg) {
  if (!cfg || typeof cfg !== 'object' || !cfg.pages || typeof cfg.pages !== 'object') {
    throw new Error('invalid config');
  }
  const cols = Math.min(10, Math.max(1, parseInt(cfg.cols, 10) || 5));
  const rows = Math.min(10, Math.max(1, parseInt(cfg.rows, 10) || 3));
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
  return { version: CONFIG_VERSION, name: String(cfg.name || 'DeckPad'), cols, rows, rootPage, pages };
}

class Store {
  constructor() {
    fs.mkdirSync(PROFILES_DIR, { recursive: true });
    this.settings = { ...defaultSettings(), ...readJson(SETTINGS_FILE, {}) };
    this.settings.integrations = { twitch: {}, youtube: {}, discord: {}, ...this.settings.integrations };
    // Older tokens had no id.
    for (const t of this.settings.tokens) if (!t.id) t.id = crypto.randomBytes(6).toString('hex');

    this.migratedFrom = null;
    if (fs.existsSync(LEGACY_CONFIG)) {
      // Pre-profile layouts (v1/v2) only had one or two pages. Keep a backup, start from the new defaults.
      const old = readJson(LEGACY_CONFIG, null);
      this.migratedFrom = old && old.version ? old.version : 1;
      fs.renameSync(LEGACY_CONFIG, path.join(DIR, `config.v${this.migratedFrom}.bak.json`));
    }

    this.profiles = {};
    for (const f of fs.readdirSync(PROFILES_DIR)) {
      if (!f.endsWith('.json')) continue;
      const p = readJson(path.join(PROFILES_DIR, f), null);
      if (!p || !p.id) continue;
      try {
        this.profiles[p.id] = { id: p.id, name: p.name || p.id, config: normalizeConfig(p.config) };
      } catch {}
    }
    if (!Object.keys(this.profiles).length) {
      this.createProfile('Streaming', defaultConfig('streaming'));
      this.createProfile('Desktop', defaultConfig('desktop'));
      this.settings.activeProfile = 'streaming';
    }
    if (!this.profiles[this.settings.activeProfile]) this.settings.activeProfile = Object.keys(this.profiles)[0];
    this.saveSettings();

    this.automations = readJson(AUTOMATIONS_FILE, null);
    if (!Array.isArray(this.automations)) {
      this.automations = defaultAutomations();
      writeJson(AUTOMATIONS_FILE, this.automations);
    }
  }

  // ---- profiles
  get activeProfile() {
    return this.settings.activeProfile;
  }

  profile(id) {
    return this.profiles[id] || this.profiles[this.activeProfile];
  }

  listProfiles() {
    return Object.values(this.profiles).map((p) => ({ id: p.id, name: p.name }));
  }

  _writeProfile(p) {
    writeJson(path.join(PROFILES_DIR, `${p.id}.json`), p);
  }

  createProfile(name, config) {
    let id = slug(name);
    for (let i = 2; this.profiles[id]; i++) id = `${slug(name)}-${i}`;
    const p = { id, name: String(name).slice(0, 40), config: normalizeConfig(config || defaultConfig('streaming')) };
    this.profiles[id] = p;
    this._writeProfile(p);
    return p;
  }

  duplicateProfile(sourceId, name) {
    const src = this.profile(sourceId);
    return this.createProfile(name, JSON.parse(JSON.stringify(src.config)));
  }

  renameProfile(id, name) {
    const p = this.profiles[id];
    if (!p) throw new Error('No such profile');
    p.name = String(name).slice(0, 40);
    this._writeProfile(p);
  }

  deleteProfile(id) {
    if (Object.keys(this.profiles).length <= 1) throw new Error('Keep at least one profile');
    if (!this.profiles[id]) throw new Error('No such profile');
    delete this.profiles[id];
    fs.rmSync(path.join(PROFILES_DIR, `${id}.json`), { force: true });
    if (this.settings.activeProfile === id) {
      this.settings.activeProfile = Object.keys(this.profiles)[0];
      this.saveSettings();
    }
  }

  /** Matches a profile by id or (case-insensitive) name. */
  resolveProfile(ref) {
    if (this.profiles[ref]) return this.profiles[ref];
    const lower = String(ref).toLowerCase();
    return Object.values(this.profiles).find((p) => p.name.toLowerCase() === lower) || null;
  }

  setActiveProfile(id) {
    if (!this.profiles[id]) throw new Error('No such profile');
    this.settings.activeProfile = id;
    this.saveSettings();
  }

  saveConfig(profileId, cfg) {
    const p = this.profile(profileId);
    p.config = normalizeConfig(cfg);
    this._writeProfile(p);
    return p.config;
  }

  /** Persist without re-normalizing (used when the companion fills in resolved icons). */
  touchProfile(id) {
    const p = this.profiles[id];
    if (p) this._writeProfile(p);
  }

  findButton(profileId, buttonId) {
    for (const page of Object.values(this.profile(profileId).config.pages)) {
      const b = page.buttons.find((x) => x && x.id === buttonId);
      if (b) return b;
    }
    return null;
  }

  // ---- settings / devices
  saveSettings() {
    writeJson(SETTINGS_FILE, this.settings);
  }

  saveAutomations(list) {
    if (!Array.isArray(list)) throw new Error('automations must be a list');
    this.automations = list.slice(0, 200).map((r) => ({ id: r.id || uid(), ...r }));
    writeJson(AUTOMATIONS_FILE, this.automations);
    return this.automations;
  }

  addToken(name) {
    const token = crypto.randomBytes(24).toString('hex');
    this.settings.tokens.push({
      id: crypto.randomBytes(6).toString('hex'),
      hash: sha(token),
      name: String(name || 'device').slice(0, 60),
      createdAt: Date.now(),
      lastSeen: Date.now(),
    });
    this.saveSettings();
    return token;
  }

  /** Returns the paired device record for a token, or null. */
  deviceForToken(token) {
    if (!token || typeof token !== 'string') return null;
    const h = sha(token);
    return this.settings.tokens.find((t) => t.hash === h) || null;
  }

  revokeDevice(id) {
    this.settings.tokens = this.settings.tokens.filter((t) => t.id !== id);
    this.saveSettings();
  }

  renameDevice(id, name) {
    const t = this.settings.tokens.find((x) => x.id === id);
    if (t) {
      t.name = String(name).slice(0, 60);
      this.saveSettings();
    }
  }
}

function defaultAutomations() {
  return [
    {
      id: 'sample-follow',
      name: 'Thank new followers in chat',
      enabled: false,
      trigger: { type: 'twitch.follow' },
      cooldown: 5,
      actions: [{ type: 'twitch', op: 'say', text: 'Thanks for the follow, {{user}}!' }],
    },
    {
      id: 'sample-live-profile',
      name: 'Switch to Streaming deck when OBS is focused',
      enabled: false,
      trigger: { type: 'app.foreground', process: 'obs64.exe' },
      cooldown: 0,
      actions: [{ type: 'profile', profile: 'Streaming' }],
    },
    {
      id: 'sample-desktop-profile',
      name: 'Switch to Desktop deck when Chrome is focused',
      enabled: false,
      trigger: { type: 'app.foreground', process: 'chrome.exe' },
      cooldown: 0,
      actions: [{ type: 'profile', profile: 'Desktop' }],
    },
    {
      id: 'sample-offline',
      name: 'Mute mic when the stream ends',
      enabled: false,
      trigger: { type: 'obs.streamStopped' },
      cooldown: 0,
      actions: [{ type: 'obs', op: 'mute', input: 'Mic/Aux' }],
    },
  ];
}

module.exports = { Store, DIR, uid, normalizeConfig };
