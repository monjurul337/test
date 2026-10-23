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
              this.dispatchEvent(new Event('input', { bubbles: true }));
              this.dispatchEvent(new Event('change', { bubbles: true }));
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
                t.dispatchEvent(new Event('input', { bubbles: true }));
                t.dispatchEvent(new Event('change', { bubbles: true }));
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
    zone.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: dt }));
    dlg.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: dt }));
  }
  return 'dropped:' + f.name;
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || msg.type !== 'PBU_MAIN' || !sender.tab || !sender.tab.id) return;
  const target = { tabId: sender.tab.id };
  let run;
  if (msg.action === 'drop') run = chrome.scripting.executeScript({ target, world: 'MAIN', func: pbuMainDrop, args: [msg.kind] });
  else if (msg.action === 'ping') run = chrome.scripting.executeScript({ target, world: 'MAIN', func: pbuMainPing, args: [] });
  else run = chrome.scripting.executeScript({ target, world: 'MAIN', func: pbuMainStage, args: [msg.payload || {}] });
  run.then((res) => sendResponse({ ok: true, result: res && res[0] && res[0].result }))
    .catch((e) => sendResponse({ ok: false, error: String((e && e.message) || e) }));
  return true;
});
