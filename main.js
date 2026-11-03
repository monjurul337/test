'use strict';
/*
 * Moxixo Antidetect Browser — main process (Electron + Node.js)
 *
 * Core idea: every profile = one persistent Electron session partition
 * (persist:moxixo-<id>). Partitions have fully separate cookies, cache,
 * localStorage and IndexedDB on disk, so accounts never leak into
 * each other. On top of that each profile gets its own proxy, user-agent,
 * language, timezone (CDP override) and a consistent fingerprint script.
 */
const { app, BrowserWindow, ipcMain, session, dialog, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const net = require('net');
const { spawn } = require('child_process');
const {
  UA_PRESETS,
  RESOLUTIONS,
  buildInjection
} = require('./src/fingerprint');
const vpnLib = require('./src/vpn');

// ---------------------------------------------------------------- store
const storeFile = () => path.join(app.getPath('userData'), 'profiles.json');

function loadProfiles() {
  try {
    const raw = fs.readFileSync(storeFile(), 'utf8');
    const data = JSON.parse(raw);
    if (Array.isArray(data)) return data;
  } catch (e) {
    /* first run */
  }
  return null;
}

function saveProfiles(list) {
  fs.mkdirSync(path.dirname(storeFile()), { recursive: true });
  fs.writeFileSync(storeFile(), JSON.stringify(list, null, 2), 'utf8');
}

function newId() {
  return crypto.randomBytes(6).toString('hex');
}

function defaultProfile(name) {
  return {
    id: newId(),
    name: name || 'New Profile',
    group: 'Default',
    notes: '',
    startUrl: 'https://www.google.com',
    uaPreset: 'win-chrome',
    resolution: '1920x1080',
    language: 'en-US',
    timezone: 'Asia/Dhaka',
    connection: 'proxy', // 'proxy' | 'vpn'
    proxy: { type: 'none', host: '', port: '', username: '', password: '' },
    vpn: { type: '', fileName: '', endpoint: '', configText: '' },
    createdAt: new Date().toISOString(),
    lastUsedAt: null
  };
}

let profiles = [];
const running = new Map(); // profileId -> BrowserWindow
const proxyAuth = new Map(); // webContents.id -> { username, password }

// Proxy authentication (HTTP/SOCKS proxies that need login)
app.on('login', (event, webContents, details, authInfo, callback) => {
  if (!authInfo.isProxy) return;
  const creds = proxyAuth.get(webContents.id);
  if (creds && creds.username) {
    event.preventDefault();
    callback(creds.username, creds.password || '');
  }
});

// ---------------------------------------------------------------- session
function proxyRulesFor(proxy) {
  if (!proxy || proxy.type === 'none' || !proxy.host) return 'direct://';
  const host = String(proxy.host).trim();
  const port = String(proxy.port || '').trim();
  const target = port ? host + ':' + port : host;
  if (proxy.type === 'socks5') return 'socks5://' + target;
  if (proxy.type === 'https') return 'https://' + target;
  return 'http://' + target;
}

async function configureSession(profile, proxyRulesOverride) {
  const ses = session.fromPartition('persist:moxixo-' + profile.id, { cache: true });
  const preset = UA_PRESETS.find((p) => p.id === profile.uaPreset) || UA_PRESETS[0];
  try {
    await ses.setProxy({ proxyRules: proxyRulesOverride || proxyRulesFor(profile.proxy) });
  } catch (e) {
    console.error('setProxy failed', e);
  }
  try {
    ses.setUserAgent(preset.userAgent, profile.language || 'en-US');
  } catch (e) {
    /* older Electron */
  }
  const lang = profile.language || 'en-US';
  ses.webRequest.onBeforeSendHeaders((details, callback) => {
    details.requestHeaders['Accept-Language'] = lang + ',' + lang.split('-')[0] + ';q=0.9,en;q=0.8';
    callback({ requestHeaders: details.requestHeaders });
  });
  return ses;
}

// ---------------------------------------------------------------- vpn tunnels
const tunnels = new Map(); // key -> { type, child, port, file }

function getFreePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.listen(0, '127.0.0.1', () => {
      const port = srv.address().port;
      srv.close(() => resolve(port));
    });
    srv.on('error', reject);
  });
}

function waitForPort(port, timeoutMs) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const attempt = () => {
      const sock = net.connect(port, '127.0.0.1');
      sock.once('connect', () => {
        sock.destroy();
        resolve();
      });
      sock.once('error', () => {
        sock.destroy();
        if (Date.now() - started > timeoutMs) reject(new Error('Tunnel port did not open in time'));
        else setTimeout(attempt, 250);
      });
    };
    attempt();
  });
}

function vpnTempDir() {
  const dir = path.join(app.getPath('userData'), 'vpn-tmp');
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

// Starts the profile's VPN tunnel.
// Returns { rules } — proxy rules the browser session must use
// (local SOCKS for WireGuard, direct for system-wide OpenVPN).
async function startTunnel(profile, key) {
  if (tunnels.has(key)) {
    const t = tunnels.get(key);
    return { rules: t.port ? 'socks5://127.0.0.1:' + t.port : 'direct://' };
  }
  const cfgText = profile.vpn && profile.vpn.configText ? profile.vpn.configText : '';
  const invalid = vpnLib.validateVpnConfig(cfgText);
  if (invalid) throw new Error(invalid);
  const { type } = vpnLib.parseVpnConfig(cfgText);
  const appRoot = app.getAppPath();

  if (type === 'wireguard') {
    const bin = vpnLib.findWireproxy(appRoot, process.resourcesPath);
    if (!bin) {
      throw new Error(
        'WireGuard engine (wireproxy) not found. The GitHub build includes it automatically; ' +
          'for a local run, put wireproxy in the app\u2019s bin/ folder or on your PATH. See README \u2192 VPN.'
      );
    }
    const port = await getFreePort();
    const file = path.join(vpnTempDir(), 'wg-' + key + '.conf');
    fs.writeFileSync(file, vpnLib.makeWireproxyConf(cfgText, port), 'utf8');
    // Validate with the engine itself before spawning
    const { spawnSync } = require('child_process');
    const test = spawnSync(bin, ['-n', '-c', file], { timeout: 8000, windowsHide: true });
    if (test.status !== 0) {
      throw new Error('WireGuard config rejected by engine: ' + String(test.stderr || test.stdout || '').trim().slice(0, 300));
    }
    const child = spawn(bin, ['-c', file], { windowsHide: true });
    let errBuf = '';
    child.stderr.on('data', (d) => (errBuf = (errBuf + d).slice(-800)));
    child.stdout.on('data', (d) => (errBuf = (errBuf + d).slice(-800)));
    tunnels.set(key, { type, child, port, file });
    try {
      await waitForPort(port, 6000);
    } catch (e) {
      stopTunnel(key);
      throw new Error('WireGuard tunnel failed to start. ' + errBuf.trim().slice(0, 300));
    }
    if (child.exitCode !== null) {
      stopTunnel(key);
      throw new Error('WireGuard engine exited early. ' + errBuf.trim().slice(0, 300));
    }
    return { rules: 'socks5://127.0.0.1:' + port };
  }

  // OpenVPN — system-wide tunnel via the installed OpenVPN client
  for (const [, t] of tunnels) {
    if (t.type === 'openvpn') {
      throw new Error('Another OpenVPN profile is already running. OpenVPN tunnels are system-wide, so only one can run at a time — stop it first.');
    }
  }
  const bin = vpnLib.findOpenvpn(appRoot, process.resourcesPath);
  if (!bin) {
    throw new Error(
      'OpenVPN client not found. Install OpenVPN (openvpn.net/community-downloads) — on Windows also run Moxixo as Administrator so routes can be set.'
    );
  }
  const file = path.join(vpnTempDir(), 'ovpn-' + key + '.ovpn');
  fs.writeFileSync(file, cfgText, 'utf8');
  const child = spawn(bin, ['--config', file, '--verb', '3'], { windowsHide: true });
  tunnels.set(key, { type, child, port: 0, file });
  await new Promise((resolve, reject) => {
    let buf = '';
    const timer = setTimeout(() => {
      stopTunnel(key);
      reject(new Error('OpenVPN did not connect within 40s. Last log: ' + buf.trim().slice(-300)));
    }, 40000);
    const onData = (d) => {
      buf = (buf + d).slice(-1500);
      if (/Initialization Sequence Completed/i.test(buf)) {
        clearTimeout(timer);
        resolve();
      }
    };
    child.stdout.on('data', onData);
    child.stderr.on('data', onData);
    child.on('exit', (code) => {
      clearTimeout(timer);
      if (tunnels.has(key)) {
        stopTunnel(key);
        reject(new Error('OpenVPN exited (code ' + code + '). On Windows it usually needs Administrator rights. Last log: ' + buf.trim().slice(-300)));
      }
    });
  });
  return { rules: 'direct://' };
}

function stopTunnel(key) {
  const t = tunnels.get(key);
  if (!t) return;
  tunnels.delete(key);
  try {
    if (t.child && t.child.exitCode === null) t.child.kill();
  } catch (e) {
    /* already gone */
  }
  try {
    if (t.file) fs.unlinkSync(t.file);
  } catch (e) {
    /* temp file may be locked; ignore */
  }
}

// ---------------------------------------------------------------- launch
async function launchProfile(profile) {
  if (running.has(profile.id)) {
    const existing = running.get(profile.id);
    if (!existing.isDestroyed()) {
      existing.focus();
      return { ok: true, already: true };
    }
    running.delete(profile.id);
  }

  let proxyRulesOverride;
  if (profile.connection === 'vpn') {
    try {
      const t = await startTunnel(profile, profile.id);
      proxyRulesOverride = t.rules;
    } catch (e) {
      return { ok: false, error: 'VPN: ' + e.message };
    }
  }
  const ses = await configureSession(profile, proxyRulesOverride);
  const preset = UA_PRESETS.find((p) => p.id === profile.uaPreset) || UA_PRESETS[0];
  const res = RESOLUTIONS.find((r) => r.id === profile.resolution) || RESOLUTIONS[0];

  const win = new BrowserWindow({
    width: Math.min(res.width, 1600),
    height: Math.min(res.height, 950),
    minWidth: 480,
    minHeight: 360,
    title: 'Moxixo — ' + profile.name,
    backgroundColor: '#121016',
    autoHideMenuBar: true,
    webPreferences: {
      session: ses,
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true
    }
  });
  win.webContents.setUserAgent(preset.userAgent);

  if (profile.proxy && profile.proxy.username) {
    proxyAuth.set(win.webContents.id, {
      username: profile.proxy.username,
      password: profile.proxy.password || ''
    });
  }

  // Timezone + locale override through Chrome DevTools Protocol
  try {
    if (!win.webContents.debugger.isAttached()) win.webContents.debugger.attach('1.3');
    if (profile.timezone && profile.timezone !== 'UTC') {
      await win.webContents.debugger.sendCommand('Emulation.setTimezoneOverride', {
        timezoneId: profile.timezone
      });
    }
    await win.webContents.debugger.sendCommand('Emulation.setLocaleOverride', {
      locale: profile.language || 'en-US'
    });
  } catch (e) {
    /* CDP override is best-effort */
  }

  const injection = buildInjection(profile);
  const inject = () => {
    win.webContents.executeJavaScript(injection, true).catch(() => {});
  };
  win.webContents.on('dom-ready', inject);
  win.webContents.on('did-navigate-in-page', inject);

  // Keep popups inside the same isolated profile session
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:\/\//i.test(url)) win.webContents.loadURL(url);
    return { action: 'deny' };
  });
  // External non-http links (mailto:, tel:) go to the OS
  win.webContents.on('will-navigate', (event, url) => {
    if (!/^https?:\/\//i.test(url) && !url.startsWith('about:') && !url.startsWith('data:')) {
      event.preventDefault();
      shell.openExternal(url).catch(() => {});
    }
  });

  win.on('closed', () => {
    running.delete(profile.id);
    proxyAuth.delete(win.webContents.id);
    stopTunnel(profile.id);
    notifyRunningChanged();
  });

  running.set(profile.id, win);
  profile.lastUsedAt = new Date().toISOString();
  saveProfiles(profiles);
  notifyRunningChanged();

  const url = /^https?:\/\//i.test(profile.startUrl || '')
    ? profile.startUrl
    : 'https://www.google.com';
  await win.loadURL(url).catch(() => {});
  return { ok: true };
}

function notifyRunningChanged() {
  if (dashboardWin && !dashboardWin.isDestroyed()) {
    dashboardWin.webContents.send('running:changed', Array.from(running.keys()));
  }
}

// Proxy / IP check: loads an IP echo page in a hidden window that uses the
// profile's own session (proxy + auth included), then reads the JSON.
async function checkProfileIp(profile) {
  let proxyRulesOverride;
  let tempTunnelKey = null;
  if (profile.connection === 'vpn') {
    if (tunnels.has(profile.id)) {
      const t = tunnels.get(profile.id);
      proxyRulesOverride = t.port ? 'socks5://127.0.0.1:' + t.port : 'direct://';
    } else {
      tempTunnelKey = 'check-' + profile.id;
      try {
        const t = await startTunnel(profile, tempTunnelKey);
        proxyRulesOverride = t.rules;
      } catch (e) {
        return { ok: false, error: 'VPN: ' + e.message };
      }
    }
  }
  const ses = await configureSession(profile, proxyRulesOverride);
  const result = await new Promise((resolve) => {
    const win = new BrowserWindow({
      show: false,
      width: 480,
      height: 360,
      webPreferences: { session: ses, nodeIntegration: false, contextIsolation: true, sandbox: true }
    });
    if (profile.proxy && profile.proxy.username) {
      proxyAuth.set(win.webContents.id, {
        username: profile.proxy.username,
        password: profile.proxy.password || ''
      });
    }
    const done = (result) => {
      proxyAuth.delete(win.webContents.id);
      if (!win.isDestroyed()) win.destroy();
      resolve(result);
    };
    const timer = setTimeout(() => done({ ok: false, error: 'Timeout (25s) — proxy unreachable' }), 25000);
    win.webContents.on('did-finish-load', async () => {
      try {
        const text = await win.webContents.executeJavaScript('document.body ? document.body.innerText : ""', true);
        clearTimeout(timer);
        const data = JSON.parse(text);
        done({
          ok: true,
          ip: data.ip || data.query || '',
          country: data.country_name || data.country || '',
          city: data.city || '',
          org: data.org || data.isp || ''
        });
      } catch (e) {
        clearTimeout(timer);
        done({ ok: false, error: 'Could not read IP response' });
      }
    });
    win.webContents.on('did-fail-load', (e, code, desc) => {
      clearTimeout(timer);
      done({ ok: false, error: 'Load failed: ' + desc + ' (' + code + ')' });
    });
    win.loadURL('https://ipapi.co/json/').catch(() => {});
  });
  if (tempTunnelKey) stopTunnel(tempTunnelKey);
  return result;
}

// ---------------------------------------------------------------- dashboard
let dashboardWin = null;

function createDashboard() {
  dashboardWin = new BrowserWindow({
    width: 1280,
    height: 840,
    minWidth: 1024,
    minHeight: 640,
    title: 'Moxixo Antidetect Browser',
    backgroundColor: '#e9eff9',
    icon: path.join(__dirname, 'assets', 'icon.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true
    }
  });
  dashboardWin.loadFile(path.join(__dirname, 'src', 'index.html'));
  dashboardWin.on('closed', () => {
    dashboardWin = null;
  });
}

// ---------------------------------------------------------------- ipc
ipcMain.handle('profiles:list', () => profiles);
ipcMain.handle('running:list', () => Array.from(running.keys()));

ipcMain.handle('profiles:save', (event, profile) => {
  if (!profile.id) profile.id = newId();
  if (!profile.createdAt) profile.createdAt = new Date().toISOString();
  const idx = profiles.findIndex((p) => p.id === profile.id);
  if (idx >= 0) profiles[idx] = profile;
  else profiles.push(profile);
  saveProfiles(profiles);
  return profile;
});

ipcMain.handle('profiles:clone', (event, id) => {
  const src = profiles.find((p) => p.id === id);
  if (!src) return null;
  const copy = JSON.parse(JSON.stringify(src));
  copy.id = newId();
  copy.name = src.name + ' (copy)';
  copy.createdAt = new Date().toISOString();
  copy.lastUsedAt = null;
  // Note: cookies/session are NOT copied — a clone starts as a fresh
  // device, which is the correct antidetect behaviour.
  profiles.push(copy);
  saveProfiles(profiles);
  return copy;
});

ipcMain.handle('profiles:delete', async (event, id) => {
  const win = running.get(id);
  if (win && !win.isDestroyed()) win.close();
  try {
    const ses = session.fromPartition('persist:moxixo-' + id);
    await ses.clearStorageData();
    await ses.clearCache();
  } catch (e) {
    /* partition may not exist yet */
  }
  profiles = profiles.filter((p) => p.id !== id);
  saveProfiles(profiles);
  return { ok: true };
});

ipcMain.handle('profiles:launch', async (event, id) => {
  const profile = profiles.find((p) => p.id === id);
  if (!profile) return { ok: false, error: 'Profile not found' };
  return launchProfile(profile);
});

ipcMain.handle('profiles:stop', (event, id) => {
  const win = running.get(id);
  if (win && !win.isDestroyed()) win.close(); // 'closed' also stops the tunnel
  stopTunnel(id);
  return { ok: true };
});

ipcMain.handle('vpn:tools', () => {
  return {
    wireproxy: vpnLib.findWireproxy(app.getAppPath(), process.resourcesPath),
    openvpn: vpnLib.findOpenvpn(app.getAppPath(), process.resourcesPath)
  };
});

ipcMain.handle('vpn:parse', (event, text) => {
  return Object.assign({}, vpnLib.parseVpnConfig(text || ''), {
    error: vpnLib.validateVpnConfig(text || '')
  });
});

ipcMain.handle('vpn:pick-file', async () => {
  const result = await dialog.showOpenDialog(dashboardWin, {
    title: 'Choose a VPN config file',
    properties: ['openFile'],
    filters: [
      { name: 'VPN config', extensions: ['conf', 'ovpn', 'txt'] },
      { name: 'All files', extensions: ['*'] }
    ]
  });
  if (result.canceled || !result.filePaths.length) return { ok: false };
  try {
    const filePath = result.filePaths[0];
    const text = fs.readFileSync(filePath, 'utf8');
    return Object.assign(
      { ok: true, fileName: path.basename(filePath), text },
      vpnLib.parseVpnConfig(text),
      { error: vpnLib.validateVpnConfig(text) }
    );
  } catch (e) {
    return { ok: false, error: 'Could not read that file' };
  }
});

ipcMain.handle('profiles:check-ip', async (event, id) => {
  const profile = profiles.find((p) => p.id === id);
  if (!profile) return { ok: false, error: 'Profile not found' };
  return checkProfileIp(profile);
});

ipcMain.handle('profiles:export', async () => {
  const result = await dialog.showSaveDialog(dashboardWin, {
    title: 'Export Moxixo profiles',
    defaultPath: 'moxixo-profiles.json',
    filters: [{ name: 'JSON', extensions: ['json'] }]
  });
  if (result.canceled || !result.filePath) return { ok: false };
  fs.writeFileSync(result.filePath, JSON.stringify(profiles, null, 2), 'utf8');
  return { ok: true, count: profiles.length };
});

ipcMain.handle('profiles:import', async () => {
  const result = await dialog.showOpenDialog(dashboardWin, {
    title: 'Import Moxixo profiles',
    properties: ['openFile'],
    filters: [{ name: 'JSON', extensions: ['json'] }]
  });
  if (result.canceled || !result.filePaths.length) return { ok: false };
  try {
    const imported = JSON.parse(fs.readFileSync(result.filePaths[0], 'utf8'));
    if (!Array.isArray(imported)) throw new Error('not an array');
    let added = 0;
    for (const p of imported) {
      if (!p || typeof p.name !== 'string') continue;
      const fresh = Object.assign(defaultProfile(p.name), p);
      fresh.id = newId(); // fresh session partition on this machine
      fresh.lastUsedAt = null;
      profiles.push(fresh);
      added++;
    }
    saveProfiles(profiles);
    return { ok: true, count: added };
  } catch (e) {
    return { ok: false, error: 'Invalid profiles file' };
  }
});

ipcMain.handle('meta:presets', () => {
  const { UA_PRESETS, RESOLUTIONS, LANGUAGES, TIMEZONES } = require('./src/fingerprint');
  return { UA_PRESETS, RESOLUTIONS, LANGUAGES, TIMEZONES };
});

// ---------------------------------------------------------------- boot
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (dashboardWin) {
      if (dashboardWin.isMinimized()) dashboardWin.restore();
      dashboardWin.focus();
    }
  });

  app.whenReady().then(() => {
    profiles = loadProfiles() || [defaultProfile('Demo Profile — Facebook Ads')];
    saveProfiles(profiles);
    createDashboard();
    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) createDashboard();
    });
  });

  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
  });

  app.on('before-quit', () => {
    for (const key of [...tunnels.keys()]) stopTunnel(key);
  });
}
