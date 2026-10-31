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
$volOk = $false
try {
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
  int RegisterControlChangeNotify(IntPtr p); int UnregisterControlChangeNotify(IntPtr p);
  int GetChannelCount(out uint c);
  int SetMasterVolumeLevel(float l, ref Guid g); int SetMasterVolumeLevelScalar(float l, ref Guid g);
  int GetMasterVolumeLevel(out float l); int GetMasterVolumeLevelScalar(out float l);
  int SetChannelVolumeLevel(uint n, float l, ref Guid g); int SetChannelVolumeLevelScalar(uint n, float l, ref Guid g);
  int GetChannelVolumeLevel(uint n, out float l); int GetChannelVolumeLevelScalar(uint n, out float l);
  int SetMute([MarshalAs(UnmanagedType.Bool)] bool m, ref Guid g); int GetMute(out bool m);
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice { int Activate(ref Guid id, uint ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { int EnumAudioEndpoints(int f, int s, out IntPtr d); int GetDefaultAudioEndpoint(int f, int r, out IMMDevice d); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorComObject {}
public class Vol {
  static IAudioEndpointVolume Ep() {
    var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
    IMMDevice dev; en.GetDefaultAudioEndpoint(0, 1, out dev);
    var iid = typeof(IAudioEndpointVolume).GUID; object o; dev.Activate(ref iid, 23, IntPtr.Zero, out o);
    return (IAudioEndpointVolume)o;
  }
  public static void Set(float v) { var g = Guid.Empty; Ep().SetMasterVolumeLevelScalar(Math.Max(0f, Math.Min(1f, v)), ref g); }
  public static void Delta(float d) { float c; var e = Ep(); e.GetMasterVolumeLevelScalar(out c); var g = Guid.Empty; e.SetMasterVolumeLevelScalar(Math.Max(0f, Math.Min(1f, c + d)), ref g); }
  public static void Mute(bool m) { var g = Guid.Empty; Ep().SetMute(m, ref g); }
  public static void Toggle() { bool m; var e = Ep(); e.GetMute(out m); var g = Guid.Empty; e.SetMute(!m, ref g); }
  public static string Get() { float c; bool m; var e = Ep(); e.GetMasterVolumeLevelScalar(out c); e.GetMute(out m); return c.ToString(System.Globalization.CultureInfo.InvariantCulture) + " " + (m ? "1" : "0"); }
}
"@
$volOk = $true
} catch { }
$fgOk = $false
try {
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public class Fg {
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static string Name() {
    uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid);
    try { return System.Diagnostics.Process.GetProcessById((int)pid).ProcessName + ".exe"; } catch { return ""; }
  }
}
"@
$fgOk = $true
} catch { }
$out = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput())
$out.AutoFlush = $true
while (($line = [Console]::In.ReadLine()) -ne $null) {
  try {
    $p = $line.Split(' ')
    switch ($p[0]) {
      'V' { if ($volOk) { switch ($p[1]) { 'set' { [Vol]::Set([single]$p[2]) } 'delta' { [Vol]::Delta([single]$p[2]) } 'mute' { [Vol]::Mute($p[2] -eq '1') } 'toggle' { [Vol]::Toggle() } } } }
      'Q' { if ($volOk) { $out.WriteLine('STAT ' + [Vol]::Get()) } }
      'F' { if ($fgOk) { $out.WriteLine('FG ' + [Fg]::Name()) } }
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
      { stdio: ['pipe', 'pipe', 'ignore'], windowsHide: true },
    );
    this.proc.on('error', () => {});
    this.proc.stdin.on('error', () => {});
    let buf = '';
    this.proc.stdout.on('data', (d) => {
      buf += d;
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i).trim();
        buf = buf.slice(i + 1);
        const m = /^STAT ([\d.eE+-]+) ([01])$/.exec(line);
        if (m) this.audio = { volume: Math.round(parseFloat(m[1]) * 100), muted: m[2] === '1' };
        const f = /^FG (.*)$/.exec(line);
        if (f) {
          this.foreground = f[1];
          if (this.onForeground) this.onForeground(f[1]);
        }
      }
    });
  }

  /** Last known foreground process (e.g. "obs64.exe"); refreshed by queryForeground(). */
  foreground = '';
  onForeground = null;

  queryForeground() {
    this._send(['F']);
  }

  /** Last known system audio state (refreshed by query()). */
  audio = null;

  query() {
    this._send(['Q']);
  }

  setVolume(percent) {
    this._send([`V set ${Math.max(0, Math.min(100, Number(percent) || 0)) / 100}`]);
  }

  changeVolume(percentDelta) {
    this._send([`V delta ${(Number(percentDelta) || 0) / 100}`]);
  }

  setMute(mode) {
    this._send([mode === 'toggle' ? 'V toggle' : `V mute ${mode ? 1 : 0}`]);
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
  audio = null;
  foreground = '';
  onForeground = null;
  query() {}
  queryForeground() {}
  setVolume() {
    return this.hotkey();
  }
  changeVolume() {
    return this.hotkey();
  }
  setMute() {
    return this.hotkey();
  }
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
