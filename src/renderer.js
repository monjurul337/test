'use strict';
/* Moxixo Antidetect Browser — dashboard logic (MostLogin-style layout) */
const $ = (id) => document.getElementById(id);

let profiles = [];
let runningIds = new Set();
let presets = { UA_PRESETS: [], RESOLUTIONS: [], LANGUAGES: [], TIMEZONES: [] };
let selected = new Set();
let ipNotes = {}; // profileId -> "103.1.2.3 · City, Country"
let opsTargetId = null;

const OS_SHORT = {
  'win-chrome': '🪟 Windows · Chrome',
  'win-edge': '🪟 Windows · Edge',
  'mac-chrome': '🍎 macOS · Chrome',
  'linux-chrome': '🐧 Linux · Chrome'
};
const OS_CHIP = {
  'win-chrome': '🪟 Windows',
  'win-edge': '🪟 Windows · Edge',
  'mac-chrome': '🍎 macOS',
  'linux-chrome': '🐧 Linux'
};
const GEO_PACKS = [
  { language: 'en-US', timezone: 'America/New_York' },
  { language: 'en-US', timezone: 'America/Los_Angeles' },
  { language: 'en-GB', timezone: 'Europe/London' },
  { language: 'bn-BD', timezone: 'Asia/Dhaka' },
  { language: 'es-ES', timezone: 'Europe/Berlin' },
  { language: 'en-GB', timezone: 'Australia/Sydney' }
];

function toast(msg) {
  const el = $('toast');
  el.textContent = msg;
  el.hidden = false;
  clearTimeout(toast._t);
  toast._t = setTimeout(() => (el.hidden = true), 3600);
}
function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
function proxyText(p) {
  if (p.connection === 'vpn') {
    const v = p.vpn || {};
    const label = v.type === 'openvpn' ? 'OpenVPN' : 'WireGuard';
    return '🔒 ' + label + (v.endpoint ? ' · ' + v.endpoint : '');
  }
  if (p.proxy && p.proxy.type !== 'none' && p.proxy.host)
    return p.proxy.type + '://' + p.proxy.host + (p.proxy.port ? ':' + p.proxy.port : '');
  return 'direct';
}

async function refresh() {
  profiles = await window.moxixo.listProfiles();
  runningIds = new Set(await window.moxixo.listRunning());
  selected = new Set([...selected].filter((id) => profiles.some((p) => p.id === id)));
  render();
}

function render() {
  renderProfilesTable();
  renderFolders();
  renderProxies();
  const groups = [...new Set(profiles.map((p) => p.group || 'Default'))].sort();
  const gf = $('group-filter');
  const cur = gf.value;
  gf.innerHTML =
    '<option value="">All folders</option>' +
    groups.map((g) => `<option ${g === cur ? 'selected' : ''}>${esc(g)}</option>`).join('');
  $('group-list').innerHTML = groups.map((g) => `<option value="${esc(g)}">`).join('');
  $('settings-stats').textContent =
    profiles.length + ' profiles · ' + groups.length + ' folders · ' + runningIds.size + ' running now';
}

function visibleProfiles() {
  const q = $('search').value.trim().toLowerCase();
  const gf = $('group-filter').value;
  return profiles.filter((p) => {
    if (gf && (p.group || 'Default') !== gf) return false;
    if (!q) return true;
    return (p.name + ' ' + (p.group || '') + ' ' + (p.notes || '')).toLowerCase().includes(q);
  });
}

function renderProfilesTable() {
  const vis = visibleProfiles();
  $('empty').hidden = vis.length !== 0;
  $('total-label').textContent = 'Total ' + vis.length + ' items';
  $('foot-stats').textContent =
    profiles.length + ' profiles · ' + runningIds.size + ' running · ' +
    profiles.filter((p) => p.connection === 'vpn' || (p.proxy && p.proxy.type !== 'none' && p.proxy.host)).length + ' with proxy/VPN';

  $('rows').innerHTML = vis
    .map((p, i) => {
      const live = runningIds.has(p.id);
      const last = p.lastUsedAt ? new Date(p.lastUsedAt).toLocaleDateString() : '—';
      return `
      <tr data-id="${p.id}">
        <td><input type="checkbox" class="row-check" ${selected.has(p.id) ? 'checked' : ''} /></td>
        <td class="c-no">${profiles.length - profiles.indexOf(p)}</td>
        <td>
          <div class="p-title">${esc(p.name)}</div>
          ${p.notes ? `<div class="p-sub">${esc(p.notes)}</div>` : ''}
        </td>
        <td><span class="status ${live ? 'running' : ''}">${live ? 'Running' : 'Ready'}</span></td>
        <td>
          <div class="ops-cell">
            ${live
              ? `<button class="play-btn stop" data-act="stop" title="Stop">■</button>`
              : `<button class="play-btn" data-act="launch" title="Start">▶</button>`}
            <button class="dots-btn" data-act="ops" title="More actions">⋮</button>
          </div>
        </td>
        <td class="folder-cell">📁 ${esc(p.group || 'Default')}</td>
        <td class="os-cell">${OS_SHORT[p.uaPreset] || esc(p.uaPreset)}</td>
        <td class="proxy-cell">${esc(proxyText(p))}${ipNotes[p.id] ? `<span class="ip-note">✓ ${esc(ipNotes[p.id])}</span>` : ''}</td>
        <td class="c-order">${esc(last)}</td>
      </tr>`;
    })
    .join('');
  $('check-all').checked = vis.length > 0 && vis.every((p) => selected.has(p.id));
}

function renderFolders() {
  const groups = {};
  profiles.forEach((p) => {
    const g = p.group || 'Default';
    groups[g] = (groups[g] || 0) + 1;
  });
  $('folder-grid').innerHTML = Object.keys(groups)
    .sort()
    .map(
      (g) => `
      <div class="folder-card" data-group="${esc(g)}">
        <div class="f-name">📁 ${esc(g)}</div>
        <div class="f-count">${groups[g]} profile${groups[g] === 1 ? '' : 's'} — click to view</div>
      </div>`
    )
    .join('') || '<p class="empty">No folders yet.</p>';
}

function renderProxies() {
  const rows = [];
  profiles.forEach((p) => {
    if (p.connection === 'vpn') {
      const v = p.vpn || {};
      rows.push({ id: p.id, type: v.type === 'openvpn' ? 'OpenVPN' : 'WireGuard', host: v.endpoint || '(from config)', user: '🔒 config', name: p.name });
    } else if (p.proxy && p.proxy.type !== 'none' && p.proxy.host) {
      rows.push({ id: p.id, type: p.proxy.type.toUpperCase(), host: p.proxy.host + (p.proxy.port ? ':' + p.proxy.port : ''), user: p.proxy.username || '—', name: p.name });
    }
  });
  $('proxy-empty').hidden = rows.length !== 0;
  $('proxy-rows').innerHTML = rows
    .map(
      (r) => `
      <tr data-id="${r.id}">
        <td>${esc(r.type)}</td>
        <td>${esc(r.host)}</td>
        <td>${esc(r.user)}</td>
        <td>${esc(r.name)}</td>
        <td><button class="play-btn" data-act="check" title="Check IP">🌐</button></td>
      </tr>`
    )
    .join('');
}

// ---------------- actions ----------------
async function doCheckIp(id, btn) {
  if (btn) btn.disabled = true;
  toast('Checking exit IP through this profile…');
  const r = await window.moxixo.checkIp(id);
  if (btn) btn.disabled = false;
  if (r.ok) {
    ipNotes[id] = (r.ip || '?') + (r.country ? ' · ' + (r.city ? r.city + ', ' : '') + r.country : '');
    toast('IP OK: ' + ipNotes[id]);
  } else {
    toast('Check failed: ' + (r.error || 'unknown error'));
  }
  renderProfilesTable();
}

document.addEventListener('click', async (e) => {
  // close floating menus when clicking elsewhere
  if (!e.target.closest('.dropdown')) $('batch-menu').hidden = true;
  if (!e.target.closest('[data-act="ops"]') && !e.target.closest('#ops-menu')) $('ops-menu').hidden = true;

  const check = e.target.closest('.row-check');
  if (check) {
    const id = check.closest('tr').dataset.id;
    if (check.checked) selected.add(id); else selected.delete(id);
    renderProfilesTable();
    return;
  }

  const folderCard = e.target.closest('.folder-card');
  if (folderCard) {
    $('group-filter').value = folderCard.dataset.group;
    switchTab('profiles');
    renderProfilesTable();
    return;
  }

  const btn = e.target.closest('button[data-act]');
  if (!btn) return;
  const row = btn.closest('tr');
  const id = row ? row.dataset.id : opsTargetId;
  const profile = profiles.find((p) => p.id === id);

  if (btn.dataset.act === 'launch') {
    btn.disabled = true;
    const r = await window.moxixo.launchProfile(id);
    if (!r.ok) toast('Launch failed: ' + (r.error || 'unknown error'));
    await refresh();
  }
  if (btn.dataset.act === 'stop') {
    await window.moxixo.stopProfile(id);
    await refresh();
  }
  if (btn.dataset.act === 'check') doCheckIp(id, btn);
  if (btn.dataset.act === 'ops') {
    opsTargetId = id;
    const menu = $('ops-menu');
    const rect = btn.getBoundingClientRect();
    menu.style.top = rect.bottom + 6 + 'px';
    menu.style.left = Math.max(8, rect.right - 190) + 'px';
    menu.hidden = false;
  }
});

$('ops-menu').addEventListener('click', async (e) => {
  const btn = e.target.closest('button[data-ops]');
  if (!btn || !opsTargetId) return;
  const id = opsTargetId;
  const profile = profiles.find((p) => p.id === id);
  $('ops-menu').hidden = true;
  if (btn.dataset.ops === 'check') doCheckIp(id, null);
  if (btn.dataset.ops === 'edit' && profile) openEditor(profile);
  if (btn.dataset.ops === 'clone') {
    await window.moxixo.cloneProfile(id);
    toast('Profile cloned — the clone starts with a fresh, clean session.');
    await refresh();
  }
  if (btn.dataset.ops === 'delete' && profile) {
    if (confirm('Delete "' + profile.name + '"?\n\nThis also erases its saved cookies and logins on this device. This cannot be undone.')) {
      await window.moxixo.deleteProfile(id);
      delete ipNotes[id];
      toast('Profile deleted.');
      await refresh();
    }
  }
});

$('check-all').addEventListener('change', (e) => {
  const vis = visibleProfiles();
  if (e.target.checked) vis.forEach((p) => selected.add(p.id));
  else vis.forEach((p) => selected.delete(p.id));
  renderProfilesTable();
});

// ---------------- toolbar ----------------
$('btn-refresh').addEventListener('click', refresh);
$('search').addEventListener('input', renderProfilesTable);
$('group-filter').addEventListener('change', renderProfilesTable);

$('btn-quick').addEventListener('click', async () => {
  let n = 1;
  profiles.forEach((p) => {
    const m = /^Profile (\d+)$/.exec(p.name || '');
    if (m) n = Math.max(n, parseInt(m[1], 10) + 1);
  });
  const geo = GEO_PACKS[Math.floor(Math.random() * GEO_PACKS.length)];
  const uaIds = presets.UA_PRESETS.map((x) => x.id);
  const resIds = presets.RESOLUTIONS.map((x) => x.id);
  const profile = {
    name: 'Profile ' + n,
    group: 'Default',
    notes: '',
    startUrl: 'https://www.google.com',
    uaPreset: uaIds[Math.floor(Math.random() * uaIds.length)],
    resolution: resIds[Math.floor(Math.random() * resIds.length)],
    language: geo.language,
    timezone: geo.timezone,
    proxy: { type: 'none', host: '', port: '', username: '', password: '' }
  };
  await window.moxixo.saveProfile(profile);
  toast('⚡ Quick profile created — fingerprint generated automatically. Edit it (⋮) to add a proxy.');
  await refresh();
});

$('btn-batch').addEventListener('click', () => {
  $('batch-menu').hidden = !$('batch-menu').hidden;
});
$('batch-menu').addEventListener('click', async (e) => {
  const btn = e.target.closest('button[data-batch]');
  if (!btn) return;
  $('batch-menu').hidden = true;
  const act = btn.dataset.batch;
  if (act === 'export') return $('btn-export').click();
  if (act === 'stop-all') {
    for (const id of [...runningIds]) await window.moxixo.stopProfile(id);
    toast('All running profiles stopped.');
    return refresh();
  }
  if (!selected.size) return toast('Select at least one profile first (checkbox).');
  if (act === 'start') {
    for (const id of [...selected]) await window.moxixo.launchProfile(id);
    toast('Started ' + selected.size + ' profile(s).');
    return refresh();
  }
  if (act === 'delete') {
    if (confirm('Delete ' + selected.size + ' selected profile(s)? Their saved logins on this device will be erased.')) {
      for (const id of [...selected]) await window.moxixo.deleteProfile(id);
      selected.clear();
      toast('Selected profiles deleted.');
      return refresh();
    }
  }
});

// ---------------- views & tabs ----------------
function switchView(name) {
  document.querySelectorAll('#side-nav .nav-item').forEach((b) =>
    b.classList.toggle('active', b.dataset.view === name)
  );
  ['profiles', 'proxies', 'team', 'resources', 'settings'].forEach((v) => {
    $('view-' + v).hidden = v !== name;
  });
}
$('side-nav').addEventListener('click', (e) => {
  const btn = e.target.closest('.nav-item');
  if (btn) switchView(btn.dataset.view);
});
function switchTab(name) {
  document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === name));
  ['profiles', 'folders', 'extensions'].forEach((t) => {
    $('tab-' + t).hidden = t !== name;
  });
}
document.querySelector('.tabs').addEventListener('click', (e) => {
  const tab = e.target.closest('.tab');
  if (tab) switchTab(tab.dataset.tab);
});

// ---------------- editor ----------------
function fillSelect(el, items, getVal, getLabel, selectedVal) {
  el.innerHTML = items
    .map((it) => `<option value="${esc(getVal(it))}" ${getVal(it) === selectedVal ? 'selected' : ''}>${esc(getLabel(it))}</option>`)
    .join('');
}
function renderOsChips(selectedId) {
  $('os-chips').innerHTML = presets.UA_PRESETS.map(
    (p) => `<span class="chip ${p.id === selectedId ? 'active' : ''}" data-ua="${p.id}">${OS_CHIP[p.id] || esc(p.label)}</span>`
  ).join('');
  $('f-ua').value = selectedId;
}
$('os-chips').addEventListener('click', (e) => {
  const chip = e.target.closest('.chip[data-ua]');
  if (chip) renderOsChips(chip.dataset.ua);
});

// ---------------- connection mode (proxy / vpn) ----------------
let vpnParsed = { type: '', endpoint: '', error: null };

function setConnectionUI(mode) {
  $('f-connection').value = mode;
  document.querySelectorAll('#conn-chips .chip').forEach((c) =>
    c.classList.toggle('active', c.dataset.conn === mode)
  );
  $('vpn-box').hidden = mode !== 'vpn';
  $('proxy-box-wrap').style.display = mode === 'vpn' ? 'none' : '';
}
$('conn-chips').addEventListener('click', (e) => {
  const chip = e.target.closest('.chip[data-conn]');
  if (chip) setConnectionUI(chip.dataset.conn);
});

function renderVpnSummary() {
  const box = $('vpn-summary');
  const text = $('f-vpn-text').value;
  if (!text.trim()) {
    box.className = 'vpn-summary';
    box.textContent = 'Paste or import a config — type and server will be detected automatically.';
    return;
  }
  if (vpnParsed.error) {
    box.className = 'vpn-summary bad';
    box.textContent = '⚠ ' + vpnParsed.error;
  } else {
    box.className = 'vpn-summary ok';
    box.textContent =
      '✓ ' + (vpnParsed.type === 'openvpn' ? 'OpenVPN' : 'WireGuard') +
      ' config detected' + (vpnParsed.endpoint ? ' — server: ' + vpnParsed.endpoint : '');
  }
}

let vpnParseTimer = null;
async function refreshVpnParse() {
  const text = $('f-vpn-text').value;
  if (!text.trim()) {
    vpnParsed = { type: '', endpoint: '', error: null };
    renderVpnSummary();
    return;
  }
  vpnParsed = await window.moxixo.vpnParse(text);
  renderVpnSummary();
}
$('f-vpn-text').addEventListener('input', () => {
  clearTimeout(vpnParseTimer);
  vpnParseTimer = setTimeout(refreshVpnParse, 350);
});

$('btn-vpn-file').addEventListener('click', async () => {
  const r = await window.moxixo.vpnPickFile();
  if (!r.ok) {
    if (r.error) toast(r.error);
    return;
  }
  $('f-vpn-text').value = r.text;
  $('vpn-filename').textContent = r.fileName;
  $('f-vpn-text').dataset.fileName = r.fileName;
  vpnParsed = { type: r.type, endpoint: r.endpoint, error: r.error };
  renderVpnSummary();
});
$('btn-vpn-clear').addEventListener('click', () => {
  $('f-vpn-text').value = '';
  $('f-vpn-text').dataset.fileName = '';
  $('vpn-filename').textContent = 'No file imported';
  vpnParsed = { type: '', endpoint: '', error: null };
  renderVpnSummary();
});

function openEditor(profile) {
  const p = profile || {
    id: '', name: '', group: 'Default', notes: '', startUrl: 'https://www.google.com',
    uaPreset: 'win-chrome', resolution: '1920x1080', language: 'en-US', timezone: 'Asia/Dhaka',
    connection: 'proxy',
    proxy: { type: 'none', host: '', port: '', username: '', password: '' },
    vpn: { type: '', fileName: '', endpoint: '', configText: '' }
  };
  $('modal-title-label').textContent = p.id ? 'Edit profile' : 'Advanced create';
  $('f-id').value = p.id || '';
  $('f-name').value = p.name || '';
  $('f-group').value = p.group || 'Default';
  $('f-starturl').value = p.startUrl || '';
  $('f-notes').value = p.notes || '';
  renderOsChips(p.uaPreset);
  fillSelect($('f-resolution'), presets.RESOLUTIONS, (x) => x.id, (x) => x.label, p.resolution);
  fillSelect($('f-language'), presets.LANGUAGES, (x) => x.value, (x) => x.label, p.language);
  $('f-timezone').innerHTML = presets.TIMEZONES.map(
    (tz) => `<option ${tz === p.timezone ? 'selected' : ''}>${esc(tz)}</option>`
  ).join('');
  $('f-proxy-type').value = (p.proxy && p.proxy.type) || 'none';
  $('f-proxy-host').value = (p.proxy && p.proxy.host) || '';
  $('f-proxy-port').value = (p.proxy && p.proxy.port) || '';
  $('f-proxy-user').value = (p.proxy && p.proxy.username) || '';
  $('f-proxy-pass').value = (p.proxy && p.proxy.password) || '';
  // VPN fields
  const v = p.vpn || {};
  $('f-vpn-text').value = v.configText || '';
  $('f-vpn-text').dataset.fileName = v.fileName || '';
  $('vpn-filename').textContent = v.fileName || 'No file imported';
  vpnParsed = { type: v.type || '', endpoint: v.endpoint || '', error: null };
  if ((v.configText || '').trim()) refreshVpnParse(); else renderVpnSummary();
  setConnectionUI(p.connection || 'proxy');
  $('modal').hidden = false;
}
function closeEditor() { $('modal').hidden = true; }

$('profile-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const existing = profiles.find((p) => p.id === $('f-id').value) || {};
  const profile = Object.assign({}, existing, {
    id: $('f-id').value || undefined,
    name: $('f-name').value.trim(),
    group: $('f-group').value.trim() || 'Default',
    startUrl: $('f-starturl').value.trim() || 'https://www.google.com',
    notes: $('f-notes').value.trim(),
    uaPreset: $('f-ua').value,
    resolution: $('f-resolution').value,
    language: $('f-language').value,
    timezone: $('f-timezone').value,
    proxy: {
      type: $('f-proxy-type').value,
      host: $('f-proxy-host').value.trim(),
      port: $('f-proxy-port').value.trim(),
      username: $('f-proxy-user').value.trim(),
      password: $('f-proxy-pass').value
    },
    connection: $('f-connection').value,
    vpn: {
      type: vpnParsed.type || '',
      fileName: $('f-vpn-text').dataset.fileName || '',
      endpoint: vpnParsed.endpoint || '',
      configText: $('f-vpn-text').value
    }
  });
  await window.moxixo.saveProfile(profile);
  closeEditor();
  toast('Profile saved.');
  await refresh();
});

$('btn-new').addEventListener('click', () => openEditor(null));
$('modal-close').addEventListener('click', closeEditor);
$('btn-cancel').addEventListener('click', closeEditor);
$('modal').addEventListener('click', (e) => {
  if (e.target === $('modal')) closeEditor();
});

// ---------------- import / export ----------------
async function doExport() {
  const r = await window.moxixo.exportProfiles();
  if (r.ok) toast('Exported ' + r.count + ' profiles (settings only — cookies stay on this device).');
}
async function doImport() {
  const r = await window.moxixo.importProfiles();
  if (r.ok) {
    toast('Imported ' + r.count + ' profiles.');
    await refresh();
  } else if (r.error) toast('Import failed: ' + r.error);
}
$('btn-export').addEventListener('click', doExport);
$('btn-import').addEventListener('click', doImport);
$('btn-export-2').addEventListener('click', doExport);
$('btn-import-2').addEventListener('click', doImport);

window.moxixo.onRunningChanged(async () => {
  runningIds = new Set(await window.moxixo.listRunning());
  renderProfilesTable();
});

(async function init() {
  presets = await window.moxixo.getPresets();
  try {
    const tools = await window.moxixo.vpnTools();
    $('tool-wg').textContent = tools.wireproxy ? '✓ Found' : '✗ Not found (GitHub build includes it)';
    $('tool-ovpn').textContent = tools.openvpn ? '✓ Found' : '✗ Not installed';
  } catch (e) {
    /* settings view only */
  }
  await refresh();
})();
