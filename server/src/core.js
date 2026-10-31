'use strict';
// Shared in-process event bus + action history + notable-event log.
const { EventEmitter } = require('events');

const bus = new EventEmitter();
bus.setMaxListeners(100);

const history = []; // newest first
const events = []; // newest first

function addHistory(entry) {
  const e = { ts: Date.now(), ...entry };
  history.unshift(e);
  if (history.length > 200) history.pop();
  bus.emit('history', e);
  return e;
}

/** Notable events shown as notifications in the app (follows, subs, raids ...). */
function addEvent(entry) {
  const e = { ts: Date.now(), ...entry };
  events.unshift(e);
  if (events.length > 100) events.pop();
  bus.emit('notify', e);
  return e;
}

/** Short human description of an action, for history and logs. */
function describe(a) {
  if (!a || typeof a !== 'object') return 'none';
  switch (a.type) {
    case 'hotkey': return `Hotkey ${a.keys || ''}`;
    case 'text': return `Type "${String(a.text || '').slice(0, 30)}"`;
    case 'open': return `Open ${a.target || ''}`;
    case 'command': return `Run ${String(a.command || '').slice(0, 40)}`;
    case 'media': return `Media ${a.key}`;
    case 'obs': return `OBS ${a.op}${a.scene ? ' ' + a.scene : ''}${a.input ? ' ' + a.input : ''}`;
    case 'volume': return `Volume ${a.op}${a.app ? ' (' + a.app + ')' : ''}${a.value !== undefined ? ' ' + a.value : ''}`;
    case 'twitch': return `Twitch ${a.op}`;
    case 'youtube': return `YouTube ${a.op}`;
    case 'discord': return `Discord ${a.op}`;
    case 'multi': return `Macro (${(a.actions || []).length} steps)`;
    case 'toggle': return 'Toggle';
    case 'cycle': return 'Cycle';
    case 'profile': return `Switch profile ${a.profile}`;
    default: return a.type || 'none';
  }
}

module.exports = { bus, history, events, addHistory, addEvent, describe };
