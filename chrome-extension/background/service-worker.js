/**
 * Background Service Worker - IVAC Visa Bot Chrome Extension
 * Maintains WebSocket connection to backend, routes OTPs to active tab.
 */

import { CONFIG_KEYS, DEFAULT_CONFIG, WS_MSG } from './constants.js';

let ws = null;
let sessionId = null;
let pairingCode = null;
let reconnectTimer = null;
let pingTimer = null;
let reconnectAttempts = 0;
const MAX_RECONNECT_DELAY = 30000;

// ─── Storage helpers ───────────────────────────────────────────────────────────
async function getConfig(key) {
  const result = await chrome.storage.local.get(key);
  return result[key];
}

async function setConfig(key, value) {
  await chrome.storage.local.set({ [key]: value });
}

async function getAllConfig() {
  const result = await chrome.storage.local.get(null);
  return { ...DEFAULT_CONFIG, ...result };
}

// ─── Session management ────────────────────────────────────────────────────────
async function initSession() {
  let sid = await getConfig(CONFIG_KEYS.SESSION_ID);
  const serverUrl = await getConfig(CONFIG_KEYS.SERVER_URL) || DEFAULT_CONFIG.serverUrl;

  if (!sid) {
    try {
      const resp = await fetch(`${serverUrl}/api/sessions`, { method: 'POST' });
      const data = await resp.json();
      if (data.success) {
        sid = data.sessionId;
        pairingCode = data.pairingCode;
        await setConfig(CONFIG_KEYS.SESSION_ID, sid);
        await setConfig(CONFIG_KEYS.PAIRING_CODE, pairingCode);
        console.log('[SW] New session created:', sid, 'Code:', pairingCode);
      }
    } catch (err) {
      console.error('[SW] Failed to create session:', err);
      return null;
    }
  } else {
    pairingCode = await getConfig(CONFIG_KEYS.PAIRING_CODE);
  }
  sessionId = sid;
  return sid;
}

// ─── WebSocket connection ──────────────────────────────────────────────────────
async function connectWebSocket() {
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) return;

  const serverUrl = await getConfig(CONFIG_KEYS.SERVER_URL) || DEFAULT_CONFIG.serverUrl;
  const wsUrl = serverUrl.replace(/^http/, 'ws') + '/ws';

  if (!sessionId) {
    await initSession();
    if (!sessionId) return;
  }

  console.log('[SW] Connecting to WebSocket:', wsUrl);
  ws = new WebSocket(wsUrl);

  ws.onopen = () => {
    console.log('[SW] WebSocket connected');
    reconnectAttempts = 0;
    ws.send(JSON.stringify({ type: WS_MSG.EXTENSION_CONNECT, sessionId }));
    startPing();
    notifyPopup({ type: 'ws_status', connected: true, pairingCode });
  };

  ws.onmessage = async (event) => {
    let msg;
    try { msg = JSON.parse(event.data); } catch { return; }
    console.log('[SW] WS message:', msg.type);

    switch (msg.type) {
      case 'connected':
        pairingCode = msg.pairingCode;
        await setConfig(CONFIG_KEYS.PAIRING_CODE, pairingCode);
        notifyPopup({ type: 'connected', pairingCode, sessionId });
        break;

      case 'otp':
        await handleIncomingOTP(msg);
        break;

      case 'session_status':
        notifyPopup({ type: 'session_status', ...msg });
        break;

      case 'pong':
        break;

      case 'error':
        console.error('[SW] Server error:', msg.error);
        break;
    }
  };

  ws.onclose = () => {
    console.log('[SW] WebSocket disconnected');
    stopPing();
    ws = null;
    notifyPopup({ type: 'ws_status', connected: false });
    scheduleReconnect();
  };

  ws.onerror = (err) => {
    console.error('[SW] WebSocket error:', err);
  };
}

function startPing() {
  stopPing();
  pingTimer = setInterval(() => {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'ping' }));
    }
  }, 25000);
}

function stopPing() {
  if (pingTimer) { clearInterval(pingTimer); pingTimer = null; }
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  const delay = Math.min(2000 * Math.pow(2, reconnectAttempts), MAX_RECONNECT_DELAY);
  reconnectAttempts++;
  console.log(`[SW] Reconnecting in ${delay}ms (attempt ${reconnectAttempts})`);
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connectWebSocket();
  }, delay);
}

// ─── OTP handling ──────────────────────────────────────────────────────────────
async function handleIncomingOTP(msg) {
  const { otp, rawMessage, sender, receivedAt } = msg;
  console.log('[SW] Received OTP:', otp, 'from:', sender);

  // Store in buffer
  const buffer = (await getConfig(CONFIG_KEYS.OTP_BUFFER)) || [];
  buffer.push({ otp, rawMessage, sender, receivedAt: receivedAt || Date.now() });
  await setConfig(CONFIG_KEYS.OTP_BUFFER, buffer.slice(-10)); // keep last 10

  // Show notification
  chrome.notifications.create({
    type: 'basic',
    iconUrl: '../icons/icon48.png',
    title: 'OTP Received',
    message: `OTP: ${otp} from ${sender}`,
  });

  // Route to active IVAC tab
  const tabs = await chrome.tabs.query({ url: 'https://appointment.ivacbd.com/*' });
  if (tabs.length > 0) {
    const activeTab = tabs.find(t => t.active) || tabs[0];
    try {
      await chrome.tabs.sendMessage(activeTab.id, { type: 'otp_received', otp, rawMessage, sender });
      console.log('[SW] OTP sent to tab:', activeTab.id);
    } catch (err) {
      console.warn('[SW] Could not send OTP to tab:', err.message);
    }
  }

  notifyPopup({ type: 'otp_received', otp, sender, receivedAt: receivedAt || Date.now() });
}

// ─── Notify popup if open ──────────────────────────────────────────────────────
function notifyPopup(msg) {
  chrome.runtime.sendMessage(msg).catch(() => {});
}

// ─── Alarm for slot monitoring ─────────────────────────────────────────────────
chrome.alarms.create('slot_check', { periodInMinutes: 0.33 }); // ~20 seconds

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === 'slot_check') {
    const config = await getAllConfig();
    if (!config[CONFIG_KEYS.BOT_ACTIVE]) return;

    const tabs = await chrome.tabs.query({ url: 'https://appointment.ivacbd.com/*' });
    if (tabs.length > 0) {
      const tab = tabs.find(t => t.active) || tabs[0];
      try {
        await chrome.tabs.sendMessage(tab.id, { type: 'check_slots', config });
      } catch (err) {
        console.warn('[SW] Slot check message failed:', err.message);
      }
    }
  }
});

// ─── Message handler from popup & content scripts ─────────────────────────────
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  (async () => {
    switch (msg.type) {
      case 'get_status': {
        const config = await getAllConfig();
        sendResponse({
          connected: ws && ws.readyState === WebSocket.OPEN,
          sessionId,
          pairingCode: pairingCode || config[CONFIG_KEYS.PAIRING_CODE],
          botActive: config[CONFIG_KEYS.BOT_ACTIVE],
          config,
        });
        break;
      }
      case 'save_config': {
        for (const [k, v] of Object.entries(msg.config)) {
          await setConfig(k, v);
        }
        if (msg.config[CONFIG_KEYS.SERVER_URL]) {
          // Reconnect with new server URL
          if (ws) ws.close();
          sessionId = null;
          await chrome.storage.local.remove([CONFIG_KEYS.SESSION_ID, CONFIG_KEYS.PAIRING_CODE]);
          pairingCode = null;
          await connectWebSocket();
        }
        sendResponse({ success: true });
        break;
      }
      case 'toggle_bot': {
        await setConfig(CONFIG_KEYS.BOT_ACTIVE, msg.active);
        sendResponse({ success: true, active: msg.active });
        break;
      }
      case 'reset_session': {
        if (ws) ws.close();
        sessionId = null;
        pairingCode = null;
        await chrome.storage.local.remove([CONFIG_KEYS.SESSION_ID, CONFIG_KEYS.PAIRING_CODE]);
        await connectWebSocket();
        sendResponse({ success: true });
        break;
      }
      case 'get_otp_buffer': {
        const buffer = (await getConfig(CONFIG_KEYS.OTP_BUFFER)) || [];
        sendResponse({ otps: buffer });
        break;
      }
      case 'open_ivac_tab': {
        chrome.tabs.create({ url: 'https://appointment.ivacbd.com/' });
        sendResponse({ success: true });
        break;
      }
    }
  })();
  return true;
});

// ─── Install / startup ────────────────────────────────────────────────────────
chrome.runtime.onInstalled.addListener(async () => {
  console.log('[SW] Extension installed');
  await chrome.storage.local.set(DEFAULT_CONFIG);
  await connectWebSocket();
});

chrome.runtime.onStartup.addListener(async () => {
  console.log('[SW] Extension startup');
  await connectWebSocket();
});

// ─── Action Click: Toggle In-Page Widget ────────────────────────────────────────
chrome.action.onClicked.addListener(async (tab) => {
  if (tab?.id) {
    try {
      await chrome.tabs.sendMessage(tab.id, { type: 'toggle_inpage_ui' });
    } catch {
      // If content script is not yet injected or tab is not on IVAC, open IVAC portal
      chrome.tabs.create({ url: 'https://appointment.ivacbd.com/' });
    }
  }
});

// Initial connection
connectWebSocket();
