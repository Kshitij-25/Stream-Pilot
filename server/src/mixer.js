'use strict';
// Per-application audio mixer (Windows Core Audio sessions) in its own long-lived PowerShell process.
const { spawn } = require('child_process');

const PS = `
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System; using System.Collections.Generic; using System.Diagnostics; using System.Runtime.InteropServices;
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice2 { int Activate(ref Guid id, uint ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator2 { int EnumAudioEndpoints(int f, int s, out IntPtr d); int GetDefaultAudioEndpoint(int f, int r, out IMMDevice2 d); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorComObject2 {}
[Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionManager2 {
  int GetAudioSessionControl(IntPtr g, uint f, out IntPtr c);
  int GetSimpleAudioVolume(IntPtr g, uint f, out IntPtr v);
  int GetSessionEnumerator(out IAudioSessionEnumerator e);
}
[Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionEnumerator { int GetCount(out int c); int GetSession(int i, out IAudioSessionControl2 s); }
[Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionControl2 {
  int GetState(out int s);
  int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string n);
  int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string v, ref Guid g);
  int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string p);
  int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string p, ref Guid g);
  int GetGroupingParam(out Guid g);
  int SetGroupingParam(ref Guid o, ref Guid e);
  int RegisterAudioSessionNotification(IntPtr n);
  int UnregisterAudioSessionNotification(IntPtr n);
  int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string s);
  int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string s);
  int GetProcessId(out uint pid);
  int IsSystemSoundsSession();
  int SetDuckingPreference([MarshalAs(UnmanagedType.Bool)] bool b);
}
[Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface ISimpleAudioVolume2 {
  int SetMasterVolume(float l, ref Guid g); int GetMasterVolume(out float l);
  int SetMute([MarshalAs(UnmanagedType.Bool)] bool m, ref Guid g); int GetMute(out bool m);
}
public class Mix {
  static List<object> Sessions() {
    var en = (IMMDeviceEnumerator2)new MMDeviceEnumeratorComObject2();
    IMMDevice2 dev; en.GetDefaultAudioEndpoint(0, 1, out dev);
    var iid = typeof(IAudioSessionManager2).GUID; object o; dev.Activate(ref iid, 23, IntPtr.Zero, out o);
    var mgr = (IAudioSessionManager2)o;
    IAudioSessionEnumerator se; mgr.GetSessionEnumerator(out se);
    int n; se.GetCount(out n);
    var list = new List<object>();
    for (int i = 0; i < n; i++) { IAudioSessionControl2 c; se.GetSession(i, out c); list.Add(c); }
    return list;
  }
  static string NameOf(IAudioSessionControl2 c) {
    uint pid; c.GetProcessId(out pid);
    if (pid == 0) return "System sounds";
    try { return Process.GetProcessById((int)pid).ProcessName; } catch { return "pid" + pid; }
  }
  // lines: name|volume(0-100)|muted(0/1), aggregated per process name
  public static string List() {
    var seen = new Dictionary<string, string>();
    foreach (IAudioSessionControl2 c in Sessions()) {
      string name = NameOf(c); var v = (ISimpleAudioVolume2)c; float vol; bool m;
      v.GetMasterVolume(out vol); v.GetMute(out m);
      if (!seen.ContainsKey(name)) seen[name] = name + "|" + (int)Math.Round(vol * 100) + "|" + (m ? 1 : 0);
    }
    return string.Join(";", new List<string>(seen.Values).ToArray());
  }
  static bool Match(string name, string want) { return name.ToLower().Contains(want.ToLower()); }
  public static int Set(string want, float vol, bool relative) {
    int hit = 0; var g = Guid.Empty;
    foreach (IAudioSessionControl2 c in Sessions()) {
      if (!Match(NameOf(c), want)) continue;
      var v = (ISimpleAudioVolume2)c; float cur; v.GetMasterVolume(out cur);
      float next = relative ? cur + vol : vol;
      v.SetMasterVolume(Math.Max(0f, Math.Min(1f, next)), ref g); hit++;
    }
    return hit;
  }
  public static int Mute(string want, int mode) { // 0 unmute, 1 mute, 2 toggle
    int hit = 0; var g = Guid.Empty;
    foreach (IAudioSessionControl2 c in Sessions()) {
      if (!Match(NameOf(c), want)) continue;
      var v = (ISimpleAudioVolume2)c; bool cur; v.GetMute(out cur);
      v.SetMute(mode == 2 ? !cur : mode == 1, ref g); hit++;
    }
    return hit;
  }
}
"@
$out = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput())
$out.AutoFlush = $true
while (($line = [Console]::In.ReadLine()) -ne $null) {
  $p = $line.Split(' ', 3)
  try {
    switch ($p[0]) {
      'L' { $out.WriteLine('SESS ' + [Mix]::List()) }
      'S' { $r = [Mix]::Set($p[2], [single]$p[1], $false); $out.WriteLine("ACK $r") }
      'D' { $r = [Mix]::Set($p[2], [single]$p[1], $true); $out.WriteLine("ACK $r") }
      'M' { $r = [Mix]::Mute($p[2], [int]$p[1]); $out.WriteLine("ACK $r") }
    }
  } catch { $out.WriteLine('ERR ' + $_.Exception.Message.Replace("\`n", ' ')) }
}
`;

class Mixer {
  constructor() {
    this.proc = null;
    this.waiters = [];
    this.buf = '';
  }

  _ensure() {
    if (this.proc && this.proc.exitCode === null) return;
    if (process.platform !== 'win32') throw new Error('The per-app mixer is only available on Windows hosts');
    const encoded = Buffer.from(PS, 'utf16le').toString('base64');
    this.proc = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded], {
      stdio: ['pipe', 'pipe', 'ignore'],
      windowsHide: true,
    });
    this.proc.on('error', () => {});
    this.proc.on('close', () => {
      for (const w of this.waiters.splice(0)) w.reject(new Error('Mixer process stopped'));
    });
    this.proc.stdin.on('error', () => {});
    this.proc.stdout.on('data', (d) => {
      this.buf += d;
      let i;
      while ((i = this.buf.indexOf('\n')) >= 0) {
        const line = this.buf.slice(0, i).trim();
        this.buf = this.buf.slice(i + 1);
        const w = this.waiters.shift();
        if (w) (line.startsWith('ERR ') ? w.reject(new Error(line.slice(4))) : w.resolve(line));
      }
    });
  }

  _call(cmd) {
    this._ensure();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Mixer timed out')), 15000);
      this.waiters.push({
        resolve: (v) => { clearTimeout(timer); resolve(v); },
        reject: (e) => { clearTimeout(timer); reject(e); },
      });
      this.proc.stdin.write(cmd + '\n');
    });
  }

  async apps() {
    const line = await this._call('L');
    const body = line.replace(/^SESS /, '');
    if (!body) return [];
    return body.split(';').map((s) => {
      const [name, volume, muted] = s.split('|');
      return { name, volume: Number(volume), muted: muted === '1' };
    });
  }

  async setVolume(app, percent) {
    const hit = await this._ack(`S ${Math.max(0, Math.min(100, Number(percent) || 0)) / 100} ${app}`);
    if (!hit) throw new Error(`No audio session for "${app}" (is it playing sound?)`);
  }

  async changeVolume(app, deltaPercent) {
    const hit = await this._ack(`D ${(Number(deltaPercent) || 0) / 100} ${app}`);
    if (!hit) throw new Error(`No audio session for "${app}" (is it playing sound?)`);
  }

  async setMute(app, mode) {
    const hit = await this._ack(`M ${mode === 'toggle' ? 2 : mode ? 1 : 0} ${app}`);
    if (!hit) throw new Error(`No audio session for "${app}" (is it playing sound?)`);
  }

  async _ack(cmd) {
    const line = await this._call(cmd);
    return Number(line.replace(/^ACK /, '')) || 0;
  }

  close() {
    try { this.proc && this.proc.kill(); } catch {}
  }
}

module.exports = { Mixer };
