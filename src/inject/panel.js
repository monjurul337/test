// Wafid Assistant — floating in-page panel (isolated world, Shadow DOM)
window.__bdInitPanel = function(){
  if (window.__bdPanelLoaded) return;
  window.__bdPanelLoaded = true;

  const NATIONALITIES = [["1049", "Afghan"], ["2", "Albanian"], ["1012", "Algeria"], ["3", "Algerian"], ["1070", "Angolan"], ["8", "Argentinian"], ["9", "Armenian"], ["10", "Australian"], ["11", "Austrian"], ["12", "Azerbaijani"], ["14", "Bahraini"], ["15", "Bangladeshi"], ["19", "Belarusian"], ["20", "Belgian"], ["21", "Belizean"], ["1084", "Beninese"], ["23", "Bhutanese"], ["25", "Bosnian"], ["26", "Brazilian"], ["1014", "Britain"], ["30", "Burkinabe"], ["32", "Burundian"], ["33", "Cambodian"], ["34", "Cameroonian"], ["35", "Canadian"], ["38", "Chadian"], ["1082", "Chilean"], ["40", "Chinese"], ["41", "Colombian"], ["1083", "Congolese"], ["1072", "Cuban"], ["47", "Cypriot"], ["48", "Czech"], ["49", "Danish"], ["50", "Djibouti"], ["1050", "Dominica"], ["52", "Dutch"], ["54", "Ecuadorean"], ["55", "Egyptian"], ["58", "Eritrean"], ["60", "Ethiopian"], ["177", "Filipino"], ["63", "Finnish"], ["64", "French"], ["68", "German"], ["69", "Ghanaian"], ["70", "Greek"], ["1076", "Guatemalan"], ["74", "GuineanGuyanese"], ["1067", "Guineense"], ["78", "Hungarian"], ["1", "Indian"], ["81", "Indonesian"], ["82", "Iranian"], ["83", "Iraqi"], ["84", "Irish"], ["86", "Italian"], ["87", "Ivorian"], ["88", "Jamaican"], ["89", "Japanese"], ["90", "Jordanian"], ["91", "Kazakhstani"], ["92", "Kenyan"], ["94", "Kuwaiti"], ["1080", "Kyrgyzstani"], ["96", "Laotian"], ["98", "Lebanese"], ["100", "Libyan"], ["102", "Lithuanian"], ["105", "Malagasy"], ["1069", "Malawian"], ["1015", "Malaysia"], ["108", "Maldivian"], ["109", "Malian"], ["110", "Maltese"], ["112", "Mauritanian"], ["114", "Mexican"], ["1066", "Montenegrin"], ["119", "Moroccan"], ["1068", "Myanmar"], ["125", "Nepalese"], ["127", "New Zealander"], ["130", "Nigerian"], ["1073", "Nigerien"], ["133", "Norwegian"], ["134", "Omani"], ["135", "Pakistani"], ["1007", "Palestine"], ["137", "Panamanian"], ["141", "Peruvian"], ["142", "Polish"], ["1064", "Portuguese"], ["144", "Qatari"], ["145", "Romanian"], ["146", "Russian"], ["1071", "Rwandan"], ["1060", "Saint Kitts and Nevis"], ["1086", "Saint Lucian"], ["148", "Saudi"], ["1074", "Senegalese"], ["150", "Serbian"], ["1053", "Sierra Leonean"], ["1062", "Sierra Leonean"], ["1081", "singapore"], ["1079", "Slovakian"], ["1078", "Slovenian"], ["152", "Somali"], ["1011", "South Africa"], ["154", "South Korean"], ["155", "Spanish"], ["156", "Sri Lankan"], ["157", "Sudanese"], ["189", "Swedish"], ["159", "Swiss"], ["160", "Syrian"], ["161", "Taiwanese"], ["162", "Tajik"], ["163", "Tanzanian"], ["164", "Thai"], ["195", "Togolese"], ["194", "Tunisian"], ["165", "Turkish"], ["1063", "Turkmen"], ["166", "Ugandan"], ["167", "Ukrainian"], ["1013", "United states of America"], ["169", "Uzbekistani"], ["185", "Vanuatu"], ["170", "Venezuelan"], ["171", "Vietnamese"], ["172", "YEMENI"], ["1085", "Zambian"], ["174", "Zimbabwean"]];
  const POSITIONS = [["18", "Banking & Finance"], ["19", "Carpenter"], ["20", "Cashier"], ["21", "Electrician"], ["22", "Engineer"], ["23", "General Secretory"], ["24", "Health & Medicine & Nursing"], ["25", "Heavy Driver"], ["26", "IT & Internet Engineer"], ["27", "Leisure & Tourism"], ["28", "Light Driver"], ["29", "Mason"], ["30", "President"], ["31", "Labour"], ["32", "Plumber"], ["33", "Doctor"], ["34", "Family"], ["35", "Steel Fixer"], ["36", "Aluminum Technician"], ["37", "Nurse"], ["38", "Male Nurse"], ["39", "Ward Boy"], ["40", "Shovel Operator"], ["41", "Dozer Operator"], ["42", "Car Mechanic"], ["43", "Petrol Mechanic"], ["44", "Diesel Mechanic"], ["45", "Student"], ["46", "Accountant"], ["47", "Lab Technician"], ["48", "Drafts man"], ["49", "Auto-Cad Operator"], ["50", "Painter"], ["51", "Tailor"], ["52", "Welder"], ["53", "X-ray Technician"], ["54", "Lecturer"], ["55", "A.C Technician"], ["56", "Business"], ["57", "Cleaner"], ["58", "Security Guard"], ["59", "House Maid"], ["60", "Manager"], ["61", "Hospital Cleaning"], ["62", "Mechanic"], ["63", "Computer Operator"], ["64", "House Driver"], ["65", "Driver"], ["66", "Cleaning Labour"], ["67", "Building Electrician"], ["68", "Salesman"], ["69", "Plastermason"], ["70", "Servant"], ["71", "Barber"], ["72", "Residence"], ["73", "Shepherds"], ["74", "Employment"], ["75", "Fuel Filler"], ["76", "Worker"], ["77", "House Boy"], ["78", "House Wife"], ["79", "RCC Fitter"], ["80", "Clerk"], ["81", "Microbiologist"], ["82", "Teacher"], ["83", "Helper"], ["84", "Hajj Duty"], ["85", "Shuttering"], ["86", "Supervisor"], ["87", "Medical Specialist"], ["88", "Office Secretary"], ["89", "Technician"], ["90", "Butcher"], ["91", "Arabic Food Cook"], ["92", "Agricultural Worker"], ["93", "Service"], ["94", "Studio CAD Designer"], ["95", "Financial Analyst"], ["96", "Cabin Appearance (AIR LINES)"], ["97", "Car Washer"], ["98", "Surveyor"], ["99", "Electrical Technician"], ["100", "Waiter"], ["103", "Nursing helper"], ["104", "Anesthesia technician"], ["105", "<s>Marvel"], ["106", "Marvel"], ["107", "Construction worker"], ["108", "Other"]];
  const CITIES = [["80","Dhaka"],["81","Chitagong"],["83","Sylhet"],["2031","Barishal"],["2061","Chandpur"],["2033","Cox's Bazar"],["2032","Cumilla"],["2030","Rajshahi"],["2059","Sherpur"]];
  const DESTS = [["SA","Saudi Arabia"],["KW","Kuwait"],["OM","Oman"],["QA","Qatar"],["BH","Bahrain"],["UAE","UAE"],["YEM","Yemen"]];

  /* ---------- icons (Lucide-style, stroke) ---------- */
  const P = {
    logo: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10"/><path d="M12 8v6"/><path d="M9 11h6"/>',
    center: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M12 8v8"/><path d="M8 12h8"/>',
    fill: '<rect width="8" height="4" x="8" y="2" rx="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><path d="M8 11h8"/><path d="M8 15h5"/>',
    ok: '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
    bad: '<circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/>',
    warn: '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
    search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
    unlock: '<rect width="18" height="11" x="3" y="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 9.9-1"/>',
    lock: '<rect width="18" height="11" x="3" y="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',
    save: '<path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"/><path d="M17 21v-8H7v8"/><path d="M7 3v5h8"/>',
    plus: '<path d="M5 12h14"/><path d="M12 5v14"/>',
    trash: '<path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>',
    x: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    min: '<path d="M5 12h14"/>',
    zap: '<path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z"/>',
    send: '<path d="m22 2-7 20-4-9-9-4Z"/><path d="M22 2 11 13"/>',
    pin: '<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/>',
    refresh: '<path d="M21 12a9 9 0 1 1-3-6.7L21 8"/><path d="M21 3v5h-5"/>'
  };
  const ic = (n, s = 16) => `<svg class="ic" width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${P[n]}</svg>`;
  const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const opts = (l, sel) => l.map(([v, t]) => `<option value="${esc(v)}"${v === sel ? " selected" : ""}>${esc(t)}</option>`).join("");

  /* ---------- bridge to MAIN world ---------- */
  let seq = 0; const pending = new Map();
  const call = (cmd, args) => new Promise(res => {
    const id = ++seq; pending.set(id, res);
    window.postMessage({ __bd: true, type: "req", id, cmd, args }, location.origin);
    setTimeout(() => { if (pending.has(id)) { pending.delete(id); res(null); } }, 15000);
  });

  /* ---------- DOM ---------- */
  const host = document.createElement("div");
  host.id = "bd-wafid-assistant";
  host.style.cssText = "all:initial;position:fixed;z-index:2147483647;top:0;left:0;width:0;height:0";
  document.documentElement.appendChild(host);
  const root = host.attachShadow({ mode: "closed" });

  root.innerHTML = `<style>
  :host{all:initial}
  *{box-sizing:border-box;font-family:Inter,"Segoe UI",Roboto,Arial,sans-serif}
  .ic{flex:none;display:block}
  .launcher{position:fixed;right:20px;bottom:20px;display:flex;align-items:center;gap:8px;padding:10px 14px 10px 12px;border-radius:999px;
    background:#0f172a;color:#fff;font-size:12.5px;font-weight:600;cursor:pointer;box-shadow:0 10px 30px rgba(15,23,42,.35);border:none}
  .launcher .dot{width:8px;height:8px;border-radius:50%;background:#94a3b8}
  .panel{position:fixed;right:20px;bottom:20px;width:380px;max-height:calc(100vh - 40px);display:flex;flex-direction:column;background:#fff;
    border-radius:14px;box-shadow:0 24px 60px rgba(15,23,42,.28),0 0 0 1px rgba(15,23,42,.08);overflow:hidden;color:#0f172a;font-size:13px}
  .hd{display:flex;align-items:center;gap:10px;padding:12px 14px;background:#0f172a;color:#fff;cursor:move;user-select:none}
  .hd .t{font-weight:700;font-size:13.5px;letter-spacing:.2px}.hd .s{font-size:11px;color:#94a3b8;font-weight:500}
  .hd .sp{flex:1}.ibtn{display:grid;place-items:center;width:28px;height:28px;border-radius:8px;border:none;background:transparent;color:#cbd5e1;cursor:pointer}
  .ibtn:hover{background:rgba(255,255,255,.1);color:#fff}
  .body{overflow:auto;padding:12px 14px 14px}
  .status{display:flex;gap:10px;padding:10px 12px;border-radius:10px;border:1px solid;margin-bottom:12px}
  .status .h{font-weight:700;font-size:12.5px}.status .d{font-size:12px;margin-top:2px;color:#334155;word-break:break-word}
  .status code{font-family:ui-monospace,Consolas,monospace;font-size:12px;background:rgba(15,23,42,.06);padding:1px 5px;border-radius:4px}
  .st-ok{background:#f0fdf4;border-color:#bbf7d0;color:#15803d}.st-bad{background:#fef2f2;border-color:#fecaca;color:#b91c1c}
  .st-warn{background:#fff7ed;border-color:#fed7aa;color:#c2410c}.st-idle{background:#f8fafc;border-color:#e2e8f0;color:#475569}
  .chips{display:flex;flex-wrap:wrap;gap:4px;margin-top:6px}.chip{font-size:10.5px;padding:2px 7px;border-radius:999px;background:#fff;border:1px solid #e2e8f0;color:#475569}
  .tabs{display:flex;gap:4px;padding:3px;background:#f1f5f9;border-radius:10px;margin-bottom:12px}
  .tab{flex:1;white-space:nowrap;display:flex;align-items:center;justify-content:center;gap:6px;padding:7px;border:none;border-radius:8px;background:transparent;color:#475569;font-size:12.5px;font-weight:600;cursor:pointer}
  .tab.on{background:#fff;color:#0f172a;box-shadow:0 1px 3px rgba(15,23,42,.12)}
  .btn{display:flex;align-items:center;justify-content:center;gap:7px;width:100%;padding:9px 12px;border-radius:9px;border:1px solid transparent;font-size:12.5px;font-weight:600;cursor:pointer}
  .btn.pri{background:#2563eb;color:#fff}.btn.pri:hover{background:#1d4ed8}
  .btn.dark{background:#0f172a;color:#fff}.btn.dark:hover{background:#1e293b}
  .btn.ghost{background:#fff;color:#0f172a;border-color:#e2e8f0}.btn.ghost:hover{background:#f8fafc}
  .btn.danger{background:#dc2626;color:#fff}
  .row{display:flex;gap:6px;margin-bottom:10px}.row .btn{width:auto}
  .inp{position:relative;margin-bottom:8px}.inp .ic{position:absolute;left:10px;top:50%;transform:translateY(-50%);color:#94a3b8}
  input,select{width:100%;padding:7px 9px;border:1px solid #e2e8f0;border-radius:8px;font-size:12.5px;color:#0f172a;background:#fff;outline:none}
  input:focus,select:focus{border-color:#2563eb;box-shadow:0 0 0 3px rgba(37,99,235,.12)}
  .inp input{padding-left:32px}
  .list{border:1px solid #e2e8f0;border-radius:10px;max-height:300px;overflow:auto}
  .gh{position:sticky;top:0;display:flex;align-items:center;gap:6px;padding:6px 10px;background:#f8fafc;border-bottom:1px solid #e2e8f0;font-size:11px;font-weight:700;color:#2563eb;text-transform:uppercase;letter-spacing:.4px}
  .it{display:flex;align-items:center;gap:8px;padding:8px 10px;border-bottom:1px solid #f1f5f9;cursor:pointer;font-size:12.5px}
  .it:hover{background:#f8fafc}.it .n{flex:1}.it .id{font-family:ui-monospace,Consolas,monospace;font-size:11px;color:#64748b;background:#f1f5f9;padding:1px 6px;border-radius:5px}
  .it.sel{background:#eff6ff;color:#1d4ed8;font-weight:600}.it.sel .id{background:#dbeafe;color:#1d4ed8}
  .empty{padding:14px;text-align:center;color:#94a3b8;font-size:12px}
  .g2{display:grid;grid-template-columns:1fr 1fr;gap:8px}
  label{display:block;font-size:11px;font-weight:600;color:#475569;margin-bottom:8px}label input,label select{margin-top:4px}
  .sec{font-size:10.5px;font-weight:700;text-transform:uppercase;letter-spacing:.5px;color:#94a3b8;margin:4px 0 8px}
  .stack{display:grid;gap:6px;margin-top:4px}
  .res{margin-top:10px;border:1px solid #e2e8f0;border-radius:10px;padding:8px 10px;max-height:180px;overflow:auto}
  .res .r{display:flex;align-items:center;gap:6px;font-size:12px;padding:2px 0}.res .r.y{color:#15803d}.res .r.n{color:#c2410c}
  .note{display:flex;gap:6px;align-items:flex-start;font-size:11.5px;color:#475569;margin-top:8px}
  .toast{font-size:12px;margin-top:8px;color:#15803d;display:flex;gap:6px;align-items:center}
  .ov{position:fixed;inset:0;background:rgba(15,23,42,.45);display:grid;place-items:center}
  .md{width:400px;max-width:calc(100vw - 32px);background:#fff;border-radius:14px;padding:20px;box-shadow:0 30px 80px rgba(0,0,0,.35);color:#0f172a}
  .md .mh{display:flex;gap:10px;align-items:center;font-weight:700;font-size:15px;color:#c2410c;margin-bottom:10px}
  .hide{display:none!important}
  </style>
  <button class="launcher" id="launch">${ic("logo", 16)}<span>Wafid Assistant</span><span class="dot" id="ldot"></span></button>
  <div class="panel hide" id="panel">
    <div class="hd" id="drag">${ic("logo", 20)}<div><div class="t">Wafid Assistant</div><div class="s" id="sub">Medical Center &amp; Auto Fill</div></div>
      <div class="sp"></div><button class="ibtn" id="minB" title="Minimize">${ic("min")}</button></div>
    <div class="body">
      <div class="status st-idle" id="status"></div>
      <div id="bookingUI">
        <div class="tabs"><button class="tab on" data-t="c">${ic("center", 15)}Center</button><button class="tab" data-t="f">${ic("fill", 15)}Auto Fill</button></div>
        <div id="t-c">
          <div class="row"><button class="btn ghost" id="unlockB" style="flex:1">${ic("unlock", 15)}Unlock Dropdown</button></div>
          <div class="inp">${ic("search", 15)}<input id="q" placeholder="Search center name or code (e.g. 328, Ibn Sina)"></div>
          <div class="list" id="list"></div>
        </div>
        <div id="t-f" class="hide">
          <div class="row"><select id="prof" style="flex:1"></select>
            <button class="btn ghost" id="newP" title="New profile">${ic("plus", 15)}</button>
            <button class="btn ghost" id="delP" title="Delete profile" style="color:#dc2626">${ic("trash", 15)}</button></div>
          <form id="pf" autocomplete="off">
            <label>Profile name<input name="_label" placeholder="e.g. Shawon"></label>
            <div class="sec">Location</div>
            <div class="g2"><label>City<select name="city">${opts(CITIES, "80")}</select></label>
              <label>Travelling to<select name="traveled_country">${opts(DESTS, "SA")}</select></label></div>
            <div class="sec">Candidate</div>
            <div class="g2"><label>First name<input name="first_name"></label><label>Last name<input name="last_name"></label></div>
            <div class="g2"><label>Date of birth<input type="date" name="dob"></label><label>Nationality<select name="nationality">${opts(NATIONALITIES, "15")}</select></label></div>
            <div class="g2"><label>Gender<select name="gender">${opts([["male","Male"],["female","Female"]])}</select></label>
              <label>Marital status<select name="marital_status">${opts([["married","Married"],["unmarried","Single"]])}</select></label></div>
            <div class="sec">Passport</div>
            <div class="g2"><label>Passport no<input name="passport"></label><label>Issue place<input name="passport_issue_place" value="Dhaka"></label></div>
            <div class="g2"><label>Issue date<input type="date" name="passport_issue_date"></label><label>Expiry date<input type="date" name="passport_expiry_on"></label></div>
            <div class="sec">Visa &amp; Contact</div>
            <div class="g2"><label>Visa type<select name="visa_type">${opts([["wv","Work Visa"],["fv","Family Visa"],["sv","Study Visa"]])}</select></label><label>National ID<input name="national_id"></label></div>
            <div class="g2"><label>Email<input type="email" name="email"></label><label>Phone<input name="phone" placeholder="+8801XXXXXXXXX"></label></div>
            <label>Applied position<select name="applied_position">${opts(POSITIONS)}</select></label>
            <label id="otherW" class="hide">Other position<input name="applied_position_other"></label>
          </form>
          <div class="stack"><button class="btn ghost" id="saveP">${ic("save", 15)}Save Profile</button><button class="btn pri" id="fillB">${ic("zap", 15)}Auto Fill Form</button></div>
          <div id="msg"></div>
        </div>
      </div>
    </div>
  </div>
  <div class="ov hide" id="ov"><div class="md">
    <div class="mh">${ic("warn", 22)}<span id="mT">Submission paused</span></div>
    <div id="mB"></div>
    <div class="act"><button class="btn ghost" id="mC">Cancel</button><button class="btn danger" id="mS">${ic("send", 15)}Submit anyway</button></div>
  </div></div>`;

  const $ = id => root.getElementById(id);
  const panel = $("panel"), launch = $("launch");

  /* ---------- open / minimize / drag ---------- */
  const setOpen = o => { panel.classList.toggle("hide", !o); launch.classList.toggle("hide", o); chrome.storage.local.set({ bdPanelOpen: o }); };
  launch.onclick = () => setOpen(true);
  $("minB").onclick = () => setOpen(false);
  (() => {
    let sx, sy, ox, oy, dragging = false;
    $("drag").addEventListener("mousedown", e => {
      if (e.target.closest(".ibtn")) return;
      const r = panel.getBoundingClientRect(); dragging = true; sx = e.clientX; sy = e.clientY; ox = r.left; oy = r.top; e.preventDefault();
    });
    window.addEventListener("mousemove", e => {
      if (!dragging) return;
      const l = Math.max(0, Math.min(window.innerWidth - 100, ox + e.clientX - sx)), t = Math.max(0, Math.min(window.innerHeight - 60, oy + e.clientY - sy));
      Object.assign(panel.style, { left: l + "px", top: t + "px", right: "auto", bottom: "auto" });
    });
    window.addEventListener("mouseup", () => { dragging = false; });
  })();

  /* ---------- form status ---------- */
  let st = null, groups = [];
  function renderStatus() {
    const box = $("status"), dot = $("ldot");
    if (!st) { box.className = "status st-idle"; box.innerHTML = `${ic("refresh", 18)}<div><div class="h">Connecting to page…</div></div>`; return; }
    if (st.page === "pay") {
      const l = st.last;
      const ok = l && l.medical_center;
      box.className = "status " + (ok ? "st-ok" : l ? "st-bad" : "st-idle");
      dot.style.background = ok ? "#22c55e" : l ? "#ef4444" : "#94a3b8";
      box.innerHTML = `${ic(ok ? "ok" : l ? "bad" : "warn", 18)}<div><div class="h">${ok ? "Last POST sent your target center" : l ? "Last POST had an empty medical center" : "No POST recorded in this tab"}</div>` +
        (l ? `<div class="d">medical_center = <code>${esc(l.medical_center || '""')}</code>${l.name ? " · " + esc(l.name) : ""}</div><div class="d">${esc(new Date(l.at).toLocaleString())}</div>` : "") +
        `<div class="d" style="margin-top:6px">Final proof: after payment, check the assigned center on Search Slip.</div></div>`;
      return;
    }
    const v = st.v, p = v.p || {};
    const M = {
      ok: ["st-ok", "ok", "Your target center will be sent", `medical_center = <code>${esc(v.sent)}</code>${v.sentName ? " · " + esc(v.sentName) : ""}`, "#22c55e"],
      empty: ["st-bad", "bad", "Empty value will be sent", `medical_center = <code>""</code> · server will auto-assign. Pick a center below.`, "#ef4444"],
      mismatch: ["st-warn", "warn", "Different center will be sent", `Sending <code>${esc(v.sent)}</code> ${esc(v.sentName)} · you chose <code>${esc(v.chosen)}</code> ${esc(v.chosenName)}`, "#f97316"],
      unchosen: ["st-warn", "warn", "Center auto-picked by the site", `Sending <code>${esc(v.sent)}</code> ${esc(v.sentName)} · not chosen by you. Pick your target below.`, "#f97316"],
      missing: ["st-idle", "warn", "Medical center field not found", "Open the Book Appointment form.", "#94a3b8"]
    }[v.status];
    box.className = "status " + M[0]; dot.style.background = M[4];
    box.innerHTML = `${ic(M[1], 18)}<div style="min-width:0"><div class="h">${M[2]}</div><div class="d">${M[3]}</div>
      <div class="chips"><span class="chip">${esc(p.country || "—")}</span><span class="chip">${ic("pin", 10).replace('class="ic"', 'class="ic" style="display:inline;vertical-align:-1px"')} ${esc(st.cityName || p.city || "—")}</span><span class="chip">${esc(p.traveled_country || "—")}</span><span class="chip">${esc(p.appointment_type || "—")}</span></div></div>`;
  }

  let lastCity = null, lastSel = null;
  window.addEventListener("message", e => {
    if (e.source !== window || !e.data || !e.data.__bd) return;
    const d = e.data;
    if (d.type === "res" && pending.has(d.id)) { pending.get(d.id)(d.result); pending.delete(d.id); }
    else if (d.type === "state") {
      st = d.state; renderStatus();
      if (st.page === "pay") { $("bookingUI").classList.add("hide"); $("sub").textContent = "Payment page"; return; }
      const city = st.v.p.city, sel = st.selected.value;
      if (city !== lastCity || sel !== lastSel) { lastCity = city; lastSel = sel; renderList(); }
    }
    else if (d.type === "gate") showGate(d.v);
  });

  /* ---------- tabs ---------- */
  root.querySelectorAll(".tab").forEach(t => t.onclick = () => {
    root.querySelectorAll(".tab").forEach(x => x.classList.toggle("on", x === t));
    ["c", "f"].forEach(k => $("t-" + k).classList.toggle("hide", t.dataset.t !== k));
  });

  /* ---------- centers ---------- */
  function renderList() {
    const q = $("q").value.toLowerCase().trim(), list = $("list");
    const city = st && st.v ? String(st.v.p.city) : "";
    const sel = st && st.selected ? String(st.selected.value) : "";
    const g = groups.find(x => x.cityId === city);
    const show = g ? [g] : groups;
    let html = "";
    show.forEach(gr => {
      const f = gr.centers.filter(c => c.name.toLowerCase().includes(q) || c.value.includes(q));
      if (!f.length) return;
      html += `<div class="gh">${ic("pin", 12)}${esc(gr.label)} · ${f.length}</div>`;
      html += f.map(c => `<div class="it${c.value === sel ? " sel" : ""}" data-v="${esc(c.value)}" data-n="${esc(c.name)}">${ic(c.value === sel ? "lock" : "center", 14)}<span class="n">${esc(c.name)}</span><span class="id">#${esc(c.value)}</span></div>`).join("");
    });
    list.innerHTML = html || `<div class="empty">No matching medical center found.</div>`;
  }
  $("q").oninput = renderList;
  $("list").onclick = async e => {
    const it = e.target.closest(".it"); if (!it) return;
    await call("select", { value: it.dataset.v, name: it.dataset.n });
    lastSel = null;
  };
  $("unlockB").onclick = () => call("unlock");

  /* ---------- profiles ---------- */
  const form = $("pf"), profSel = $("prof");
  let profiles = [{}], cur = 0;
  const readF = () => Object.fromEntries(new FormData(form).entries());
  const writeF = p => Array.from(form.elements).forEach(el => {
    if (!el.name) return;
    if (p[el.name] !== undefined) el.value = p[el.name];
    else if (el.tagName === "INPUT") el.value = el.name === "passport_issue_place" ? "Dhaka" : "";
  });
  const other = () => $("otherW").classList.toggle("hide", form.applied_position.value !== "108");
  form.applied_position.onchange = other;
  const renderProf = () => { profSel.innerHTML = profiles.map((p, i) => `<option value="${i}">${esc(p._label || p.first_name || "Profile " + (i + 1))}</option>`).join(""); profSel.value = String(cur); };
  const persist = () => chrome.storage.local.set({ wafidProfiles: profiles, wafidCurrent: cur });
  const msg = (html, ok = true) => { $("msg").innerHTML = `<div class="toast" style="color:${ok ? "#15803d" : "#b91c1c"}">${ic(ok ? "ok" : "bad", 14)}${html}</div>`; };

  profSel.onchange = () => { cur = Number(profSel.value); writeF(profiles[cur]); other(); persist(); };
  $("newP").onclick = () => { profiles.push({}); cur = profiles.length - 1; renderProf(); writeF({}); other(); persist(); };
  $("delP").onclick = () => { profiles.splice(cur, 1); if (!profiles.length) profiles = [{}]; cur = 0; renderProf(); writeF(profiles[0]); other(); persist(); msg("Profile deleted"); };
  $("saveP").onclick = () => {
    const p = readF();
    if (p.passport && !/^[A-Za-z0-9]+$/.test(p.passport)) return msg("Passport no: letters and numbers only", false);
    profiles[cur] = p; renderProf(); persist(); msg("Profile saved");
  };
  $("fillB").onclick = async () => {
    const p = readF(); profiles[cur] = p; persist();
    $("msg").innerHTML = `<div class="toast" style="color:#475569">${ic("refresh", 14)}Filling form…</div>`;
    const r = await call("autofill", { profile: p });
    if (!Array.isArray(r)) return msg("Could not fill. Reload the page and try again.", false);
    const okN = r.filter(x => x.ok).length;
    $("msg").innerHTML = `<div class="res">${r.map(x => `<div class="r ${x.ok ? "y" : "n"}">${ic(x.ok ? "ok" : "warn", 13)}${esc(x.k)}</div>`).join("")}</div>
      <div class="note">${ic("lock", 14)}<span>${okN}/${r.length} fields filled. Complete Captcha and OTP yourself, then submit.</span></div>`;
  };

  /* ---------- submit gate modal ---------- */
  function showGate(v) {
    const B = {
      empty: `<p>The form is about to send <b>medical_center = ""</b> (empty).</p><p>The server will auto-assign a center instead of your target.</p>`,
      mismatch: `<p>The form will send <b>${esc(v.sent)}</b> ${esc(v.sentName)}</p><p>but you selected <b>${esc(v.chosen)}</b> ${esc(v.chosenName)}.</p>`,
      unchosen: `<p>The form will send <b>${esc(v.sent)}</b> ${esc(v.sentName)}.</p><p>This center was auto-picked by the site, not selected by you.</p>`,
      missing: `<p>The medical_center field was not found in the form.</p>`
    }[v.status] || "";
    $("mB").innerHTML = B; $("ov").classList.remove("hide");
  }
  $("mC").onclick = () => { $("ov").classList.add("hide"); setOpen(true); root.querySelector('.tab[data-t="c"]').click(); };
  $("mS").onclick = async () => { $("ov").classList.add("hide"); await call("forceSubmit"); };

  /* ---------- init ---------- */
  chrome.storage.local.get(["wafidProfiles", "wafidCurrent", "bdPanelOpen"], d => {
    profiles = d.wafidProfiles && d.wafidProfiles.length ? d.wafidProfiles : [{}];
    cur = Math.min(d.wafidCurrent || 0, profiles.length - 1);
    renderProf(); writeF(profiles[cur]); other();
    setOpen(d.bdPanelOpen !== false);
  });
  renderStatus();
  (async function loadGroups() {
    const g = await call("groups");
    if (Array.isArray(g)) { groups = g; renderList(); } else setTimeout(loadGroups, 1000);
  })();
};