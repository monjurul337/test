"use strict";const PARTNER_HOME="https://play.google.com/books/publish",POLL_ALARM="pbu-poll-processing";async function getJob(){const{job:t}=await chrome.storage.local.get("job");return t||null}async function saveJob(t){await chrome.storage.local.set({job:t})}function nowTime(){return(new Date).toLocaleTimeString([],{hour12:!1})}async function log(t,e="info"){const o=await getJob();o&&(o.log=o.log||[],o.log.push({t:nowTime(),level:e,text:t}),o.log.length>600&&(o.log=o.log.slice(-600)),await saveJob(o))}async function setStatus(t,e){const o=await getJob();o&&(o.status=t,e&&(o.stage=e),await saveJob(o))}function notify(t,e){chrome.notifications.create({type:"basic",iconUrl:"icons/icon128.png",title:t,message:String(e||"").slice(0,240)},()=>{chrome.runtime.lastError})}async function findPartnerTab(){const t=await getJob(),e=await chrome.tabs.query({url:"https://play.google.com/books/publish*"});let o=e&&e[0];if(t&&t.bookUrl&&e.length){const a=e.find(e=>e.url&&e.url.split("#")[0].split("?")[0]===t.bookUrl.split("#")[0].split("?")[0]);a&&(o=a)}return o||(o=await chrome.tabs.create({url:t&&t.bookUrl||PARTNER_HOME,active:!1}),await log("Poll: no Partner Center tab was open — opened one so processing checks can continue.")),"complete"!==o.status&&await new Promise(t=>{const e=(a,s)=>{a===o.id&&"complete"===s.status&&(chrome.tabs.onUpdated.removeListener(e),t())};chrome.tabs.onUpdated.addListener(e),setTimeout(()=>{chrome.tabs.onUpdated.removeListener(e),t()},3e4)}),o}async function waitForContentScript(t,e=40){for(let o=0;o<e;o++){try{const e=await chrome.tabs.sendMessage(t,{type:"PING"});if(e&&e.ok)return!0}catch(t){}await new Promise(t=>setTimeout(t,750))}try{await chrome.scripting.executeScript({target:{tabId:t},files:["content.js"]});const e=await chrome.tabs.sendMessage(t,{type:"PING"});return!(!e||!e.ok)}catch(t){return!1}}function sendStage(t,e,o){return chrome.tabs.sendMessage(t,{type:"RUN_STAGE",stage:e,payload:{meta:o.meta,ggkey:o.ggkey,bookUrl:o.bookUrl}})}async function pollProcessing(){let t=await getJob();if(!t||"processing"!==t.status&&"publishing"!==t.status)return;const e=await findPartnerTab();if(!await waitForContentScript(e.id))return void await log("Poll: content script not ready; will retry next cycle.");let o,a;try{o=await sendStage(e.id,"processing_check",t)}catch(t){return void await log("Poll: no response from page ("+(t&&t.message||t)+"); will retry.")}if(t=await getJob(),!t||"stopped"===t.status)return;if(!o||!o.ok){const t=o&&o.error||"Unknown processing-check error";return o&&o.stopCondition?void await stopCondition(t):o&&o.processingError?void await failJob("EPUB processing error: "+t):void await log("Poll: "+t+" (will retry next cycle)")}if("number"==typeof o.step&&o.step!==t.lastStep&&(t.lastStep=o.step,await saveJob(t),await log(`Processing: completed step ${o.step} of 6.`)),!o.done){return void((Date.now()-(t.startedAt||Date.now()))/864e5>=3&&!t.escalationSent&&(t.escalationSent=!0,await saveJob(t),notify("Play Books: processing is very slow","EPUB processing is still not complete after 3 days. Next step: contact Google Play Books support."),await log("Processing unusually slow (3+ days) — support-ticket escalation noted.","error")))}await log("Processing complete (step 6 of 6). Publishing now…","stage"),await setStatus("publishing","publish"),t=await getJob();try{a=await sendStage(e.id,"publish",t)}catch(t){a={ok:!1,error:"No response from page: "+(t&&t.message||t)}}if(!a||!a.ok){const t=a&&a.error||"Unknown publish error";return a&&a.stopCondition?void await stopCondition(t):void await failJob("Publish failed: "+t)}if(a.log)for(const t of a.log)await log(t.text,t.level||"info");const s=a&&a.catalogStatus||"unknown";if("unknown"===s||!["live","published","preorder","pre-order"].includes(String(s).toLowerCase())){const t=await getJob();return t&&(t.status="error",t.stage="publish",t.catalogStatus=s,t.error="unknown"===s?"Publish was clicked, but the book's catalog status could not be verified — check the book in the Partner Center before assuming it is published.":`Publish was clicked, but the book's status reads "${s}", not a published state — check the book in the Partner Center.`,await saveJob(t)),chrome.alarms.clear(POLL_ALARM),await log("⚠ Publish unverified: "+(t?t.error:s),"error"),void notify("Play Books: publish NOT verified","unknown"===s?"The publish button was clicked, but the catalog status could not be read back. Please check the book in the Partner Center.":`The publish button was clicked, but the book's status reads "${s}". Please check the book in the Partner Center.`)}t=await getJob(),t&&(t.status="done",t.stage="done",t.catalogStatus=s,t.finishedAt=Date.now(),await saveJob(t)),chrome.alarms.clear(POLL_ALARM),await log(`✅ Published. Catalog status: ${s}.`,"ok"),notify("Play Books: book published ✅",`"${t&&t.meta?t.meta.title:"Your book"}" was published. Catalog status: ${s}.`)}async function failJob(t){const e=await getJob();e&&(e.status="error",e.error=t,await saveJob(e)),chrome.alarms.clear(POLL_ALARM),await log("✖ "+t,"error"),notify("Play Books upload failed",t)}async function stopCondition(t){const e=await getJob();e&&(e.status="stop_condition",e.error=t,await saveJob(e)),chrome.alarms.clear(POLL_ALARM),await log("⛔ Stopped — your action is needed: "+t,"error"),notify("Play Books: action needed",t)}chrome.runtime.onMessage.addListener((t,e,o)=>((async()=>{if(t&&t.type)if("START_JOB"===t.type){const t=await getJob();t&&"running"===t.status&&t.meta&&await log(`Run started: "${t.meta.title}" by ${t.meta.author} — ${t.meta.currency} ${t.meta.price}, ${t.meta.pages||"?"} pages.`,"stage"),o({ok:!0})}else if("ARM_POLL"===t.type){const t=await getJob();t&&"processing"===t.status&&(await log("Upload finished. Waiting for Google to process the EPUB — checking every ~2 minutes. Publishing happens automatically when processing completes.","stage"),chrome.alarms.create(POLL_ALARM,{periodInMinutes:2,delayInMinutes:.2})),o({ok:!0})}else if("STOP_JOB"===t.type){const t=await getJob();t&&"stopped"!==t.status&&(t.status="stopped",await saveJob(t)),chrome.alarms.clear(POLL_ALARM),await log("Stopped by user.","error"),notify("Play Books upload stopped","The upload job was stopped from the extension panel."),o({ok:!0})}else"NOTIFY"===t.type&&(notify(t.title||"Play Books Auto Uploader",t.message||""),o({ok:!0}))})(),!0)),chrome.alarms.onAlarm.addListener(t=>{t.name===POLL_ALARM&&pollProcessing()}),chrome.action&&chrome.action.onClicked&&chrome.action.onClicked.addListener(async t=>{if(t&&t.id&&/^https:\/\/play\.google\.com\/books\/publish/.test(t.url||""))try{await chrome.tabs.sendMessage(t.id,{type:"TOGGLE_PANEL"})}catch(t){}}),chrome.runtime.onStartup.addListener(async()=>{const t=await getJob();t&&("processing"!==t.status&&"publishing"!==t.status||chrome.alarms.create(POLL_ALARM,{periodInMinutes:2,delayInMinutes:.2}))});

/* ================= v9.8 main-world upload bridge =================
 * The current console's upload dialog has NO <input type="file">
 * anywhere (verified by the v9.6 census: 0 in page, 0 in shadow
 * roots/frames) and it ignores drag & drop events dispatched from
 * the content script's isolated world. The two functions below are
 * SERIALISED by chrome.scripting and executed in the page's MAIN
 * world (same world as the console's own code), where the staged
 * files are handed to the page directly: showOpenFilePicker is
 * answered with a staged file, a programmatic click on a transient
 * file input is served the staged file instead of opening the OS
 * picker, and drag & drop is dispatched with a main-world
 * DataTransfer the page can actually read. */
function pbuMainStage(payload) {
  const files = {};
  for (const f of (payload && payload.files) || []) {
    try {
      const bin = atob(f.base64);
      const bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      files[f.key] = new File([bytes], f.name, { type: f.type || 'application/octet-stream' });
    } catch (e) { /* skip this file */ }
  }
  window.__pbuStaged = files;
  if (!window.__pbuArmed) {
    window.__pbuArmed = true;
    window.__pbuServed = {};
    const pick = (acceptStr) => {
      const staged = window.__pbuStaged || {};
      const keys = Object.keys(staged);
      if (!keys.length) return null;
      const acc = String(acceptStr || '').toLowerCase();
      const match = (file) => {
        if (!acc) return true;
        const ext = '.' + String(file.name.split('.').pop() || '').toLowerCase();
        if (acc.includes(ext)) return true;
        if (/image/.test(acc) && /^image\//.test(file.type)) return true;
        if (/epub/.test(acc) && /epub/i.test(file.type + ' ' + file.name)) return true;
        if (/pdf/.test(acc) && /pdf/i.test(file.type + ' ' + file.name)) return true;
        return false;
      };
      const fresh = keys.filter((k) => !window.__pbuServed[k] && match(staged[k]));
      const anyM = keys.filter((k) => match(staged[k]));
      const key = fresh[0] || anyM[0] || keys[0];
      if (key) window.__pbuServed[key] = true;
      return key ? staged[key] : null;
    };
    window.showOpenFilePicker = async (opts) => {
      let acceptStr = '';
      try {
        const types = (opts && opts.types) || [];
        acceptStr = types.map((t) => Object.values(t.accept || {}).flat().join(',')).join(',');
      } catch (e) { /* ignore */ }
      const f = pick(acceptStr);
      if (!f) throw new DOMException('The user aborted a request.', 'AbortError');
      return [{
        kind: 'file', name: f.name,
        getFile: async () => f,
        queryPermission: async () => 'granted',
        requestPermission: async () => 'granted',
        isSameEntry: async () => false
      }];
    };
    const proto = window.HTMLInputElement && window.HTMLInputElement.prototype;
    if (proto && !proto.__pbuPatched) {
      const origClick = proto.click;
      proto.click = function () {
        try {
          if (this && this.__pbuServed) return;
          if (this && this.type === 'file' && window.__pbuStaged) {
            const f = pick(this.getAttribute && this.getAttribute('accept'));
            if (f) {
              this.__pbuServed = true;
              const dt = new DataTransfer();
              dt.items.add(f);
              this.files = dt.files;
              this.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
              this.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
              return;
            }
          }
        } catch (e) { /* fall through to the native click */ }
        return origClick.apply(this, arguments);
      };
      proto.__pbuPatched = true;
    }
    if (!window.__pbuClickArmed) {
      window.__pbuClickArmed = true;
      document.addEventListener('click', (e) => {
        try {
          const t = e.target;
          if (t && t.tagName === 'INPUT' && t.type === 'file' && !t.__pbuServed && window.__pbuStaged) {
            const f = pick(t.getAttribute && t.getAttribute('accept'));
            if (f) {
              e.preventDefault();
              e.stopImmediatePropagation();
              t.__pbuServed = true;
              const dt = new DataTransfer();
              dt.items.add(f);
              t.files = dt.files;
              setTimeout(() => {
                t.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
                t.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
              }, 0);
            }
          }
        } catch (err) { /* never break the page */ }
      }, true);
    }
  }
  return Object.keys(files);
}

function pbuMainPing() {
  return {
    armed: !!window.__pbuArmed,
    clickArmed: !!window.__pbuClickArmed,
    staged: Object.keys(window.__pbuStaged || {})
  };
}

function pbuMainDrop(key) {
  const staged = window.__pbuStaged || {};
  const f = staged[key] || Object.values(staged)[0];
  if (!f) return 'no-staged-file';
  const clean = (s) => String(s || '').replace(/\s+/g, ' ');
  const dlg = [...document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container')]
    .find((d) => /upload content and cover|drag and drop/i.test(clean(d.innerText || d.textContent)));
  if (!dlg) return 'no-dialog';
  const zone = [...dlg.querySelectorAll('*')]
    .find((e) => /drag and drop/i.test(clean(e.innerText || e.textContent)) && e.querySelectorAll('*').length < 12) || dlg;
  const dt = new DataTransfer();
  dt.items.add(f);
  for (const type of ['dragenter', 'dragover', 'drop']) {
    zone.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, composed: true, dataTransfer: dt }));
    dlg.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, composed: true, dataTransfer: dt }));
  }
  return 'dropped:' + f.name;
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || msg.type !== 'PBU_MAIN' || !sender.tab || !sender.tab.id) return;
  const target = { tabId: sender.tab.id };
  let run;
  if (msg.action === 'drop') run = chrome.scripting.executeScript({ target, world: 'MAIN', func: pbuMainDrop, args: [msg.kind] });
  else if (msg.action === 'ping') run = chrome.scripting.executeScript({ target, world: 'MAIN', func: pbuMainPing, args: [] });
  else if (msg.action === 'stage') run = chrome.scripting.executeScript({ target, world: 'MAIN', func: pbuMainStage, args: [msg.payload || {}] });
  else return; // other actions (assign, hunt-*) have their own listeners below
  run.then((res) => sendResponse({ ok: true, result: res && res[0] && res[0].result }))
    .catch((e) => sendResponse({ ok: false, error: String((e && e.message) || e) }));
  return true;
});

/* ================= v9.12 page-world direct assign =================
 * New bridge action "assign": instead of hoping the page asks for
 * the files (picker/input-click interception), the page world now
 * performs the picker's own end result directly — it finds the
 * upload dialog's real input[name="Filedata"], builds a DataTransfer
 * in the PAGE world from the staged page-world Files, sets
 * input.files and dispatches input+change in the PAGE world. Every
 * object the console's uploader component touches (File,
 * DataTransfer, the events) is then of its own world, exactly as
 * when a user picks files in the OS dialog. The return string is a
 * read-back: how many files the input actually holds afterwards. */
function pbuMainAssign(keys) {
  const staged = window.__pbuStaged || {};
  const wanted = (keys && keys.length ? keys : Object.keys(staged))
    .filter((k) => staged[k]);
  if (!wanted.length) return 'no-staged-file';
  const clean = (s) => String(s || '').replace(/\s+/g, ' ');
  const dlg = [...document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container')]
    .find((d) => /upload content and cover|drag and drop/i.test(clean(d.innerText || d.textContent)));
  if (!dlg) return 'no-dialog';
  const input = dlg.querySelector('input[type="file"][name="Filedata"]') || dlg.querySelector('input[type="file"]');
  if (!input) return 'no-input';
  try {
    const dt = new DataTransfer();
    for (const k of wanted) {
      dt.items.add(staged[k]);
      window.__pbuServed = window.__pbuServed || {};
      window.__pbuServed[k] = true;
    }
    input.files = dt.files;
    input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
    input.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
    return 'assigned:' + wanted.map((k) => staged[k].name).join(' + ') +
      ' (input now holds ' + (input.files ? input.files.length : 0) + ' file(s))';
  } catch (e) {
    return 'assign-error:' + String((e && e.message) || e);
  }
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || msg.type !== 'PBU_MAIN' || msg.action !== 'assign' || !sender.tab || !sender.tab.id) return;
  chrome.scripting.executeScript({
    target: { tabId: sender.tab.id },
    world: 'MAIN',
    func: pbuMainAssign,
    args: [msg.keys || []]
  })
    .then((res) => sendResponse({ ok: true, result: res && res[0] && res[0].result }))
    .catch((e) => sendResponse({ ok: false, error: String((e && e.message) || e) }));
  return true;
});

/* ================= v9.17 hidden-input hunter (page world) =================
 * The user's direction (2026-10-24): stop depending on drag & drop
 * and the Browse picker — find the page's HIDDEN file input, set
 * the File objects on it directly, fire input/change. The direct
 * assignment itself has been the lead route since v9.12
 * (pbuMainAssign), but it only ever searched the open upload
 * dialog, from the moment the dialog was opened. Three places an
 * input could exist that neither pbuMainAssign nor the content
 * script's shadow-piercing search could ever see:
 *   (1) inside a CLOSED shadow root (element.shadowRoot is null
 *       from every world once attached — unless the root object
 *       was captured when attachShadow was called);
 *   (2) created and removed again between the flow's checkpoints
 *       (the isolated-world capture net sees document insertions,
 *       but nothing ever ASSIGNED to a briefly-present input
 *       outside the dialog flow);
 *   (3) appended somewhere outside the dialog (some uploaders park
 *       a single global input on <body>).
 * The hunter closes those gaps: installed in the page world at
 * bridge-arm time (BEFORE the dialog opens), it wraps
 * Element.prototype.attachShadow to record every shadow root —
 * open or closed — keeps a MutationObserver net over the document
 * and every recorded root, and registers every input[type=file]
 * the moment it appears, wherever it appears. "assign-any" then
 * performs the picker's own end result on the best registered
 * input: page-world DataTransfer, input.files set, input+change
 * dispatched, read-back verified — exactly the user's requested
 * mechanism, applied to any input on the page. All three functions
 * below are self-contained (they are serialised into the page
 * world by chrome.scripting, like the other bridge functions). */

function pbuMainHuntInstall() {
    if (window.__pbuHuntInstalled) {
        return 'hunt-already-armed: roots=' + (window.__pbuRoots || []).length +
            ' inputs=' + (window.__pbuInputReg || []).length;
    }
    window.__pbuHuntInstalled = true;
    window.__pbuRoots = window.__pbuRoots || [];
    window.__pbuInputReg = window.__pbuInputReg || [];
    const roots = window.__pbuRoots;
    const reg = window.__pbuInputReg;
    const seen = new WeakSet();
    function inPanel(el) {
        // The extension's OWN panel (host #pbu-panel-host) carries
        // file inputs of its own (EPUB/cover/metadata pickers) —
        // they are not the console's uploader and must never be
        // hunted or assigned to. (Caught by the jsdom suite: the
        // hunter's first-ever pick was the panel's own input.)
        try {
            const root = el.getRootNode && el.getRootNode();
            if (root && root.host && root.host.id === 'pbu-panel-host') return true;
            if (el.closest && el.closest('#pbu-panel-host')) return true;
        } catch (e) { /* ignore */ }
        return false;
    }
    function noteInput(el, where) {
        if (!el || seen.has(el) || inPanel(el)) return;
        seen.add(el);
        reg.push({ el: el, where: where, at: Date.now() });
    }
    function noteRoot(root, mode) {
        if (!root || roots.indexOf(root) >= 0) return;
        roots.push(root);
        scan(root, 'shadow-' + mode);
        observe(root, 'shadow-' + mode);
    }
    function scan(node, where) {
        if (!node || (node.nodeType !== 1 && node.nodeType !== 9 && node.nodeType !== 11)) return;
        try {
            if (node.tagName === 'INPUT' && node.type === 'file') noteInput(node, where);
            if (node.querySelectorAll) {
                node.querySelectorAll('input[type="file"]').forEach((i) => noteInput(i, where));
                node.querySelectorAll('*').forEach((h) => { if (h.shadowRoot && h.id !== 'pbu-panel-host') noteRoot(h.shadowRoot, 'open'); });
            }
        } catch (e) { /* never break the page */ }
    }
    function observe(root, where) {
        try {
            const mo = new MutationObserver((muts) => {
                for (const m of muts) {
                    m.addedNodes.forEach((n) => scan(n, where === 'document' ? 'added' : where));
                }
            });
            mo.observe(root, { childList: true, subtree: true });
        } catch (e) { /* ignore */ }
    }
    scan(document, 'preexisting');
    observe(document, 'document');
    try {
        const proto = window.Element && window.Element.prototype;
        if (proto && proto.attachShadow && !proto.__pbuHuntPatched) {
            const orig = proto.attachShadow;
            proto.attachShadow = function (init) {
                const root = orig.apply(this, arguments);
                try { noteRoot(root, (init && init.mode) || 'open'); } catch (e) { /* ignore */ }
                return root;
            };
            proto.__pbuHuntPatched = true;
        }
    } catch (e) { /* ignore */ }
    return 'hunt-installed: roots=' + roots.length + ' inputs=' + reg.length;
}

function pbuMainHuntCensus() {
    // Fresh sweep first: even if an observer missed an insertion,
    // a scan of the document + every recorded root finds the input.
    const inPanel = (el) => {
        try {
            const root = el.getRootNode && el.getRootNode();
            if (root && root.host && root.host.id === 'pbu-panel-host') return true;
            if (el.closest && el.closest('#pbu-panel-host')) return true;
        } catch (e) { /* ignore */ }
        return false;
    };
    try {
        const reg0 = window.__pbuInputReg || (window.__pbuInputReg = []);
        const seenEls = new Set(reg0.map((r) => r.el));
        const sweep = (node, where) => {
            if (!node || !node.querySelectorAll) return;
            node.querySelectorAll('input[type="file"]').forEach((i) => {
                if (!seenEls.has(i) && !inPanel(i)) { seenEls.add(i); reg0.push({ el: i, where: where, at: Date.now() }); }
            });
        };
        sweep(document, 'added');
        (window.__pbuRoots || []).forEach((root) => sweep(root, 'shadow-sweep'));
    } catch (e) { /* ignore */ }
    const reg = window.__pbuInputReg || [];
    return {
        roots: (window.__pbuRoots || []).length,
        inputs: reg.map((r, i) => {
            let inDialog = false;
            try {
                inDialog = !!(r.el.closest && r.el.closest('[role="dialog"], .mat-dialog-container, mat-dialog-container'));
            } catch (e) { /* ignore */ }
            return {
                idx: i,
                name: (r.el.getAttribute && r.el.getAttribute('name')) || '',
                accept: (r.el.getAttribute && r.el.getAttribute('accept')) || '',
                multiple: !!r.el.multiple,
                connected: !!r.el.isConnected,
                inDialog: inDialog,
                where: r.where,
                holds: r.el.files ? r.el.files.length : 0
            };
        })
    };
}

function pbuMainAssignAny(keys) {
    const staged = window.__pbuStaged || {};
    let wanted = (keys && keys.length ? keys : Object.keys(staged))
        .filter((k) => staged[k]);
    if (!wanted.length) return 'no-staged-file';
    const clean = (s) => String(s || '').replace(/\s+/g, ' ');
    const candidates = [];
    const dlg = [...document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container')]
        .find((d) => /upload content and cover|drag and drop/i.test(clean(d.innerText || d.textContent)));
    if (dlg) {
        const di = dlg.querySelector('input[type="file"][name="Filedata"]') || dlg.querySelector('input[type="file"]');
        if (di) candidates.push({ el: di, where: 'dialog' });
    }
    // Fresh sweep (same belt-and-braces as the census): register
    // any input the observers missed before choosing a candidate.
    const inPanel = (el) => {
        try {
            const root = el.getRootNode && el.getRootNode();
            if (root && root.host && root.host.id === 'pbu-panel-host') return true;
            if (el.closest && el.closest('#pbu-panel-host')) return true;
        } catch (e) { /* ignore */ }
        return false;
    };
    try {
        const reg0 = window.__pbuInputReg || (window.__pbuInputReg = []);
        const seenEls = new Set(reg0.map((r) => r.el));
        const sweep = (node, where) => {
            if (!node || !node.querySelectorAll) return;
            node.querySelectorAll('input[type="file"]').forEach((i) => {
                if (!seenEls.has(i) && !inPanel(i)) { seenEls.add(i); reg0.push({ el: i, where: where, at: Date.now() }); }
            });
        };
        sweep(document, 'added');
        (window.__pbuRoots || []).forEach((root) => sweep(root, 'shadow-sweep'));
    } catch (e) { /* ignore */ }
    const reg = (window.__pbuInputReg || []).slice();
    reg.sort((a, b) => {
        const score = (r) => {
            let s = 0;
            try {
                if ((r.el.getAttribute('name') || '') === 'Filedata') s += 40;
                if (r.el.closest && r.el.closest('[role="dialog"], .mat-dialog-container, mat-dialog-container')) s += 30;
                if (String(r.where).indexOf('shadow') === 0) s += 20;
                if (r.el.isConnected) s += 10;
            } catch (e) { /* ignore */ }
            return s;
        };
        return score(b) - score(a) || b.at - a.at;
    });
    for (const r of reg) {
        if (inPanel(r.el)) continue;
        if (!candidates.some((c) => c.el === r.el)) candidates.push({ el: r.el, where: r.where });
    }
    if (!candidates.length) {
        return 'no-input-anywhere: roots=' + (window.__pbuRoots || []).length +
            ' registered=' + reg.length;
    }
    let lastErr = '';
    for (const cand of candidates) {
        const input = cand.el;
        let use = wanted;
        if (!input.multiple && use.length > 1) use = use.slice(0, 1);
        try {
            const dt = new DataTransfer();
            for (const k of use) dt.items.add(staged[k]);
            input.files = dt.files;
            const held = input.files ? input.files.length : 0;
            if (!held) { lastErr = 'read-back held 0 file(s) on a ' + cand.where + ' input'; continue; }
            for (const k of use) {
                window.__pbuServed = window.__pbuServed || {};
                window.__pbuServed[k] = true;
            }
            input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
            input.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
            return 'assigned-anywhere[' + cand.where + ']: ' + use.map((k) => staged[k].name).join(' + ') +
                ' (input now holds ' + held + ' file(s))';
        } catch (e) {
            lastErr = String((e && e.message) || e);
        }
    }
    return 'assign-anywhere-failed: ' + (lastErr || 'no candidate accepted the files');
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (!msg || msg.type !== 'PBU_MAIN' || !sender.tab || !sender.tab.id) return;
    const fns = {
        'hunt-install': pbuMainHuntInstall,
        'hunt-census': pbuMainHuntCensus,
        'assign-any': pbuMainAssignAny
    };
    const fn = fns[msg.action];
    if (!fn) return;
    chrome.scripting.executeScript({
            target: { tabId: sender.tab.id },
            world: 'MAIN',
            func: fn,
            args: msg.action === 'assign-any' ? [msg.keys || []] : []
        })
        .then((res) => sendResponse({ ok: true, result: res && res[0] && res[0].result }))
        .catch((e) => sendResponse({ ok: false, error: String((e && e.message) || e) }));
    return true;
});

/* ================= v9.20 page-world interception (user's spec) =================
 * The user's diagnosis from the panel logs (2026-10-24): the page
 * has NO <input type="file"> beforehand ("inputs in dialog=[none]").
 * Only when the user clicks "Browse" does Angular create the input
 * dynamically in memory — document.createElement('input') then
 * .click() — or call window.showOpenFilePicker(). v9.19 stopped
 * pressing Browse, so no input was ever created. v9.20 implements
 * the user's prescribed fix, all in the page world (MAIN), with no
 * CDP channel involved:
 *   1. HTMLInputElement.prototype.click — when a file input is
 *      clicked, the native dialog is NEVER opened (the original
 *      click is not called); instead the prepared EPUB + cover are
 *      put into a new DataTransfer(), set as this.files, and
 *      `input` + `change` are dispatched {bubbles, composed}.
 *      A multiple input receives ALL not-yet-served staged files
 *      at once (the pre-v9.20 bridge served only ONE file per
 *      picker hit — a plausible cause of the v9.13 run uploading
 *      the EPUB but never the cover); a single-file input receives
 *      the next unserved one.
 *   2. Document.prototype.createElement — inputs created in memory
 *      are tracked (window.__pbuCreatedInputs); a type trap
 *      registers the element with the v9.17 hunter registry the
 *      moment its type becomes "file", so the census/assign routes
 *      can find even a never-inserted input.
 *   3. window.showOpenFilePicker — answered with custom
 *      FileSystemFileHandle objects (getFile: async () => staged
 *      file) for the staged files instead of the native picker;
 *      all of them when the caller allows multiple selection.
 *   4. pbuMainDrop — the drag & drop fallback now fires
 *      dragenter/dragover/drop on EVERY relevant element (the
 *      "Drag and drop" zone, its parent, its children,
 *      mat-dialog-content, the dialog) and force-binds the
 *      DataTransfer onto each event via Object.defineProperty,
 *      because some browsers reset it from the DragEvent init.
 * These functions are serialised into the page world by
 * chrome.scripting, exactly like the bridge functions they replace
 * (same names — the listeners call the latest declarations), so
 * each one is fully self-contained. */
function pbuMainStage(payload) {
    const files = {};
    for (const f of (payload && payload.files) || []) {
        try {
            const bin = atob(f.base64);
            const bytes = new Uint8Array(bin.length);
            for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
            files[f.key] = new File([bytes], f.name, { type: f.type || 'application/octet-stream' });
        } catch (e) { /* skip this file */ }
    }
    window.__pbuStaged = files;
    window.__pbuServed = window.__pbuServed || {};

    const acceptMatch = (file, acc) => {
        if (!acc) return true;
        const ext = '.' + String(file.name.split('.').pop() || '').toLowerCase();
        if (acc.includes(ext)) return true;
        if (/image/.test(acc) && /^image\//.test(file.type)) return true;
        if (/epub/.test(acc) && /epub/i.test(file.type + ' ' + file.name)) return true;
        if (/pdf/.test(acc) && /pdf/i.test(file.type + ' ' + file.name)) return true;
        return false;
    };
    // The serve set for one picker/input hit: not-yet-served staged
    // files matching the accept list (falling back to all matching
    // when everything was already served once).
    const serveKeys = (acceptStr) => {
        const staged = window.__pbuStaged || {};
        const keys = Object.keys(staged);
        if (!keys.length) return [];
        const acc = String(acceptStr || '').toLowerCase();
        let cands = keys.filter((k) => acceptMatch(staged[k], acc));
        if (!cands.length) cands = keys;
        const fresh = cands.filter((k) => !window.__pbuServed[k]);
        return fresh.length ? fresh : cands;
    };
    const serveInto = (input, keys) => {
        const staged = window.__pbuStaged || {};
        const dt = new DataTransfer();
        for (const k of keys) { dt.items.add(staged[k]); window.__pbuServed[k] = true; }
        input.files = dt.files;
        input.__pbuServed = true;
        input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
        input.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
        return keys.length;
    };
    const registerFileInput = (el, where) => {
        try {
            if (!el || el.__pbuRegged) return;
            const root = el.getRootNode && el.getRootNode();
            if (root && root.host && root.host.id === 'pbu-panel-host') return;
            if (el.closest && el.closest('#pbu-panel-host')) return;
            el.__pbuRegged = true;
            (window.__pbuInputReg = window.__pbuInputReg || []).push({ el: el, where: where, at: Date.now() });
        } catch (e) { /* ignore */ }
    };
    window.__pbuRegisterFileInput = registerFileInput;

    // (3) File System Access picker — custom handles, no native UI.
    window.showOpenFilePicker = async (opts) => {
        let acceptStr = '';
        try {
            const types = (opts && opts.types) || [];
            acceptStr = types.map((t) => Object.values(t.accept || {}).flat().join(',')).join(',');
        } catch (e) { /* ignore */ }
        let keys = serveKeys(acceptStr);
        if (!keys.length) throw new DOMException('The user aborted a request.', 'AbortError');
        if (!(opts && opts.multiple)) keys = keys.slice(0, 1);
        const staged = window.__pbuStaged || {};
        return keys.map((k) => {
            window.__pbuServed[k] = true;
            const f = staged[k];
            return {
                kind: 'file', name: f.name,
                getFile: async () => f,
                queryPermission: async () => 'granted',
                requestPermission: async () => 'granted',
                isSameEntry: async () => false
            };
        });
    };
    window.__pbuPickerArmed = true;

    // (1) File-input click interception. The previous click
    // implementation is captured BEFORE overwriting (on a fresh
    // page it is the native one; the handler below only ever falls
    // back to it for non-file inputs or when nothing is staged).
    const proto = window.HTMLInputElement && window.HTMLInputElement.prototype;
    if (proto && !proto.__pbuPatched920) {
        const origClick920 = proto.click;
        proto.click = function () {
            try {
                if (this && this.__pbuServed) return;
                if (this && this.type === 'file' && window.__pbuStaged) {
                    registerFileInput(this, 'input-click');
                    let keys = serveKeys(this.getAttribute && this.getAttribute('accept'));
                    if (!this.multiple) keys = keys.slice(0, 1);
                    if (keys.length) { serveInto(this, keys); return; }
                }
            } catch (e) { /* fall through to the original click */ }
            return origClick920.apply(this, arguments);
        };
        proto.__pbuPatched920 = true;
    }
    // Capture-phase listener: activations that reach a file input as
    // an EVENT (label clicks, dispatchEvent) rather than a .click()
    // method call get the same treatment, and the native picker is
    // suppressed via preventDefault + stopImmediatePropagation.
    if (!window.__pbuClickArmed920) {
        window.__pbuClickArmed920 = true;
        window.__pbuClickArmed = true;
        document.addEventListener('click', (e) => {
            try {
                const t = e.target;
                if (t && t.tagName === 'INPUT' && t.type === 'file' && !t.__pbuServed && window.__pbuStaged) {
                    let keys = serveKeys(t.getAttribute && t.getAttribute('accept'));
                    if (!t.multiple) keys = keys.slice(0, 1);
                    if (keys.length) {
                        e.preventDefault();
                        e.stopImmediatePropagation();
                        registerFileInput(t, 'input-click-event');
                        setTimeout(() => { try { serveInto(t, keys); } catch (err) {} }, 0);
                    }
                }
            } catch (err) { /* never break the page */ }
        }, true);
    }

    // (2) createElement tracking — inputs born in memory.
    const docProto = window.Document && window.Document.prototype;
    if (docProto && !docProto.__pbuCreatePatched920) {
        const origCreate = docProto.createElement;
        docProto.createElement = function (tag) {
            const el = origCreate.apply(this, arguments);
            try {
                if (el && String(tag).toLowerCase() === 'input') {
                    (window.__pbuCreatedInputs = window.__pbuCreatedInputs || []).push(el);
                    const typeDesc = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'type');
                    if (typeDesc && typeDesc.set && !el.__pbuTypeTrapped) {
                        el.__pbuTypeTrapped = true;
                        Object.defineProperty(el, 'type', {
                            configurable: true, enumerable: true,
                            get() { return typeDesc.get.call(this); },
                            set(v) {
                                typeDesc.set.call(this, v);
                                if (String(v).toLowerCase() === 'file') registerFileInput(this, 'created-input');
                            }
                        });
                    }
                    if (el.type === 'file') registerFileInput(el, 'created-input');
                }
            } catch (e) { /* never break the page */ }
            return el;
        };
        docProto.__pbuCreatePatched920 = true;
    }
    window.__pbuCreateArmed = true;
    window.__pbuArmed = true;
    return Object.keys(files);
}

function pbuMainPing() {
    return {
        armed: !!window.__pbuArmed,
        clickArmed: !!window.__pbuClickArmed920,
        createArmed: !!window.__pbuCreateArmed,
        pickerArmed: !!window.__pbuPickerArmed,
        staged: Object.keys(window.__pbuStaged || {})
    };
}

/* ================= v9.20 improved drag & drop (page world) =================
 * dragenter/dragover/drop are fired on every element the console's
 * uploader might listen on — the "Drag and drop" zone, its parent,
 * its children, mat-dialog-content and the dialog itself — and the
 * DataTransfer is force-bound onto each event with
 * Object.defineProperty, since some browsers reset it from the
 * DragEvent constructor's init dict. */
function pbuMainDrop(key) {
    const staged = window.__pbuStaged || {};
    const f = staged[key] || Object.values(staged)[0];
    if (!f) return 'no-staged-file';
    const clean = (s) => String(s || '').replace(/\s+/g, ' ');
    const dlg = [...document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container')]
        .find((d) => /upload content and cover|drag and drop/i.test(clean(d.innerText || d.textContent)));
    if (!dlg) return 'no-dialog';
    const content = dlg.querySelector('mat-dialog-content') || dlg;
    const zone = [...dlg.querySelectorAll('*')]
        .find((e) => /drag and drop/i.test(clean(e.innerText || e.textContent)) && e.querySelectorAll('*').length < 12) || content;
    const targets = [];
    const add = (el) => { if (el && !targets.includes(el)) targets.push(el); };
    add(zone);
    if (zone) {
        add(zone.parentElement);
        for (const ch of zone.children || []) add(ch);
    }
    add(content);
    add(dlg);
    const dt = new DataTransfer();
    dt.items.add(f);
    const fire = (el, type) => {
        let ev;
        try { ev = new DragEvent(type, { bubbles: true, cancelable: true, composed: true, dataTransfer: dt }); }
        catch (e) { ev = new Event(type, { bubbles: true, cancelable: true, composed: true }); }
        try { Object.defineProperty(ev, 'dataTransfer', { value: dt }); } catch (e) { /* keep the ctor value */ }
        el.dispatchEvent(ev);
    };
    for (const type of ['dragenter', 'dragover', 'drop']) {
        for (const t of targets) fire(t, type);
    }
    return 'dropped:' + f.name + ' onto ' + targets.length + ' element(s)';
}
/* ================= v9.21 early-interception cooperation (page world) =================
 * The user's correction (2026-10-24): the console creates its hidden
 * <input type="file"> in memory at PAGE LOAD and only calls .click()
 * on it when "Browse" is pressed — so hooks installed at Run time
 * can arrive too late, and Browse must never be skipped. v9.21
 * therefore installs the hooks at document_start in the MAIN world
 * (manifest entry for early-intercept.js, world: "MAIN",
 * run_at: "document_start"), BEFORE Angular loads.
 *
 * This block rewrites what pbuMainStage does at Run time:
 *  - It ALWAYS (re)stages the job's EPUB + cover into
 *    window.__pbuStaged and preserves window.__pbuInterceptHits.
 *  - If the early hooks are armed (window.__pbuEarlyInterceptArmed),
 *    it does NOT re-patch HTMLInputElement.prototype.click /
 *    showPicker / showOpenFilePicker / createElement: the early
 *    patches already captured the true originals at page load, and
 *    a second patch would capture the early patch as "original"
 *    and could double-serve. It only adds the capture-phase click
 *    listener (for label/event activations, which the early script
 *    does not cover), guarded so it is added once.
 *  - If the early hooks are NOT armed (e.g. a browser that ignores
 *    the manifest MAIN-world entry), it installs the full fallback
 *    patches — click + showPicker + showOpenFilePicker +
 *    createElement tracking — with the same serve-set semantics
 *    and the same intercept-hit recording, so the run still works.
 *  - pbuMainPing now also reports earlyArmed, the served keys, and
 *    the intercept hits, so the content script can log, after a
 *    Browse press, whether the interceptor actually fired.
 * All functions here are self-contained (serialised into the page
 * world by chrome.scripting, like the ones they replace). No CDP
 * channel is involved anywhere. */
function pbuMainStage(payload) {
    const files = {};
    for (const f of (payload && payload.files) || []) {
        try {
            const bin = atob(f.base64);
            const bytes = new Uint8Array(bin.length);
            for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
            files[f.key] = new File([bytes], f.name, { type: f.type || 'application/octet-stream' });
        } catch (e) { /* skip this file */ }
    }
    window.__pbuStaged = files;
    window.__pbuServed = window.__pbuServed || {};
    window.__pbuInterceptHits = window.__pbuInterceptHits || [];

    const acceptMatch = (file, acc) => {
        if (!acc) return true;
        const ext = '.' + String(file.name.split('.').pop() || '').toLowerCase();
        if (acc.includes(ext)) return true;
        if (/image/.test(acc) && /^image\//.test(file.type)) return true;
        if (/epub/.test(acc) && /epub/i.test(file.type + ' ' + file.name)) return true;
        if (/pdf/.test(acc) && /pdf/i.test(file.type + ' ' + file.name)) return true;
        return false;
    };
    const serveKeys = (acceptStr) => {
        const staged = window.__pbuStaged || {};
        const keys = Object.keys(staged);
        if (!keys.length) return [];
        const acc = String(acceptStr || '').toLowerCase();
        let cands = keys.filter((k) => acceptMatch(staged[k], acc));
        if (!cands.length) cands = keys;
        const fresh = cands.filter((k) => !window.__pbuServed[k]);
        return fresh.length ? fresh : cands;
    };
    const recordHit = (via, keys, extra) => {
        const staged = window.__pbuStaged || {};
        const hit = { at: Date.now(), via: via, keys: keys.slice(), names: keys.map((k) => staged[k] && staged[k].name) };
        if (extra) Object.assign(hit, extra);
        window.__pbuInterceptHits.push(hit);
    };
    const alreadyHolds = (input, keys) => {
        try {
            if (!input.files || !input.files.length) return false;
            const have = {};
            for (let i = 0; i < input.files.length; i++) have[input.files[i].name] = true;
            const staged = window.__pbuStaged || {};
            return keys.every((k) => staged[k] && have[staged[k].name]);
        } catch (e) { return false; }
    };
    const serveInto = (input, keys) => {
        const staged = window.__pbuStaged || {};
        const dt = new DataTransfer();
        for (const k of keys) { dt.items.add(staged[k]); window.__pbuServed[k] = true; }
        input.files = dt.files;
        input.__pbuServed = true;
        input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
        input.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
        return keys.length;
    };
    const inPanel = (el) => {
        try {
            const root = el.getRootNode && el.getRootNode();
            if (root && root.host && root.host.id === 'pbu-panel-host') return true;
            if (el.closest && el.closest('#pbu-panel-host')) return true;
        } catch (e) { /* ignore */ }
        return false;
    };
    const tryServe = (input, via) => {
        try {
            if (!input || input.type !== 'file' || inPanel(input)) return false;
            if (!Object.keys(window.__pbuStaged || {}).length) return false;
            let keys = serveKeys(input.getAttribute && input.getAttribute('accept'));
            if (!input.multiple) keys = keys.slice(0, 1);
            if (!keys.length) return false;
            if (alreadyHolds(input, keys)) { recordHit(via, keys, { alreadyHeld: true }); return true; }
            serveInto(input, keys);
            recordHit(via, keys, { detached: !input.isConnected });
            return true;
        } catch (e) { return false; }
    };
    window.__pbuTryServe921 = tryServe;

    const earlyArmed = !!window.__pbuEarlyInterceptArmed;
    // Capture-phase listener (label/event activations). Added in
    // BOTH modes — the early script has no such listener — once.
    if (!window.__pbuClickArmed921) {
        window.__pbuClickArmed921 = true;
        window.__pbuClickArmed = true;
        document.addEventListener('click', (e) => {
            try {
                const t = e.target;
                if (t && t.tagName === 'INPUT' && t.type === 'file' && window.__pbuStaged && Object.keys(window.__pbuStaged).length) {
                    let keys = serveKeys(t.getAttribute && t.getAttribute('accept'));
                    if (!t.multiple) keys = keys.slice(0, 1);
                    if (keys.length && !alreadyHolds(t, keys)) {
                        e.preventDefault();
                        e.stopImmediatePropagation();
                        setTimeout(() => { try { if (!alreadyHolds(t, keys)) { serveInto(t, keys); recordHit('click-event', keys, {}); } } catch (err) {} }, 0);
                    } else if (keys.length && alreadyHolds(t, keys)) {
                        e.preventDefault();
                        e.stopImmediatePropagation();
                    }
                }
            } catch (err) { /* never break the page */ }
        }, true);
    }

    if (!earlyArmed) {
        // Fallback patches (only when the document_start hooks did
        // not load). Each one records intercept hits like the early
        // script, and never opens the native picker while staged
        // files exist.
        const proto = window.HTMLInputElement && window.HTMLInputElement.prototype;
        if (proto && !proto.__pbuEarlyClickPatched && !proto.__pbuFallbackClick921) {
            const origClick = proto.click;
            proto.click = function () {
                try { if (tryServe(this, 'click')) return; } catch (e) { /* fall through */ }
                return origClick.apply(this, arguments);
            };
            proto.__pbuFallbackClick921 = true;
        }
        if (proto && !proto.__pbuEarlyShowPickerPatched && !proto.__pbuFallbackPicker921) {
            const origShowPicker = proto.showPicker;
            proto.showPicker = function () {
                try { if (tryServe(this, 'showPicker')) return undefined; } catch (e) { /* fall through */ }
                if (origShowPicker) return origShowPicker.apply(this, arguments);
                return undefined;
            };
            proto.__pbuFallbackPicker921 = true;
        }
        if (!window.__pbuEarlyFsaPatched && !window.__pbuFallbackFsa921) {
            const origFsa = window.showOpenFilePicker;
            window.showOpenFilePicker = async (opts) => {
                const staged = window.__pbuStaged || {};
                if (Object.keys(staged).length) {
                    let acceptStr = '';
                    try {
                        const types = (opts && opts.types) || [];
                        acceptStr = types.map((t) => Object.values(t.accept || {}).flat().join(',')).join(',');
                    } catch (e) { /* ignore */ }
                    let keys = serveKeys(acceptStr);
                    if (!keys.length) keys = Object.keys(staged);
                    if (!(opts && opts.multiple)) keys = keys.slice(0, 1);
                    const out = keys.map((k) => {
                        window.__pbuServed[k] = true;
                        const f = staged[k];
                        return {
                            kind: 'file', name: f.name,
                            getFile: async () => f,
                            queryPermission: async () => 'granted',
                            requestPermission: async () => 'granted',
                            isSameEntry: async () => false
                        };
                    });
                    recordHit('picker', keys, { multiple: !!(opts && opts.multiple) });
                    return out;
                }
                if (origFsa) return origFsa.apply(this, arguments);
                throw new DOMException('The user aborted a request.', 'AbortError');
            };
            window.__pbuFallbackFsa921 = true;
        }
        window.__pbuPickerArmed = true;
        const docProto = window.Document && window.Document.prototype;
        if (docProto && !docProto.__pbuEarlyCreatePatched && !docProto.__pbuCreatePatched920 && !docProto.__pbuCreatePatched921) {
            const origCreate = docProto.createElement;
            docProto.createElement = function (tag) {
                const el = origCreate.apply(this, arguments);
                try {
                    if (el && String(tag).toLowerCase() === 'input') {
                        (window.__pbuCreatedInputs = window.__pbuCreatedInputs || []).push(el);
                        const typeDesc = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'type');
                        if (typeDesc && typeDesc.set && !el.__pbuTypeTrapped) {
                            el.__pbuTypeTrapped = true;
                            Object.defineProperty(el, 'type', {
                                configurable: true, enumerable: true,
                                get() { return typeDesc.get.call(this); },
                                set(v) {
                                    typeDesc.set.call(this, v);
                                    if (String(v).toLowerCase() === 'file' && !inPanel(this) && !this.__pbuRegged) {
                                        this.__pbuRegged = true;
                                        (window.__pbuInputReg = window.__pbuInputReg || []).push({ el: this, where: 'created-input', at: Date.now() });
                                    }
                                }
                            });
                        }
                        if (el.type === 'file' && !inPanel(el) && !el.__pbuRegged) {
                            el.__pbuRegged = true;
                            (window.__pbuInputReg = window.__pbuInputReg || []).push({ el: el, where: 'created-input', at: Date.now() });
                        }
                    }
                } catch (e) { /* never break the page */ }
                return el;
            };
            docProto.__pbuCreatePatched921 = true;
        }
        window.__pbuCreateArmed = true;
    }
    window.__pbuArmed = true;
    window.__pbuStageEarlyArmed921 = earlyArmed;
    return Object.keys(files);
}

function pbuMainPing() {
    const proto = window.HTMLInputElement && window.HTMLInputElement.prototype;
    const hits = window.__pbuInterceptHits || [];
    return {
        armed: !!window.__pbuArmed,
        earlyArmed: !!window.__pbuEarlyInterceptArmed,
        clickArmed: !!(proto && (proto.__pbuEarlyClickPatched || proto.__pbuPatched920 || proto.__pbuFallbackClick921)),
        createArmed: !!window.__pbuCreateArmed,
        pickerArmed: !!window.__pbuPickerArmed,
        staged: Object.keys(window.__pbuStaged || {}),
        served: Object.keys(window.__pbuServed || {}),
        interceptCount: hits.length,
        interceptHits: hits.slice(-20)
    };
}
/* ================= v9.22 isTrusted bypass + all-routes drivers =================
 * Live evidence from the v9.21 run: a programmatic Browse click
 * recorded ZERO input-click intercept hits, and a dispatched
 * DragEvent on the dropzone registered nothing — the console
 * ignores untrusted events (isTrusted check) or never receives
 * them through the simulated path. v9.22 therefore (user's
 * 5-point order):
 *  1. document_start MAIN hooks (early-intercept.js, all_frames)
 *     wrap addEventListener so every watched listener receives a
 *     Proxy event whose isTrusted always reads true, and the
 *     callbacks are saved as el.__capturedListeners.
 *  2. pbuMainDirectDrop (below): a fully spoofed dataTransfer
 *     (real FileList files, array-like items with getAsFile(),
 *     types ['Files'], getData/setData, dropEffect 'copy',
 *     effectAllowed 'all'), dispatched as dragenter/dragover/drop
 *     on the dialog elements, PLUS direct invocation of captured
 *     drop callbacks — but ONLY those the dispatch did not
 *     already invoke (invocation counts prove it), so a working
 *     dispatch is never double-fired into a duplicate upload.
 *  3. pbuMainAssignCreated: every input in
 *     window.__allCreatedInputs (createElement/createElementNS,
 *     DOM or detached) that is a file input gets the staged
 *     files set directly + input/change dispatched, even if
 *     .click() was never called on it; captured change callbacks
 *     the dispatch missed are then called directly.
 *  4. pbuMainNgInject: scans the dialog's ng-component/dropzone
 *     for __ngContext__ and methods named onFileSelected /
 *     onDrop / handleFiles / uploadFiles (etc.) and calls the
 *     best match with the staged FileList (array fallback).
 *  5. pbuMainDiag: reports (a) created-input counts, (b)
 *     captured click/drop listener counts on dialog elements,
 *     (c) Angular methods found — all printed by the content
 *     script in the panel log.
 * pbuMainStage v922: stages files into the top frame AND every
 * same-origin frame (all_frames hooks need staged files in their
 * own window), preserves hits, never re-patches over armed early
 * hooks, and installs the full fallback hook set (listener wrap,
 * dispatch hook, create tracking) only when the early hooks are
 * absent. New background listener 5 routes the actions
 * ensure-early / diag / direct-drop / assign-created / ng-inject.
 * All driver functions are self-contained (serialised into the
 * page world by chrome.scripting). No CDP channel anywhere. */
function pbuMainStage(payload) {
    const files = {};
    for (const f of (payload && payload.files) || []) {
        try {
            const bin = atob(f.base64);
            const bytes = new Uint8Array(bin.length);
            for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
            files[f.key] = new File([bytes], f.name, { type: f.type || 'application/octet-stream' });
        } catch (e) { /* skip this file */ }
    }
    window.__pbuStaged = files;
    window.__pbuServed = window.__pbuServed || {};
    window.__pbuInterceptHits = window.__pbuInterceptHits || [];
    window.__allCreatedInputs = window.__allCreatedInputs || [];
    // Same-origin frames run their own document_start hooks; give
    // them the staged files too, or an iframe uploader's hooks
    // would see an empty staged set and fall through.
    try {
        for (let i = 0; i < window.frames.length; i++) {
            try {
                const fw = window.frames[i];
                if (fw && fw !== window) {
                    fw.__pbuStaged = files;
                    fw.__pbuServed = fw.__pbuServed || {};
                    fw.__pbuInterceptHits = fw.__pbuInterceptHits || [];
                    fw.__allCreatedInputs = fw.__allCreatedInputs || [];
                }
            } catch (e) { /* cross-origin frame: skip */ }
        }
    } catch (e) { /* ignore */ }

    const acceptMatch = (file, acc) => {
        if (!acc) return true;
        const ext = '.' + String(file.name.split('.').pop() || '').toLowerCase();
        if (acc.includes(ext)) return true;
        if (/image/.test(acc) && /^image\//.test(file.type)) return true;
        if (/epub/.test(acc) && /epub/i.test(file.type + ' ' + file.name)) return true;
        if (/pdf/.test(acc) && /pdf/i.test(file.type + ' ' + file.name)) return true;
        return false;
    };
    const serveKeys = (acceptStr) => {
        const staged = window.__pbuStaged || {};
        const keys = Object.keys(staged);
        if (!keys.length) return [];
        const acc = String(acceptStr || '').toLowerCase();
        let cands = keys.filter((k) => acceptMatch(staged[k], acc));
        if (!cands.length) cands = keys;
        const fresh = cands.filter((k) => !window.__pbuServed[k]);
        return fresh.length ? fresh : cands;
    };
    const recordHit = (via, keys, extra) => {
        const staged = window.__pbuStaged || {};
        const hit = { at: Date.now(), via: via, keys: keys.slice(), names: keys.map((k) => staged[k] && staged[k].name) };
        if (extra) Object.assign(hit, extra);
        window.__pbuInterceptHits.push(hit);
    };
    const alreadyHolds = (input, keys) => {
        try {
            if (!input.files || !input.files.length) return false;
            const have = {};
            for (let i = 0; i < input.files.length; i++) have[input.files[i].name] = true;
            const staged = window.__pbuStaged || {};
            return keys.every((k) => staged[k] && have[staged[k].name]);
        } catch (e) { return false; }
    };
    const serveInto = (input, keys) => {
        const staged = window.__pbuStaged || {};
        const dt = new DataTransfer();
        for (const k of keys) { dt.items.add(staged[k]); window.__pbuServed[k] = true; }
        input.files = dt.files;
        input.__pbuServed = true;
        input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
        input.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
        return keys.length;
    };
    const inPanel = (el) => {
        try {
            const root = el.getRootNode && el.getRootNode();
            if (root && root.host && root.host.id === 'pbu-panel-host') return true;
            if (el.closest && el.closest('#pbu-panel-host')) return true;
        } catch (e) { /* ignore */ }
        return false;
    };
    const tryServe = (input, via) => {
        try {
            if (!input || input.type !== 'file' || inPanel(input)) return false;
            if (!Object.keys(window.__pbuStaged || {}).length) return false;
            let keys = serveKeys(input.getAttribute && input.getAttribute('accept'));
            if (!input.multiple) keys = keys.slice(0, 1);
            if (!keys.length) return false;
            if (alreadyHolds(input, keys)) { recordHit(via, keys, { alreadyHeld: true }); return true; }
            serveInto(input, keys);
            recordHit(via, keys, { detached: !input.isConnected });
            return true;
        } catch (e) { return false; }
    };
    window.__pbuTryServe921 = tryServe;

    const earlyArmed = !!window.__pbuEarlyInterceptArmed;
    if (!window.__pbuClickArmed921) {
        window.__pbuClickArmed921 = true;
        window.__pbuClickArmed = true;
        document.addEventListener('click', (e) => {
            try {
                const t = e.target;
                if (t && t.tagName === 'INPUT' && t.type === 'file' && window.__pbuStaged && Object.keys(window.__pbuStaged).length) {
                    let keys = serveKeys(t.getAttribute && t.getAttribute('accept'));
                    if (!t.multiple) keys = keys.slice(0, 1);
                    if (keys.length && !alreadyHolds(t, keys)) {
                        e.preventDefault();
                        e.stopImmediatePropagation();
                        setTimeout(() => { try { if (!alreadyHolds(t, keys)) { serveInto(t, keys); recordHit('click-event', keys, {}); } } catch (err) {} }, 0);
                    } else if (keys.length && alreadyHolds(t, keys)) {
                        e.preventDefault();
                        e.stopImmediatePropagation();
                    }
                }
            } catch (err) { /* never break the page */ }
        }, true);
    }

    if (!earlyArmed) {
        // Fallback hook set (only when document_start hooks did not
        // load): listener wrap + dispatch hook + create tracking,
        // mirroring early-intercept.js. The early hooks, when
        // present, already captured the true originals at page
        // load and must not be re-patched over.
        const registerFileInput = (el, where) => {
            try {
                if (!el || el.__pbuRegged || inPanel(el)) return;
                el.__pbuRegged = true;
                (window.__pbuInputReg = window.__pbuInputReg || []).push({ el: el, where: where, at: Date.now() });
            } catch (e) { /* ignore */ }
        };
        const createdSeen = new WeakSet();
        const trackCreated = (el, where) => {
            try {
                if (!el || createdSeen.has(el)) return;
                createdSeen.add(el);
                window.__allCreatedInputs.push({ el: el, at: Date.now(), where: where });
                const typeDesc = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'type');
                if (typeDesc && typeDesc.set && !el.__pbuTypeTrapped) {
                    el.__pbuTypeTrapped = true;
                    Object.defineProperty(el, 'type', {
                        configurable: true, enumerable: true,
                        get() { return typeDesc.get.call(this); },
                        set(v) {
                            typeDesc.set.call(this, v);
                            if (String(v).toLowerCase() === 'file') registerFileInput(this, 'created-input');
                        }
                    });
                }
                if (el.type === 'file') registerFileInput(el, 'created-input');
            } catch (e) { /* ignore */ }
        };
        const etProto = window.EventTarget && window.EventTarget.prototype;
        if (etProto && !etProto.__pbuListenerWrapped922) {
            const proxied = new WeakSet();
            const proxyEvent = (ev) => {
                try {
                    if (!ev || typeof ev !== 'object' || proxied.has(ev)) return ev;
                    const proxy = new Proxy(ev, {
                        get(target, prop) {
                            if (prop === 'isTrusted') return true;
                            const v = Reflect.get(target, prop, target);
                            return (typeof v === 'function') ? v.bind(target) : v;
                        },
                        set(target, prop, value) { return Reflect.set(target, prop, value); }
                    });
                    proxied.add(proxy);
                    return proxy;
                } catch (e) { return ev; }
            };
            const WATCHED = ['click', 'mousedown', 'pointerdown', 'drop', 'dragover', 'dragenter', 'change'];
            const origAdd = etProto.addEventListener;
            const origRemove = etProto.removeEventListener;
            etProto.addEventListener = function (type, listener, options) {
                try {
                    if (WATCHED.indexOf(type) >= 0 && listener) {
                        const cap = (typeof options === 'boolean') ? options : !!(options && options.capture);
                        const records = this.__pbuListenerRecords = this.__pbuListenerRecords || [];
                        for (const r of records) { if (r.type === type && r.orig === listener && r.capture === cap) return; }
                        const el = this;
                        const record = { type: type, orig: listener, capture: cap, calls: 0, lastInvokedAt: 0 };
                        const wrapped = function (ev) {
                            try {
                                el.__pbuCalls = el.__pbuCalls || {};
                                el.__pbuCalls[type] = (el.__pbuCalls[type] || 0) + 1;
                                record.calls++;
                                record.lastInvokedAt = Date.now();
                            } catch (e) { /* ignore */ }
                            const prox = proxyEvent(ev);
                            if (listener && typeof listener.handleEvent === 'function') return listener.handleEvent.call(listener, prox);
                            return listener.call(el, prox);
                        };
                        record.wrapped = wrapped;
                        records.push(record);
                        const capList = this.__capturedListeners = this.__capturedListeners || {};
                        (capList[type] = capList[type] || []).push(record);
                        return origAdd.call(this, type, wrapped, options);
                    }
                } catch (e) { /* fall through */ }
                return origAdd.apply(this, arguments);
            };
            etProto.removeEventListener = function (type, listener, options) {
                try {
                    if (WATCHED.indexOf(type) >= 0 && listener) {
                        const cap = (typeof options === 'boolean') ? options : !!(options && options.capture);
                        const records = this.__pbuListenerRecords || [];
                        for (let i = records.length - 1; i >= 0; i--) {
                            if (records[i].type === type && records[i].orig === listener && records[i].capture === cap) {
                                const rec = records[i];
                                records.splice(i, 1);
                                const list = (this.__capturedListeners || {})[type] || [];
                                for (let j = list.length - 1; j >= 0; j--) { if (list[j] === rec) list.splice(j, 1); }
                                return origRemove.call(this, type, rec.wrapped, options);
                            }
                        }
                    }
                } catch (e) { /* fall through */ }
                return origRemove.apply(this, arguments);
            };
            etProto.__pbuListenerWrapped922 = true;
        }
        if (etProto && !etProto.__pbuDispatchHooked922) {
            const origDispatch = etProto.dispatchEvent;
            etProto.dispatchEvent = function (ev) {
                try {
                    if (ev && ev.type === 'click' && this && this.tagName === 'INPUT' && this.type === 'file') {
                        if (tryServe(this, 'dispatch-click')) return true;
                    }
                } catch (e) { /* fall through */ }
                return origDispatch.call(this, ev);
            };
            etProto.__pbuDispatchHooked922 = true;
        }
        const proto = window.HTMLInputElement && window.HTMLInputElement.prototype;
        if (proto && !proto.__pbuEarlyClickPatched && !proto.__pbuFallbackClick921) {
            const origClick = proto.click;
            proto.click = function () {
                try { if (tryServe(this, 'click')) return; } catch (e) { /* fall through */ }
                return origClick.apply(this, arguments);
            };
            proto.__pbuFallbackClick921 = true;
        }
        if (proto && !proto.__pbuEarlyShowPickerPatched && !proto.__pbuFallbackPicker921) {
            const origShowPicker = proto.showPicker;
            proto.showPicker = function () {
                try { if (tryServe(this, 'showPicker')) return undefined; } catch (e) { /* fall through */ }
                if (origShowPicker) return origShowPicker.apply(this, arguments);
                return undefined;
            };
            proto.__pbuFallbackPicker921 = true;
        }
        if (!window.__pbuEarlyFsaPatched && !window.__pbuFallbackFsa921) {
            const origFsa = window.showOpenFilePicker;
            window.showOpenFilePicker = async (opts) => {
                const staged = window.__pbuStaged || {};
                if (Object.keys(staged).length) {
                    let acceptStr = '';
                    try {
                        const types = (opts && opts.types) || [];
                        acceptStr = types.map((t) => Object.values(t.accept || {}).flat().join(',')).join(',');
                    } catch (e) { /* ignore */ }
                    let keys = serveKeys(acceptStr);
                    if (!keys.length) keys = Object.keys(staged);
                    if (!(opts && opts.multiple)) keys = keys.slice(0, 1);
                    const out = keys.map((k) => {
                        window.__pbuServed[k] = true;
                        const f = staged[k];
                        return {
                            kind: 'file', name: f.name,
                            getFile: async () => f,
                            queryPermission: async () => 'granted',
                            requestPermission: async () => 'granted',
                            isSameEntry: async () => false
                        };
                    });
                    recordHit('picker', keys, { multiple: !!(opts && opts.multiple) });
                    return out;
                }
                if (origFsa) return origFsa.apply(this, arguments);
                throw new DOMException('The user aborted a request.', 'AbortError');
            };
            window.__pbuFallbackFsa921 = true;
        }
        window.__pbuPickerArmed = true;
        const docProto = window.Document && window.Document.prototype;
        if (docProto && !docProto.__pbuEarlyCreatePatched922 && !docProto.__pbuCreatePatched920 && !docProto.__pbuCreatePatched921) {
            const origCreate = docProto.createElement;
            docProto.createElement = function (tag) {
                const el = origCreate.apply(this, arguments);
                try { if (el && String(tag).toLowerCase() === 'input') trackCreated(el, 'createElement'); } catch (e) { /* ignore */ }
                return el;
            };
            const origCreateNS = docProto.createElementNS;
            if (origCreateNS) {
                docProto.createElementNS = function (ns, name) {
                    const el = origCreateNS.apply(this, arguments);
                    try { if (el && String(name).toLowerCase() === 'input') trackCreated(el, 'createElementNS'); } catch (e) { /* ignore */ }
                    return el;
                };
            }
            docProto.__pbuCreatePatched921 = true;
        }
        if (!window.__pbuSweepStarted922) {
            window.__pbuSweepStarted922 = true;
            setInterval(function () {
                try {
                    const list = window.__allCreatedInputs || [];
                    for (const entry of list) {
                        const el = entry && entry.el;
                        if (el && el.type === 'file') registerFileInput(el, 'sweep');
                    }
                } catch (e) { /* ignore */ }
            }, 2000);
        }
        window.__pbuCreateArmed = true;
    }
    window.__pbuArmed = true;
    window.__pbuStageEarlyArmed921 = earlyArmed;
    return Object.keys(files);
}

function pbuMainPing() {
    const proto = window.HTMLInputElement && window.HTMLInputElement.prototype;
    const hits = window.__pbuInterceptHits || [];
    const created = window.__allCreatedInputs || [];
    return {
        armed: !!window.__pbuArmed,
        earlyArmed: !!window.__pbuEarlyInterceptArmed,
        clickArmed: !!(proto && (proto.__pbuEarlyClickPatched || proto.__pbuPatched920 || proto.__pbuFallbackClick921)),
        createArmed: !!window.__pbuCreateArmed,
        pickerArmed: !!window.__pbuPickerArmed,
        staged: Object.keys(window.__pbuStaged || {}),
        served: Object.keys(window.__pbuServed || {}),
        interceptCount: hits.length,
        interceptHits: hits.slice(-20),
        createdTotal: created.length,
        createdFile: created.filter((e) => e && e.el && e.el.type === 'file').length
    };
}

/* Shared driver helpers (each driver below is self-contained). */
function pbuMainFindDialog() {
    const clean = (s) => String(s || '').replace(/\s+/g, ' ');
    return [...document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container')]
        .find((d) => /upload content and cover|drag and drop/i.test(clean(d.innerText || d.textContent))) || null;
}
function pbuMainStagedFiles() {
    const staged = window.__pbuStaged || {};
    const keys = Object.keys(staged);
    if (!keys.length) return null;
    const dt = new DataTransfer();
    for (const k of keys) dt.items.add(staged[k]);
    return { keys: keys, files: dt.files, list: keys.map((k) => staged[k]) };
}

function pbuMainDiag() {
    const dlg = pbuMainFindDialog();
    const createdRaw = window.__allCreatedInputs || [];
    const created = createdRaw.map((entry) => {
        const el = entry && entry.el;
        if (!el) return null;
        let inDialog = false;
        try { inDialog = !!(dlg && el.isConnected && dlg.contains(el)); } catch (e) { /* ignore */ }
        return {
            where: entry.where || '', type: el.type || '', name: el.name || '',
            accept: (el.getAttribute && el.getAttribute('accept')) || '',
            multiple: !!el.multiple, connected: !!el.isConnected, inDialog: inDialog
        };
    }).filter(Boolean);
    let capClick = 0, capDrop = 0, capChange = 0, capElements = 0;
    if (dlg) {
        const els = [dlg, ...dlg.querySelectorAll('*')];
        for (const el of els) {
            const cap = el.__capturedListeners;
            if (!cap) continue;
            capElements++;
            capClick += (cap.click || []).length;
            capDrop += (cap.drop || []).length;
            capChange += (cap.change || []).length;
        }
    }
    const ng = pbuMainNgScan(dlg);
    return {
        dialogOpen: !!dlg,
        createdTotal: created.length,
        createdFile: created.filter((c) => c.type === 'file').length,
        created: created,
        captured: { click: capClick, drop: capDrop, change: capChange, elements: capElements },
        ng: ng
    };
}

function pbuMainNgScan(dlg) {
    const TARGETS = ['onFileSelected', 'onFilesSelected', 'onDrop', 'handleFiles', 'handleDrop', 'uploadFiles', 'onFileChange', 'onFilesChange'];
    const methods = [];
    if (!dlg) return { scanned: 0, methods: methods };
    const cands = [];
    const pushCand = (el, source) => { if (el) cands.push({ el: el, source: source }); };
    pushCand(dlg, 'dialog');
    for (const el of dlg.querySelectorAll('ng-component, [xapuploaderdropzone]')) pushCand(el, el.tagName.toLowerCase());
    const seen = [];
    const scanObj = (obj, tag, source) => {
        if (!obj || (typeof obj !== 'object' && typeof obj !== 'function')) return;
        if (seen.indexOf(obj) >= 0) return;
        seen.push(obj);
        for (const name of TARGETS) {
            try {
                if (typeof obj[name] === 'function') methods.push({ tag: tag, name: name, source: source });
            } catch (e) { /* ignore */ }
        }
        try {
            if (obj.fileInput && obj.fileInput.tagName === 'INPUT') methods.push({ tag: tag, name: 'fileInput', source: source });
        } catch (e) { /* ignore */ }
    };
    let scanned = 0;
    for (const cand of cands) {
        scanned++;
        const el = cand.el;
        const tag = (el.tagName || 'element').toLowerCase();
        scanObj(el, tag, cand.source + ':host');
        try {
            const ctx = el.__ngContext__;
            if (Array.isArray(ctx)) {
                for (const item of ctx) scanObj(item, tag, cand.source + ':__ngContext__');
            } else if (ctx && typeof ctx === 'object') {
                scanObj(ctx, tag, cand.source + ':__ngContext__');
            }
        } catch (e) { /* ignore */ }
    }
    return { scanned: scanned, methods: methods };
}

function pbuMainDirectDrop() {
    const dlg = pbuMainFindDialog();
    if (!dlg) return 'no-dialog';
    const staged = pbuMainStagedFiles();
    if (!staged) return 'no-staged-file';
    const clean = (s) => String(s || '').replace(/\s+/g, ' ');
    const content = dlg.querySelector('mat-dialog-content') || dlg;
    const zone = [...dlg.querySelectorAll('*')]
        .find((e) => /drag and drop/i.test(clean(e.innerText || e.textContent)) && e.querySelectorAll('*').length < 12) || content;
    const targets = [];
    const add = (el) => { if (el && targets.indexOf(el) < 0) targets.push(el); };
    add(zone);
    if (zone) {
        add(zone.parentElement);
        for (const ch of zone.children || []) add(ch);
    }
    add(content);
    add(dlg);
    // Elements carrying captured drop callbacks get the dispatch too.
    const dropRecords = [];
    for (const el of [dlg, ...dlg.querySelectorAll('*')]) {
        const list = (el.__capturedListeners && el.__capturedListeners.drop) || [];
        for (const rec of list) { dropRecords.push({ el: el, rec: rec }); add(el); }
    }
    const items = staged.list.map((f) => ({ kind: 'file', type: f.type, name: f.name, getAsFile: () => f }));
    const spoof = {
        files: staged.files, items: items, types: ['Files'],
        getData: () => '', setData: () => {}, dropEffect: 'copy', effectAllowed: 'all'
    };
    const fire = (el, type) => {
        let ev;
        try { ev = new DragEvent(type, { bubbles: true, cancelable: true, composed: true, dataTransfer: spoof }); }
        catch (e) { ev = new Event(type, { bubbles: true, cancelable: true, composed: true }); }
        try { Object.defineProperty(ev, 'dataTransfer', { value: spoof }); } catch (e) { /* keep ctor value */ }
        el.dispatchEvent(ev);
    };
    // Per-record invocation counts: a stopImmediatePropagation
    // handler can make dispatch reach SOME callbacks but not
    // others, so a global count is not enough — a callback whose
    // own count did not move is called directly below.
    const beforeCounts = dropRecords.map((d) => d.rec.calls || 0);
    for (const type of ['dragenter', 'dragover', 'drop']) {
        for (const t of targets) { try { fire(t, type); } catch (e) { /* ignore */ } }
    }
    const names = staged.list.map((f) => f.name).join(' + ');
    let dispatched = 0;
    let direct = 0;
    for (let i = 0; i < dropRecords.length; i++) {
        const d = dropRecords[i];
        if ((d.rec.calls || 0) > beforeCounts[i]) { dispatched++; continue; }
        try {
            let ev;
            try { ev = new DragEvent('drop', { bubbles: true, cancelable: true, composed: true, dataTransfer: spoof }); }
            catch (e) { ev = new Event('drop', { bubbles: true, cancelable: true, composed: true }); }
            try { Object.defineProperty(ev, 'dataTransfer', { value: spoof }); } catch (e) { /* ignore */ }
            d.rec.wrapped.call(d.el, ev);
            direct++;
        } catch (e) { /* ignore */ }
    }
    if (dispatched > 0 || direct > 0) {
        const hit = { at: Date.now(), via: (direct > 0 && dispatched === 0) ? 'drop-direct' : 'drop', keys: staged.keys.slice(), names: staged.list.map((f) => f.name) };
        (window.__pbuInterceptHits = window.__pbuInterceptHits || []).push(hit);
        return 'dropped:' + names + ' (dispatch invoked ' + dispatched + ', direct ' + direct + ' captured drop callback(s), ' + targets.length + ' element(s))';
    }
    return 'no-drop-listener-invoked: dispatched to ' + targets.length + ' element(s), no captured drop callbacks';
}

function pbuMainAssignCreated() {
    const staged = window.__pbuStaged || {};
    if (!Object.keys(staged).length) return 'no-staged-file';
    const acceptMatch = (file, acc) => {
        if (!acc) return true;
        const ext = '.' + String(file.name.split('.').pop() || '').toLowerCase();
        if (acc.includes(ext)) return true;
        if (/image/.test(acc) && /^image\//.test(file.type)) return true;
        if (/epub/.test(acc) && /epub/i.test(file.type + ' ' + file.name)) return true;
        if (/pdf/.test(acc) && /pdf/i.test(file.type + ' ' + file.name)) return true;
        return false;
    };
    const inPanel = (el) => {
        try {
            const root = el.getRootNode && el.getRootNode();
            if (root && root.host && root.host.id === 'pbu-panel-host') return true;
            if (el.closest && el.closest('#pbu-panel-host')) return true;
        } catch (e) { /* ignore */ }
        return false;
    };
    const cands = [];
    const addCand = (el) => { if (el && el.tagName === 'INPUT' && el.type === 'file' && !inPanel(el) && cands.indexOf(el) < 0) cands.push(el); };
    for (const entry of (window.__allCreatedInputs || [])) addCand(entry && entry.el);
    for (const el of document.querySelectorAll('input[type="file"]')) addCand(el);
    if (!cands.length) return 'none: no file input found in __allCreatedInputs or the document';
    const assigned = [];
    let directChange = 0;
    for (const input of cands) {
        const keysAll = Object.keys(staged);
        const acc = String((input.getAttribute && input.getAttribute('accept')) || '').toLowerCase();
        let keys = keysAll.filter((k) => acceptMatch(staged[k], acc));
        if (!keys.length) keys = keysAll;
        if (!input.multiple) keys = keys.slice(0, 1);
        const have = {};
        try { for (let i = 0; i < (input.files || []).length; i++) have[input.files[i].name] = true; } catch (e) { /* ignore */ }
        const already = keys.every((k) => staged[k] && have[staged[k].name]);
        if (!already) {
            const dt = new DataTransfer();
            for (const k of keys) { dt.items.add(staged[k]); window.__pbuServed = window.__pbuServed || {}; window.__pbuServed[k] = true; }
            input.files = dt.files;
            input.__pbuServed = true;
        }
        const changeRecs = (input.__capturedListeners && input.__capturedListeners.change) || [];
        const changeBefore = changeRecs.map((r) => r.calls || 0);
        input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
        input.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
        for (let i = 0; i < changeRecs.length; i++) {
            if ((changeRecs[i].calls || 0) > changeBefore[i]) continue; // dispatch reached it
            try { changeRecs[i].wrapped.call(input, new Event('change', { bubbles: true, composed: true })); directChange++; } catch (e) { /* ignore */ }
        }
        for (const k of keys) { const n = staged[k].name; if (assigned.indexOf(n) < 0) assigned.push(n); }
    }
    if (!assigned.length) return 'none: file inputs found but no staged file matched';
    const hit = { at: Date.now(), via: 'assign-created', keys: Object.keys(staged), names: assigned.slice() };
    (window.__pbuInterceptHits = window.__pbuInterceptHits || []).push(hit);
    return 'assigned:' + assigned.join(' + ') + ' (' + cands.length + ' input(s), direct-change calls: ' + directChange + ')';
}

function pbuMainNgInject() {
    const dlg = pbuMainFindDialog();
    if (!dlg) return 'no-dialog';
    const staged = pbuMainStagedFiles();
    if (!staged) return 'no-staged-file';
    const TARGETS = ['onFileSelected', 'onFilesSelected', 'onDrop', 'handleFiles', 'handleDrop', 'uploadFiles', 'onFileChange', 'onFilesChange'];
    const scan = pbuMainNgScan(dlg);
    if (!scan.methods.length) return 'none: no Angular file methods found on dialog elements';
    // Re-walk and actually call (the scan is read-only; calling
    // needs the live objects, so repeat the candidate walk here).
    const cands = [];
    cands.push({ el: dlg, source: 'dialog' });
    for (const el of dlg.querySelectorAll('ng-component, [xapuploaderdropzone]')) cands.push({ el: el, source: el.tagName.toLowerCase() });
    const seen = [];
    const results = [];
    let callsLeft = 3;
    const tryCall = (obj, name, tag, source) => {
        if (callsLeft <= 0) return;
        callsLeft--;
        let outcome = '';
        try {
            obj[name](staged.files);
            outcome = 'FileList ok';
        } catch (e1) {
            try { obj[name](staged.list); outcome = 'array ok'; }
            catch (e2) {
                try { obj[name](staged.list[0]); outcome = 'single ok'; }
                catch (e3) { outcome = 'error: ' + String((e3 && e3.message) || e3).slice(0, 120); }
            }
        }
        results.push(tag + '.' + name + ' (' + source + '): ' + outcome);
    };
    for (const cand of cands) {
        if (callsLeft <= 0) break;
        const el = cand.el;
        const tag = (el.tagName || 'element').toLowerCase();
        const hosts = [el];
        try {
            const ctx = el.__ngContext__;
            if (Array.isArray(ctx)) { for (const item of ctx) hosts.push(item); }
            else if (ctx && typeof ctx === 'object') hosts.push(ctx);
        } catch (e) { /* ignore */ }
        for (const obj of hosts) {
            if (callsLeft <= 0) break;
            if (!obj || (typeof obj !== 'object' && typeof obj !== 'function') || seen.indexOf(obj) >= 0) continue;
            seen.push(obj);
            try {
                if (obj.fileInput && obj.fileInput.tagName === 'INPUT') {
                    const dt = new DataTransfer();
                    for (const f of staged.list) dt.items.add(f);
                    obj.fileInput.files = dt.files;
                    obj.fileInput.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
                    obj.fileInput.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
                    results.push(tag + '.fileInput (' + cand.source + '): assigned + change dispatched');
                    callsLeft--;
                    continue;
                }
            } catch (e) { /* ignore */ }
            for (const name of TARGETS) {
                if (callsLeft <= 0) break;
                try { if (typeof obj[name] === 'function') tryCall(obj, name, tag, cand.source); } catch (e) { /* ignore */ }
            }
        }
    }
    if (!results.length) return 'found: ' + scan.methods.map((m) => m.tag + '.' + m.name).join(', ') + ' — but no call could be made';
    return 'ng-inject: ' + results.join(' | ');
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (!msg || msg.type !== 'PBU_MAIN' || !sender.tab || !sender.tab.id) return;
    const target = { tabId: sender.tab.id };
    let run;
    if (msg.action === 'ensure-early') {
        run = (async () => {
            let injected = false;
            try {
                await chrome.scripting.executeScript({ target: target, world: 'MAIN', files: ['early-intercept.js'] });
                injected = true;
            } catch (e) { /* the Run-time fallback patches still apply */ }
            const res = await chrome.scripting.executeScript({ target: target, world: 'MAIN', func: pbuMainPing, args: [] });
            return { earlyInjected: injected, ping: res && res[0] && res[0].result };
        })();
    }
    else if (msg.action === 'diag') run = chrome.scripting.executeScript({ target: target, world: 'MAIN', func: pbuMainDiag, args: [] }).then((res) => res && res[0] && res[0].result);
    else if (msg.action === 'direct-drop') run = chrome.scripting.executeScript({ target: target, world: 'MAIN', func: pbuMainDirectDrop, args: [] }).then((res) => res && res[0] && res[0].result);
    else if (msg.action === 'assign-created') run = chrome.scripting.executeScript({ target: target, world: 'MAIN', func: pbuMainAssignCreated, args: [] }).then((res) => res && res[0] && res[0].result);
    else if (msg.action === 'ng-inject') run = chrome.scripting.executeScript({ target: target, world: 'MAIN', func: pbuMainNgInject, args: [] }).then((res) => res && res[0] && res[0].result);
    else return;
    Promise.resolve(run)
        .then((result) => sendResponse({ ok: true, result: result }))
        .catch((e) => sendResponse({ ok: false, error: String((e && e.message) || e) }));
    return true;
});
/* =====================================================================
 * v9.23 — FIX for the v9.22 live log (GGKEY:NNC2GUQ5UYX, 2026-10-24
 * 14:22-14:31 +06). Root causes found by reading the shipped code
 * against that log, not by guessing:
 *   (1) diag / direct-drop / ng-inject answered NOTHING, while
 *       assign-created DID answer ("none: ..."). Reason: the three
 *       silent drivers call helper functions defined in
 *       background.js (findDialog, stagedFiles, ngScan) — but a
 *       function sent via chrome.scripting.executeScript is
 *       serialised ALONE into the page world, where those helpers
 *       do not exist, so it throws ReferenceError and the bridge
 *       returns ok:false. assign-created is self-contained, so it
 *       worked. Every v9.23 driver below is therefore FULLY
 *       SELF-CONTAINED: all helpers are defined INSIDE the driver
 *       function body. A static check (test-drivers-v923.js) proves
 *       no driver references another background function.
 *   (2) Browse gave 0 intercept hits although "early hooks armed:
 *       YES". The early script may have been injected LATE (by the
 *       Run-time ensure-early step, after Angular had already
 *       registered its Browse handler), so the handler never passed
 *       through the addEventListener wrap and never got a proxied
 *       trusted event. v9.23 measures this: ensure-early923 pings
 *       BEFORE injecting, so the log proves whether the manifest
 *       document_start entry armed the hooks or the bridge did it
 *       late. And direct-browse923 calls the Browse button's
 *       CAPTURED click callbacks directly (when capture exists),
 *       which needs no trusted dispatch at all.
 *   (3) Hunter assign read back 0 files on a setAttribute-type
 *       input outside the dialog, with no detail about that input.
 *       assign-any923 logs the candidate's full detail (name,
 *       accept, multiple, disabled, connected, inDialog, type,
 *       parent chain) and tries the native files-setter descriptor
 *       as well as direct assignment, single-file as well as
 *       multi-file, before giving up on a candidate.
 * No CDP channel anywhere; manual pick stays removed.
 * ===================================================================== */

function pbuMainDiag923() {
    var clean = function (s) { return String(s || '').replace(/\s+/g, ' ').trim(); };
    var findDlg = function () {
        var list = document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container');
        for (var i = 0; i < list.length; i++) {
            if (/upload content and cover|drag and drop/i.test(clean(list[i].innerText || list[i].textContent))) return list[i];
        }
        return list.length ? list[0] : null;
    };
    var dlg = findDlg();
    var createdRaw = window.__allCreatedInputs || [];
    var created = createdRaw.map(function (e) {
        var el = e && e.el;
        var inDlg = false;
        try { inDlg = !!(el && el.closest && el.closest('[role="dialog"], .mat-dialog-container, mat-dialog-container')); } catch (err) { /* ignore */ }
        return { name: (el && el.getAttribute && el.getAttribute('name')) || '', accept: (el && el.getAttribute && el.getAttribute('accept')) || '', type: (el && el.type) || '', connected: !!(el && el.isConnected), inDialog: inDlg, where: (e && e.where) || '' };
    });
    var createdFile = created.filter(function (c) { return c.type === 'file'; }).length;
    var captured = { click: 0, drop: 0, change: 0, elements: 0 };
    var browseInfo = 'no-dialog';
    if (dlg) {
        var els = [dlg];
        try { dlg.querySelectorAll('*').forEach(function (x) { els.push(x); }); } catch (err) { /* ignore */ }
        els.forEach(function (el) {
            var rec = el.__capturedListeners;
            if (!rec) return;
            captured.elements++;
            ['click', 'drop', 'change'].forEach(function (t) {
                if (rec[t] && rec[t].length) captured[t] += rec[t].length;
            });
        });
        var btns = [];
        try { dlg.querySelectorAll('button, [role="button"]').forEach(function (b) { btns.push(b); }); } catch (err) { /* ignore */ }
        var browse = null;
        for (var b = 0; b < btns.length; b++) {
            var t = clean(btns[b].innerText || btns[b].textContent);
            if (t === 'Browse' || btns[b].getAttribute('xapuploadertrigger') !== null) { browse = btns[b]; break; }
        }
        if (browse) {
            var bc = browse.__capturedListeners && browse.__capturedListeners.click ? browse.__capturedListeners.click.length : 0;
            browseInfo = 'found capturedClick=' + bc + ' onclick=' + (typeof browse.onclick === 'function' ? 'yes' : 'no');
        } else browseInfo = 'not-found';
    }
    var reg = window.__pbuInputReg || [];
    var hunter = reg.map(function (r) {
        var el = r && r.el;
        var inDlg2 = false;
        try { inDlg2 = !!(el && el.closest && el.closest('[role="dialog"], .mat-dialog-container, mat-dialog-container')); } catch (err) { /* ignore */ }
        return { name: (el && el.getAttribute && el.getAttribute('name')) || '', accept: (el && el.getAttribute && el.getAttribute('accept')) || '', multiple: !!(el && el.multiple), disabled: !!(el && el.disabled), connected: !!(el && el.isConnected), inDialog: inDlg2, type: (el && el.type) || '', where: (r && r.where) || '' };
    });
    var ngHosts = [];
    if (dlg) {
        ngHosts.push(dlg);
        try { dlg.querySelectorAll('ng-component, [xapuploaderdropzone]').forEach(function (x) { ngHosts.push(x); }); } catch (err) { /* ignore */ }
    }
    var methods = [];
    ngHosts.forEach(function (host) {
        var ctx = host.__ngContext__;
        if (!ctx) return;
        var items = Array.isArray(ctx) ? ctx : [ctx];
        items.forEach(function (it) {
            if (!it || typeof it !== 'object') return;
            ['onFileSelected', 'onFilesSelected', 'onDrop', 'handleFiles', 'handleDrop', 'uploadFiles', 'onFileChange', 'onFilesChange'].forEach(function (nm) {
                if (typeof it[nm] === 'function') methods.push(host.tagName.toLowerCase() + '.' + nm);
            });
            if (it.fileInput) methods.push(host.tagName.toLowerCase() + '.fileInput(prop)');
        });
    });
    return {
        dialogOpen: !!dlg, browse: browseInfo,
        createdTotal: created.length, createdFile: createdFile, created: created,
        captured: captured, hunter: hunter,
        ngMethods: methods, ngScanned: ngHosts.length,
        earlyArmed: !!window.__pbuEarlyInterceptArmed,
        earlyReadyState: window.__pbuEarlyReadyState || '',
        earlyPerfMs: window.__pbuEarlyPerfMs || 0
    };
}

function pbuMainDirectDrop923() {
    var clean = function (s) { return String(s || '').replace(/\s+/g, ' ').trim(); };
    var dlg = null;
    var list = document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container');
    for (var i = 0; i < list.length; i++) {
        if (/upload content and cover|drag and drop/i.test(clean(list[i].innerText || list[i].textContent))) { dlg = list[i]; break; }
    }
    if (!dlg) return 'no-dialog';
    var staged = window.__pbuStaged || {};
    var keys = Object.keys(staged);
    if (!keys.length) return 'no-staged-file';
    var dt = new DataTransfer();
    keys.forEach(function (k) { try { dt.items.add(staged[k]); } catch (err) { /* ignore */ } });
    var spoof = {
        files: dt.files,
        items: keys.map(function (k) { var f = staged[k]; return { kind: 'file', type: f.type || '', name: f.name, getAsFile: function () { return f; } }; }),
        types: ['Files'], dropEffect: 'copy', effectAllowed: 'all',
        getData: function () { return ''; }, setData: function () { return true; }
    };
    var targets = [dlg];
    try { dlg.querySelectorAll('*').forEach(function (x) { targets.push(x); }); } catch (err) { /* ignore */ }
    if (dlg.parentElement) targets.push(dlg.parentElement);
    var zone = null;
    try { zone = dlg.querySelector('[xapuploaderdropzone]') || dlg; } catch (err) { zone = dlg; }
    if (zone && targets.indexOf(zone) < 0) targets.push(zone);
    var dropRecords = [];
    targets.forEach(function (el) {
        var rec0 = el.__capturedListeners;
        if (!rec0 || !rec0.drop) return;
        rec0.drop.forEach(function (r) { dropRecords.push({ el: el, r: r, before: (r.calls || 0) }); });
    });
    var dispatched = 0;
    ['dragenter', 'dragover', 'drop'].forEach(function (type) {
        targets.forEach(function (el) {
            try {
                var ev = new DragEvent(type, { bubbles: true, cancelable: true, composed: true });
                try { Object.defineProperty(ev, 'dataTransfer', { value: spoof }); } catch (err) { /* ignore */ }
                el.dispatchEvent(ev); dispatched++;
            } catch (err) { /* ignore */ }
        });
    });
    var direct = 0, directNames = [];
    dropRecords.forEach(function (item) {
        if ((item.r.calls || 0) !== item.before) return;
        try {
            var ev2 = new DragEvent('drop', { bubbles: true, cancelable: true, composed: true });
            try { Object.defineProperty(ev2, 'dataTransfer', { value: spoof }); } catch (err2) { /* ignore */ }
            var proxy2 = new Proxy(ev2, { get: function (t, p) { if (p === 'isTrusted') return true; if (p === 'target' || p === 'currentTarget') return item.el; var v = Reflect.get(t, p); return (typeof v === 'function') ? v.bind(t) : v; } });
            var fn = item.r.orig || item.r.wrapped;
            if (fn) { fn.call(item.el, proxy2); direct++; directNames.push(item.el.tagName.toLowerCase()); }
        } catch (err3) { /* ignore */ }
    });
    return 'dropped: dispatched-to=' + dispatched + ' direct-called=' + direct + (directNames.length ? ' (' + directNames.join(',') + ')' : '') + ' files=' + keys.map(function (k) { return staged[k].name; }).join(' + ');
}

function pbuMainNgInject923() {
    var clean = function (s) { return String(s || '').replace(/\s+/g, ' ').trim(); };
    var dlg = null;
    var list = document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container');
    for (var i = 0; i < list.length; i++) {
        if (/upload content and cover|drag and drop/i.test(clean(list[i].innerText || list[i].textContent))) { dlg = list[i]; break; }
    }
    if (!dlg) return 'no-dialog';
    var staged = window.__pbuStaged || {};
    var keys = Object.keys(staged);
    if (!keys.length) return 'no-staged-file';
    var dt = new DataTransfer();
    keys.forEach(function (k) { try { dt.items.add(staged[k]); } catch (err) { /* ignore */ } });
    var files = dt.files;
    var TARGETS = ['onFileSelected', 'onFilesSelected', 'onDrop', 'handleFiles', 'handleDrop', 'uploadFiles', 'onFileChange', 'onFilesChange'];
    var hosts = [dlg];
    try { dlg.querySelectorAll('ng-component, [xapuploaderdropzone]').forEach(function (x) { hosts.push(x); }); } catch (err) { /* ignore */ }
    var found = [];
    var results = [];
    var calls = 0;
    hosts.forEach(function (host) {
        var ctx = host.__ngContext__;
        if (!ctx) return;
        var items = Array.isArray(ctx) ? ctx : [ctx];
        items.forEach(function (it) {
            if (!it || typeof it !== 'object') return;
            if (it.fileInput) {
                try {
                    it.fileInput.files = files;
                    it.fileInput.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
                    it.fileInput.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
                    results.push(host.tagName.toLowerCase() + '.fileInput assigned'); calls++;
                } catch (err) { /* ignore */ }
            }
            TARGETS.forEach(function (nm) {
                if (typeof it[nm] !== 'function' || calls >= 3) return;
                found.push(host.tagName.toLowerCase() + '.' + nm);
                try { it[nm].call(it, files); results.push(host.tagName.toLowerCase() + '.' + nm + '(FileList)'); calls++; }
                catch (err1) {
                    try { it[nm].call(it, Array.prototype.slice.call(files)); results.push(host.tagName.toLowerCase() + '.' + nm + '(array)'); calls++; }
                    catch (err2) { /* ignore */ }
                }
            });
        });
    });
    if (!results.length) return 'found: ' + found.join(', ') + ' — but no call could be made (scanned ' + hosts.length + ' host(s))';
    return 'ng-inject: ' + results.join(' | ');
}

function pbuMainDirectBrowse923() {
    var clean = function (s) { return String(s || '').replace(/\s+/g, ' ').trim(); };
    var dlg = null;
    var list = document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container');
    for (var i = 0; i < list.length; i++) {
        if (/upload content and cover|drag and drop/i.test(clean(list[i].innerText || list[i].textContent))) { dlg = list[i]; break; }
    }
    if (!dlg) return 'no-dialog';
    var btns = [];
    try { dlg.querySelectorAll('button, [role="button"]').forEach(function (b) { btns.push(b); }); } catch (err) { /* ignore */ }
    var browse = null;
    for (var i = 0; i < btns.length; i++) {
        if (clean(btns[i].innerText || btns[i].textContent) === 'Browse' || btns[i].getAttribute('xapuploadertrigger') !== null) { browse = btns[i]; break; }
    }
    if (!browse) return 'no-browse-button';
    var rec = browse.__capturedListeners;
    var clicks = rec && rec.click ? rec.click : [];
    if (!clicks.length) {
        return 'no-captured-click: Browse found but no click listener was captured (handler registered before the wrap, or via onclick=' + (typeof browse.onclick === 'function' ? 'yes' : 'no') + ')';
    }
    var called = 0;
    clicks.forEach(function (r) {
        try {
            var ev = new MouseEvent('click', { bubbles: true, cancelable: true, composed: true, view: window });
            if (r.wrapped) { r.wrapped.call(browse, ev); called++; }
            else if (r.orig) {
                var proxy = new Proxy(ev, { get: function (t, p) { if (p === 'isTrusted') return true; if (p === 'target' || p === 'currentTarget') return browse; var v = Reflect.get(t, p); return (typeof v === 'function') ? v.bind(t) : v; } });
                r.orig.call(browse, proxy); called++;
            }
        } catch (err) { /* ignore */ }
    });
    return 'direct-browse: called ' + called + ' captured click record(s) on Browse';
}

function pbuMainNgBrowse923() {
    var clean = function (s) { return String(s || '').replace(/\s+/g, ' ').trim(); };
    var dlg = null;
    var list = document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container');
    for (var i = 0; i < list.length; i++) {
        if (/upload content and cover|drag and drop/i.test(clean(list[i].innerText || list[i].textContent))) { dlg = list[i]; break; }
    }
    if (!dlg) return 'no-dialog';
    var hitsBefore = (window.__pbuInterceptHits || []).length;
    var hosts = [dlg];
    try { dlg.querySelectorAll('ng-component, [xapuploaderdropzone]').forEach(function (x) { hosts.push(x); }); } catch (err) { /* ignore */ }
    var tried = [];
    var calls = 0;
    hosts.forEach(function (host) {
        var ctx = host.__ngContext__;
        if (!ctx) return;
        var items = Array.isArray(ctx) ? ctx : [ctx];
        items.forEach(function (it) {
            if (!it || typeof it !== 'object' || calls >= 2) return;
            Object.keys(it).forEach(function (nm) {
                if (calls >= 2) return;
                if (typeof it[nm] !== 'function') return;
                if (!/^(open|trigger|show|start|browse|select)/i.test(nm)) return;
                if (!/(file|picker|upload|browse|dialog)/i.test(nm)) return;
                tried.push(host.tagName.toLowerCase() + '.' + nm);
                try { it[nm].call(it); calls++; } catch (err) { /* ignore */ }
            });
        });
    });
    var hitsAfter = (window.__pbuInterceptHits || []).length;
    return 'ng-browse: tried ' + (tried.length ? tried.join(', ') : 'none') + ' | intercept hits ' + hitsBefore + ' -> ' + hitsAfter;
}

function pbuMainAssignAny923(keys) {
    var staged = window.__pbuStaged || {};
    var wanted = (keys && keys.length ? keys : Object.keys(staged)).filter(function (k) { return staged[k]; });
    if (!wanted.length) return 'no-staged-file';
    var clean = function (s) { return String(s || '').replace(/\s+/g, ' ').trim(); };
    var chain = function (el) {
        var parts = [];
        try {
            var n = el;
            while (n && parts.length < 4) { parts.push((n.tagName || '?').toLowerCase() + (n.id ? '#' + n.id : '')); n = n.parentElement; }
        } catch (err) { /* ignore */ }
        return parts.join(' < ');
    };
    var detail = function (el, where) {
        var inDlg = false;
        try { inDlg = !!(el.closest && el.closest('[role="dialog"], .mat-dialog-container, mat-dialog-container')); } catch (err) { /* ignore */ }
        return 'where=' + where + ' name=' + ((el.getAttribute && el.getAttribute('name')) || '') + ' accept=' + ((el.getAttribute && el.getAttribute('accept')) || '') + ' multiple=' + !!el.multiple + ' disabled=' + !!el.disabled + ' type=' + (el.type || '') + ' connected=' + !!el.isConnected + ' inDialog=' + inDlg + ' chain=' + chain(el);
    };
    var cands = [];
    var dlg = null;
    var list = document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container');
    for (var i = 0; i < list.length; i++) {
        if (/upload content and cover|drag and drop/i.test(clean(list[i].innerText || list[i].textContent))) { dlg = list[i]; break; }
    }
    if (dlg) {
        var di = dlg.querySelector('input[type="file"][name="Filedata"]') || dlg.querySelector('input[type="file"]');
        if (di) cands.push({ el: di, where: 'dialog' });
    }
    var reg = (window.__pbuInputReg || []).slice();
    reg.sort(function (a, b) {
        var score = function (r) {
            var s = 0;
            try {
                if ((r.el.getAttribute('name') || '') === 'Filedata') s += 40;
                if (r.el.closest && r.el.closest('[role="dialog"], .mat-dialog-container, mat-dialog-container')) s += 30;
                if (r.el.isConnected) s += 10;
            } catch (err) { /* ignore */ }
            return s;
        };
        return score(b) - score(a) || (b.at || 0) - (a.at || 0);
    });
    reg.forEach(function (r) {
        if (!cands.some(function (c) { return c.el === r.el; })) cands.push({ el: r.el, where: r.where || 'registry' });
    });
    if (!cands.length) return 'assign923-failed: no candidate anywhere (registry=' + reg.length + ')';
    var reports = [];
    for (var ci = 0; ci < cands.length; ci++) {
        var input = cands[ci].el;
        var use = wanted;
        if (!input.multiple && use.length > 1) use = use.slice(0, 1);
        var methods = ['descriptor', 'direct'];
        for (var mi = 0; mi < methods.length; mi++) {
            try {
                var dt = new DataTransfer();
                use.forEach(function (k) { dt.items.add(staged[k]); });
                if (methods[mi] === 'descriptor') {
                    var desc = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'files');
                    if (desc && desc.set) desc.set.call(input, dt.files); else continue;
                } else {
                    input.files = dt.files;
                }
                var held = input.files ? input.files.length : 0;
                reports.push(detail(input, cands[ci].where) + ' via=' + methods[mi] + ' held=' + held);
                if (held) {
                    use.forEach(function (k) { window.__pbuServed = window.__pbuServed || {}; window.__pbuServed[k] = true; });
                    input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
                    input.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
                    return 'assigned923[' + cands[ci].where + ' via ' + methods[mi] + ']: ' + use.map(function (k) { return staged[k].name; }).join(' + ') + ' (input now holds ' + held + ' file(s))';
                }
            } catch (err) {
                reports.push(detail(input, cands[ci].where) + ' via=' + methods[mi] + ' error=' + String((err && err.message) || err));
            }
        }
    }
    return 'assign923-failed: ' + reports.join(' || ');
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (!msg || msg.type !== 'PBU_MAIN' || !sender.tab || !sender.tab.id) return;
    const target = { tabId: sender.tab.id };
    let run;
    if (msg.action === 'ensure-early923') {
        run = (async () => {
            const pingFn = () => ({ earlyArmed: !!window.__pbuEarlyInterceptArmed, readyState: window.__pbuEarlyReadyState || '', perfMs: window.__pbuEarlyPerfMs || 0, hits: (window.__pbuInterceptHits || []).length });
            let before = null;
            try { const r = await chrome.scripting.executeScript({ target: target, world: 'MAIN', func: pingFn, args: [] }); before = r && r[0] && r[0].result; } catch (e) { /* ignore */ }
            let injected = false;
            try { await chrome.scripting.executeScript({ target: target, world: 'MAIN', files: ['early-intercept.js'] }); injected = true; } catch (e) { /* ignore */ }
            let after = null;
            try { const r = await chrome.scripting.executeScript({ target: target, world: 'MAIN', func: pingFn, args: [] }); after = r && r[0] && r[0].result; } catch (e) { /* ignore */ }
            return { armedBefore: !!(before && before.earlyArmed), armedAfter: !!(after && after.earlyArmed), before: before, after: after, injected: injected };
        })();
    }
    else if (msg.action === 'diag923') run = chrome.scripting.executeScript({ target: target, world: 'MAIN', func: pbuMainDiag923, args: [] }).then((res) => res && res[0] && res[0].result);
    else if (msg.action === 'direct-drop923') run = chrome.scripting.executeScript({ target: target, world: 'MAIN', func: pbuMainDirectDrop923, args: [] }).then((res) => res && res[0] && res[0].result);
    else if (msg.action === 'ng-inject923') run = chrome.scripting.executeScript({ target: target, world: 'MAIN', func: pbuMainNgInject923, args: [] }).then((res) => res && res[0] && res[0].result);
    else if (msg.action === 'direct-browse923') run = chrome.scripting.executeScript({ target: target, world: 'MAIN', func: pbuMainDirectBrowse923, args: [] }).then((res) => res && res[0] && res[0].result);
    else if (msg.action === 'ng-browse923') run = chrome.scripting.executeScript({ target: target, world: 'MAIN', func: pbuMainNgBrowse923, args: [] }).then((res) => res && res[0] && res[0].result);
    else if (msg.action === 'assign-any923') run = chrome.scripting.executeScript({ target: target, world: 'MAIN', func: pbuMainAssignAny923, args: [msg.keys || []] }).then((res) => res && res[0] && res[0].result);
    else return;
    Promise.resolve(run)
        .then((result) => sendResponse({ ok: true, result: result }))
        .catch((e) => sendResponse({ ok: false, error: String((e && e.message) || e) }));
    return true;
});
