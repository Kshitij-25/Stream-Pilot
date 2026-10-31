# DeckPad

A Stream Deck for your phone. A Flutter app (iOS + Android) is the button surface; a small Node
**companion** on your PC runs the actions.

```
 phone (Flutter)  ──WebSocket over Wi-Fi──▶  companion (Node, server/)  ──▶  keyboard / apps / OBS / Twitch / YouTube / Discord
```

## Quick start

1. **PC companion** (Node 18+, Windows recommended):
   ```bash
   cd server
   npm install
   npm start          # or double-click start-companion.bat
   ```
   It prints a QR code and a 6-digit PIN. Allow Node through the Windows firewall on *Private* networks.
   **After updating the project, always close and restart the companion**: an old one doesn't know the new actions
   (the app shows a red "companion is outdated" banner when that happens). An old saved layout is backed up
   (`~/.deckpad/config.v1.bak.json`) and replaced by the new profiles.
2. **Phone app**: `flutter run` (same Wi-Fi). Tap **Scan QR code**, or **Find PCs on Wi-Fi** and type the PIN.
3. **OBS**: OBS 28+ → *Tools → WebSocket Server Settings* → enable. Enter the port/password in *Settings → OBS*.
4. **Twitch / YouTube / Discord** (optional): *Settings → Tools → Integrations* (needs your own free app registrations).

## What's in it

**Deck**: hardware-style landscape layout (square keys, screen rail) or portrait; 9 ready-made screens
(Stream, Audio, Twitch, YouTube, Discord, Desktop, Macros, Sounds, Monitor); folders; pages are yours to add/rename/delete;
grid presets 3×2 / 5×3 / 8×4 / 4×5 or any size; drag to rearrange; long-press and double-tap actions per button.

**Icons**: real icons. Buttons for apps use the app's own icon extracted from your PC (Start Menu apps list → *App icon from PC*),
websites use their favicon, everything else uses a vector icon library (no emoji by default). Emoji / gallery pictures are still available under "More".
Default buttons for Spotify, Discord, OBS, Chrome, Explorer, Twitch, YouTube… resolve their real icons automatically at companion start.

**Dynamic buttons**: an "active look" (icon/label/colour) while OBS is live/recording/muted/on that scene, a toggle is ON,
PC audio or Discord is muted, Twitch chat mode is on. Live widgets: clock, date, CPU, RAM, GPU, network, OBS FPS, dropped frames, bitrate,
stream/record timer, PC volume, Twitch viewers/followers, YouTube viewers.

**Actions**: hotkeys · type text · open app/file/URL · media keys · PC **and per-app** volume · play sound (soundboard) · system (lock, sleep, screen off, task manager, screenshot) ·
shell command · webhook · OBS (scene, stream, record, pause, replay buffer, virtual cam, studio mode, mute, input volume, source/filter toggles, OBS hotkeys) ·
Twitch (clip, marker, say, announce, chat modes, clear chat, timeout, ban, unban, shoutout, raid, ads, title, category) ·
YouTube (say, go live, end) · Discord (real mute/deafen/leave/volume, with hotkey fallback) · switch profile · open tool screen.

**Macros**: sequences with waits, repeat N times, **Toggle** (remembers ON/OFF), **Cycle** (next step each press), reorder/duplicate steps, 40+ presets.

**Tool screens**: audio **mixer** (master, each app, OBS inputs), **performance** charts, action **history**, **automations**, **integrations**, **chat & moderation**, **events**.

**Automations**: trigger → actions with `{{user}}`-style variables and cooldowns. Triggers: OBS stream/record/scene, Twitch follow/sub/gift/cheer/raid/redeem/chat command/online/offline,
YouTube Super Chat/member/chat command, app in focus, time of day, CPU above, device connected.
Automatic profile switching = a rule "app in focus → *Switch profile*" (two disabled examples are included).

**Profiles & devices**: several deck layouts; each phone either *follows the PC* (so automations can switch it) or is pinned to its own profile;
multiple phones/tablets at once, live-synced; device list with revoke.

**Reliability**: auto-reconnect (phone ↔ PC and companion ↔ OBS/Twitch/Discord), layout persisted on the PC (`~/.deckpad/profiles/*.json`).

## Setting up the integrations

- **Twitch**: dev.twitch.tv/console → register an app, *Client Type: Public*, redirect `http://localhost` → paste the Client ID → *Log in* → enter the code on the page that opens.
- **YouTube**: Google Cloud → enable *YouTube Data API v3* → OAuth client of type *TV and Limited Input devices* → paste Client ID + secret. The API has a daily quota; chat polling is rate-limited accordingly.
- **Discord**: discord.com/developers → new application → add redirect `http://localhost` → paste Client ID + secret → *Connect* → click *Authorize* in the Discord window.
  Without this, Discord buttons fall back to keyboard shortcuts (bind Ctrl+Shift+M / Ctrl+Shift+D in Discord → Keybinds).

## Verification status (what has and hasn't been tested)

| Area | How it was verified |
|---|---|
| Phone ↔ companion protocol: pairing, taps, long/double press, profiles, stats, discovery, **auto-reconnect**, edits persisted | End-to-end test: the real Node companion driven by the app's own connection code (`flutter test test/e2e_companion_test.dart`) |
| **Vol + / Vol −**, per-app mixer, foreground-app probe, GPU/network stats, real app-icon extraction (Start Menu apps) | Run for real on a Windows 11 PC (system volume actually changed and was restored) |
| OBS WebSocket (auth handshake, scenes, stream, mute, source toggle, events, reconnect) | **Mock OBS server** following the obs-websocket v5 spec. *Not yet run against a live OBS.* |
| Twitch (device login, token refresh, EventSub, chat, moderation calls), YouTube (login, chat poll, Super Chat, moderation), Discord IPC | **Local mock servers** following each documented API. *Not run against the real services*: first live use may reveal differences |
| Layout (landscape/portrait), tiles, dynamic icons, tool screens render without overflow | Flutter widget tests; Android debug APK builds |
| iOS | Not built (needs a Mac). Permissions are in `Info.plist` |

Run everything: `cd server && npm test` and, from the project root, `flutter test`.

## Notes / limits

- The companion is **Node, not a Flutter desktop app**: it needs OS-level control (PowerShell, Core Audio, named pipes) and a tiny dependency footprint.
  A Flutter desktop shell/tray UI around it is possible but not built.
- Hotkeys, typing, media keys, per-app mixer, app icons, window-focus triggers and network stats are **Windows-only**. Other features (OBS, Twitch, YouTube, webhooks, open/command) are cross-platform in principle.
- Credentials (OBS password, Twitch/YouTube/Discord tokens) are stored in plain text in `~/.deckpad/settings.json`. Traffic between phone and PC is unencrypted WebSocket on your LAN; use trusted Wi-Fi.
  Anyone paired can run shell commands on the PC (the *Shell command* action): revoke devices under Settings → Connected devices.
- Games and elevated (admin) windows may ignore injected keys unless the companion runs as admin.
- Twitch moderation by name only works with a typed login; from the chat screen it uses user IDs directly.
- Output-device switching, Twitch/YouTube analytics, and a conditional (`if`) macro step are not implemented.

## Layout of the code

- `lib/` – Flutter app: `connection.dart` (protocol, state, discovery), `screens/` (deck, editor, settings, connect), `tools/` (mixer, performance, history, events, automations, integrations, chat), `widgets/`
- `server/src/` – companion: `index.js` (server, RPC), `actions.js`, `input.js` (keys/volume/foreground), `mixer.js`, `perf.js`, `obs.js`, `twitch.js`, `youtube.js`, `discord.js`, `automations.js`, `appicons.js`, `store.js` (profiles/settings), `defaults.js` (starter screens), `discovery.js`
- `server/test/`, `test/` – test suites described above
