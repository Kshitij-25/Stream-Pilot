'use strict';
// OBS client vs a mock obs-websocket v5 server (auth handshake, requests, events, reconnect).
const assert = require('assert');
const crypto = require('crypto');
const WebSocket = require('ws');
const { ObsClient } = require('../src/obs');

const PORT = 18850;
const PASSWORD = 'secret123';
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const sha = (s) => crypto.createHash('sha256').update(s).digest('base64');

const calls = [];
let wss;
let sockets = [];
let streaming = false;
let scene = 'Gameplay';

function startMock() {
  wss = new WebSocket.Server({ port: PORT, handleProtocols: (p) => [...p][0] });
  wss.on('connection', (ws) => {
    sockets.push(ws);
    const salt = 'saltysalt';
    const challenge = 'challenge42';
    ws.send(JSON.stringify({ op: 0, d: { obsWebSocketVersion: '5.5.0', rpcVersion: 1, authentication: { challenge, salt } } }));
    ws.on('message', (raw) => {
      const m = JSON.parse(raw.toString());
      if (m.op === 1) {
        const expect = sha(sha(PASSWORD + salt) + challenge);
        if (m.d.authentication !== expect) return ws.close(4009, 'Authentication failed');
        assert.strictEqual(m.d.rpcVersion, 1);
        assert.ok(m.d.eventSubscriptions & 64, 'subscribes to Outputs');
        return ws.send(JSON.stringify({ op: 2, d: { negotiatedRpcVersion: 1 } }));
      }
      if (m.op === 6) {
        const { requestType: t, requestId, requestData: d } = m.d;
        calls.push({ t, d });
        const ok = (data = {}) => ws.send(JSON.stringify({ op: 7, d: { requestType: t, requestId, requestStatus: { result: true, code: 100 }, responseData: data } }));
        const fail = (comment) => ws.send(JSON.stringify({ op: 7, d: { requestType: t, requestId, requestStatus: { result: false, code: 600, comment } } }));
        const event = (eventType, eventData) => ws.send(JSON.stringify({ op: 5, d: { eventType, eventData } }));
        switch (t) {
          case 'GetStreamStatus': return ok({ outputActive: streaming, outputDuration: 5000 });
          case 'GetRecordStatus': return ok({ outputActive: false });
          case 'GetCurrentProgramScene': return ok({ currentProgramSceneName: scene });
          case 'SetCurrentProgramScene':
            if (d.sceneName === 'Nope') return fail('No scene was found by the name of Nope.');
            scene = d.sceneName; ok(); return event('CurrentProgramSceneChanged', { sceneName: scene });
          case 'ToggleStream': streaming = !streaming; ok({ outputActive: streaming }); return event('StreamStateChanged', { outputActive: streaming });
          case 'ToggleInputMute': ok({ inputMuted: true }); return event('InputMuteStateChanged', { inputName: d.inputName, inputMuted: true });
          case 'GetSceneList': return ok({ scenes: [{ sceneName: 'BRB' }, { sceneName: 'Gameplay' }] });
          case 'GetInputList': return ok({ inputs: [{ inputName: 'Mic/Aux' }] });
          case 'GetSceneItemId': return ok({ sceneItemId: 7 });
          case 'GetSceneItemEnabled': return ok({ sceneItemEnabled: true });
          default: return ok();
        }
      }
    });
  });
}

(async () => {
  startMock();
  let password = 'wrong';
  const obs = new ObsClient(() => ({ host: '127.0.0.1', port: PORT, password }));
  obs.start();
  await wait(800);
  assert.strictEqual(obs.state.connected, false, 'wrong password must not connect');
  console.log('ok wrong password rejected');

  password = PASSWORD;
  obs.reconnect();
  for (let i = 0; i < 30 && !obs.state.connected; i++) await wait(100);
  assert.ok(obs.state.connected, 'connects with the right password');
  await wait(200);
  assert.strictEqual(obs.state.scene, 'Gameplay');
  assert.strictEqual(obs.state.streaming, false);
  console.log('ok authentication + initial state');

  await obs.perform({ op: 'scene', scene: 'BRB' });
  await wait(100);
  assert.strictEqual(obs.state.scene, 'BRB', 'scene event updates state');
  await assert.rejects(obs.perform({ op: 'scene', scene: 'Nope' }), /No scene was found/);
  await obs.perform({ op: 'toggleStream' });
  await wait(100);
  assert.strictEqual(obs.state.streaming, true);
  assert.ok(obs.state.streamStart > 0, 'stream start time tracked');
  await obs.perform({ op: 'toggleMute', input: 'Mic/Aux' });
  await wait(100);
  assert.strictEqual(obs.state.muted['Mic/Aux'], true);
  await obs.perform({ op: 'toggleSource', source: 'Webcam' });
  assert.ok(calls.some((c) => c.t === 'SetSceneItemEnabled' && c.d.sceneItemEnabled === false && c.d.sceneItemId === 7));
  const list = await obs.listScenesAndInputs();
  assert.deepStrictEqual(list.scenes, ['Gameplay', 'BRB']);
  console.log('ok scenes / stream / mute / source toggle + live state events');

  // OBS restarts: client notices, then reconnects by itself
  sockets.forEach((s) => s.terminate());
  await wait(300);
  assert.strictEqual(obs.state.connected, false);
  assert.strictEqual(obs.state.streaming, false, 'state cleared while disconnected');
  await assert.rejects(obs.perform({ op: 'toggleStream' }), /not connected/i);
  for (let i = 0; i < 80 && !obs.state.connected; i++) await wait(100);
  assert.ok(obs.state.connected, 'reconnected automatically');
  console.log('ok disconnect handling + automatic reconnect');

  obs.stop();
  wss.close();
  console.log('OBS PASSED');
})().catch((e) => { console.error('FAILED', e); process.exitCode = 1; })
  .finally(() => setTimeout(() => process.exit(), 300));
