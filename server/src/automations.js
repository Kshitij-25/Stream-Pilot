'use strict';
// Trigger -> actions rules. Events arrive on the bus as { type, ...vars }; action strings may use {{vars}}.
const { bus, addHistory, describe } = require('./core');

function expand(value, vars) {
  if (typeof value === 'string') return value.replace(/\{\{(\w+)\}\}/g, (_, k) => (vars[k] === undefined ? '' : String(vars[k])));
  if (Array.isArray(value)) return value.map((v) => expand(v, vars));
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, expand(v, vars)]));
  return value;
}

const lc = (v) => String(v === undefined || v === null ? '' : v).toLowerCase();

/** Whether `event` satisfies the rule's trigger filters. */
function matches(trigger, event) {
  if (!trigger || trigger.type !== event.type) return false;
  for (const [k, want] of Object.entries(trigger)) {
    if (k === 'type' || want === '' || want === undefined || want === null) continue;
    switch (k) {
      case 'scene': if (event.scene !== want) return false; break;
      case 'process': if (lc(event.process) !== lc(want)) return false; break;
      case 'command': if (lc(event.command) !== lc(want)) return false; break;
      case 'reward': if (lc(event.reward) !== lc(want)) return false; break;
      case 'time': if (event.time !== want) return false; break;
      case 'days': if (Array.isArray(want) && want.length && !want.includes(event.day)) return false; break;
      case 'minBits': if ((event.bits || 0) < Number(want)) return false; break;
      case 'minViewers': if ((event.viewers || 0) < Number(want)) return false; break;
      case 'minAmount': if ((event.amount || 0) < Number(want)) return false; break;
      case 'modOnly': if (want && !event.isMod) return false; break;
      case 'above': if ((event.cpu || 0) < Number(want)) return false; break;
      default: break;
    }
  }
  return true;
}

class Automations {
  constructor({ store, makeCtx, run }) {
    this.store = store;
    this.makeCtx = makeCtx;
    this.run = run;
    this.lastFired = new Map();
    this.armed = new Map(); // rule id -> bool for edge-triggered rules (system.cpu)
    this.lastMinute = '';
  }

  start() {
    bus.on('event', (e) => this.handle(e));
    this.timer = setInterval(() => this._tick(), 15000);
    this.timer.unref();
  }

  stop() {
    clearInterval(this.timer);
  }

  _tick() {
    const d = new Date();
    const time = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    if (time !== this.lastMinute) {
      this.lastMinute = time;
      bus.emit('event', { type: 'schedule', time, day: d.getDay() });
    }
  }

  usesForeground() {
    return this.store.automations.some((r) => r.enabled && r.trigger && r.trigger.type === 'app.foreground');
  }

  async handle(event) {
    for (const rule of this.store.automations) {
      if (!rule.enabled || !matches(rule.trigger, event)) continue;
      if (rule.trigger.type === 'system.cpu') {
        // Edge-triggered: fire once when crossing above, re-arm when it drops below.
        if (this.armed.get(rule.id)) continue;
        this.armed.set(rule.id, true);
      }
      const cool = (Number(rule.cooldown) || 0) * 1000;
      const now = Date.now();
      if (cool && now - (this.lastFired.get(rule.id) || 0) < cool) continue;
      this.lastFired.set(rule.id, now);
      this.fire(rule, event);
    }
    if (event.type === 'system.cpu') {
      for (const rule of this.store.automations) {
        if (rule.trigger && rule.trigger.type === 'system.cpu' && event.cpu < Number(rule.trigger.above || 0)) this.armed.set(rule.id, false);
      }
    }
  }

  /** Runs a rule's actions (also used by the "test rule" button). */
  async fire(rule, event = {}) {
    const vars = { ...event };
    let error = null;
    for (const action of rule.actions || []) {
      try {
        await this.run(expand(action, vars), this.makeCtx());
      } catch (e) {
        error = e.message;
        break;
      }
    }
    addHistory({
      source: 'automation',
      label: rule.name || 'Automation',
      action: `${event.type || 'manual'} → ${(rule.actions || []).map(describe).join(', ')}`,
      ok: !error,
      error,
    });
  }
}

module.exports = { Automations, matches, expand };
