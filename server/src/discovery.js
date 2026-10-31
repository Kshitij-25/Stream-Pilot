'use strict';
// LAN discovery: the phone broadcasts "DECKPAD?" over UDP and every companion answers with its address.
const dgram = require('dgram');
const os = require('os');

const DISCOVERY_PORT = parseInt(process.env.DECKPAD_DISCOVERY_PORT, 10) || 8766;

function lanAddresses() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const i of list || []) if (i.family === 'IPv4' && !i.internal) out.push(i.address);
  }
  return out.sort((a, b) => Number(/^(192\.168|10\.)/.test(b)) - Number(/^(192\.168|10\.)/.test(a)));
}

function startDiscovery(wsPort) {
  const sock = dgram.createSocket({ type: 'udp4', reuseAddr: true });
  sock.on('message', (msg, rinfo) => {
    if (msg.toString().trim() !== 'DECKPAD?') return;
    const reply = JSON.stringify({ app: 'deckpad', name: os.hostname(), port: wsPort, addresses: lanAddresses() });
    sock.send(reply, rinfo.port, rinfo.address);
  });
  sock.on('error', () => {}); // discovery is optional; QR / manual entry still work
  sock.bind(DISCOVERY_PORT);
  return sock;
}

module.exports = { startDiscovery, lanAddresses, DISCOVERY_PORT };
