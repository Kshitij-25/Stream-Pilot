'use strict';
const { spawn, exec } = require('child_process');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const MAX_DEPTH = 5;

function detached(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { detached: true, stdio: 'ignore', windowsHide: true, ...opts });
    child.once('error', reject);
    child.once('spawn', () => {
      child.unref();
      resolve();
    });
  });
}

async function openTarget(target, args) {
  if (!target) throw new Error('No target to open');
  const isUrl = /^[a-z][a-z0-9+.-]*:\/\//i.test(target) || /^(mailto|spotify|steam|tel):/i.test(target);
  if (process.platform === 'win32') {
    if (isUrl) return detached('rundll32', ['url.dll,FileProtocolHandler', target]);
    const ps = ['-NoProfile', '-NonInteractive', '-Command', 'Start-Process', '-FilePath', target];
    if (args) ps.push('-ArgumentList', args);
    return detached('powershell.exe', ps);
  }
  const opener = process.platform === 'darwin' ? 'open' : 'xdg-open';
  return detached(opener, [target, ...(args ? [args] : [])]);
}

function runCommand(command) {
  return new Promise((resolve, reject) => {
    if (!command) return reject(new Error('Empty command'));
    exec(command, { windowsHide: true, timeout: 30000 }, (err, stdout, stderr) => {
      if (err) reject(new Error((stderr || err.message).toString().trim().slice(0, 300)));
      else resolve((stdout || '').toString().slice(0, 300));
    });
  });
}

async function webhook(a) {
  const method = (a.method || 'GET').toUpperCase();
  const res = await fetch(a.url, {
    method,
    headers: a.body ? { 'Content-Type': 'application/json' } : undefined,
    body: method === 'GET' || !a.body ? undefined : a.body,
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
}

/**
 * Executes one action. ctx = { input, obs }.
 * Client-only actions (folder/back) are acknowledged and ignored.
 */
async function run(action, ctx, depth = 0) {
  if (!action || typeof action !== 'object') throw new Error('Button has no action');
  if (depth > MAX_DEPTH) throw new Error('Macro nested too deeply');
  switch (action.type) {
    case 'none':
    case 'folder':
    case 'back':
    case 'home':
      return;
    case 'hotkey':
      return ctx.input.hotkey(action.keys);
    case 'media':
      return ctx.input.hotkey(String(action.key || ''));
    case 'text':
      return ctx.input.type(action.text || '', !!action.enter);
    case 'open':
      return openTarget(action.target, action.args);
    case 'command':
      return runCommand(action.command);
    case 'http':
      return webhook(action);
    case 'obs':
      return ctx.obs.perform(action);
    case 'delay':
      return sleep(Math.min(60000, Math.max(0, Number(action.ms) || 0)));
    case 'multi':
      for (const step of action.actions || []) await run(step, ctx, depth + 1);
      return;
    default:
      throw new Error(`Unknown action type "${action.type}"`);
  }
}

module.exports = { run };
