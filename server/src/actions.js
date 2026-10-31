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

function playSound(file) {
  if (!file) throw new Error('No sound file set');
  if (process.platform !== 'win32') return openTarget(file);
  const script =
    "Add-Type -AssemblyName PresentationCore; $m = New-Object System.Windows.Media.MediaPlayer; " +
    "$m.Open([uri]$env:DECKPAD_FILE); $m.Play(); $n = 0; " +
    "while (-not $m.NaturalDuration.HasTimeSpan -and $n -lt 50) { Start-Sleep -Milliseconds 100; $n++ }; " +
    "if ($m.NaturalDuration.HasTimeSpan) { Start-Sleep -Milliseconds ([int]$m.NaturalDuration.TimeSpan.TotalMilliseconds + 300) }";
  return detached('powershell.exe', ['-NoProfile', '-NonInteractive', '-STA', '-Command', script], {
    env: { ...process.env, DECKPAD_FILE: file },
  });
}

async function system(op, ctx) {
  const win = process.platform === 'win32';
  switch (op) {
    case 'lock':
      return win ? detached('rundll32.exe', ['user32.dll,LockWorkStation']) : runCommand('loginctl lock-session');
    case 'sleep':
      return win ? detached('rundll32.exe', ['powrprof.dll,SetSuspendState', '0,1,0']) : runCommand('systemctl suspend');
    case 'monitorOff':
      if (!win) throw new Error('Windows only');
      return detached('powershell.exe', ['-NoProfile', '-Command',
        "(Add-Type '[DllImport(\"user32.dll\")]public static extern int SendMessage(int h,int m,int w,int l);' -Name a -Pas)::SendMessage(-1,0x0112,0xF170,2)"]);
    case 'taskManager':
      return openTarget('taskmgr.exe');
    case 'showDesktop':
      return ctx.input.hotkey('win+d');
    case 'screenshot':
      return ctx.input.hotkey('win+shift+s');
    case 'emptyRecycleBin':
      if (!win) throw new Error('Windows only');
      return detached('powershell.exe', ['-NoProfile', '-Command', 'Clear-RecycleBin -Force -ErrorAction SilentlyContinue']);
    default:
      throw new Error(`Unknown system operation "${op}"`);
  }
}

function volume(a, ctx) {
  switch (a.op) {
    case 'set': return ctx.input.setVolume(a.value);
    case 'up': return ctx.input.changeVolume(Number(a.value) || 5);
    case 'down': return ctx.input.changeVolume(-(Number(a.value) || 5));
    case 'mute': return ctx.input.setMute(true);
    case 'unmute': return ctx.input.setMute(false);
    case 'toggleMute': return ctx.input.setMute('toggle');
    default: throw new Error(`Unknown volume operation "${a.op}"`);
  }
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
    case 'widget':
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
    case 'multi': {
      const times = Math.min(100, Math.max(1, parseInt(action.repeat, 10) || 1));
      for (let i = 0; i < times; i++) {
        for (const step of action.actions || []) await run(step, ctx, depth + 1);
      }
      return;
    }
    case 'volume':
      return volume(action, ctx);
    case 'system':
      return system(action.op, ctx);
    case 'sound':
      return playSound(action.file);
    case 'toggle': {
      // Two-state button: alternates between running `on` and `off`.
      if (depth > 0 || !ctx.buttonId) return run(action.on, ctx, depth + 1);
      const wasOn = !!ctx.state.toggles[ctx.buttonId];
      await run(wasOn ? action.off : action.on, ctx, depth + 1);
      ctx.state.toggles[ctx.buttonId] = !wasOn;
      ctx.changed();
      return;
    }
    case 'cycle': {
      // Each press runs the next action in the list.
      const list = action.actions || [];
      if (!list.length) return;
      const i = ctx.buttonId ? (ctx.state.cycles[ctx.buttonId] || 0) % list.length : 0;
      if (ctx.buttonId) ctx.state.cycles[ctx.buttonId] = i + 1;
      return run(list[i], ctx, depth + 1);
    }
    default:
      throw new Error(`Unknown action type "${action.type}"`);
  }
}

module.exports = { run };
