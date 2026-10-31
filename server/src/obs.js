'use strict';
// Minimal obs-websocket v5 client (OBS 28+ has it built in: Tools > WebSocket Server Settings).
const { EventEmitter } = require('events');
const crypto = require('crypto');
const WebSocket = require('ws');

// General(1) | Scenes(4) | Inputs(8) | Outputs(64)
const SUBSCRIPTIONS = 1 | 4 | 8 | 64;

class ObsClient extends EventEmitter {
  constructor(getSettings) {
    super();
    this.getSettings = getSettings;
    this.ws = null;
    this.ready = false;
    this.pending = new Map();
    this.seq = 0;
    this.timer = null;
    this.stopped = false;
    this.state = { connected: false, streaming: false, recording: false, scene: null, muted: {}, streamStart: null, recordStart: null };
  }

  start() {
    this.stopped = false;
    this._connect();
  }

  stop() {
    this.stopped = true;
    clearTimeout(this.timer);
    if (this.ws) this.ws.close();
  }

  reconnect() {
    clearTimeout(this.timer);
    if (this.ws) {
      this.ws.removeAllListeners();
      try { this.ws.close(); } catch {}
    }
    this._dropped();
    this._connect();
  }

  _setState(patch) {
    Object.assign(this.state, patch);
    this.emit('state', this.state);
  }

  _dropped() {
    this.ready = false;
    for (const { reject } of this.pending.values()) reject(new Error('OBS disconnected'));
    this.pending.clear();
    if (this.state.connected) this._setState({ connected: false, streaming: false, recording: false, streamStart: null, recordStart: null });
  }

  _connect() {
    if (this.stopped) return;
    const { host, port, password } = this.getSettings();
    let ws;
    try {
      ws = new WebSocket(`ws://${host}:${port}`, ['obswebsocket.json']);
    } catch {
      return this._retry();
    }
    this.ws = ws;
    ws.on('message', (data) => this._onMessage(ws, data, password));
    ws.on('error', () => {});
    ws.on('close', () => {
      if (this.ws !== ws) return;
      this._dropped();
      this._retry();
    });
  }

  _retry() {
    if (this.stopped) return;
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this._connect(), 4000);
  }

  _onMessage(ws, raw, password) {
    let msg;
    try { msg = JSON.parse(raw.toString()); } catch { return; }
    const { op, d } = msg;
    if (op === 0) {
      const identify = { rpcVersion: 1, eventSubscriptions: SUBSCRIPTIONS };
      if (d.authentication) {
        const secret = crypto.createHash('sha256').update(password + d.authentication.salt).digest('base64');
        identify.authentication = crypto.createHash('sha256').update(secret + d.authentication.challenge).digest('base64');
      }
      ws.send(JSON.stringify({ op: 1, d: identify }));
    } else if (op === 2) {
      this.ready = true;
      this._setState({ connected: true });
      this._refresh().catch(() => {});
    } else if (op === 5) {
      this._onEvent(d);
    } else if (op === 7) {
      const p = this.pending.get(d.requestId);
      if (!p) return;
      this.pending.delete(d.requestId);
      if (d.requestStatus && d.requestStatus.result) p.resolve(d.responseData || {});
      else p.reject(new Error((d.requestStatus && d.requestStatus.comment) || 'OBS request failed'));
    }
  }

  _onEvent({ eventType, eventData }) {
    switch (eventType) {
      case 'StreamStateChanged':
        this._setState({ streaming: !!eventData.outputActive, streamStart: eventData.outputActive ? Date.now() : null });
        break;
      case 'RecordStateChanged':
        this._setState({ recording: !!eventData.outputActive, recordStart: eventData.outputActive ? Date.now() : null });
        break;
      case 'CurrentProgramSceneChanged':
        this._setState({ scene: eventData.sceneName });
        break;
      case 'InputMuteStateChanged':
        this._setState({ muted: { ...this.state.muted, [eventData.inputName]: !!eventData.inputMuted } });
        break;
    }
  }

  async _refresh() {
    const [stream, record, scene] = await Promise.all([
      this.request('GetStreamStatus'),
      this.request('GetRecordStatus'),
      this.request('GetCurrentProgramScene'),
    ]);
    this._setState({
      streaming: !!stream.outputActive,
      recording: !!record.outputActive,
      streamStart: stream.outputActive ? Date.now() - (stream.outputDuration || 0) : null,
      recordStart: record.outputActive ? Date.now() - (record.outputDuration || 0) : null,
      scene: scene.currentProgramSceneName || scene.sceneName || null,
    });
  }

  request(requestType, requestData) {
    if (!this.ready) return Promise.reject(new Error('OBS is not connected (check host/port/password in Settings)'));
    const requestId = String(++this.seq);
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => {
        this.pending.delete(requestId);
        reject(new Error('OBS request timed out'));
      }, 8000);
      this.pending.set(requestId, {
        resolve: (v) => { clearTimeout(t); resolve(v); },
        reject: (e) => { clearTimeout(t); reject(e); },
      });
      this.ws.send(JSON.stringify({ op: 6, d: { requestType, requestId, requestData } }));
    });
  }

  async listScenesAndInputs() {
    const [s, i] = await Promise.all([this.request('GetSceneList'), this.request('GetInputList')]);
    return {
      scenes: (s.scenes || []).map((x) => x.sceneName).reverse(),
      inputs: (i.inputs || []).map((x) => x.inputName),
    };
  }

  async perform(a) {
    switch (a.op) {
      case 'scene':
        return this.request('SetCurrentProgramScene', { sceneName: a.scene });
      case 'toggleStream':
        return this.request('ToggleStream');
      case 'startStream':
        return this.request('StartStream');
      case 'stopStream':
        return this.request('StopStream');
      case 'toggleRecord':
        return this.request('ToggleRecord');
      case 'toggleMute':
        return this.request('ToggleInputMute', { inputName: a.input });
      case 'mute':
        return this.request('SetInputMute', { inputName: a.input, inputMuted: true });
      case 'unmute':
        return this.request('SetInputMute', { inputName: a.input, inputMuted: false });
      case 'saveReplay':
        return this.request('SaveReplayBuffer');
      case 'toggleReplayBuffer':
        return this.request('ToggleReplayBuffer');
      case 'toggleVirtualCam':
        return this.request('ToggleVirtualCam');
      case 'pauseRecord':
        return this.request('ToggleRecordPause');
      case 'studioTransition':
        return this.request('TriggerStudioModeTransition');
      case 'toggleStudioMode': {
        const { studioModeEnabled } = await this.request('GetStudioModeEnabled');
        return this.request('SetStudioModeEnabled', { studioModeEnabled: !studioModeEnabled });
      }
      case 'toggleFilter': {
        const { filterEnabled } = await this.request('GetSourceFilter', { sourceName: a.source, filterName: a.filter });
        return this.request('SetSourceFilterEnabled', { sourceName: a.source, filterName: a.filter, filterEnabled: !filterEnabled });
      }
      case 'setVolume':
        return this.request('SetInputVolume', { inputName: a.input, inputVolumeDb: Math.max(-100, Math.min(26, Number(a.db) || 0)) });
      case 'hotkey':
        return this.request('TriggerHotkeyByName', { hotkeyName: a.name });
      case 'toggleSource': {
        const { sceneItemId } = await this.request('GetSceneItemId', { sceneName: a.scene || this.state.scene, sourceName: a.source });
        const sceneName = a.scene || this.state.scene;
        const { sceneItemEnabled } = await this.request('GetSceneItemEnabled', { sceneName, sceneItemId });
        return this.request('SetSceneItemEnabled', { sceneName, sceneItemId, sceneItemEnabled: !sceneItemEnabled });
      }
      default:
        throw new Error(`Unknown OBS operation "${a.op}"`);
    }
  }
}

module.exports = { ObsClient };
