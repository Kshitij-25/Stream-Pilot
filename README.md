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

- Button grid (1–8 columns × 1–10 rows), multiple pages, folders, Back/Home buttons
- Actions: **hotkeys**, **type text**, **open app/file/URL**, **OBS** (switch scene, stream, record, mute, show/hide source, replay buffer), **media keys**, **shell command**, **webhook**, and **multi-actions** (macros with waits)
- Live feedback: buttons light up for active scene / streaming / recording / muted; LIVE and REC badges
- On-phone editor: label, emoji icon, colour, action form, "Test on PC", drag to rearrange, resize grid, manage pages
- Layout is stored on the PC (`~/.deckpad/config.json`) and syncs to every paired phone
- Auto-reconnect, keep-screen-on, haptics

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
- Some games and elevated (admin) windows ignore injected keys unless the companion also runs as admin.
