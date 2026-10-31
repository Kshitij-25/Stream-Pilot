# DeckPad

A Stream Deck for your phone. A Flutter app (iOS + Android) is the button surface; a small Node
**companion** on your PC runs the actions.

```
 phone (Flutter)  ──WebSocket over Wi-Fi──▶  companion (Node, server/)  ──▶  keyboard / apps / OBS
```

## Quick start

1. **PC companion** (Node 18+):
   ```bash
   cd server
   npm install
   npm start          # or double-click start-companion.bat
   ```
   It prints a QR code and a 6-digit PIN. Allow Node through the Windows firewall on *Private* networks.
2. **Phone app**: `flutter run` (device on the same Wi-Fi), tap **Scan QR code**.
   The pairing is remembered; the PIN rotates after every successful pairing.
3. **OBS** (optional): OBS 28+ → *Tools → WebSocket Server Settings* → enable. Then enter the port/password in the app under *Settings → OBS*.

## Features

- **Hardware-style landscape layout**: square keys centred on a dark "deck", with a screen-switcher rail on the left (portrait gets a top bar + tab strip). Orientation is a setting (landscape by default); grid presets Mini 3×2, Classic 5×3, XL 8×4, Tall 4×5 or any size up to 10×10
- **Multiple screens** out of the box: *Stream*, *Discord*, *Desktop*, *Audio*, *Sounds*. Add, rename, reorder-by-pinning or delete screens; folders still work for sub-pages
- **Custom icons**: pick any picture from your phone gallery, use the built-in vector icon library, or any emoji/text
- **Dynamic icons**: every button can have an "active look" (icon / label / colour) that shows while OBS is live, recording, muted or on that scene, while a Toggle is ON, or while PC audio is muted. **Live widgets** show clock, date, CPU, RAM, PC volume, stream timer and record timer
- **Actions**: hotkeys, type text, open app/file/URL, media keys, PC volume (set / step / mute), play sound (soundboard), system (lock, sleep, screen off, task manager, screenshot, show desktop), shell command, webhook, folder/back/home
- **OBS**: scene, stream, record, pause record, replay buffer + save, virtual camera, studio mode + transition, mute/unmute/toggle input, set input volume, show/hide source, toggle filter, trigger OBS hotkey
- **Macros**: ordered steps with waits, *repeat N times*, **Toggle** (ON/OFF actions with remembered state), **Cycle** (each press runs the next step). Duplicate/reorder steps
- **Preset library** (macros like *Starting Soon*, *BRB mode*, *End Stream*, *Panic*, plus Discord, Audio, Desktop, Editing, Widgets) to start a button from
- On-phone editor with live preview (normal/active), "Test on PC now", drag to rearrange
- Layout is stored on the PC (`~/.deckpad/config.json`) and syncs to every paired phone; auto-reconnect, keep-screen-on, haptics

## Discord / audio notes

- Discord has no remote API for mute/deafen, so those buttons send hotkeys. Bind them under Discord → Settings → Keybinds
  (defaults used: Ctrl+Shift+M mute, Ctrl+Shift+D deafen). Toggle buttons track their own state; press once to resync if you change it elsewhere.
- Soundboard buttons need the file path of an mp3/wav on the PC. Sounds play through the PC's default output so OBS captures them via Desktop Audio.
- PC volume buttons use the Windows default output device. Switching output devices isn't built in (use a *Shell command* with a tool such as SoundVolumeView).

## Security

Only devices that paired with the PIN can send actions, and the PIN rotates after each pairing (5 wrong
tries locks that IP for a minute). Traffic is plain WebSocket on your LAN, so use trusted Wi-Fi. Anyone
paired can run shell commands on the PC (that is the point of the *Shell command* action): use *Forget*
in the app or delete `tokens` from `~/.deckpad/settings.json` to revoke.

## Layout

- `lib/` – Flutter app (`connection.dart` protocol/state, `screens/`, `widgets/`)
- `server/src/` – companion (`index.js` WebSocket server, `actions.js`, `input.js` key injection, `obs.js`)
- `server/test/protocol.test.js` – end-to-end test (`cd server && npm test`)

## Notes / limits

- Hotkey, typing and media keys are implemented for **Windows hosts** (via a persistent PowerShell
  process). On macOS/Linux, open/command/webhook/OBS work but key injection returns an error.
- iOS builds require a Mac with Xcode (`flutter build ios`); iOS permissions (camera, local network)
  are already in `Info.plist`. The Android debug build is verified.
- Existing layouts keep their pages. To get the new default screens, delete `~/.deckpad/config.json` (this resets your layout) and restart the companion.
- Some games and elevated (admin) windows ignore injected keys unless the companion also runs as admin.
