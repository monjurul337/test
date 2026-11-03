'use strict';
/*
 * VPN helpers for Moxixo Antidetect Browser.
 *
 * WireGuard: run in userspace by "wireproxy" — it turns a normal
 * WireGuard .conf into a local SOCKS5 port, so ONLY this profile's
 * browser traffic uses the tunnel. No admin rights, per-profile.
 *
 * OpenVPN: no userspace equivalent exists, so the system OpenVPN client
 * is started with the profile's .ovpn file. That tunnel is system-wide
 * while it runs and needs the OpenVPN client installed (+ admin rights
 * on Windows). Only one OpenVPN profile can run at a time.
 */
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function detectVpnType(text) {
  const t = String(text || '');
  if (/\[Interface\]/i.test(t) && /PrivateKey\s*=/i.test(t)) return 'wireguard';
  if (/^\s*client\b/im.test(t) || /^\s*remote\s+\S+/im.test(t) || /\.ovpn/i.test(t)) return 'openvpn';
  return '';
}

function parseVpnConfig(text) {
  const t = String(text || '');
  const type = detectVpnType(t);
  let endpoint = '';
  if (type === 'wireguard') {
    const m = /^\s*Endpoint\s*=\s*(\S+)/im.exec(t);
    if (m) endpoint = m[1];
  } else if (type === 'openvpn') {
    const m = /^\s*remote\s+(\S+)(?:\s+(\d+))?/im.exec(t);
    if (m) endpoint = m[2] ? m[1] + ':' + m[2] : m[1];
  }
  return { type, endpoint };
}

function validateVpnConfig(text) {
  const { type } = parseVpnConfig(text);
  const t = String(text || '');
  if (!type) return 'Config not recognised — paste a WireGuard .conf or an OpenVPN .ovpn file.';
  if (type === 'wireguard') {
    if (!/PrivateKey\s*=\s*\S+/i.test(t)) return 'WireGuard config is missing PrivateKey.';
    if (!/PublicKey\s*=\s*\S+/i.test(t)) return 'WireGuard config is missing the peer PublicKey.';
    if (!/Endpoint\s*=\s*\S+/i.test(t)) return 'WireGuard config is missing the peer Endpoint.';
  }
  if (type === 'openvpn') {
    if (!/^\s*remote\s+\S+/im.test(t)) return 'OpenVPN config is missing a remote server line.';
  }
  return null;
}

// Build the config wireproxy will run: original .conf + a [Socks5]
// section bound to a local port (any existing one is replaced).
function makeWireproxyConf(text, port) {
  let t = String(text || '').replace(/\r\n/g, '\n');
  // drop an existing [Socks5] section (up to the next section or EOF)
  t = t.replace(/\[Socks5\][\s\S]*?(?=\n\[|$)/gi, '');
  t = t.trim() + '\n\n[Socks5]\nBindAddress = 127.0.0.1:' + port + '\n';
  return t;
}

function exeName(base) {
  return process.platform === 'win32' ? base + '.exe' : base;
}

function binaryWorks(candidate) {
  try {
    const r = spawnSync(candidate, ['--version'], { timeout: 4000, windowsHide: true });
    return !r.error;
  } catch (e) {
    return false;
  }
}

function fileExists(p) {
  try {
    return !!p && fs.existsSync(p);
  } catch (e) {
    return false;
  }
}

// appRoot = app.getAppPath(), resourcesPath = process.resourcesPath
function findWireproxy(appRoot, resourcesPath) {
  const exe = exeName('wireproxy');
  const candidates = [
    resourcesPath ? path.join(resourcesPath, 'bin', exe) : '',
    appRoot ? path.join(appRoot, 'bin', exe) : '',
    appRoot ? path.join(appRoot, '..', 'bin', exe) : ''
  ].filter(Boolean);
  for (const c of candidates) if (fileExists(c)) return c;
  if (binaryWorks(exe)) return exe; // on PATH
  return null;
}

function findOpenvpn(appRoot, resourcesPath) {
  const exe = exeName('openvpn');
  const candidates = [
    resourcesPath ? path.join(resourcesPath, 'bin', exe) : '',
    appRoot ? path.join(appRoot, 'bin', exe) : ''
  ].filter(Boolean);
  if (process.platform === 'win32') {
    candidates.push(
      'C:\\Program Files\\OpenVPN\\bin\\openvpn.exe',
      'C:\\Program Files (x86)\\OpenVPN\\bin\\openvpn.exe'
    );
  }
  for (const c of candidates) if (fileExists(c)) return c;
  try {
    const r = spawnSync(exe, ['--version'], { timeout: 4000, windowsHide: true });
    if (!r.error) return exe; // on PATH
  } catch (e) {
    /* not found */
  }
  return null;
}

module.exports = {
  detectVpnType,
  parseVpnConfig,
  validateVpnConfig,
  makeWireproxyConf,
  findWireproxy,
  findOpenvpn
};
