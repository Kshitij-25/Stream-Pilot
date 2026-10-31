'use strict';
// Real icons: installed-app icons (Windows, extracted from the exe/shortcut) and website favicons.
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const FAVICON_URL = process.env.DECKPAD_FAVICON_URL || 'https://www.google.com/s2/favicons';

const PS_ICON = `
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public class IconX {
  [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern uint PrivateExtractIcons(string f, int i, int cx, int cy, IntPtr[] h, uint[] id, uint n, uint fl);
  [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
}
"@
$p = [Environment]::ExpandEnvironmentVariables($env:DECKPAD_PATH)
$idx = 0
if ($p -like '*.lnk') {
  $s = (New-Object -ComObject WScript.Shell).CreateShortcut($p)
  $parts = ([string]$s.IconLocation).Split(',')
  $f = [Environment]::ExpandEnvironmentVariables($parts[0])
  if ($f -and (Test-Path $f)) { $p = $f; if ($parts.Length -gt 1) { $idx = [int]$parts[1] } } else { $p = $s.TargetPath }
}
if (-not (Test-Path $p)) { $c = Get-Command $p -ErrorAction SilentlyContinue; if ($c) { $p = $c.Source } }
if (-not (Test-Path $p)) { throw 'not found' }
$bmp = $null
try {
  $h = New-Object IntPtr[] 1
  $ids = New-Object uint32[] 1
  $n = [IconX]::PrivateExtractIcons($p, $idx, 256, 256, $h, $ids, 1, 0)
  if ($n -ge 1 -and $h[0] -ne [IntPtr]::Zero) {
    $bmp = [System.Drawing.Icon]::FromHandle($h[0]).ToBitmap()
    [IconX]::DestroyIcon($h[0]) | Out-Null
  }
} catch { }
if (-not $bmp) { $bmp = [System.Drawing.Icon]::ExtractAssociatedIcon($p).ToBitmap() }
$out = New-Object System.Drawing.Bitmap 128, 128
$g = [System.Drawing.Graphics]::FromImage($out)
$g.InterpolationMode = 'HighQualityBicubic'
$g.SmoothingMode = 'HighQuality'
$g.DrawImage($bmp, 0, 0, 128, 128)
$ms = New-Object IO.MemoryStream
$out.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
[Console]::Out.Write([Convert]::ToBase64String($ms.ToArray()))
`;

const cache = new Map();

function iconForPath(p) {
  if (process.platform !== 'win32') return Promise.reject(new Error('App icons are only available on Windows hosts'));
  if (cache.has(p)) return Promise.resolve(cache.get(p));
  return new Promise((resolve, reject) => {
    const encoded = Buffer.from(PS_ICON, 'utf16le').toString('base64');
    const ps = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded], {
      env: { ...process.env, DECKPAD_PATH: p },
      windowsHide: true,
    });
    let out = '';
    ps.stdout.on('data', (d) => (out += d));
    const timer = setTimeout(() => ps.kill(), 20000);
    ps.on('close', () => {
      clearTimeout(timer);
      const b64 = out.trim();
      if (/^[A-Za-z0-9+/=]{100,}$/.test(b64)) {
        cache.set(p, b64);
        resolve(b64);
      } else {
        reject(new Error(`Could not read an icon from ${p}`));
      }
    });
    ps.on('error', reject);
  });
}

async function faviconFor(domain) {
  const d = String(domain).replace(/^https?:\/\//, '').split('/')[0];
  const key = `site:${d}`;
  if (cache.has(key)) return cache.get(key);
  const res = await fetch(`${FAVICON_URL}?domain=${encodeURIComponent(d)}&sz=128`, { signal: AbortSignal.timeout(8000) });
  if (!res.ok) throw new Error(`Favicon request failed (${res.status})`);
  const b64 = Buffer.from(await res.arrayBuffer()).toString('base64');
  if (b64.length < 100) throw new Error('No favicon found');
  cache.set(key, b64);
  return b64;
}

function startMenuDirs() {
  const dirs = [];
  if (process.env.ProgramData) dirs.push(path.join(process.env.ProgramData, 'Microsoft', 'Windows', 'Start Menu', 'Programs'));
  if (process.env.APPDATA) dirs.push(path.join(process.env.APPDATA, 'Microsoft', 'Windows', 'Start Menu', 'Programs'));
  return dirs;
}

/** Installed apps = Start Menu shortcuts. Returns [{ name, path }]. */
function listApps() {
  if (process.platform !== 'win32') return [];
  const apps = new Map();
  const walk = (dir, depth) => {
    let entries = [];
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory() && depth < 3) walk(full, depth + 1);
      else if (e.isFile() && e.name.toLowerCase().endsWith('.lnk')) {
        const name = e.name.slice(0, -4);
        if (/uninstall|readme|license|release notes|help|documentation|website|manual/i.test(name)) continue;
        if (!apps.has(name.toLowerCase())) apps.set(name.toLowerCase(), { name, path: full });
      }
    }
  };
  startMenuDirs().forEach((d) => walk(d, 0));
  return [...apps.values()].sort((a, b) => a.name.localeCompare(b.name));
}

/** Resolves an icon hint ({app}|{exe}|{site}) to base64 PNG. */
async function resolveHint(hint) {
  if (hint.site) return faviconFor(hint.site);
  if (hint.exe) return iconForPath(hint.exe);
  if (hint.app) {
    const want = hint.app.toLowerCase();
    const apps = listApps();
    const found = apps.find((a) => a.name.toLowerCase() === want) || apps.find((a) => a.name.toLowerCase().includes(want));
    if (!found) throw new Error(`App "${hint.app}" not found in the Start Menu`);
    return iconForPath(found.path);
  }
  throw new Error('Unknown icon hint');
}

/**
 * Fills `image` for every button that has an `iconHint` and no picture yet.
 * Runs sequentially in the background; failures just keep the vector icon.
 */
async function resolveDefaultIcons(store, onChange) {
  for (const profile of Object.values(store.profiles)) {
    let changed = false;
    for (const page of Object.values(profile.config.pages)) {
      for (const b of page.buttons) {
        if (!b || !b.iconHint || b.image || b.iconTried) continue;
        b.iconTried = true;
        try {
          b.image = await resolveHint(b.iconHint);
          changed = true;
        } catch {
          /* keep vector icon */
        }
      }
    }
    store.touchProfile(profile.id);
    if (changed) onChange(profile.id);
  }
}

module.exports = { iconForPath, faviconFor, listApps, resolveHint, resolveDefaultIcons };
