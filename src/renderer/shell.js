/* Sotizence Play Books Browser - shell UI (tabs, toolbar, settings) */
const $ = id => document.getElementById(id);
const esc = s => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const tm = t => { const d = new Date(t); return d.toLocaleTimeString([], { hour12: false }); };

let S = { tabs: [], activeId: null, settings: {}, profiles: [], meta: {}, vpnStatus: {}, vpnStore: {}, extensions: [], bookmarks: [], history: [] };
let page = null; // "settings" | null
let editingUrl = false;
let setSec = "vpn";

/* ---------- static icons ---------- */
$("newTab").innerHTML = icon("plus", 15);
$("bBack").innerHTML = icon("back", 17);
$("bFwd").innerHTML = icon("fwd", 17);
$("bReload").innerHTML = icon("reload", 15);
$("bHome").innerHTML = icon("home", 15);
$("bSettings").innerHTML = icon("settings", 16);
if ($("searchIcon")) $("searchIcon").innerHTML = icon("search", 14);
if ($("bCopyUrl")) $("bCopyUrl").innerHTML = icon("copy", 13);

function updateBookmarkStar() {
  const star = $("bStar");
  if (!star) return;
  const t = cur();
  const isHome = t && t.url && t.url.includes("home.html");
  if (!t || !t.url || isHome) {
    star.classList.add("hide");
    return;
  }
  star.classList.remove("hide");
  const isBookmarked = (S.bookmarks || []).some(b => b.url === t.url);
  if (isBookmarked) {
    star.classList.add("starred");
    star.innerHTML = icon("starFilled", 15);
    star.title = "Remove bookmark";
  } else {
    star.classList.remove("starred");
    star.innerHTML = icon("star", 15);
    star.title = "Bookmark this page (Ctrl+D)";
  }
}

if ($("bStar")) {
  $("bStar").innerHTML = icon("star", 15);
  $("bStar").onclick = async () => {
    const t = cur();
    const isHome = t && t.url && t.url.includes("home.html");
    if (!t || !t.url || isHome) return;
    const res = await app.bookmarksToggle({ url: t.url, title: t.title, favicon: t.favicon });
    if (res && res.bookmarks) S.bookmarks = res.bookmarks;
    updateBookmarkStar();
    if (page === "settings" && setSec === "bookmarks") renderSettings();
    toast(res && res.bookmarked ? "Bookmarked page ⭐" : "Bookmark removed");
  };
}
document.querySelector('[data-w="min"]').innerHTML = icon("min", 13);
document.querySelector('[data-w="max"]').innerHTML = icon("max", 12);
document.querySelector('[data-w="close"]').innerHTML = icon("x", 14);

document.querySelectorAll(".winctl button").forEach(b => b.onclick = () => app.win(b.dataset.w));
$("titlebar").addEventListener("dblclick", e => { if (e.target.classList.contains("drag") || e.target.id === "titlebar") app.win("max"); });
$("newTab").onclick = () => app.newTab();
$("bBack").onclick = () => app.nav("back");
$("bFwd").onclick = () => app.nav("forward");
$("bReload").onclick = () => { const t = cur(); app.nav(t && t.loading ? "stop" : "reload"); };
$("bHome").onclick = () => { closePage(); app.nav("home"); };
$("bSettings").onclick = () => page === "settings" ? closePage() : openPage("settings");
if ($("bVpn")) $("bVpn").onclick = () => { setSec = "vpn"; page === "settings" ? renderSettings() : openPage("settings"); };
if ($("bCopyUrl")) $("bCopyUrl").onclick = () => {
  const u = $("url").value.trim();
  if (u) {
    if (app.copyText) app.copyText(u);
    try { navigator.clipboard.writeText(u); } catch (e) {}
    toast("URL copied to clipboard");
  }
};
$("zoomBadge").onclick = () => app.nav("zoom", { d: 0 });
$("url").addEventListener("focus", () => { editingUrl = true; setTimeout(() => $("url").select(), 0); });
$("url").addEventListener("blur", () => { editingUrl = false; renderToolbar(); });
$("addr").addEventListener("submit", e => { e.preventDefault(); closePage(); app.nav("go", { url: $("url").value }); $("url").blur(); });
document.addEventListener("keydown", e => {
  if (e.key === "Escape" && page) closePage();
  if (e.key === "Escape" && editingUrl) $("url").blur();
});

const cur = () => S.tabs.find(t => t.id === S.activeId);

function renderVpnPill() {
  const pill = $("bVpn"), txt = $("vpnText");
  if (!pill || !txt) return;
  const st = S.vpnStatus || {};
  if (st.connecting) {
    pill.className = "vpn-pill connecting";
    txt.textContent = "Connecting...";
    pill.title = "Proton WireGuard: Connecting to tunnel...";
  } else if (st.running) {
    pill.className = "vpn-pill on";
    const loc = [st.city, st.country].filter(Boolean).join(", ");
    txt.textContent = st.country ? `VPN: ${st.country}` : "VPN Active";
    pill.title = `Proton WireGuard Connected\nIP: ${st.ip || "Routing Active"}\nLocation: ${loc || "United States"}\nPort: ${st.port || 10808}`;
  } else if (st.error) {
    pill.className = "vpn-pill error";
    txt.textContent = "VPN Error";
    pill.title = "WireGuard Error: " + st.error;
  } else {
    pill.className = "vpn-pill off";
    txt.textContent = "VPN Off";
    pill.title = "Proton WireGuard: Disconnected (Click to configure)";
  }
}


/* ---------- tabs ---------- */
function renderTabs() {
  const box = $("tabs");
  const ids = S.tabs.map(t => String(t.id));
  [...box.children].forEach(el => { if (!ids.includes(el.dataset.id)) el.remove(); });
  S.tabs.forEach((t, i) => {
    let el = box.querySelector(`[data-id="${t.id}"]`);
    if (!el) {
      el = document.createElement("div");
      el.className = "tab"; el.dataset.id = t.id;
      el.innerHTML = `<span class="pcol"></span><span class="fav"></span><span class="t"></span><button class="x" title="Close tab (Ctrl+W)">${icon("x", 13)}</button>`;
      el.addEventListener("mousedown", e => { if (e.button === 1) { e.preventDefault(); app.closeTab(t.id); } });
      el.addEventListener("click", e => { if (e.target.closest(".x")) app.closeTab(t.id); else { closePage(); app.activate(t.id); } });
    }
    if (box.children[i] !== el) box.insertBefore(el, box.children[i] || null);
    el.classList.toggle("active", t.id === S.activeId);
    const isHome = t.url && t.url.includes("home.html");
    el.querySelector(".t").textContent = isHome ? "Homepage" : (t.title || "New tab");
    el.querySelector(".pcol").style.background = S.profiles.length > 1 ? t.profile.color : "transparent";
    const fav = el.querySelector(".fav");
    const favHtml = t.loading ? '<span class="spin"></span>' : isHome ? icon("home", 14) : t.favicon ? `<img src="${esc(t.favicon)}" alt="">` : icon("globe", 14);
    if (fav.dataset.h !== favHtml) { fav.innerHTML = favHtml; fav.dataset.h = favHtml; }
  });
}

/* ---------- toolbar / status ---------- */
function renderToolbar() {
  const t = cur();
  $("bBack").disabled = !t || !t.canBack;
  $("bFwd").disabled = !t || !t.canForward;
  $("bReload").innerHTML = icon(t && t.loading ? "stop" : "reload", 15);
  $("bReload").classList.toggle("spinning", !!(t && t.loading));
  const isHome = t && t.url && t.url.includes("home.html");
  if (!editingUrl) {
    $("url").value = isHome ? "" : (t ? t.url : "");
    $("url").placeholder = "Search or Enter URL";
  }
  if ($("bCopyUrl")) $("bCopyUrl").classList.toggle("hide", !t || !t.url || isHome);
  const secure = t && (/^https:/.test(t.url) || isHome);
  $("lock").innerHTML = icon(secure ? "lock" : "globe", 14);
  $("lock").className = secure || !t || !t.url ? "" : "insecure";
  $("lock").classList.toggle("hide", !!isHome);
  if ($("searchIcon")) $("searchIcon").classList.toggle("hide", !isHome);
  if (t) {
    $("profileBadge").innerHTML = `<i style="background:${esc(t.profile.color)}"></i>${esc(t.profile.name)}${t.profile.proxy ? " · proxy" : ""}`;
    const z = Math.round((t.zoom || 1) * 100);
    $("zoomBadge").textContent = z + "%"; $("zoomBadge").classList.toggle("hide", z === 100);
  }
  updateBookmarkStar();
  renderVpnPill();
  renderStatus();
}

function renderStatus() {
  const t = cur();
  let left = "Ready";
  const indicator = document.querySelector(".sb-indicator-dot");
  if (t && t.loading) {
    left = "Connecting & loading " + esc(t.url);
    if (indicator) {
      indicator.style.background = "var(--warn)";
      indicator.style.boxShadow = "0 0 6px var(--warn-glow)";
    }
  } else if (t && t.url) {
    left = esc(t.url);
    if (indicator) {
      indicator.style.background = "var(--ok)";
      indicator.style.boxShadow = "0 0 6px var(--ok-glow)";
    }
  } else {
    if (indicator) {
      indicator.style.background = "var(--ok)";
      indicator.style.boxShadow = "0 0 6px var(--ok-glow)";
    }
  }
  $("sbLeft").innerHTML = left;
  const vpnOn = S.vpnStatus && S.vpnStatus.running;
  let proxyTxt = "Direct network";
  if (t && t.profile.proxy) {
    proxyTxt = `Proxy: ${t.profile.proxy}`;
  } else if (vpnOn) {
    proxyTxt = `WireGuard: ${S.vpnStatus.ip || "Connected"} (Port ${S.vpnStatus.port || 10808})`;
  }
  $("sbProxy").textContent = t ? proxyTxt : "";
}

/* ---------- pages ---------- */
function openPage(p) {
  page = p;
  app.overlay(true);
  $("page-settings").classList.toggle("hide", p !== "settings");
  $("bSettings").classList.toggle("on", p === "settings");
  if (p === "settings") renderSettings();
}
function closePage() {
  if (!page) return;
  page = null;
  $("page-settings").classList.add("hide");
  $("bSettings").classList.remove("on");
  app.overlay(false);
}

function toast(msg) {
  const d = document.createElement("div"); d.className = "toast"; d.textContent = msg;
  document.body.appendChild(d); setTimeout(() => d.remove(), 2200);
}

/* settings */
const sw = (id, on) => `<label class="sw"><input type="checkbox" id="${id}" ${on ? "checked" : ""}><span></span></label>`;
const row = (title, desc, ctl) => `<div class="row"><div class="l"><b>${title}</b><small>${desc}</small></div>${ctl}</div>`;

function renderSettings() {
  const s = S.settings;
  const vpn = S.vpnStatus || {};
  const vpnCfg = S.vpnStore || {};
  const secs = [
    ["vpn", "shield", "Proton WireGuard"],
    ["extensions", "puzzle", "Extensions"],
    ["bookmarks", "bookmark", "Bookmarks"],
    ["history", "history", "History"],
    ["cleardata", "trash", "Clear Data"],
    ["general", "sliders", "General"],
    ["profiles", "user", "Profiles & proxy"],
    ["identity", "shield", "Identity & privacy"],
    ["about", "info", "About"]
  ];
  let body = "";

  if (setSec === "vpn") {
    const isConn = vpn.running;
    const isConnPending = vpn.connecting;
    const statusBadge = isConnPending
      ? `<span class="badge warn"><span class="spin" style="width:10px;height:10px;border-width:1.5px"></span> Connecting...</span>`
      : isConn
      ? `<span class="badge ok">${icon("check", 12)} Connected</span>`
      : vpn.error
      ? `<span class="badge bad">${icon("x", 12)} Error</span>`
      : `<span class="badge dim">Disconnected</span>`;

    const locDesc = isConn
      ? `Connected via <b>${esc(vpn.ip || "WireGuard")}</b> ${vpn.city || vpn.country ? `(${esc([vpn.city, vpn.country].filter(Boolean).join(", "))})` : ""} · Socks5 Port <b>${esc(vpn.port || 10808)}</b>`
      : "Routing all browser tabs securely through Proton VPN WireGuard tunnel.";

    body = `
      <h3>Proton VPN (WireGuard)</h3>
      <p class="sub">Userspace WireGuard proxy tunnel. Direct .conf support without needing admin privileges or TAP/TUN network adapter.</p>
      
      <div class="card" style="border-color:${isConn ? 'var(--ok-border)' : vpn.error ? 'var(--bad-border)' : 'var(--border-subtle)'}; background:${isConn ? 'linear-gradient(180deg, rgba(16, 185, 129, 0.08) 0%, rgba(16, 24, 40, 0.8) 100%)' : 'var(--bg-card)'}">
        <div class="row" style="padding:18px 22px;">
          <div class="l">
            <div style="display:flex;align-items:center;gap:10px;margin-bottom:6px;">
              <span style="font-size:14px;font-weight:700;">Tunnel Status:</span>
              ${statusBadge}
            </div>
            <div style="font-size:12.5px;color:var(--tx-secondary);line-height:1.5;">${locDesc}</div>
            ${!isConn && vpn.error ? `<div style="color:var(--bad);margin-top:8px;font-size:12px;background:rgba(239,68,68,0.1);padding:8px 12px;border-radius:6px;border:1px solid rgba(239,68,68,0.25);"><b>Error:</b> ${esc(vpn.error)}</div>` : ""}
          </div>
          <div style="display:flex;gap:10px;align-items:center;">
            ${isConn
              ? `<button class="btn danger" id="vDisconnect">${icon("x", 14)} Disconnect</button>
                 <button class="btn" id="vTestIp" title="Open https://browserleaks.com/ip in new tab">${icon("external", 14)} Check IP (BrowserLeaks)</button>`
              : `<button class="btn pri" id="vConnect" ${!vpnCfg.config ? "disabled title='Please import or paste a WireGuard config first'" : ""}>${icon("shield", 14)} Connect VPN</button>
                 <button class="btn" id="vTestIp" title="Open https://browserleaks.com/ip in new tab">${icon("external", 14)} Check IP (BrowserLeaks)</button>`
            }
          </div>
        </div>
        <div style="padding:0 22px 14px;font-size:12px;color:var(--tx-muted);">
          IP &amp; Leak testing tool: <a href="#" id="vLeaksLink" style="color:var(--acc);text-decoration:none;font-weight:600;">https://browserleaks.com/ip</a>
        </div>
        ${row("Auto-connect on startup", "Automatically launch the WireGuard tunnel when the browser starts.", sw("vAutoConnect", vpnCfg.autoConnect))}
      </div>

      <div class="card">
        <div class="row">
          <div class="l">
            <b>Import WireGuard Config (.conf)</b>
            <small>Download from <a href="#" id="vProtonLink" style="color:var(--acc);text-decoration:none;font-weight:600">account.protonvpn.com</a> &rarr; Downloads &rarr; WireGuard configuration.</small>
          </div>
          <button class="btn" id="vImportFile">${icon("folder", 14)} Select .conf File</button>
        </div>
        <div class="row">
          <div class="l">
            <b>Current Config File</b>
            <small id="vFileName" style="font-family:monospace;color:var(--tx-primary);background:rgba(255,255,255,0.05);padding:2px 8px;border-radius:5px;">${esc(vpnCfg.fileName || "No file imported yet (paste config below or select a file)")}</small>
          </div>
          <div style="display:flex;align-items:center;gap:10px">
            <span style="color:var(--tx-muted);font-size:12px;font-weight:600;">Local Port:</span>
            <input class="txt" id="vPort" style="width:90px;font-family:monospace;font-weight:600;text-align:center;" type="number" value="${esc(vpnCfg.port || 10808)}">
          </div>
        </div>
        <div style="padding:16px 20px">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
            <div style="font-size:12px;color:var(--tx-secondary)"><b>Configuration Content:</b> (Standard WireGuard <code>[Interface]</code> &amp; <code>[Peer]</code>)</div>
            <span style="font-size:11px;color:var(--tx-muted);">Embedded wireproxy</span>
          </div>
          <textarea class="txt" id="vConfText" style="width:100%;height:180px;" placeholder="[Interface]&#10;PrivateKey = ...&#10;Address = 10.2.0.2/32&#10;DNS = 10.2.0.1&#10;&#10;[Peer]&#10;PublicKey = ...&#10;Endpoint = ...:51820&#10;AllowedIPs = 0.0.0.0/0">${esc(vpnCfg.config || "")}</textarea>
        </div>
      </div>
      
      <div style="display:flex;gap:12px;margin-top:6px;">
        <button class="btn pri" id="vSaveConfig">${icon("check", 14)} Save Configuration</button>
        ${!isConn && vpnCfg.config ? `<button class="btn" id="vConnectAlt">${icon("shield", 14)} Connect Now</button>` : ""}
      </div>
    `;
  }
  if (setSec === "extensions") {
    const list = S.extensions || [];
    body = `
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;">
        <div>
          <h3>Chrome Extensions</h3>
          <p class="sub">Load and manage unpacked Chrome extensions (Manifest V2 / V3) for your browser sessions.</p>
        </div>
        <button class="btn pri" id="extInstallBtn">${icon("plus", 14)} Load Unpacked</button>
      </div>

      <div class="card" style="margin-bottom:16px;">
        <div style="padding:14px 18px;display:flex;align-items:center;gap:14px;background:rgba(99,102,241,0.08);border-radius:10px;">
          <span style="font-size:22px;flex:none;">🧩</span>
          <div style="font-size:12px;color:var(--tx-secondary);line-height:1.5;">
            <b>How to install Chrome extensions:</b> Download any extension from the Chrome Web Store (using a CRX downloader or GitHub), extract the folder on your computer, and click <b>Load Unpacked</b> to select the folder containing <code>manifest.json</code>.
          </div>
        </div>
      </div>

      <div class="card" id="extListContainer">
        ${!list.length ? `
          <div style="padding:32px 20px;text-align:center;color:var(--tx-muted);">
            <div style="font-size:32px;margin-bottom:8px;opacity:0.6;">📦</div>
            <div style="font-size:14px;font-weight:600;color:var(--tx-secondary);margin-bottom:4px;">No extensions installed yet</div>
            <div style="font-size:12px;">Click <b>Load Unpacked</b> above to install your first extension.</div>
          </div>
        ` : list.map(ext => `
          <div class="row" style="padding:14px 18px;border-bottom:1px solid var(--border-subtle);display:flex;justify-content:space-between;align-items:center;">
            <div style="display:flex;align-items:center;gap:12px;flex:1;min-width:0;">
              <div style="width:36px;height:36px;border-radius:8px;background:rgba(255,255,255,0.08);display:flex;align-items:center;justify-content:center;font-size:18px;flex:none;">
                🧩
              </div>
              <div style="min-width:0;flex:1;">
                <div style="display:flex;align-items:center;gap:8px;">
                  <b style="font-size:13.5px;color:var(--tx-primary);">${esc(ext.name)}</b>
                  <span class="badge dim" style="font-size:10.5px;">v${esc(ext.version)}</span>
                  ${ext.isBuiltin ? `<span class="badge pri" style="font-size:10px;">Built-in</span>` : ""}
                  ${ext.enabled ? `<span class="badge ok" style="font-size:10px;">Active</span>` : `<span class="badge dim" style="font-size:10px;background:rgba(239,68,68,0.12);color:var(--bad);">Off</span>`}
                  ${!ext.existsOnDisk ? `<span class="badge bad" style="font-size:10px;">Folder missing</span>` : ""}
                </div>
                <div style="font-size:11.5px;color:var(--tx-muted);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;" title="${esc(ext.description || ext.path)}">${esc(ext.description || ext.path)}</div>
              </div>
            </div>
            <div style="display:flex;align-items:center;gap:12px;flex:none;margin-left:16px;">
              <div style="display:flex;align-items:center;gap:8px;padding:3px 10px;border-radius:6px;background:rgba(255,255,255,0.03);border:1px solid var(--border-subtle);">
                <span style="font-size:11.5px;font-weight:600;color:${ext.enabled ? 'var(--ok)' : 'var(--tx-muted)'};">${ext.enabled ? 'Active' : 'Off'}</span>
                <label class="sw" title="${ext.enabled ? "Turn Off Extension" : "Turn On / Activate Extension"}">
                  <input type="checkbox" class="ext-toggle" data-id="${esc(ext.id)}" ${ext.enabled ? "checked" : ""}>
                  <span></span>
                </label>
              </div>
              ${ext.isBuiltin ? `
                <span style="font-size:11px;color:var(--tx-muted);padding:4px 8px;background:rgba(255,255,255,0.05);border-radius:6px;border:1px solid var(--border-subtle);">Permanent</span>
              ` : `
                <button class="btn danger ext-remove" data-id="${esc(ext.id)}" title="Uninstall extension">${icon("trash", 14)}</button>
              `}
            </div>
          </div>
        `).join("")}
      </div>
    `;
  }
  if (setSec === "bookmarks") {
    const list = S.bookmarks || [];
    body = `
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;">
        <div>
          <div style="display:flex;align-items:center;gap:8px;">
            <h3 style="margin:0;">Bookmarks</h3>
            <span class="badge pri" style="font-size:11px;">${list.length} saved</span>
          </div>
          <p class="sub" style="margin:4px 0 0;">Quick access to your saved pages and Play Books tools.</p>
        </div>
        <button class="btn pri" id="bmAddManual">${icon("plus", 14)} Add Bookmark</button>
      </div>

      <div style="margin-bottom:12px;">
        <input class="txt" id="bmSearch" placeholder="Filter bookmarks by title or URL..." style="width:100%;">
      </div>

      <div class="card" id="bmListContainer">
        ${!list.length ? `
          <div style="padding:36px 20px;text-align:center;color:var(--tx-muted);">
            <div style="font-size:36px;margin-bottom:8px;opacity:0.6;">⭐</div>
            <div style="font-size:14px;font-weight:600;color:var(--tx-secondary);margin-bottom:4px;">No bookmarks yet</div>
            <div style="font-size:12px;">Click the star icon in the address bar to bookmark any page.</div>
          </div>
        ` : list.map(b => `
          <div class="row bm-item" data-url="${esc(b.url)}" data-title="${esc(b.title || '')}" style="padding:12px 18px;border-bottom:1px solid var(--border-subtle);display:flex;justify-content:space-between;align-items:center;">
            <div style="display:flex;align-items:center;gap:12px;flex:1;min-width:0;cursor:pointer;" class="bm-open-row" data-url="${esc(b.url)}">
              <div style="width:32px;height:32px;border-radius:8px;background:rgba(251,191,36,0.12);color:#fbbf24;display:flex;align-items:center;justify-content:center;flex:none;">
                ${b.favicon ? `<img src="${esc(b.favicon)}" style="width:16px;height:16px;border-radius:2px;" onerror="this.replaceWith(icon('bookmark', 15))">` : icon("bookmark", 15)}
              </div>
              <div style="min-width:0;flex:1;">
                <div style="font-size:13.5px;font-weight:600;color:var(--tx-primary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;" title="${esc(b.title || b.url)}">${esc(b.title || b.url)}</div>
                <div style="font-size:11.5px;color:var(--tx-muted);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;" title="${esc(b.url)}">${esc(b.url)}</div>
              </div>
            </div>
            <div style="display:flex;gap:8px;align-items:center;flex:none;margin-left:14px;">
              <button class="btn bm-open" data-url="${esc(b.url)}" title="Open in new tab">${icon("external", 13)} Open</button>
              <button class="btn danger bm-remove" data-id="${esc(b.id)}" title="Delete bookmark">${icon("trash", 13)}</button>
            </div>
          </div>
        `).join("")}
      </div>
    `;
  }
  if (setSec === "history") {
    const list = S.history || [];
    body = `
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;">
        <div>
          <div style="display:flex;align-items:center;gap:8px;">
            <h3 style="margin:0;">Browsing History</h3>
            <span class="badge dim" style="font-size:11px;">${list.length} pages</span>
          </div>
          <p class="sub" style="margin:4px 0 0;">Pages you have visited in this browser.</p>
        </div>
        ${list.length ? `<button class="btn danger" id="histClearAll">${icon("trash", 14)} Clear History</button>` : ""}
      </div>

      <div style="margin-bottom:12px;">
        <input class="txt" id="histSearch" placeholder="Filter history by page title or URL..." style="width:100%;">
      </div>

      <div class="card" id="histListContainer" style="max-height:480px;overflow-y:auto;">
        ${!list.length ? `
          <div style="padding:36px 20px;text-align:center;color:var(--tx-muted);">
            <div style="font-size:36px;margin-bottom:8px;opacity:0.6;">🕒</div>
            <div style="font-size:14px;font-weight:600;color:var(--tx-secondary);margin-bottom:4px;">No browsing history yet</div>
            <div style="font-size:12px;">Web pages you visit will appear here.</div>
          </div>
        ` : list.map(h => {
          const d = new Date(h.time || Date.now());
          const timeStr = d.toLocaleDateString([], { month: "short", day: "numeric" }) + " · " + d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
          return `
            <div class="row hist-item" data-url="${esc(h.url)}" data-title="${esc(h.title || '')}" style="padding:11px 18px;border-bottom:1px solid var(--border-subtle);display:flex;justify-content:space-between;align-items:center;">
              <div style="display:flex;align-items:center;gap:12px;flex:1;min-width:0;cursor:pointer;" class="hist-open-row" data-url="${esc(h.url)}">
                <div style="width:28px;height:28px;border-radius:6px;background:rgba(255,255,255,0.05);display:flex;align-items:center;justify-content:center;flex:none;color:var(--tx-muted);">
                  ${h.favicon ? `<img src="${esc(h.favicon)}" style="width:15px;height:15px;border-radius:2px;" onerror="this.replaceWith(icon('globe', 14))">` : icon("globe", 14)}
                </div>
                <div style="min-width:0;flex:1;">
                  <div style="font-size:13px;font-weight:500;color:var(--tx-primary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;" title="${esc(h.title || h.url)}">${esc(h.title || h.url)}</div>
                  <div style="font-size:11px;color:var(--tx-muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;" title="${esc(h.url)}">${esc(h.url)}</div>
                </div>
              </div>
              <div style="display:flex;gap:10px;align-items:center;flex:none;margin-left:14px;">
                <span style="font-size:11px;color:var(--tx-muted);white-space:nowrap;">${timeStr}</span>
                <button class="btn hist-open" data-url="${esc(h.url)}" title="Open in new tab">${icon("external", 13)}</button>
                <button class="btn danger hist-remove" data-id="${esc(h.id)}" title="Remove from history">${icon("x", 12)}</button>
              </div>
            </div>
          `;
        }).join("")}
      </div>
    `;
  }
  if (setSec === "cleardata") body = `
    <h3>Clear Browsing Data</h3>
    <p class="sub">Clear cache, cookies, local storage, and history across all browser profiles and sessions.</p>
    
    <div class="card">
      <div class="row">
        <div class="l">
          <b>Browsing Cache & Temporary Files</b>
          <small>Frees up memory and disk space by clearing cached web pages and images.</small>
        </div>
        <label class="sw"><input type="checkbox" id="clrOptCache" checked><span></span></label>
      </div>
      <div class="row">
        <div class="l">
          <b>Cookies & Site Data</b>
          <small>Logs you out of web accounts and clears saved site session cookies.</small>
        </div>
        <label class="sw"><input type="checkbox" id="clrOptCookies" checked><span></span></label>
      </div>
      <div class="row">
        <div class="l">
          <b>Local Storage & IndexedDB</b>
          <small>Removes offline app data, cached databases, and web storage.</small>
        </div>
        <label class="sw"><input type="checkbox" id="clrOptStorage" checked><span></span></label>
      </div>
      <div class="row">
        <div class="l">
          <b>Browsing History</b>
          <small>Clears the recorded list of visited pages and addresses.</small>
        </div>
        <label class="sw"><input type="checkbox" id="clrOptHistory" checked><span></span></label>
      </div>
    </div>

    <div style="display:flex;gap:12px;align-items:center;margin-top:10px;">
      <button class="btn danger" id="btnClearBrowserData" style="display:flex;align-items:center;gap:8px;padding:9px 18px;font-weight:600;">
        ${icon("trash", 15)} Clear Selected Data
      </button>
      <span style="font-size:12px;color:var(--tx-muted);">Wipes selected storage immediately.</span>
    </div>
  `;
  if (setSec === "general") body = `
    <h3>General</h3><p class="sub">Startup, notifications and window behaviour.</p>
    <div class="card">
      ${row("Home page", "Opened by new tabs and the Home button.", `<input class="txt wide" id="sHome" value="${esc(s.homeUrl || "https://play.google.com/books/publish/u/0/")}">`)}
      ${row("Restore tabs on start", "Reopen the tabs that were open when the app was closed.", sw("sRestore", s.restoreTabs))}
      ${row("Desktop notifications", "Windows notification when a target center is selected or payment page is reached.", sw("sNotify", s.notify))}
      ${row("Always on top", "Keep the window above other windows.", sw("sTop", s.alwaysOnTop))}
      ${row("Default zoom", "Zoom used for new tabs.", `<select class="txt" id="sZoom">${[0.8, 0.9, 1, 1.1, 1.25].map(z => `<option value="${z}" ${Number(s.zoom) === z ? "selected" : ""}>${Math.round(z * 100)}%</option>`).join("")}</select>`)}
    </div>
    <div class="card">
      ${row("Clear browsing data", "Quickly wipe cache, cookies, and local data.", `<button class="btn danger" id="sQuickClearData">${icon("trash", 14)} Clear Data</button>`)}
      ${row("App data folder", esc(S.meta.dataPath || ""), `<button class="btn" id="sOpenData">${icon("folder", 14)} Open</button>`)}
    </div>
    <button class="btn pri" id="sSave">${icon("check", 14)} Save</button>`;
  if (setSec === "profiles") body = `
    <h3>Profiles & proxy</h3>
    <p class="sub">Each profile is a separate browser with its own cookies, login and (optional) proxy. If no profile proxy is specified, the active WireGuard VPN tunnel is used automatically.</p>
    <div class="card" id="profList">${S.profiles.map(p => `
      <div class="prof" data-id="${esc(p.id)}">
        <input type="color" value="${esc(p.color)}" class="pc">
        <input class="txt pn" value="${esc(p.name)}" placeholder="Name">
        <input class="txt pp" value="${esc(p.proxy)}" placeholder="Proxy (empty = WireGuard / direct)">
        <div class="acts">
          <button class="btn pt" title="Test proxy">Test</button>
          <button class="btn po" title="Open a tab with this profile">Open tab</button>
          <button class="btn pclr" title="Clear cookies and cache">Clear data</button>
          ${S.profiles.length > 1 ? `<button class="btn danger pd" title="Delete profile">${icon("trash", 14)}</button>` : ""}
        </div>
      </div><div class="msg" data-msg="${esc(p.id)}"></div>`).join("")}
    </div>
    <div style="display:flex;gap:8px"><button class="btn" id="pAdd">${icon("plus", 14)} Add profile</button><button class="btn pri" id="pSave">${icon("check", 14)} Save profiles</button></div>`;
  if (setSec === "identity") body = `
    <h3>Identity & privacy</h3>
    <p class="sub">The app presents itself as a normal Google Chrome on Windows. These options keep that identity consistent for Google Play Books authentication.</p>
    <div class="card">
      ${row("User agent", "Auto = the same Chrome version the app is built on (recommended).", `<select class="txt" id="sUaMode"><option value="auto" ${s.uaMode !== "custom" ? "selected" : ""}>Auto (Chrome ${esc((S.meta.chrome || "").split(".")[0])})</option><option value="custom" ${s.uaMode === "custom" ? "selected" : ""}>Custom</option></select>`)}
      <div class="row ${s.uaMode === "custom" ? "" : "hide"}" id="uaRow"><div class="l"><b>Custom user agent</b><small>Must look like a real Chrome on Windows.</small></div><input class="txt wide" id="sUa" value="${esc(s.customUA)}"></div>
      ${row("Accept-Language", "Language header sent to websites.", `<input class="txt" id="sLang" value="${esc(s.acceptLanguage)}">`)}
      ${row("WebRTC leak protection", "Stops WebRTC from revealing your real IP when a proxy is used.", sw("sRtc", s.webrtcProtect))}
      ${row("Block trackers", "Blocks analytics/tracking scripts. Pages load faster.", sw("sTrk", s.blockTrackers))}
    </div>
    <div class="card"><div class="kv"><span>Current user agent</span><b>${esc(S.meta.ua)}</b></div></div>
    <button class="btn pri" id="sSave">${icon("check", 14)} Save</button>`;
  if (setSec === "about") body = `
    <h3>About</h3><p class="sub">Sotizence Play Books Browser: secure browser with built-in Proton VPN WireGuard tunnel.</p>
    <div class="card"><div class="kv">
      <span>Software</span><b>Sotizence Play Books Browser</b>
      <span>Target</span><b>Google Play Books Partner Center</b>
      <span>WireGuard</span><b>Embedded wireproxy userspace SOCKS5</b>
      <span>Version</span><b>${esc(S.meta.version)}</b>
      <span>Chromium</span><b>${esc(S.meta.chrome)}</b>
      <span>Electron</span><b>${esc(S.meta.electron)}</b>
      <span>Shortcuts</span><b>Ctrl+T new tab · Ctrl+W close · Ctrl+Tab switch · F5 reload · Ctrl+L address · Ctrl +/- zoom · F12 dev tools</b>
    </div></div>`;
  $("page-settings").innerHTML = `<div class="set"><aside><h2>Settings</h2>${secs.map(([k, ic, l]) => `<button data-s="${k}" class="${k === setSec ? "on" : ""}">${icon(ic, 16)}${l}</button>`).join("")}</aside><div class="body">${body}</div></div>`;
  bindSettings();
}

function bindSettings() {
  const P = $("page-settings");
  P.querySelectorAll("aside button").forEach(b => b.onclick = () => { setSec = b.dataset.s; renderSettings(); });
  const v = id => P.querySelector("#" + id);

  // WireGuard VPN Handlers
  if (v("vProtonLink")) v("vProtonLink").onclick = e => { e.preventDefault(); closePage(); app.newTab({ url: "https://account.protonvpn.com/downloads" }); };
  if (v("vImportFile")) v("vImportFile").onclick = async () => {
    const res = await app.vpnImport();
    if (res && !res.canceled) {
      S.vpnStore = res.vpnStore;
      S.vpnStatus = res.vpnStatus;
      renderSettings();
      renderVpnPill();
      toast("Imported WireGuard config: " + (res.vpnStore.fileName || ""));
    }
  };
  const doConnect = async () => {
    const btn = v("vConnect") || v("vConnectAlt");
    if (btn) btn.disabled = true;
    const text = v("vConfText") ? v("vConfText").value.trim() : (S.vpnStore.config || "");
    const port = v("vPort") ? Number(v("vPort").value) || 10808 : 10808;
    const auto = v("vAutoConnect") ? v("vAutoConnect").checked : !!S.vpnStore.autoConnect;
    toast("Starting Proton WireGuard...");
    const res = await app.vpnConnect({ config: text, port, autoConnect: auto, fileName: S.vpnStore.fileName });
    if (res.ok) {
      S.vpnStatus = res.status;
      if (res.vpnStore) S.vpnStore = res.vpnStore;
      renderSettings();
      renderVpnPill();
      toast("WireGuard VPN connected!");
      // Automatic IP test in background
      app.vpnTest().then(testRes => {
        if (testRes.ok && testRes.data) {
          S.vpnStatus = testRes.vpnStatus;
          renderSettings();
          renderVpnPill();
        }
      });
    } else {
      toast("VPN Error: " + (res.error || "Failed to connect"));
      renderSettings();
      renderVpnPill();
    }
  };
  if (v("vConnect")) v("vConnect").onclick = doConnect;
  if (v("vConnectAlt")) v("vConnectAlt").onclick = doConnect;
  if (v("vDisconnect")) v("vDisconnect").onclick = async () => {
    v("vDisconnect").disabled = true;
    const res = await app.vpnDisconnect();
    S.vpnStatus = res.status;
    renderSettings();
    renderVpnPill();
    toast("WireGuard VPN disconnected");
  };
  if (v("vTestIp")) v("vTestIp").onclick = () => {
    closePage();
    app.overlay(false);
    app.newTab({ url: "https://browserleaks.com/ip" });
    toast("Opening BrowserLeaks IP & Leak test...");
  };
  if (v("vLeaksLink")) v("vLeaksLink").onclick = (e) => {
    e.preventDefault();
    closePage();
    app.overlay(false);
    app.newTab({ url: "https://browserleaks.com/ip" });
  };
  if (v("vSaveConfig")) v("vSaveConfig").onclick = async () => {
    const text = v("vConfText") ? v("vConfText").value.trim() : "";
    const port = v("vPort") ? Number(v("vPort").value) || 10808 : 10808;
    const auto = v("vAutoConnect") ? v("vAutoConnect").checked : false;
    const res = await app.vpnSaveConfig({ config: text, port, autoConnect: auto });
    if (res.ok) {
      S.vpnStore = res.vpnStore;
      S.vpnStatus = res.vpnStatus;
      renderSettings();
      toast("WireGuard config saved");
    }
  };
  if (v("vAutoConnect")) v("vAutoConnect").onchange = async () => {
    const auto = v("vAutoConnect").checked;
    const res = await app.vpnSaveConfig({ autoConnect: auto });
    if (res.ok) S.vpnStore = res.vpnStore;
  };

  // Extensions
  if (v("extInstallBtn")) v("extInstallBtn").onclick = async () => {
    const res = await app.extInstallFolder();
    if (res && res.canceled) return;
    if (res && !res.ok) {
      alert("Extension installation failed:\n" + (res.error || "Unknown error"));
      return;
    }
    if (res && res.extensions) S.extensions = res.extensions;
    renderSettings();
    toast("Extension installed successfully");
  };

  P.querySelectorAll(".ext-toggle").forEach(input => {
    input.onchange = async () => {
      const id = input.dataset.id;
      const enabled = input.checked;
      const res = await app.extToggle(id, enabled);
      if (res && res.extensions) S.extensions = res.extensions;
      renderSettings();
      toast(enabled ? "Extension Activated (Active)" : "Extension Turned Off");
    };
  });

  // Bookmarks handlers
  if (v("bmAddManual")) v("bmAddManual").onclick = async () => {
    const t = cur();
    const defaultUrl = t && t.url && t.url.startsWith("http") ? t.url : "https://";
    const defaultTitle = t && t.title && t.title !== "Loading…" ? t.title : "";
    const url = prompt("Enter bookmark URL:", defaultUrl);
    if (!url || !url.trim() || url === "https://") return;
    const title = prompt("Enter bookmark title:", defaultTitle || url.trim()) || url.trim();
    const res = await app.bookmarksAdd({ url: url.trim(), title: title.trim(), favicon: (t && t.url === url.trim()) ? t.favicon : "" });
    if (res) S.bookmarks = res;
    updateBookmarkStar();
    renderSettings();
    toast("Bookmark added ⭐");
  };

  if (v("bmSearch")) v("bmSearch").oninput = (e) => {
    const q = e.target.value.toLowerCase().trim();
    P.querySelectorAll(".bm-item").forEach(item => {
      const match = !q || item.dataset.url.toLowerCase().includes(q) || item.dataset.title.toLowerCase().includes(q);
      item.style.display = match ? "flex" : "none";
    });
  };

  P.querySelectorAll(".bm-open, .bm-open-row").forEach(el => {
    el.onclick = (e) => {
      if (e.target.closest(".bm-remove")) return;
      const url = el.dataset.url;
      if (!url) return;
      closePage();
      app.overlay(false);
      app.newTab({ url });
    };
  });

  P.querySelectorAll(".bm-remove").forEach(btn => {
    btn.onclick = async (e) => {
      e.stopPropagation();
      const id = btn.dataset.id;
      const res = await app.bookmarksRemove(id);
      if (res) S.bookmarks = res;
      updateBookmarkStar();
      renderSettings();
      toast("Bookmark removed");
    };
  });

  // History handlers
  if (v("histSearch")) v("histSearch").oninput = (e) => {
    const q = e.target.value.toLowerCase().trim();
    P.querySelectorAll(".hist-item").forEach(item => {
      const match = !q || item.dataset.url.toLowerCase().includes(q) || item.dataset.title.toLowerCase().includes(q);
      item.style.display = match ? "flex" : "none";
    });
  };

  P.querySelectorAll(".hist-open, .hist-open-row").forEach(el => {
    el.onclick = (e) => {
      if (e.target.closest(".hist-remove")) return;
      const url = el.dataset.url;
      if (!url) return;
      closePage();
      app.overlay(false);
      app.newTab({ url });
    };
  });

  P.querySelectorAll(".hist-remove").forEach(btn => {
    btn.onclick = async (e) => {
      e.stopPropagation();
      const id = btn.dataset.id;
      const res = await app.historyRemove(id);
      if (res) S.history = res;
      renderSettings();
      toast("History entry removed");
    };
  });

  if (v("histClearAll")) v("histClearAll").onclick = async () => {
    if (confirm("Clear all browsing history?")) {
      await app.historyClear();
      S.history = [];
      renderSettings();
      toast("Browsing history cleared");
    }
  };

  if (v("btnClearBrowserData")) v("btnClearBrowserData").onclick = async () => {
    const cache = v("clrOptCache") ? v("clrOptCache").checked : true;
    const cookies = v("clrOptCookies") ? v("clrOptCookies").checked : true;
    const storage = v("clrOptStorage") ? v("clrOptStorage").checked : true;
    const history = v("clrOptHistory") ? v("clrOptHistory").checked : true;

    if (!cache && !cookies && !storage && !history) {
      toast("Please select at least one item to clear.");
      return;
    }

    if (confirm("Are you sure you want to clear the selected browser data?")) {
      v("btnClearBrowserData").disabled = true;
      const res = await app.clearBrowserData({ cache, cookies, storage, history });
      v("btnClearBrowserData").disabled = false;
      if (history) S.history = [];
      if (res && res.ok) {
        renderSettings();
        toast("Browsing data cleared successfully!");
      } else {
        toast("Failed to clear data: " + ((res && res.error) || "unknown error"));
      }
    }
  };

  if (v("sQuickClearData")) v("sQuickClearData").onclick = async () => {
    if (confirm("Clear all cache, cookies, and browsing storage now?")) {
      v("sQuickClearData").disabled = true;
      const res = await app.clearBrowserData({ cache: true, cookies: true, storage: true, history: true });
      v("sQuickClearData").disabled = false;
      S.history = [];
      if (res && res.ok) {
        toast("All browsing data cleared successfully!");
      } else {
        toast("Failed to clear data");
      }
    }
  };

  P.querySelectorAll(".ext-remove").forEach(btn => {
    btn.onclick = async () => {
      const id = btn.dataset.id;
      if (confirm("Are you sure you want to uninstall this extension?")) {
        const res = await app.extRemove(id);
        if (res && res.extensions) S.extensions = res.extensions;
        renderSettings();
        toast("Extension uninstalled");
      }
    };
  });

  // General settings
  if (v("sUaMode")) v("sUaMode").onchange = () => v("uaRow").classList.toggle("hide", v("sUaMode").value !== "custom");
  if (v("sOpenData")) v("sOpenData").onclick = () => app.openData();
  if (v("sSave")) v("sSave").onclick = async () => {
    const s = {};
    if (v("sHome")) Object.assign(s, { homeUrl: v("sHome").value.trim() || "https://play.google.com/books/publish/u/0/", restoreTabs: v("sRestore").checked,
      notify: v("sNotify").checked, alwaysOnTop: v("sTop").checked, zoom: Number(v("sZoom").value) });
    if (v("sUaMode")) Object.assign(s, { uaMode: v("sUaMode").value, customUA: v("sUa").value.trim(), acceptLanguage: v("sLang").value.trim() || "en-US,en;q=0.9",
      webrtcProtect: v("sRtc").checked, blockTrackers: v("sTrk").checked });
    const r = await app.saveSettings(s);
    S.settings = r.settings; S.meta.ua = r.ua; renderSettings(); toast("Settings saved");
  };

  // Profiles
  const readProfiles = () => [...P.querySelectorAll(".prof")].map(el => ({ id: el.dataset.id, name: el.querySelector(".pn").value.trim() || "Profile",
    color: el.querySelector(".pc").value, proxy: el.querySelector(".pp").value.trim() }));
  if (v("pAdd")) v("pAdd").onclick = () => {
    S.profiles = readProfiles();
    const colors = ["#22c55e", "#f59e0b", "#a855f7", "#ef4444", "#14b8a6", "#ec4899"];
    S.profiles.push({ id: "p" + Date.now().toString(36), name: "Profile " + (S.profiles.length + 1), color: colors[S.profiles.length % colors.length], proxy: "" });
    renderSettings();
  };
  if (v("pSave")) v("pSave").onclick = async () => { S.profiles = await app.saveProfiles(readProfiles()); renderSettings(); toast("Profiles saved"); };
  P.querySelectorAll(".prof").forEach(el => {
    const id = el.dataset.id, msg = P.querySelector(`[data-msg="${id}"]`);
    el.querySelector(".pt").onclick = async () => {
      msg.className = "msg"; msg.textContent = "Testing connection…";
      const r = await app.testProxy(el.querySelector(".pp").value);
      msg.className = "msg " + (r.ok ? "ok" : "bad"); msg.textContent = (r.ok ? "Working: " : "Failed: ") + r.msg;
    };
    el.querySelector(".po").onclick = async () => { S.profiles = await app.saveProfiles(readProfiles()); closePage(); app.newTab({ profileId: id }); };
    el.querySelector(".pclr").onclick = async () => { if (confirm("Clear cookies, login and cache of this profile?")) { await app.clearProfile(id); msg.className = "msg ok"; msg.textContent = "Cleared. Reload the open tabs of this profile."; } };
    const d = el.querySelector(".pd");
    if (d) d.onclick = () => { if (confirm("Delete this profile?")) { S.profiles = readProfiles().filter(p => p.id !== id); renderSettings(); } };
  });
}

/* ---------- wiring ---------- */
app.on("tabs", d => { S.tabs = d.tabs; S.activeId = d.activeId; renderTabs(); renderToolbar(); });
app.on("maximized", m => { document.querySelector('[data-w="max"]').innerHTML = icon(m ? "restore" : "max", 13); });
app.on("focus-address", () => { $("url").focus(); });
app.on("vpn-status", st => {
  S.vpnStatus = st;
  renderVpnPill();
  renderStatus();
  if (page === "settings" && setSec === "vpn") renderSettings();
});

app.init().then(d => {
  S.settings = d.settings; S.profiles = d.profiles;
  S.vpnStatus = d.vpnStatus || {};
  S.vpnStore = d.vpnStore || {};
  S.extensions = d.extensions || [];
  S.bookmarks = d.bookmarks || [];
  S.history = d.history || [];
  S.meta = { version: d.version, chrome: d.chrome, electron: d.electron, ua: d.ua, dataPath: d.dataPath };
  $("sbVer").textContent = "v" + d.version;
  if ($("sbProxy")) {
    $("sbProxy").style.cursor = "pointer";
    $("sbProxy").title = "Click to test IP & leaks on BrowserLeaks (https://browserleaks.com/ip)";
    $("sbProxy").onclick = () => {
      closePage();
      app.newTab({ url: "https://browserleaks.com/ip" });
      toast("Opening https://browserleaks.com/ip");
    };
  }
  updateBookmarkStar();
  renderVpnPill();
});
