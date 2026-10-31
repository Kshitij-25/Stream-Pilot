'use strict';
// Performance sampling: CPU, RAM, GPU (NVIDIA), network throughput, OBS frame stats. Keeps a short history.
const os = require('os');
const { execFile } = require('child_process');

const HISTORY = 90; // samples (2s apart = 3 minutes)

function run(cmd, args, timeout = 3000) {
  return new Promise((resolve, reject) => {
    execFile(cmd, args, { windowsHide: true, timeout }, (err, stdout) => (err ? reject(err) : resolve(String(stdout))));
  });
}

class Perf {
  constructor(obs) {
    this.obs = obs;
    this.last = { cpu: 0, mem: 0, gpu: null, netDown: null, netUp: null, obsFps: null, dropped: null, bitrate: null };
    this.history = [];
    this._cpu = os.cpus().map((c) => ({ ...c.times }));
    this._net = null;
    this._streamBytes = null;
    this._gpuOk = true;
    this._busy = false;
  }

  _cpuPercent() {
    const now = os.cpus().map((c) => ({ ...c.times }));
    let idle = 0;
    let total = 0;
    now.forEach((t, i) => {
      const p = this._cpu[i] || t;
      total += Object.keys(t).reduce((a, k) => a + (t[k] - (p[k] || 0)), 0);
      idle += t.idle - (p.idle || 0);
    });
    this._cpu = now;
    return total ? Math.round((1 - idle / total) * 100) : 0;
  }

  async _gpu() {
    if (!this._gpuOk) return null;
    try {
      const out = await run('nvidia-smi', ['--query-gpu=utilization.gpu', '--format=csv,noheader,nounits']);
      const v = parseInt(out.split('\n')[0], 10);
      return Number.isFinite(v) ? v : null;
    } catch (e) {
      if (e.code === 'ENOENT') this._gpuOk = false; // no NVIDIA driver on this machine
      return null;
    }
  }

  async _network() {
    if (process.platform !== 'win32') return null;
    try {
      const m = /Bytes\s+(\d+)\s+(\d+)/.exec(await run('netstat', ['-e']));
      return m ? { rx: Number(m[1]), tx: Number(m[2]), at: Date.now() } : null;
    } catch {
      return null;
    }
  }

  async sample() {
    if (this._busy) return this.last;
    this._busy = true;
    try {
      const s = { cpu: this._cpuPercent(), mem: Math.round((1 - os.freemem() / os.totalmem()) * 100) };
      s.gpu = await this._gpu();

      const n = await this._network();
      if (n && this._net) {
        const dt = (n.at - this._net.at) / 1000 || 1;
        s.netDown = Math.max(0, Math.round((n.rx - this._net.rx) / dt));
        s.netUp = Math.max(0, Math.round((n.tx - this._net.tx) / dt));
      } else {
        s.netDown = s.netUp = null;
      }
      this._net = n;

      s.obsFps = s.dropped = s.bitrate = null;
      if (this.obs && this.obs.ready) {
        try {
          const st = await this.obs.request('GetStats');
          s.obsFps = Math.round(st.activeFps || 0);
          s.dropped = st.outputSkippedFrames || 0;
        } catch {}
        if (this.obs.state.streaming) {
          try {
            const ss = await this.obs.request('GetStreamStatus');
            const now = Date.now();
            if (this._streamBytes) {
              const dt = (now - this._streamBytes.at) / 1000 || 1;
              s.bitrate = Math.max(0, Math.round(((ss.outputBytes - this._streamBytes.bytes) * 8) / 1000 / dt));
            }
            this._streamBytes = { bytes: ss.outputBytes, at: now };
            s.dropped = ss.outputSkippedFrames || s.dropped;
          } catch {}
        } else {
          this._streamBytes = null;
        }
      }
      this.last = s;
      this.history.push({ t: Date.now(), ...s });
      if (this.history.length > HISTORY) this.history.shift();
    } finally {
      this._busy = false;
    }
    return this.last;
  }
}

module.exports = { Perf };
