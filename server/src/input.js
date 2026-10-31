'use strict';
// Keyboard / media key injection. Windows uses one long-lived PowerShell process
// (spawning per press would add ~300ms of latency).
const { spawn } = require('child_process');

const VK = {
  ctrl: 0x11, control: 0x11, shift: 0x10, alt: 0x12, win: 0x5b, windows: 0x5b, cmd: 0x5b, super: 0x5b, meta: 0x5b,
  enter: 0x0d, return: 0x0d, esc: 0x1b, escape: 0x1b, tab: 0x09, space: 0x20, backspace: 0x08,
  delete: 0x2e, del: 0x2e, insert: 0x2d, ins: 0x2d, home: 0x24, end: 0x23,
  pageup: 0x21, pgup: 0x21, pagedown: 0x22, pgdn: 0x22,
  up: 0x26, down: 0x28, left: 0x25, right: 0x27,
  printscreen: 0x2c, prtsc: 0x2c, pause: 0x13, capslock: 0x14, numlock: 0x90, scrolllock: 0x91, menu: 0x5d,
  playpause: 0xb3, next: 0xb0, prev: 0xb1, previous: 0xb1, stop: 0xb2,
  volup: 0xaf, voldown: 0xae, mute: 0xad,
  ';': 0xba, '=': 0xbb, '+': 0xbb, ',': 0xbc, '-': 0xbd, '.': 0xbe, '/': 0xbf, '`': 0xc0,
  '[': 0xdb, '\\': 0xdc, ']': 0xdd, "'": 0xde,
};
for (let i = 0; i < 26; i++) VK[String.fromCharCode(97 + i)] = 0x41 + i;
for (let i = 0; i < 10; i++) {
  VK[String(i)] = 0x30 + i;
  VK['num' + i] = 0x60 + i;
}
for (let i = 1; i <= 24; i++) VK['f' + i] = 0x6f + i;

// Keys that need KEYEVENTF_EXTENDEDKEY to be interpreted correctly.
const EXTENDED = new Set([0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2c, 0x2d, 0x2e, 0x5b, 0x5d, 0x6f, 0xa3, 0xa5]);

function parseKeys(combo) {
  const parts = String(combo || '')
    .toLowerCase()
    .split(/\s*\+\s*(?=.)/)
    .map((s) => s.trim())
    .filter(Boolean);
  // "ctrl++" style: a trailing "+" splits oddly; handle explicit "plus" alias.
  const codes = parts.map((p) => {
    const name = p === 'plus' ? '=' : p;
    const vk = VK[name];
    if (vk === undefined) throw new Error(`Unknown key "${p}"`);
    return vk;
  });
  if (!codes.length) throw new Error('No keys given');
  return codes;
}

const PS_SCRIPT = `
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public class K { [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra); }
"@
while (($line = [Console]::In.ReadLine()) -ne $null) {
  try {
    $p = $line.Split(' ')
    switch ($p[0]) {
      'D' { [K]::keybd_event([byte][int]$p[1], 0, [uint32][int]$p[2], [UIntPtr]::Zero) }
      'U' { [K]::keybd_event([byte][int]$p[1], 0, ([uint32][int]$p[2] -bor 2), [UIntPtr]::Zero) }
      'T' { [System.Windows.Forms.SendKeys]::SendWait([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p[1]))) }
    }
  } catch { }
}
`;

class WindowsInput {
  constructor() {
    this.proc = null;
  }

  _ensure() {
    if (this.proc && !this.proc.killed && this.proc.exitCode === null) return;
    const encoded = Buffer.from(PS_SCRIPT, 'utf16le').toString('base64');
    this.proc = spawn(
      'powershell.exe',
      ['-NoProfile', '-NoLogo', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded],
      { stdio: ['pipe', 'ignore', 'ignore'], windowsHide: true },
    );
    this.proc.on('error', () => {});
    this.proc.stdin.on('error', () => {});
  }

  _send(lines) {
    this._ensure();
    this.proc.stdin.write(lines.join('\n') + '\n');
  }

  hotkey(combo) {
    const codes = parseKeys(combo);
    const lines = [];
    for (const c of codes) lines.push(`D ${c} ${EXTENDED.has(c) ? 1 : 0}`);
    for (const c of [...codes].reverse()) lines.push(`U ${c} ${EXTENDED.has(c) ? 1 : 0}`);
    this._send(lines);
  }

  type(text, enter) {
    // SendKeys treats + ^ % ~ ( ) { } [ ] specially; wrap each in braces.
    let esc = String(text).replace(/\r\n|\r|\n/g, '\u0000').replace(/[+^%~(){}[\]]/g, (c) => `{${c}}`);
    esc = esc.replace(/\u0000/g, '{ENTER}');
    if (enter) esc += '{ENTER}';
    this._send([`T ${Buffer.from(esc, 'utf8').toString('base64')}`]);
  }

  close() {
    try {
      this.proc && this.proc.kill();
    } catch {}
  }
}

class UnsupportedInput {
  hotkey() {
    throw new Error(`Hotkeys are only implemented for Windows hosts (this is ${process.platform}).`);
  }
  type() {
    return this.hotkey();
  }
  close() {}
}

function createInput() {
  return process.platform === 'win32' ? new WindowsInput() : new UnsupportedInput();
}

module.exports = { createInput, parseKeys };
