/* Wafid Desktop - shell UI (tabs, toolbar, settings) */
const $ = id => document.getElementById(id);
const esc = s => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const tm = t => { const d = new Date(t); return d.toLocaleTimeString([], { hour12: false }); };

let S = { tabs: [], activeId: null, settings: {}, profiles: [], meta: {}, vpnStatus: {}, vpnStore: {} };
let page = null; // "settings" | null
let editingUrl = false;
let setSec = "vpn";

/* ---------- static icons ---------- */
$("newTab").innerHTML = icon("plus", 16);
$("bBack").innerHTML = icon("back", 18);
$("bFwd").innerHTML = icon("fwd", 18);
$("bReload").innerHTML = icon("reload", 16);
$("bHome").innerHTML = icon("home", 16);
$("bSettings").innerHTML = icon("settings", 17);
document.querySelector('[data-w="min"]').innerHTML = icon("min", 14);
document.querySelector('[data-w="max"]').innerHTML = icon("max", 13);
document.querySelector('[data-w="close"]').innerHTML = icon("x", 15);

document.querySelectorAll(".winctl button").forEach(b => b.onclick = () => app.win(b.dataset.w));
$("titlebar").addEventListener("dblclick", e => { if (e.target.classList.contains("drag") || e.target.id === "titlebar") app.win("max"); });
$("newTab").onclick = () => app.newTab();
$("bBack").onclick = () => app.nav("back");
$("bFwd").onclick = () => app.nav("forward");
$("bReload").onclick = () => { const t = cur(); app.nav(t && t.loading ? "stop" : "reload"); };
$("bHome").onclick = () => { closePage(); app.nav("home"); };
$("bSettings").onclick = () => page === "settings" ? closePage() : openPage("settings");
if ($("bVpn")) $("bVpn").onclick = () => { setSec = "vpn"; page === "settings" ? renderSettings() : openPage("settings"); };
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
    pill.title = "Proton WireGuard: Connecting...";
  } else if (st.running) {
    pill.className = "vpn-pill on";
    txt.textContent = st.country ? `VPN: ${st.country}` : "VPN Active";
    pill.title = `Proton WireGuard Connected\nIP: ${st.ip || "..."}\nLocation: ${[st.city, st.country].filter(Boolean).join(", ") || "Active"}\nPort: ${st.port}`;
  } else if (st.error) {
    pill.className = "vpn-pill error";
    txt.textContent = "VPN Error";
    pill.title = "VPN Error: " + st.error;
  } else {
    pill.className = "vpn-pill off";
    txt.textContent = "VPN Off";
    pill.title = "Proton WireGuard VPN: Disconnected (Click to configure)";
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
    el.title = `${t.title}\n${t.url}\nProfile: ${t.profile.name}`;
    el.querySelector(".t").textContent = t.title || "New tab";
    el.querySelector(".pcol").style.background = S.profiles.length > 1 ? t.profile.color : "transparent";
    const fav = el.querySelector(".fav");
    const favHtml = t.loading ? '<span class="spin"></span>' : t.favicon ? `<img src="${esc(t.favicon)}" alt="">` : icon("globe", 14);
    if (fav.dataset.h !== favHtml) { fav.innerHTML = favHtml; fav.dataset.h = favHtml; }
  });
}

/* ---------- toolbar / status ---------- */
function renderToolbar() {
  const t = cur();
  $("bBack").disabled = !t || !t.canBack;
  $("bFwd").disabled = !t || !t.canForward;
  $("bReload").innerHTML = icon(t && t.loading ? "stop" : "reload", 16);
  if (!editingUrl) $("url").value = t ? t.url : "";
  const secure = t && /^https:/.test(t.url);
  $("lock").innerHTML = icon(secure ? "lock" : "globe", 14);
  $("lock").className = secure || !t || !t.url ? "" : "insecure";
  if (t) {
    $("profileBadge").innerHTML = `<i style="background:${esc(t.profile.color)}"></i>${esc(t.profile.name)}${t.profile.proxy ? " · proxy" : ""}`;
    const z = Math.round((t.zoom || 1) * 100);
    $("zoomBadge").textContent = z + "%"; $("zoomBadge").classList.toggle("hide", z === 100);
  }
  renderVpnPill();
  renderStatus();
}
function renderStatus() {
  const t = cur();
  let left = "Ready";
  if (t && t.loading) left = "Loading " + esc(t.url);
  else if (t && t.url) left = esc(t.url);
  $("sbLeft").innerHTML = left;
  const vpnOn = S.vpnStatus && S.vpnStatus.running;
  let proxyTxt = "Direct connection";
  if (t && t.profile.proxy) {
    proxyTxt = "Profile proxy on";
  } else if (vpnOn) {
    proxyTxt = `WireGuard VPN: ${S.vpnStatus.ip || "Connected"}${S.vpnStatus.country ? " (" + S.vpnStatus.country + ")" : ""}`;
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
      
      <div class="card">
        <div class="row">
          <div class="l">
            <b>Tunnel Status: ${statusBadge}</b>
            <small>${locDesc}</small>
            ${vpn.error ? `<div style="color:var(--bad);margin-top:6px;font-size:12px;"><b>Error:</b> ${esc(vpn.error)}</div>` : ""}
          </div>
          <div style="display:flex;gap:8px;align-items:center;">
            ${isConn
              ? `<button class="btn danger" id="vDisconnect">${icon("x", 14)} Disconnect</button>
                 <button class="btn" id="vTestIp" title="Check public IP and location">Check IP</button>`
              : `<button class="btn pri" id="vConnect" ${!vpnCfg.config ? "disabled title='Please import or paste a WireGuard config first'" : ""}>${icon("check", 14)} Connect VPN</button>`
            }
          </div>
        </div>
        ${row("Auto-connect on startup", "Automatically launch the WireGuard tunnel when the browser starts.", sw("vAutoConnect", vpnCfg.autoConnect))}
      </div>

      <div class="card">
        <div class="row">
          <div class="l">
            <b>Import WireGuard Config (.conf)</b>
            <small>Download from <a href="#" id="vProtonLink" style="color:var(--acc);text-decoration:none">account.protonvpn.com</a> &rarr; Downloads &rarr; WireGuard configuration.</small>
          </div>
          <button class="btn" id="vImportFile">${icon("folder", 14)} Select .conf File</button>
        </div>
        <div class="row">
          <div class="l">
            <b>Current Config File</b>
            <small id="vFileName">${esc(vpnCfg.fileName || "No file imported yet (paste config below or select a file)")}</small>
          </div>
          <div style="display:flex;align-items:center;gap:8px">
            <span style="color:var(--mut);font-size:12px">Local Port:</span>
            <input class="txt" id="vPort" style="width:84px" type="number" value="${esc(vpnCfg.port || 10808)}">
          </div>
        </div>
        <div style="padding:14px 18px">
          <div style="margin-bottom:6px;font-size:12px;color:var(--mut)"><b>Configuration Content:</b> (Standard WireGuard <code>[Interface]</code> &amp; <code>[Peer]</code>)</div>
          <textarea class="txt" id="vConfText" style="width:100%" placeholder="[Interface]&#10;PrivateKey = ...&#10;Address = 10.2.0.2/32&#10;DNS = 10.2.0.1&#10;&#10;[Peer]&#10;PublicKey = ...&#10;Endpoint = ...:51820&#10;AllowedIPs = 0.0.0.0/0">${esc(vpnCfg.config || "")}</textarea>
        </div>
      </div>
      
      <div style="display:flex;gap:10px">
        <button class="btn pri" id="vSaveConfig">${icon("check", 14)} Save Configuration</button>
        ${!isConn && vpnCfg.config ? `<button class="btn" id="vConnectAlt">${icon("shield", 14)} Connect Now</button>` : ""}
      </div>
    `;
  }
  if (setSec === "general") body = `
    <h3>General</h3><p class="sub">Startup, notifications and window behaviour.</p>
    <div class="card">
      ${row("Home page", "Opened by new tabs and the Home button.", `<input class="txt wide" id="sHome" value="${esc(s.homeUrl || "https://play.google.com/books/publish/u/0/")}">`)}
      ${row("Restore tabs on start", "Reopen the tabs that were open when the app was closed.", sw("sRestore", s.restoreTabs))}
      ${row("Desktop notifications", "Windows notification when a target center is selected or payment page is reached.", sw("sNotify", s.notify))}
      ${row("Flash taskbar on alert", "Flash the taskbar button when the window is in the background.", sw("sFlash", s.flashTaskbar))}
      ${row("Always on top", "Keep the window above other windows.", sw("sTop", s.alwaysOnTop))}
      ${row("Default zoom", "Zoom used for new tabs.", `<select class="txt" id="sZoom">${[0.8, 0.9, 1, 1.1, 1.25].map(z => `<option value="${z}" ${Number(s.zoom) === z ? "selected" : ""}>${Math.round(z * 100)}%</option>`).join("")}</select>`)}
    </div>
    <div class="card">
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
    <h3>About</h3><p class="sub">Play Books Desktop: secure browser with built-in Proton VPN WireGuard tunnel.</p>
    <div class="card"><div class="kv">
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
  if (v("vTestIp")) v("vTestIp").onclick = async () => {
    v("vTestIp").disabled = true;
    toast("Checking public IP...");
    const res = await app.vpnTest();
    if (v("vTestIp")) v("vTestIp").disabled = false;
    if (res.ok && res.data) {
      toast(`IP: ${res.data.ip} (${[res.data.city, res.data.country].filter(Boolean).join(", ")})`);
      S.vpnStatus = res.vpnStatus;
      renderSettings();
      renderVpnPill();
    } else {
      toast("IP test failed: " + (res.data?.error || "Timeout"));
    }
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

  // General settings
  if (v("sUaMode")) v("sUaMode").onchange = () => v("uaRow").classList.toggle("hide", v("sUaMode").value !== "custom");
  if (v("sOpenData")) v("sOpenData").onclick = () => app.openData();
  if (v("sSave")) v("sSave").onclick = async () => {
    const s = {};
    if (v("sHome")) Object.assign(s, { homeUrl: v("sHome").value.trim() || "https://play.google.com/books/publish/u/0/", restoreTabs: v("sRestore").checked,
      notify: v("sNotify").checked, flashTaskbar: v("sFlash").checked, alwaysOnTop: v("sTop").checked, zoom: Number(v("sZoom").value) });
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
  S.meta = { version: d.version, chrome: d.chrome, electron: d.electron, ua: d.ua, dataPath: d.dataPath };
  $("sbVer").textContent = "v" + d.version;
  renderVpnPill();
});
