/**
 * Chrome Extension Popup - Main JS
 * Manages all tab interactions, profile CRUD, settings, and live status updates.
 */

// ─── Constants ─────────────────────────────────────────────────────────────────
const CONFIG_KEYS = {
  SESSION_ID: 'sessionId', PAIRING_CODE: 'pairingCode', SERVER_URL: 'serverUrl',
  BOT_ACTIVE: 'botActive', CHECK_INTERVAL: 'checkInterval', MISSION: 'mission',
  IVAC_CENTER: 'ivacCenter', VISA_TYPE: 'visaType', VISA_CATEGORY: 'visaCategory',
  PREFERRED_DATES: 'preferredDates', GAP_TIMING: 'gapTiming',
  PROFILES: 'profiles', ACTIVE_PROFILE: 'activeProfile',
  OTP_BUFFER: 'otpBuffer', LOG_ENTRIES: 'logEntries', AUTO_CONFIRM: 'autoConfirm',
};

const MISSIONS = ['Kolkata', 'Delhi', 'Mumbai', 'Chennai', 'Agartala', 'Guwahati', 'Agra', 'Chandigarh', 'Hyderabad', 'Bangalore'];
const IVAC_CENTERS = {
  'Dhaka': ['Uttara', 'Motijheel', 'Dhanmondi'],
  'Chittagong': ['Agrabad'],
  'Sylhet': ['Sylhet City'],
  'Rajshahi': ['Rajshahi City'],
  'Khulna': ['Khulna City'],
  'Mymensingh': ['Mymensingh City'],
};
const VISA_TYPES = ['Tourist', 'Business', 'Medical', 'Student', 'Employment', 'Conference'];

// ─── State ─────────────────────────────────────────────────────────────────────
let state = { config: {}, profiles: [], editingProfileIndex: -1, profileFiles: [] };

// ─── DOM helpers ───────────────────────────────────────────────────────────────
const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

function setHTML(el, html) { if (el) el.innerHTML = html; }
function setText(el, text) { if (el) el.textContent = text; }
function show(el) { el?.classList.remove('hidden'); }
function hide(el) { el?.classList.add('hidden'); }

// ─── Tab switching ─────────────────────────────────────────────────────────────
$$('.tab-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    $$('.tab-btn').forEach(b => b.classList.remove('active'));
    $$('.tab-content').forEach(c => c.classList.remove('active'));
    btn.classList.add('active');
    $(`#tab-${btn.dataset.tab}`).classList.add('active');
  });
});

// ─── Init ──────────────────────────────────────────────────────────────────────
async function init() {
  populateSelects();
  await loadStatus();
  renderOTPList();
  renderLogList();
  renderProfileList();
}

// ─── Populate static dropdowns ─────────────────────────────────────────────────
function populateSelects() {
  const missionSel = $('#qs-mission');
  MISSIONS.forEach(m => {
    const opt = document.createElement('option');
    opt.value = m; opt.textContent = m;
    missionSel.appendChild(opt);
  });

  const ivacSel = $('#qs-ivac');
  Object.entries(IVAC_CENTERS).forEach(([center, _]) => {
    const opt = document.createElement('option');
    opt.value = center; opt.textContent = center;
    ivacSel.appendChild(opt);
  });

  const typeSel = $('#qs-visa-type');
  VISA_TYPES.forEach(t => {
    const opt = document.createElement('option');
    opt.value = t; opt.textContent = t;
    typeSel.appendChild(opt);
  });
}

// ─── Load status from background SW ───────────────────────────────────────────
async function loadStatus() {
  return new Promise(resolve => {
    chrome.runtime.sendMessage({ type: 'get_status' }, (resp) => {
      if (!resp) { resolve(); return; }
      state.config = resp.config || {};
      state.profiles = resp.config?.[CONFIG_KEYS.PROFILES] || [];

      // WS status
      const dot = $('#ws-dot');
      if (resp.connected) {
        dot.classList.add('connected');
        dot.classList.remove('error');
      } else {
        dot.classList.remove('connected');
        dot.classList.add('error');
      }

      // Pairing code
      const code = resp.pairingCode || resp.config?.[CONFIG_KEYS.PAIRING_CODE] || '------';
      setText($('#pairing-code'), code);

      // Bot toggle
      const toggle = $('#toggle-bot');
      toggle.checked = resp.botActive || false;
      updateBotStatus(resp.botActive);

      // Quick settings
      if (state.config[CONFIG_KEYS.MISSION]) $('#qs-mission').value = state.config[CONFIG_KEYS.MISSION];
      if (state.config[CONFIG_KEYS.IVAC_CENTER]) $('#qs-ivac').value = state.config[CONFIG_KEYS.IVAC_CENTER];
      if (state.config[CONFIG_KEYS.VISA_TYPE]) $('#qs-visa-type').value = state.config[CONFIG_KEYS.VISA_TYPE];
      if (state.config[CONFIG_KEYS.CHECK_INTERVAL]) $('#qs-interval').value = state.config[CONFIG_KEYS.CHECK_INTERVAL];
      if (state.config[CONFIG_KEYS.PREFERRED_DATES]) {
        $('#qs-preferred-dates').value = (state.config[CONFIG_KEYS.PREFERRED_DATES] || []).join(', ');
      }
      $('#qs-auto-confirm').checked = !!state.config[CONFIG_KEYS.AUTO_CONFIRM];

      // Settings tab
      $('#set-server-url').value = state.config[CONFIG_KEYS.SERVER_URL] || 'http://localhost:3000';
      $('#set-session-id').textContent = resp.sessionId || '---';
      $('#set-gap-timing').value = state.config[CONFIG_KEYS.GAP_TIMING] || 3000;
      $('#set-auto-confirm').checked = !!state.config[CONFIG_KEYS.AUTO_CONFIRM];

      resolve();
    });
  });
}

function updateBotStatus(active) {
  const statusEl = $('#bot-status-text');
  statusEl.textContent = active ? 'Bot is active — monitoring...' : 'Bot is inactive';
  if (active) statusEl.classList.add('active');
  else statusEl.classList.remove('active');
}

// ─── OTP List ──────────────────────────────────────────────────────────────────
async function renderOTPList() {
  chrome.runtime.sendMessage({ type: 'get_otp_buffer' }, (resp) => {
    const otps = resp?.otps || [];
    const list = $('#otp-list');
    if (otps.length === 0) {
      setHTML(list, '<div class="empty-state">No OTPs received yet</div>');
      return;
    }
    setHTML(list, otps.slice().reverse().map(entry => `
      <div class="otp-entry">
        <span class="otp-code">${entry.otp}</span>
        <span class="otp-meta">from ${entry.sender || 'UNKNOWN'}</span>
        <span class="otp-time">${new Date(entry.receivedAt).toLocaleTimeString()}</span>
      </div>
    `).join(''));
  });
}

// ─── Log List ──────────────────────────────────────────────────────────────────
async function renderLogList() {
  const logs = state.config[CONFIG_KEYS.LOG_ENTRIES] || [];
  const container = $('#log-container');
  if (logs.length === 0) {
    setHTML(container, '<div class="empty-state">No log entries</div>');
    return;
  }
  setHTML(container, logs.slice().reverse().slice(0, 100).map(entry => `
    <div class="log-entry ${entry.level || 'info'}">
      <span class="log-time">${new Date(entry.ts).toLocaleTimeString()}</span>
      <span class="log-msg">${entry.msg}</span>
    </div>
  `).join(''));
}

// ─── Profile List ──────────────────────────────────────────────────────────────
function renderProfileList() {
  const profiles = state.profiles || [];
  const list = $('#profile-list');
  const activeIdx = state.config[CONFIG_KEYS.ACTIVE_PROFILE];

  if (profiles.length === 0) {
    setHTML(list, '<div class="empty-state">No profiles yet. Add one to get started.</div>');
    return;
  }

  setHTML(list, profiles.map((p, i) => `
    <div class="profile-item ${i === activeIdx ? 'active-profile' : ''}" data-index="${i}">
      <div class="profile-avatar">${(p.name || '?')[0].toUpperCase()}</div>
      <div class="profile-info">
        <div class="profile-name">${p.name || 'Unnamed'}</div>
        <div class="profile-passport">${p.passport_no || 'No passport'}</div>
      </div>
      <div class="profile-actions">
        ${i !== activeIdx ? `<button class="btn btn-sm btn-ghost" onclick="setActiveProfile(${i})">Use</button>` : '<span class="badge active">Active</span>'}
        <button class="btn btn-sm btn-ghost" onclick="editProfile(${i})">✏️</button>
        <button class="btn btn-sm btn-ghost" onclick="deleteProfile(${i})" style="color:var(--danger)">🗑</button>
      </div>
    </div>
  `).join(''));
}

window.setActiveProfile = async (index) => {
  await saveConfigKey(CONFIG_KEYS.ACTIVE_PROFILE, index);
  state.config[CONFIG_KEYS.ACTIVE_PROFILE] = index;
  renderProfileList();
};

window.editProfile = (index) => {
  state.editingProfileIndex = index;
  const profile = state.profiles[index];
  openProfileForm(profile);
};

window.deleteProfile = async (index) => {
  if (!confirm('Delete this profile?')) return;
  state.profiles.splice(index, 1);
  await saveConfigKey(CONFIG_KEYS.PROFILES, state.profiles);
  renderProfileList();
};

function openProfileForm(profile = null) {
  show($('#profile-form-card'));
  $('#profile-form-title').textContent = profile ? 'Edit Profile' : 'New Profile';

  if (profile) {
    $('#pf-name').value = profile.name || '';
    $('#pf-given-name').value = profile.given_name || '';
    $('#pf-surname').value = profile.surname || '';
    $('#pf-passport').value = profile.passport_no || '';
    $('#pf-dob').value = profile.dob || '';
    $('#pf-phone').value = profile.phone || '';
    $('#pf-email').value = profile.email || '';
    $('#pf-gender').value = profile.gender || 'Male';
    $('#pf-nationality').value = profile.nationality || '';
    $('#pf-address').value = profile.address || '';
  } else {
    $('#profile-form-card').querySelectorAll('input, select').forEach(el => el.value = '');
    state.editingProfileIndex = -1;
    state.profileFiles = [];
    setHTML($('#pf-file-list'), '');
  }
}

// ─── Profile Save ──────────────────────────────────────────────────────────────
$('#btn-save-profile').addEventListener('click', async () => {
  const profile = {
    name: $('#pf-name').value,
    given_name: $('#pf-given-name').value,
    surname: $('#pf-surname').value,
    passport_no: $('#pf-passport').value,
    dob: $('#pf-dob').value,
    phone: $('#pf-phone').value,
    email: $('#pf-email').value,
    gender: $('#pf-gender').value,
    nationality: $('#pf-nationality').value,
    address: $('#pf-address').value,
    documents: state.profileFiles,
  };

  if (!profile.name) { alert('Profile name is required'); return; }

  if (state.editingProfileIndex >= 0) {
    state.profiles[state.editingProfileIndex] = profile;
  } else {
    state.profiles.push(profile);
  }

  await saveConfigKey(CONFIG_KEYS.PROFILES, state.profiles);
  hide($('#profile-form-card'));
  renderProfileList();
  state.editingProfileIndex = -1;
  state.profileFiles = [];
});

// ─── File upload handling ──────────────────────────────────────────────────────
const fileDropZone = $('#file-drop-zone');
fileDropZone.addEventListener('click', () => $('#pf-files').click());
fileDropZone.addEventListener('dragover', e => { e.preventDefault(); fileDropZone.classList.add('drag-over'); });
fileDropZone.addEventListener('dragleave', () => fileDropZone.classList.remove('drag-over'));
fileDropZone.addEventListener('drop', e => {
  e.preventDefault();
  fileDropZone.classList.remove('drag-over');
  handleFiles([...e.dataTransfer.files]);
});
$('#pf-files').addEventListener('change', e => handleFiles([...e.target.files]));

async function handleFiles(files) {
  for (const file of files) {
    if (!file.type.includes('pdf') && !file.type.includes('image')) continue;
    const dataUrl = await readFileAsDataURL(file);
    state.profileFiles.push({ name: file.name, dataUrl, type: file.type });
  }
  renderFileList();
}

function readFileAsDataURL(file) {
  return new Promise(resolve => {
    const reader = new FileReader();
    reader.onload = e => resolve(e.target.result);
    reader.readAsDataURL(file);
  });
}

function renderFileList() {
  setHTML($('#pf-file-list'), state.profileFiles.map((f, i) => `
    <div class="file-item">
      <span>📄 ${f.name}</span>
      <span class="file-remove" onclick="removeFile(${i})">✕</span>
    </div>
  `).join(''));
}

window.removeFile = (i) => { state.profileFiles.splice(i, 1); renderFileList(); };

// ─── Bot toggle ────────────────────────────────────────────────────────────────
$('#toggle-bot').addEventListener('change', async (e) => {
  const active = e.target.checked;
  chrome.runtime.sendMessage({ type: 'toggle_bot', active }, () => {
    updateBotStatus(active);
  });
});

// ─── Buttons ───────────────────────────────────────────────────────────────────
$('#btn-open-portal').addEventListener('click', () => {
  chrome.runtime.sendMessage({ type: 'open_ivac_tab' });
  window.close();
});

$('#btn-start-automation').addEventListener('click', async () => {
  const [tab] = await chrome.tabs.query({ url: 'https://appointment.ivacbd.com/*', active: true });
  if (!tab) {
    alert('Please open the IVAC portal first (https://appointment.ivacbd.com)');
    return;
  }
  chrome.tabs.sendMessage(tab.id, { type: 'start_automation' });
  window.close();
});

$('#btn-reset-session').addEventListener('click', () => {
  if (!confirm('Generate a new pairing code? The Android app will need to re-pair.')) return;
  chrome.runtime.sendMessage({ type: 'reset_session' }, () => loadStatus());
});

$('#btn-copy-code').addEventListener('click', () => {
  const code = $('#pairing-code').textContent;
  navigator.clipboard.writeText(code).then(() => {
    $('#btn-copy-code').textContent = '✅';
    setTimeout(() => { $('#btn-copy-code').textContent = '📋'; }, 1500);
  });
});

$('#btn-add-profile').addEventListener('click', () => {
  state.editingProfileIndex = -1;
  state.profileFiles = [];
  openProfileForm();
});

$('#btn-close-profile-form').addEventListener('click', () => hide($('#profile-form-card')));
$('#btn-cancel-profile').addEventListener('click', () => hide($('#profile-form-card')));

$('#btn-save-quick').addEventListener('click', async () => {
  const dates = $('#qs-preferred-dates').value
    .split(',').map(d => d.trim()).filter(Boolean);

  const cfg = {
    [CONFIG_KEYS.MISSION]: $('#qs-mission').value,
    [CONFIG_KEYS.IVAC_CENTER]: $('#qs-ivac').value,
    [CONFIG_KEYS.VISA_TYPE]: $('#qs-visa-type').value,
    [CONFIG_KEYS.CHECK_INTERVAL]: parseInt($('#qs-interval').value) || 20,
    [CONFIG_KEYS.PREFERRED_DATES]: dates,
    [CONFIG_KEYS.AUTO_CONFIRM]: $('#qs-auto-confirm').checked,
  };

  chrome.runtime.sendMessage({ type: 'save_config', config: cfg }, () => {
    $('#btn-save-quick').textContent = '✅ Saved!';
    setTimeout(() => { $('#btn-save-quick').textContent = '💾 Save Settings'; }, 2000);
  });
});

$('#btn-save-server').addEventListener('click', () => {
  const cfg = { [CONFIG_KEYS.SERVER_URL]: $('#set-server-url').value };
  chrome.runtime.sendMessage({ type: 'save_config', config: cfg }, () => {
    loadStatus();
    $('#btn-save-server').textContent = '✅ Saved!';
    setTimeout(() => { $('#btn-save-server').textContent = 'Save & Reconnect'; }, 2000);
  });
});

$('#btn-save-automation').addEventListener('click', () => {
  const cfg = {
    [CONFIG_KEYS.GAP_TIMING]: parseInt($('#set-gap-timing').value) || 3000,
    [CONFIG_KEYS.AUTO_CONFIRM]: $('#set-auto-confirm').checked,
  };
  chrome.runtime.sendMessage({ type: 'save_config', config: cfg }, () => {
    $('#btn-save-automation').textContent = '✅ Saved!';
    setTimeout(() => { $('#btn-save-automation').textContent = 'Save'; }, 2000);
  });
});

$('#btn-reset-all').addEventListener('click', () => {
  if (!confirm('Reset ALL settings and profiles? This cannot be undone.')) return;
  chrome.storage.local.clear(() => {
    state = { config: {}, profiles: [], editingProfileIndex: -1, profileFiles: [] };
    chrome.runtime.sendMessage({ type: 'reset_session' });
    init();
  });
});

$('#btn-clear-otp').addEventListener('click', async () => {
  await chrome.storage.local.set({ [CONFIG_KEYS.OTP_BUFFER]: [] });
  renderOTPList();
});

$('#btn-clear-logs').addEventListener('click', async () => {
  await chrome.storage.local.set({ [CONFIG_KEYS.LOG_ENTRIES]: [] });
  renderLogList();
});

// ─── Save a single config key ──────────────────────────────────────────────────
async function saveConfigKey(key, value) {
  return new Promise(resolve => {
    chrome.storage.local.set({ [key]: value }, resolve);
  });
}

// ─── Listen for real-time messages from background SW ─────────────────────────
chrome.runtime.onMessage.addListener((msg) => {
  switch (msg.type) {
    case 'ws_status':
      const dot = $('#ws-dot');
      if (msg.connected) { dot.classList.add('connected'); dot.classList.remove('error'); }
      else { dot.classList.remove('connected'); dot.classList.add('error'); }
      if (msg.pairingCode) setText($('#pairing-code'), msg.pairingCode);
      break;

    case 'otp_received':
      renderOTPList();
      break;

    case 'connected':
      if (msg.pairingCode) setText($('#pairing-code'), msg.pairingCode);
      break;

    case 'session_status':
      const androidBadge = $('#badge-android');
      if (msg.androidConnected) androidBadge.classList.add('connected');
      else androidBadge.classList.remove('connected');
      break;
  }
});

// ─── Start ────────────────────────────────────────────────────────────────────
init();
