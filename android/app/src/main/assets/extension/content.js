"use strict";const sleep=e=>new Promise(t=>setTimeout(t,e));function norm(e){return String(e||"").replace(/\s+/g," ").trim()}function isVisible(e){if(!e)return!1;const t=e.getBoundingClientRect(),n=getComputedStyle(e);return t.width>0&&t.height>0&&"hidden"!==n.visibility&&"none"!==n.display}function pageText(){return document.body&&document.body.innerText||""}async function waitFor(e,t=2e4,n=400){const o=Date.now();for(;;){let r;try{r=e()}catch(e){r=null}if(r)return r;if(Date.now()-o>t)return null;await sleep(n)}}function clickEl(e){if(!e)return!1;e.scrollIntoView({block:"center",inline:"center"});const t={bubbles:!0,cancelable:!0,view:window};return e.dispatchEvent(new MouseEvent("mousedown",t)),e.dispatchEvent(new MouseEvent("mouseup",t)),e.click(),!0}function exactTextEq(e,t){const n=norm(e).toLowerCase(),o=norm(t).toLowerCase();if(!n||!o)return!1;if(n===o)return!0;const r=e=>e.replace(/\s*\([^)]*\)\s*$/,"").replace(/[\s*:]+$/,"").trim(),a=r(n),i=r(o);return""!==a&&a===i}function findByText(e,t='button, a, [role="button"], [role="tab"], [role="option"], li, label, span, div'){const n=(Array.isArray(e)?e:[e]).map(e=>norm(e).toLowerCase()),o=[];for(const e of document.querySelectorAll(t)){if(!isVisible(e))continue;const t=norm(e.textContent).toLowerCase();!t||t.length>300||n.some(e=>t===e||t.includes(e))&&o.push(e)}return o.sort((e,t)=>norm(e.textContent).length-norm(t.textContent).length),o}async function clickByText(e,t=15e3,n){const o=await waitFor(()=>findByText(e,n)[0],t);return!!o&&(clickEl(o),await sleep(600),!0)}function setNativeValue(e,t){const n=e instanceof HTMLTextAreaElement?HTMLTextAreaElement.prototype:e instanceof HTMLSelectElement?HTMLSelectElement.prototype:HTMLInputElement.prototype,o=Object.getOwnPropertyDescriptor(n,"value");o&&o.set?o.set.call(e,t):e.value=t,e.dispatchEvent(new Event("input",{bubbles:!0})),e.dispatchEvent(new Event("change",{bubbles:!0})),e.dispatchEvent(new Event("blur",{bubbles:!0}))}function setValueNoBlur(e,t){const n=e instanceof HTMLTextAreaElement?HTMLTextAreaElement.prototype:HTMLInputElement.prototype,o=Object.getOwnPropertyDescriptor(n,"value");o&&o.set?o.set.call(e,t):e.value=t,e.dispatchEvent(new Event("input",{bubbles:!0}))}async function typeInto(e,t){e.focus(),setNativeValue(e,""),await sleep(120),setNativeValue(e,t);for(const t of["keydown","keyup"])e.dispatchEvent(new KeyboardEvent(t,{bubbles:!0,key:"a"}));await sleep(200)}async function typeIntoSearch(e,t){e.focus(),setValueNoBlur(e,""),await sleep(150);let n="";for(const o of String(t))n+=o,e.dispatchEvent(new KeyboardEvent("keydown",{bubbles:!0,key:o})),setValueNoBlur(e,n),e.dispatchEvent(new KeyboardEvent("keyup",{bubbles:!0,key:o})),await sleep(25);e.dispatchEvent(new Event("change",{bubbles:!0})),await sleep(300)}const CONTROL_SEL='input:not([type="hidden"]):not([type="file"]), textarea, select, mat-select, [role="combobox"], [contenteditable="true"]';function cleanLabel(e){return norm(e).toLowerCase().replace(/[\s*:]+$/,"")}function controlForLabelIn(e,t){const n=cleanLabel(t);if(!n)return null;const o=[...e.querySelectorAll("label, .mat-form-field-label, mat-label, legend, .label")],r=[];for(const e of o){const t=cleanLabel(e.innerText||e.textContent);t&&(t===n?r.push({lab:e,score:0}):t.startsWith(n)&&t.length-n.length<=2&&r.push({lab:e,score:1}))}r.sort((e,t)=>e.score-t.score);for(const{lab:e}of r){if(e.htmlFor){const t=document.getElementById(e.htmlFor);if(t)return t}const t=e.querySelector(CONTROL_SEL);if(t)return t;const n=e.closest(".mat-form-field, mat-form-field, .form-field, fieldset");if(n){const e=n.querySelector(CONTROL_SEL);if(e)return e}const o=e.parentElement;if(o){const e=o.querySelector(CONTROL_SEL);if(e)return e;const t=o.parentElement;if(t){const e=t.querySelectorAll(CONTROL_SEL);if(1===e.length)return e[0]}}}return null}function controlForLabel(e){return controlForLabelIn(document,e)}function fieldByLabel(e){for(const t of Array.isArray(e)?e:[e]){const e=controlForLabel(t);if(e)return e}return null}function scopedControlForLabel(e,t){return e?controlForLabelIn(e,t):null}function selectOptionByText(e,t){for(const n of e.options)if(exactTextEq(n.text,t))return e.value=n.value,e.dispatchEvent(new Event("input",{bubbles:!0})),e.dispatchEvent(new Event("change",{bubbles:!0})),!0;return!1}function readSelectDisplay(e){if(!e)return null;if("SELECT"===e.tagName){const t=e.options[e.selectedIndex];return t?norm(t.text):null}if("INPUT"===e.tagName||"TEXTAREA"===e.tagName)return norm(e.value);const t=e.querySelector(".mat-mdc-select-value-text, .mat-select-value-text, .mat-mdc-select-value, .mat-select-value");return t?norm(t.innerText||t.textContent):norm(e.innerText||e.textContent)||null}function overlayOptionExact(e){const t=[...document.querySelectorAll(".cdk-overlay-pane")].filter(isVisible);for(const n of t){const t=[...n.querySelectorAll('[role="option"], mat-option, .mat-option, .mat-mdc-option, li')].filter(isVisible).find(t=>exactTextEq(t.innerText||t.textContent,e));if(t)return t}return null}async function waitOverlayClosed(e=5e3){return waitFor(()=>{const e=document.querySelector(".cdk-overlay-pane");return!e||!isVisible(e)},e,200)}async function clickOverlayOptionExact(e,t,n=9e3){clickEl(e),await sleep(700);const o=await waitFor(()=>overlayOptionExact(t),n);return o?(clickEl(o),await waitOverlayClosed(),!0):(document.dispatchEvent(new KeyboardEvent("keydown",{bubbles:!0,key:"Escape"})),!1)}async function operateSelect(e,t,n=1e4){if(!e)return{ok:!1,value:null};let o=e;if("SELECT"===o.tagName||"INPUT"===o.tagName||"TEXTAREA"===o.tagName||o.matches('mat-select, [role="combobox"]')||(o=o.querySelector('select, mat-select, [role="combobox"], input, textarea')||o),"SELECT"===o.tagName){if(!selectOptionByText(o,t))return{ok:!1,value:readSelectDisplay(o)};await sleep(200);const e=readSelectDisplay(o);return{ok:exactTextEq(e||"",t),value:e}}if("INPUT"===o.tagName||"TEXTAREA"===o.tagName){await typeIntoSearch(o,t);await clickOverlayOptionExact(o,t,Math.min(n,6e3)).catch(()=>!1);await sleep(200);const e=norm(o.value);return{ok:!!e,value:e}}let r=readSelectDisplay(o);for(let e=0;e<2;e++){const e=await clickOverlayOptionExact(o,t,n);if(r=readSelectDisplay(o),e&&r&&exactTextEq(r,t))return{ok:!0,value:r};await sleep(600)}return{ok:!1,value:r}}function comboboxByPlaceholder(e){const t=(Array.isArray(e)?e:[e]).map(e=>norm(e).toLowerCase());return[...document.querySelectorAll('mat-select, [role="combobox"]')].filter(isVisible).find(e=>{const n=norm(e.innerText||e.textContent).toLowerCase(),o=(e.getAttribute("aria-label")||"").toLowerCase();return t.some(e=>n.includes(e)||o.includes(e))})||null}async function pickSelectOption(e,t,n=15e3){const o=Date.now();let r={ok:!1,value:null};for(;Date.now()-o<n;){let n=fieldByLabel(e);if(n||(n=comboboxByPlaceholder(e)),n&&(r=await operateSelect(n,t,8e3),r.ok))return r;await sleep(700)}return r}function escapeRegExp(e){return String(e).replace(/[.*+?^${}()|[\]\\]/g,"\\$&")}function kwMatch(e,t){const n=escapeRegExp(String(t).toLowerCase());return new RegExp("(^|[^a-z0-9])"+n+"([^a-z0-9]|$)","i").test(e)}const GROUP_CONTROL_SEL='select, mat-radio-group, mat-select, [role="radiogroup"], [role="combobox"], input[type="radio"], [role="radio"]';function findGroupContainer(e){const t=Array.isArray(e)?e:[e],n=[...document.querySelectorAll("label, legend, h1, h2, h3, h4, div, span, p, mat-label, .mat-form-field-label")].filter(isVisible).map(e=>({el:e,t:norm(e.innerText||e.textContent)})).filter(({t:e})=>e&&e.length<=90&&t.some(t=>kwMatch(e,t)));n.sort((e,t)=>e.t.length-t.t.length);for(const{el:e}of n){const t=e.closest('.mat-form-field, mat-form-field, fieldset, mat-radio-group, [role="radiogroup"]');if(t&&t.querySelector(GROUP_CONTROL_SEL))return t;let n=e;for(let e=0;e<8&&n&&n!==document.body&&(n=n.parentElement,n);e++)if(n.querySelector(GROUP_CONTROL_SEL)){if(norm(n.innerText||"").length<800)return n;break}}return null}function readGroupValue(e){if(!e)return null;const t=e.querySelector("select");if(t){const e=t.options[t.selectedIndex];if(e)return norm(e.text)}const n=e.querySelector('input[type="radio"]:checked');if(n){const e=n.closest("mat-radio-button, label")||n.id&&document.querySelector(`label[for="${CSS.escape(n.id)}"]`);return norm(e?e.innerText||e.textContent:n.value)}const o=e.querySelector('input[type="checkbox"]:checked');if(o){const e=o.closest("mat-checkbox, label");if(e)return norm(e.innerText||e.textContent)}const r=e.querySelector('mat-select, [role="combobox"]');if(r){const e=readSelectDisplay(r);if(e)return e}const a=e.querySelector('[aria-checked="true"], .mat-radio-checked, .mat-mdc-radio-checked, .mat-selected, .mdc-list-item--selected, [aria-selected="true"]');return a?norm(a.innerText||a.textContent):null}async function chooseInGroup(e,t,n=12e3){const o=Array.isArray(t)?t:[t],r=await waitFor(()=>{const t=findGroupContainer(e);if(!t)return null;const n=t.querySelector("select");if(n)return{container:t,sel:n};const r=[...t.querySelectorAll('label, [role="radio"], [role="option"], mat-radio-button, mat-option, li, button')].filter(isVisible).find(e=>o.some(t=>exactTextEq(e.innerText||e.textContent,t)));if(r)return{container:t,el:r};const a=t.querySelector('mat-select, [role="combobox"]');return a?{container:t,ms:a}:null},n);if(!r)return{ok:!1,value:null};if(r.sel){if(!o.find(e=>selectOptionByText(r.sel,e)))return{ok:!1,value:readGroupValue(r.container)}}else if(r.ms){let e=!1;for(const t of o)if(await clickOverlayOptionExact(r.ms,t,8e3)){e=!0;break}if(!e)return{ok:!1,value:readGroupValue(r.container)}}else r.el&&(clickEl(r.el),await sleep(450));let a=readGroupValue(r.container);if(null==a&&r.el){const e=r.el.querySelector('input[type="radio"], input[type="checkbox"]');(e&&e.checked||"true"===r.el.getAttribute("aria-checked")||r.el.classList.contains("mat-radio-checked")||r.el.classList.contains("mat-mdc-radio-checked"))&&(a=norm(r.el.innerText||r.el.textContent))}return{ok:null!=a&&o.some(e=>exactTextEq(a,e)),value:a}}async function goSection(e,t=15e3){let n=await clickByText(e,t,'[role="tab"], [role="navigation"] a, [role="navigation"] button, nav a, nav button, aside a, aside button, [class*="sidenav"] a, [class*="side-nav"] a');return n||(n=await clickByText(e,4e3)),n&&await sleep(1200),n&&await dismissInfoDialogs(),n}function btnDisabled(e){return!!e&&(e.disabled||"true"===e.getAttribute("aria-disabled")||e.classList.contains("mat-button-disabled")||e.classList.contains("mat-mdc-button-disabled"))}function findSaveButton(){const e=[...document.querySelectorAll('button, [role="button"]')].filter(isVisible),t=t=>e.filter(e=>exactTextEq(e.innerText||e.textContent,t));for(const e of["Save & continue","Save changes","Save"]){const n=t(e),o=n.find(e=>!btnDisabled(e));if(o)return o;if(n.length)return n[0]}return null}async function saveAndWait(e={}){let t=await waitFor(()=>findSaveButton(),12e3);if(!t)return{saved:!1,error:"No Save button found on this tab."};if(btnDisabled(t)){const e=await waitFor(()=>{const e=findSaveButton();return e&&!btnDisabled(e)?e:null},1e4,400);if(!e)return{saved:!1,error:"The Save button stayed disabled — a required field on this tab is likely empty or invalid."};t=e}clickEl(t);await dismissInfoDialogs();const n=await waitFor(()=>{const e=findErrorText();if(e)return{err:e};const t=[...document.querySelectorAll(".mat-snack-bar-container, mat-snack-bar-container, .mat-mdc-snack-bar-container")].filter(isVisible)[0];if(t){const e=norm(t.innerText||t.textContent);if(/error|failed|invalid/i.test(e))return{err:e};if(/saved|updated|success/i.test(e))return{ok:!0}}return null},6e3,400);if(n&&n.err)return{saved:!1,error:n.err};if(await sleep(800),"function"==typeof e.verify){let t=!1;try{t=await e.verify()}catch(e){t=!1}if(!t)return{saved:!1,error:"Save was clicked, but the values did not persist when re-read."}}return{saved:!0}}function findErrorText(){const e=findByText(["is required","Must be","Invalid","error"],'.mat-error, [role="alert"], .error, mat-error');if(e&&isVisible(e)){const t=norm(e.innerText||e.textContent);if(t&&t.length<200)return t}return null}function visibleDialogText(){const e=[...document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container, .mat-snack-bar-container, mat-snack-bar-container')].filter(isVisible)[0];if(!e)return null;const t=norm(e.innerText||e.textContent);return t?t.slice(0,200):null}function detectBlocker(){const e=location.href;if(/accounts\.google\.com/.test(e))return"Google sign-in page reached — the extension cannot enter your password. Sign in to the Partner Center in this Chrome profile, then press Run again.";if(document.querySelector('input[type="password"]')&&isVisible(document.querySelector('input[type="password"]'))&&/Enter your password|Welcome|Sign in/i.test(pageText()))return"Google is asking for your password / 2FA — sign-in must be done by you. Complete it in this Chrome profile, then press Run again.";if(document.querySelector('iframe[src*="recaptcha"], iframe[title*="reCAPTCHA" i]')||/not a robot/i.test(pageText()))return"A CAPTCHA appeared. Solve it manually in the browser, then press Run again.";if(/\/(payments|tax)\b/.test(e))return"A tax/payment page opened. The extension never touches tax, payment or identity information — handle that yourself in the Partner Center.";const t=document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container');for(const e of t){if(!isVisible(e))continue;const t=norm(e.innerText||e.textContent);if(/tax information|payment profile|verify your identity|identity verification|bank account/i.test(t))return'A tax/payment/identity prompt appeared: "'+t.slice(0,160)+'" — this must be handled by you; the extension will not touch it.'}return null}function stopErr(e){const t=new Error(e);return t.stopCondition=!0,t}function base64ToFile(e,t,n){const o=atob(e),r=new Uint8Array(o.length);for(let e=0;e<o.length;e++)r[e]=o.charCodeAt(e);return new File([new Blob([r],{type:n||"application/octet-stream"})],t,{type:n||"application/octet-stream"})}function editorGGKEY(){const e=location.href.match(/GGKEY[:%3A\s]*([A-Z0-9]{6,})/i);if(e)return"GGKEY:"+e[1].toUpperCase();const t=document.querySelector('header, [class*="book-header"], [class*="title-header"], [class*="book-title"]');if(t){const e=norm(t.innerText||t.textContent).match(/GGKEY[:\s]*([A-Z0-9]{6,})/i);if(e)return"GGKEY:"+e[1].toUpperCase()}return null}function extractGGKEY(){const e=editorGGKEY();if(e)return e;const t=pageText().match(/GGKEY[:\s]*([A-Z0-9]{6,})/i);return t?"GGKEY:"+t[1].toUpperCase():null}function isoToConsoleDate(e){const t=/^(\d{4})-(\d{2})-(\d{2})$/.exec(e||"");return t?`${t[2]}/${t[3]}/${t[1]}`:e}function dateValueToIso(e){const t=norm(e);if(!t)return null;const n=t.match(/^(\d{4})-(\d{2})-(\d{2})/);if(n)return n[0];const o=new Date(t);return isNaN(o.getTime())?null:formatISODate(o)}async function setDateField(e,t){const n=fieldByLabel(e);return!(!n||!t)&&(await typeInto(n,isoToConsoleDate(t)),n.dispatchEvent(new KeyboardEvent("keydown",{bubbles:!0,key:"Escape"})),document.dispatchEvent(new KeyboardEvent("keydown",{bubbles:!0,key:"Escape"})),await sleep(300),dateValueToIso(n.value)===t||(await typeInto(n,t),await sleep(300),dateValueToIso(n.value)===t))}function dateFieldEquals(e,t){return!(!e||!t)&&dateValueToIso(e.value)===t}async function setRichText(e,t){if(!e||null==t)return!1;const n=norm(t).slice(0,40);if("INPUT"===e.tagName||"TEXTAREA"===e.tagName)return await typeInto(e,t),norm(e.value).includes(n);const o=e.isContentEditable?e:e.querySelector('[contenteditable="true"], [contenteditable=""]')||e;o.focus();let r=!1;try{document.execCommand("selectAll",!1,null),r=document.execCommand("insertText",!1,t)}catch(e){r=!1}if(!r)try{o.innerText=t}catch(e){o.textContent=t}return o.dispatchEvent(new Event("input",{bubbles:!0})),o.dispatchEvent(new Event("change",{bubbles:!0})),await sleep(300),norm(o.innerText||o.textContent).includes(n)}const stageLog=[];function L(e,t="info"){stageLog.push({text:e,level:t})}function onCreatePage(){if(/book\/create/.test(location.href))return!0;if(findByText(["Select a sell option"]).length)return!0;return[...document.querySelectorAll("h1, h2")].filter(isVisible).some(e=>"add a book"===norm(e.innerText||e.textContent).toLowerCase())}function catalogAddBookBtn(){return findByText(["Add book"],'button, a, [role="button"]')[0]||null}function onCatalogPage(){return!!catalogAddBookBtn()||/book catalog/i.test(pageText().slice(0,4e3))}async function waitForCreateOrCatalog(e=3e4){return waitFor(()=>onCreatePage()?"create":onCatalogPage()?"catalog":null,e)}function findSaveContinueBtn(){return[...document.querySelectorAll('button, [role="button"]')].filter(isVisible).find(e=>/^save\s*(&|and)\s*continue$/i.test(norm(e.innerText||e.textContent))&&!e.disabled&&!e.hasAttribute("disabled")&&"true"!==e.getAttribute("aria-disabled")&&!e.classList.contains("mat-button-disabled")&&!e.classList.contains("mat-mdc-button-disabled"))||null}async function tryAdoptExistingBook(e){try{const t=[...document.querySelectorAll('input[type="search"], input[placeholder*="search" i], input[aria-label*="search" i]')].filter(isVisible)[0];if(!t)return L("Create: no catalog search box found — skipping the existing-book check."),null;await typeIntoSearch(t,e),t.dispatchEvent(new KeyboardEvent("keydown",{bubbles:!0,key:"Enter"})),await sleep(1500);const n=await waitFor(()=>findByText([e],'a, [role="link"], td, [role="cell"], span, div').find(t=>{return n=t.innerText||t.textContent,o=e,norm(n).toLowerCase()===norm(o).toLowerCase();var n,o})||null,8e3);if(!n){L(`Create: no existing book titled "${e}" found in the catalog — creating a new one.`);try{setNativeValue(t,""),t.dispatchEvent(new KeyboardEvent("keydown",{bubbles:!0,key:"Enter"})),await sleep(800)}catch(e){}return null}clickEl(n.closest("a")||n);const o=await waitFor(()=>editorGGKEY()||extractGGKEY(),15e3);return o||(L("Create: opened a catalog match but could not read its GGKEY — returning to the catalog.","error"),await clickByText(["Book Catalog","Catalog"],8e3),await sleep(1200),null)}catch(e){return L("Create: the catalog existing-book check could not be completed — continuing to create.","error"),null}}async function stageCreate(e){const t=e&&e.meta||{};if(e&&e.ggkey)return L(`Create: this job already created ${e.ggkey} in a previous attempt — resuming with it, not creating a duplicate.`),{ggkey:e.ggkey,bookUrl:e.bookUrl||location.href};if(e&&(e._attempt||1)>=2){const e=editorGGKEY();if(e)return L(`Create: a previous attempt already created ${e} (its editor is open) — resuming with it, not creating a duplicate.`),{ggkey:e,bookUrl:location.href}}let n=await waitForCreateOrCatalog(3e4);if(n||(L("Create: neither the create page nor the catalog detected yet — trying the Book Catalog link.","info"),await clickByText(["Book Catalog","Catalog"],8e3),await sleep(1500),n=await waitForCreateOrCatalog(2e4)),n||/play\.google\.com\/books\/publish/.test(location.href)||(location.href="https://play.google.com/books/publish",n=await waitForCreateOrCatalog(3e4)),!n)throw new Error('Create: could not reach the Book Catalog or the "Add a book" page — neither an "Add book" button nor a "Select a sell option" control appeared.');const o=detectBlocker();if(o)throw stopErr(o);if("catalog"===n&&t.title){const e=await tryAdoptExistingBook(t.title);if(e)return L(`Create: found existing book "${t.title}" (${e}) in the catalog — resuming it instead of creating a duplicate.`),{ggkey:e,bookUrl:location.href};const o=await waitForCreateOrCatalog(15e3);o&&(n=o)}if("catalog"===n){L('Create: on the Book Catalog — clicking "Add book".');let e=await waitFor(()=>catalogAddBookBtn(),12e3);if(e||(await clickByText(["Book Catalog","Catalog"],8e3),await sleep(1500),e=await waitFor(()=>catalogAddBookBtn(),15e3)),!e)throw new Error('Create: could not find the "Add book" button on the Book Catalog page.');clickEl(e);if(!await waitFor(()=>onCreatePage(),2e4))throw new Error('Create: clicked "Add book" but the create page (with the "Select a sell option" control) did not appear.');L('Create: "Add a book" page is open.')}else L('Create: already on the "Add a book" page — skipping the catalog "Add book" click.');const r=await pickSelectOption(["Select a sell option","Sell option"],"Sell ebook on Google Play",2e4);if(!r.ok)throw new Error('Create: could not set the sell option to "Sell ebook on Google Play" (the control shows "'+(r.value||"nothing")+'").');L('Create: sell option verified as "Sell ebook on Google Play".'),await sleep(400);const a=await waitFor(()=>fieldByLabel(["Select a book ID","Book ID"])||comboboxByPlaceholder(["Select a book ID"]),15e3);if(!a)throw new Error('Create: the required "Select a book ID" control never appeared after choosing the sell option.');const i=await operateSelect(a,"Get a Google book ID (GGKEY)",12e3);if(!i.ok)throw new Error('Create: could not set the book ID to "Get a Google book ID (GGKEY)" (the control shows "'+(i.value||"nothing")+'").');L('Create: book ID verified as "Get a Google book ID (GGKEY)".'),await sleep(400);const s=detectBlocker();if(s)throw stopErr(s);const l=await waitFor(()=>findSaveContinueBtn(),3e4);if(!l)throw new Error('Create: the "Save & Continue" button never became enabled — the sell option / book ID selections may be incomplete.');clickEl(l),await sleep(1500),L('Create: clicked "Save & Continue".');const c=await waitFor(()=>extractGGKEY(),3e4);if(!c){const e=findErrorText()||visibleDialogText();throw new Error("Create: the book was submitted but its GGKEY could not be read from the resulting page/URL."+(e?' The page says: "'+e+'"':""))}return L(`Created new book ${c}.`),{ggkey:c,bookUrl:location.href}}async function stageAbout(e){await goSection(["About the book","About this book","Book details"]);const t=detectBlocker();if(t)throw stopErr(t);const n=async(e,t,n)=>{if(null==t||""===t)return;const o=fieldByLabel(e);o?await typeInto(o,String(t)):L(`About: field not found for ${n} — skipped (check on first live run).`,"error")},o=fieldByLabel(["Title"]);if(!o)throw new Error("About: the Title field was not found.");if(await typeInto(o,e.title),e.subtitle){let t=fieldByLabel(["Subtitle"]);if(!t){const e=findByText(["Add a subtitle"],'button, [role="button"]')[0];e&&(clickEl(e),t=await waitFor(()=>fieldByLabel(["Subtitle"]),8e3))}t?await typeInto(t,e.subtitle):L('About: the Subtitle field could not be revealed (the "Add a subtitle" button was not found) — subtitle skipped.',"error")}const r=fieldByLabel(["Description"]);if(!r)throw new Error("About: description field not found.");await setRichText(r,e.description)||L("About: the description was entered but could not be verified in the field.","error");const a=e.language||"English",i=fieldByLabel(["Language"]);if(i)if("SELECT"===i.tagName)selectOptionByText(i,a)||L(`About: language option "${a}" not found in the Language select.`,"error");else{const e=await operateSelect(i,a,1e4);e.ok||L(`About: language could not be verified as "${a}" (field shows "${e.value||"—"}").`,"error")}await n(["Publisher"],e.publisher||e.author,"Publisher");(await chooseInGroup(["Format","Book format"],["Ebook","E-book"],5e3)).ok||L("About: format control not set to Ebook (it may not exist or may already be fixed).","error"),await n(["Number of pages","Page count","Pages"],e.pages,"Page count");!await setDateField(["Publication date"],e.publicationDate)&&e.publicationDate&&L("About: the publication date could not be verified in its field.","error");!await setDateField(["Release date","On-sale date"],e.releaseDate)&&e.releaseDate&&L("About: the release date could not be verified in its field.","error"),await n(["Minimum age","Min age"],e.minAge,"Minimum age");(await chooseInGroup(["mature"],["No"],8e3)).ok||L('About: mature-audiences control not verified as "No" — check it on the Review page.',"error");const s=await saveAndWait({verify:()=>{const t=fieldByLabel(["Title"]);if(t&&norm(t.value)!==norm(e.title))return!1;const n=fieldByLabel(["Subtitle"]);if(n&&e.subtitle){if(norm("INPUT"===n.tagName||"TEXTAREA"===n.tagName?n.value:n.innerText||n.textContent)!==norm(e.subtitle))return!1}const o=fieldByLabel(["Number of pages","Page count","Pages"]);if(o&&e.pages&&parseInt(o.value,10)!==Number(e.pages))return!1;const r=fieldByLabel(["Description"]);if(r&&e.description){const t="INPUT"===r.tagName||"TEXTAREA"===r.tagName?r.value:r.innerText||r.textContent;if(t&&!norm(t).includes(norm(e.description).slice(0,40)))return!1}return!0}});if(!s.saved)throw new Error("About tab save failed"+(s.error?": "+s.error:" (no Save button found or a validation error is showing)."));return L(`About saved (release date ${e.releaseDate}, publication ${e.publicationDate}).`),{bookUrl:location.href}}function genreChips(){return[...document.querySelectorAll('mat-chip, .mat-chip, .mat-mdc-chip, [class*="chip"], [class*="tag"]')].filter(isVisible).map(e=>norm(e.innerText||e.textContent)).filter(Boolean)}function genreSegments(e){return e.split("/").map(e=>e.trim()).filter(Boolean)}function genreChipFull(e){const t=genreSegments(e).map(e=>e.toLowerCase());return genreChips().some(e=>{const n=e.toLowerCase();return t.every(e=>n.includes(e))})}function genrePresent(e){if(genreChipFull(e))return!0;const t=genreSegments(e),n=(t[0]||"").toLowerCase(),o=(t[t.length-1]||"").toLowerCase();return genreChips().some(e=>{const t=e.toLowerCase();return n&&o&&t.includes(n)&&t.includes(o)})}function genreOptionScore(e,t){const n=norm(e).replace(/[›>»|]/g,"/").toLowerCase();if(!n||n.length>220)return-1;const o=t.join(" / ").toLowerCase();if(n===o)return 1e3-n.length;return t.filter(e=>n.includes(e.toLowerCase())).length===t.length?500-n.length:-1}function stripGenreCode(e){return norm(e).replace(/^\([A-Za-z]{3}\d{3,}\)\s*/,"")}function genrePathSegments(e){return norm(e).replace(/[›>»|]/g,"/").split("/").map(e=>norm(e).toLowerCase()).filter(Boolean)}function genreOptionMatchesGenre(e,t){const n=genrePathSegments(stripGenreCode(e)),o=genrePathSegments(t);return!(!n.length||n.length!==o.length)&&n.every((e,t)=>e===o[t])}const GENRE_COMBO_LABEL="enter a genre name or code";function genreComboboxes(){const e=[],t=new Set,n=n=>{n&&!t.has(n)&&(t.add(n),e.push(n))};for(const e of document.querySelectorAll("label, .mat-form-field-label, mat-label, legend")){if(cleanLabel(e.innerText||e.textContent)!==GENRE_COMBO_LABEL)continue;let t=null;if(e.htmlFor&&(t=document.getElementById(e.htmlFor)),t||(t=e.querySelector(CONTROL_SEL)),!t){const n=e.closest(".mat-form-field, mat-form-field, .form-field, fieldset");n&&(t=n.querySelector(CONTROL_SEL))}n(t)}for(const e of document.querySelectorAll('input, [role="combobox"]')){if(!isVisible(e))continue;norm((e.getAttribute("aria-label")||"")+" "+(e.getAttribute("placeholder")||"")).toLowerCase().includes(GENRE_COMBO_LABEL)&&n(e)}return e}function genreComboValue(e){return e?"INPUT"===e.tagName||"TEXTAREA"===e.tagName?norm(e.value):norm(readSelectDisplay(e))||"":""}function genreAlreadyAdded(e){return!!genrePresent(e)||genreComboboxes().some(t=>genreOptionMatchesGenre(genreComboValue(t),e))}async function ensureEmptyGenreCombo(){const e=()=>genreComboboxes().find(e=>!genreComboValue(e))||null;let t=e();if(t)return t;const n=findByText(["Add a genre"],'button, [role="button"]')[0];if(!n)return null;const o=genreComboboxes().length;return clickEl(n),t=await waitFor(()=>{const t=e();if(t)return t;const n=genreComboboxes();return n.length>o?n[n.length-1]:null},8e3),t}function genreVisibleOptions(){const e=[],t=new Set;for(const n of document.querySelectorAll('[role="option"], mat-option, .mat-option, .mat-mdc-option'))isVisible(n)&&!t.has(n)&&(t.add(n),e.push(n));return e}async function genreTypeQuery(e,t){let n=null;if(n="INPUT"===e.tagName||"TEXTAREA"===e.tagName?e:e.querySelector("input, textarea"),n||(clickEl(e),await sleep(600),n=document.querySelector('.cdk-overlay-pane input, [role="listbox"] input, mat-autocomplete-panel input')),n)return await typeIntoSearch(n,t),n;e.focus();for(const n of String(t))e.dispatchEvent(new KeyboardEvent("keydown",{bubbles:!0,key:n})),e.dispatchEvent(new KeyboardEvent("keyup",{bubbles:!0,key:n})),await sleep(25);return await sleep(300),e}async function stageGenres(e){await goSection(["Genres","Categories"]);const t=detectBlocker();if(t)throw stopErr(t);for(const t of e.genres){if(genreAlreadyAdded(t)){L(`Genre already present, skipping: ${t}`);continue}const e=await ensureEmptyGenreCombo();if(!e)throw new Error('Genres: no empty genre row was available and no "Add a genre" button was found.');const n=genreSegments(t),o=[],r=e=>{const t=norm(e);t&&!o.includes(t)&&o.push(t)};n.length>=3?r(n[1]):2===n.length&&r(n[0]),r(n[n.length-1]),r(t);let a=!1;const i=[];for(const n of o){await genreTypeQuery(e,n);const o=await waitFor(()=>{const e=genreVisibleOptions();for(const t of e){const e=norm(t.innerText||t.textContent);e&&!i.includes(e)&&i.push(e)}return e.find(e=>genreOptionMatchesGenre(e.innerText||e.textContent,t))||null},8e3);if(!o)continue;clickEl(o);if(await waitFor(()=>{const o=genreComboValue(e);if(!o)return null;if(genreOptionMatchesGenre(o,t))return!0;if(/^\([A-Za-z]{3}\d{3,}\)/.test(o))return!0;return!(genreVisibleOptions().length>0)&&o.toLowerCase()!==n.toLowerCase()||null},8e3,400)){a=!0;break}await sleep(500)}if(!a)throw new Error(`Genres: could not add "${t}" — no suggestion exactly matched the full BISAC path. Suggestions seen: ${i.slice(0,12).join(" | ")||"(none)"}`);L(`Genre added: ${t}`),await sleep(400)}const n=await saveAndWait({verify:()=>{const t=genreComboboxes(),n=document.querySelector("mat-chip, .mat-chip, .mat-mdc-chip");if(!t.length&&!n)return!0;if(e.genres.filter(e=>genrePresent(e)||t.some(t=>genreOptionMatchesGenre(genreComboValue(t),e))).length===e.genres.length)return!0;return t.filter(e=>genreComboValue(e)).length===e.genres.length}});if(!n.saved)throw new Error("Genres save failed"+(n.error?": "+n.error:"."));return{bookUrl:location.href}}function contributorRow(e){let t=e;for(let e=0;e<7&&t&&t!==document.body&&(t=t.parentElement,t);e++)if(t.querySelector('select, mat-select, [role="combobox"]'))return t;return e.closest("div, fieldset, form")||document.body}
/* --- v9.2 contributors fix (patched onto the v9.1 build): the name
 * field's floating label can carry the value ("Name MonJuruL"), which
 * defeats exact label matching, and the row renders lazily. --- */
function contributorBioField() {
  const byLabel = fieldByLabel(['Contributor biography', 'Biography', 'Bio', 'About the author']);
  if (byLabel) return byLabel;
  const editors = [...document.querySelectorAll('[contenteditable="true"], textarea')].filter(isVisible);
  return editors.find((e) => /contributor biography/i.test(e.getAttribute('aria-label') || '')) || null;
}
function contributorNameField() {
  const byLabel = fieldByLabel(['Name', 'Contributor name']);
  if (byLabel && byLabel.tagName === 'INPUT') return byLabel;
  const textInputs = () => [...document.querySelectorAll(
    'input:not([type="hidden"]):not([type="file"]):not([type="checkbox"]):not([type="radio"]):not([type="search"])')]
    .filter(isVisible);
  const byAttr = textInputs().find((i) =>
    /^\s*name\s*$/i.test(i.getAttribute('aria-label') || '') ||
    /^\s*name\s*$/i.test(i.getAttribute('placeholder') || ''));
  if (byAttr) return byAttr;
  const labels = [...document.querySelectorAll('label, mat-label, .mat-form-field-label, .mdc-floating-label, .mat-mdc-floating-label')];
  for (const lab of labels) {
    const t = cleanLabel(lab.innerText || lab.textContent);
    if (t === 'name' || t.startsWith('name ')) {
      if (lab.htmlFor) {
        const c = document.getElementById(lab.htmlFor);
        if (c && c.tagName === 'INPUT') return c;
      }
      const ff = lab.closest('.mat-form-field, mat-form-field, .mat-mdc-form-field, fieldset') || lab.parentElement;
      const c = ff && ff.querySelector('input:not([type="hidden"]):not([type="file"])');
      if (c) return c;
    }
  }
  const bio = contributorBioField();
  if (bio) {
    let node = bio;
    for (let up = 0; up < 8 && node && node !== document.body; up++) {
      node = node.parentElement;
      if (!node) break;
      if (node.querySelector('[role="combobox"], mat-select, select')) {
        const cand = textInputs().find((i) => node.contains(i) && i !== bio);
        if (cand) return cand;
      }
    }
  }
  return null;
}

/* --- v9.3: dismiss the console's informational "Pre-order content
 * requirements" dialog (shown when the release date is within 7 days;
 * it MODALS the page and stalls the run until "Close" is clicked).
 * Only this known-benign dialog is dismissed; tax/payment/identity
 * dialogs are never touched (they are stop conditions). --- */
async function dismissInfoDialogs() {
  const dialogs = [...document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container')].filter(isVisible);
  for (const d of dialogs) {
    const t = norm(d.innerText || d.textContent);
    if (!t) continue;
    if (/tax information|payment profile|verify your identity|identity verification|bank account/i.test(t)) continue;
    if (/pre-order/i.test(t) && /complete content|content requirements/i.test(t)) {
      const btn = [...d.querySelectorAll('button')].filter(isVisible)
        .find((b) => /^(close|ok|got it|dismiss)$/i.test(norm(b.innerText || b.textContent)));
      if (btn) {
        clickEl(btn);
        L('Dismissed the informational dialog: "' + t.slice(0, 70) + '" (clicked Close).');
        await sleep(600);
        return true;
      }
    }
  }
  return false;
}
async function stageContributors(e){await goSection(["Contributors","Authors"]);const t=detectBlocker();if(t)throw stopErr(t);let n=await waitFor(()=>contributorNameField(),2e4,500);if(n||(await clickByText(["Add a contributor","Add contributor","Add author"],8e3),await sleep(1e3),n=await waitFor(()=>contributorNameField(),12e3,500)),!n)throw new Error("Contributors: name field not found (tried label, aria-label, placeholder, floating-label and row-structure lookups).");norm(n.value)===norm(e.author)?L("Contributors: the author row is already present — not duplicating it."):await typeInto(n,e.author);const o=contributorRow(n),r=scopedControlForLabel(o,"Role")||o.querySelector('select, mat-select, [role="combobox"]');if(r){const e=await operateSelect(r,"Author",1e4);e.ok||L(`Contributors: the role could not be verified as "Author" (the control shows "${e.value||"—"}").`,"error")}else{(await chooseInGroup(["Role"],["Author"],5e3)).ok||L("Contributors: role control not found — check the role on the Review page.","error")}const a=contributorBioField()||(o?o.querySelector('[contenteditable="true"], textarea'):null);if(a){await setRichText(a,e.biography)||L("Contributors: the biography was entered but could not be verified in the field.","error")}else L("Contributors: biography field not found — bio not entered.","error");const i=await saveAndWait({verify:()=>{const t=contributorNameField();return!t||norm(t.value)===norm(e.author)}});if(!i.saved)throw new Error("Contributors save failed"+(i.error?": "+i.error:"."));return L(`Contributor saved: ${e.author} (Author).`),{bookUrl:location.href}}async function stageSettings(e){await goSection(["Settings"]);const t=detectBlocker();if(t)throw stopErr(t);const n=await chooseInGroup(["DRM","encryption"],["No (recommended)","No"],1e4);if(!n.ok)throw new Error('Settings: DRM could not be verified as "No" (the control shows "'+(n.value||"nothing")+'").');const o=await chooseInGroup(["Preview","Google Books preview"],["20% (recommended)","20%"],1e4);if(!o.ok)throw new Error('Settings: preview limit could not be verified as "20%" (the control shows "'+(o.value||"nothing")+'").');let r=await chooseInGroup(["Copy","paste","Copy/paste"],["0%"],1e4);if(!r.ok){const e=fieldByLabel(["Copy","Copy and paste"]);if(e){await typeInto(e,"0");const t=norm(e.value);"0"!==t&&"0%"!==t||(r={ok:!0,value:t})}}if(!r.ok)throw new Error('Settings: copy/paste limit could not be verified as "0%" (the control shows "'+(r.value||"nothing")+'").');const a=await saveAndWait({verify:()=>{const e=[["No",readGroupValue(findGroupContainer(["DRM","encryption"]))],["20%",readGroupValue(findGroupContainer(["Preview","Google Books preview"]))],["0%",readGroupValue(findGroupContainer(["Copy","paste","Copy/paste"]))]];return!e.filter(([,e])=>null!=e).length||e.every(([e,t])=>null!=t&&exactTextEq(t,e))}});if(!a.saved)throw new Error("Settings save failed"+(a.error?": "+a.error:"."));return L("Settings saved: DRM No / Preview 20% / Copy-paste 0% (all three read back and verified)."),{bookUrl:location.href}}function assignFileToInput(e,t){const n=new DataTransfer;n.items.add(t),e.files=n.files,e.dispatchEvent(new Event("input",{bubbles:!0})),e.dispatchEvent(new Event("change",{bubbles:!0}))}function inputsByKind(){const e=[...document.querySelectorAll('input[type="file"]')],t=[],n=[],o=e=>{let t=e;for(let e=0;e<8&&t&&t!==document.body&&(t=t.parentElement,t);e++){const e=t.querySelector(':scope > h1, :scope > h2, :scope > h3, :scope > h4, :scope > [class*="heading"], :scope > [class*="title"]');if(e)return norm(e.innerText||e.textContent).toLowerCase()}return""};for(const r of e){const e=(r.getAttribute("accept")||"").toLowerCase(),a=o(r);let i="",s=r;for(let e=0;e<5&&s;e++)s=s.parentElement,s&&(i+=" "+norm(s.innerText||"").toLowerCase().slice(0,160));/image|jpg|jpeg|png/.test(e)||/cover/.test(a)?n.push(r):/epub|pdf/.test(e)||/book file|ebook|content file/.test(a)?t.push(r):/cover/.test(i)&&!/epub|pdf/.test(e)?n.push(r):t.push(r)}return{epub:t,cover:n,all:e}}async function revealFileInputs(){return!!document.querySelector('input[type="file"]')||(await clickByText(["Upload file","Upload new file","Upload"],8e3),!!await waitFor(()=>document.querySelector('input[type="file"]'),8e3))}function fileRows(){return[...document.querySelectorAll('tr, [role="row"]')].filter(isVisible).map(e=>({el:e,text:norm(e.innerText||e.textContent)})).filter(e=>e.text)}function currentEpubRow(e){let t=fileRows().filter(e=>/\.epub/i.test(e.text));if(!t.length)return null;if(e){const n=String(e).replace("GGKEY:",""),o=t.filter(e=>e.text.includes(n));o.length&&(t=o)}const n=t.map(e=>{const t=e.text.match(/Version\s+(\d+)/i),n=e.text.match(/(\d{4}-\d{2}-\d{2}[ T]\d{1,2}:\d{2}(?::\d{2})?\s*(?:[AP]M)?)/i);return{r:e,v:t?parseInt(t[1],10):0,t:n&&Date.parse(n[1])||0}});return n.sort((e,t)=>t.v-e.v||t.t-e.t),n[0].r}async function uploadOne(e,t,n=18e4){let o=inputsByKind(),r=("cover"===e?o.cover:o.epub)[0]||o.all[0];if(r||(await revealFileInputs(),o=inputsByKind(),r=("cover"===e?o.cover:o.epub)[0]||o.all[0]),!r)throw new Error(`Content: no file input found for the ${e} upload.`);const a=new Set(fileRows().map(e=>e.text)),i=/Successfully uploaded/i.test(pageText());assignFileToInput(r,t),r.files&&r.files[0]&&r.files[0].name===t.name||L(`Content: warning — after assigning, the ${e} input does not show "${t.name}".`,"error"),await sleep(1e3);const s=r.closest('[role="dialog"], .mat-dialog-container, mat-dialog-container');if(s){const e=[...s.querySelectorAll("button")].find(e=>isVisible(e)&&/^(upload|add|done|save)$/i.test(norm(e.innerText||e.textContent)));e&&clickEl(e)}const l=await waitFor(()=>{const t=fileRows();for(const e of t)if(!a.has(e.text)&&/failed|epubcheck|invalid|corrupt|not a valid/i.test(e.text))return{fail:e.text.slice(0,220)};return t.find(t=>{return!a.has(t.text)&&(n=t.text,"epub"===e?/\.epub/i.test(n):/frontcover|front cover/i.test(n)||/\.(jpe?g|png)/i.test(n)&&/cover/i.test(n));var n})?{ok:!0,via:"row"}:!i&&/Successfully uploaded/i.test(pageText())?{ok:!0,via:"banner"}:null},n,1200);if(!l){const e=findErrorText();throw new Error(`Content: "${t.name}" upload did not confirm`+(e?": "+e:" (timed out waiting for its file row / success banner)."))}if(l.fail)throw new Error(`Content: "${t.name}" upload failed — the console reports: "${l.fail}"`);L(`Uploaded ${t.name} — confirmed via its ${"row"===l.via?"file row":"success banner"}.`)}async function stageContent(){await goSection(["Content"]);const e=detectBlocker();if(e)throw stopErr(e);const{job:t}=await chrome.storage.local.get("job");if(!t||!t.files)throw new Error("Content: stored files are missing (job data not found).");const n=base64ToFile(t.files.epub.base64,t.files.epub.name,t.files.epub.type),o=base64ToFile(t.files.cover.base64,t.files.cover.name,t.files.cover.type);await uploadOne("epub",n),await sleep(1500),await uploadOne("cover",o),await sleep(1500);fileRows().find(e=>/front cover|frontcover/i.test(e.text))?L('Cover registered (a "front cover" row is shown on the Content tab).'):L('Cover upload confirmed, but "front cover" registration was not visible — check on Review.',"error");const r=currentEpubRow(t.ggkey);if(r){const e=r.text.match(/step\s+(\d)\s+of\s+6/i);e&&L(`EPUB processing started: completed step ${e[1]} of 6 (current version).`)}return{bookUrl:location.href}}function pricingNumberInput(){return document.querySelector('[role="dialog"] input[type="number"], [role="dialog"] input[inputmode="decimal"]')||[...document.querySelectorAll('input[type="number"], input[inputmode="decimal"]')].filter(isVisible)[0]||null}function pricingPageUrl(e){const t=e&&e.ggkey||editorGGKEY();if(!t)return null;return`${location.href.split("#")[0]}#book/${t}/jc=true/pricing`}async function stagePricing(e,t){const n=detectBlocker();if(n)throw stopErr(n);let o=fieldByLabel(["Amount","Price"])||pricingNumberInput();if(o||(await goSection(["Pricing","Price"],8e3),o=fieldByLabel(["Amount","Price"])||pricingNumberInput()),!o){const e=pricingPageUrl(t||{});e&&!location.href.startsWith(e)&&(L("Pricing: no Pricing nav item for this book — opening the pricing page directly by URL."),location.href=e,await sleep(2800));for(let e=0;e<3&&(!fieldByLabel(["Amount","Price"])&&!pricingNumberInput());e++){const e=[...document.querySelectorAll('a, button, [role="button"]')].filter(isVisible).find(e=>exactTextEq(e.innerText||e.textContent,"Retry"));if(!e)break;L('Pricing: the pricing page showed an error screen — clicking "Retry".'),clickEl(e),await sleep(2800)}o=await waitFor(()=>fieldByLabel(["Amount","Price"])||pricingNumberInput(),15e3)}if(o||(await clickByText(["Add price","Add a price","Set price","Add territory pricing","Edit"],8e3),await sleep(1e3),o=await waitFor(()=>fieldByLabel(["Amount","Price"])||pricingNumberInput(),12e3)),!o)throw new Error("Pricing: the amount field was not found — the price editor did not open.");await typeInto(o,String(e.price));const r=fieldByLabel(["Currency"]);if(r){const t=await operateSelect(r,e.currency||"USD",8e3);if(!t.ok)throw new Error(`Pricing: the currency could not be verified as ${e.currency||"USD"} (the control shows "${t.value||"—"}").`)}if(!(await chooseInGroup(["Territor","Countries","Sales territories"],["Worldwide","World","All countries"],8e3)).ok){await clickByText(["Worldwide","World","Select all"],4e3)&&L('Pricing: territories set via a "Worldwide" click (no read-back available) — verify on Review.',"error")}const a=await saveAndWait({verify:()=>{const t=fieldByLabel(["Amount","Price"]);return t?norm(t.value).includes(String(e.price)):pageText().includes(String(e.price))}});if(!a.saved)throw new Error("Pricing save failed"+(a.error?": "+a.error:"."));if(!pageText().includes(String(e.price)))throw new Error(`Pricing: saved, but "${e.price}" is not visible on the Pricing tab afterwards.`);return L(`Pricing saved: ${e.currency} ${e.price} (Worldwide).`),{bookUrl:location.href}}async function stageVerify(e,t){const n=detectBlocker();if(n)throw stopErr(n);const o=[],r=(e,t,n)=>{L(`Verify ${e}: ${t?"PASS":"FAIL"}`,t?"ok":"error"),t||o.push({name:e,critical:!!n})};await goSection(["Settings"]),await sleep(800);const a=readGroupValue(findGroupContainer(["DRM","encryption"]));r('Settings DRM = No (shows "'+(a||"—")+'")',!!a&&exactTextEq(a,"No"),!0);const i=readGroupValue(findGroupContainer(["Preview","Google Books preview"]));r('Settings Preview = 20% (shows "'+(i||"—")+'")',!!i&&exactTextEq(i,"20%"),!0);const s=readGroupValue(findGroupContainer(["Copy","paste","Copy/paste"]));r('Settings Copy/paste = 0% (shows "'+(s||"—")+'")',!!s&&exactTextEq(s,"0%"),!0),await goSection(["About the book","About this book","Book details"]),await sleep(800);const l=fieldByLabel(["Description"]),c=l?"INPUT"===l.tagName||"TEXTAREA"===l.tagName?l.value:l.innerText||l.textContent:"";r("Description present",!!c&&norm(c).includes(norm(e.description).slice(0,40)),!0);const u=fieldByLabel(["Publication date"]);r("Publication date "+e.publicationDate,dateFieldEquals(u,e.publicationDate),!1);const p=fieldByLabel(["Release date","On-sale date"]);r("Release date "+e.releaseDate,dateFieldEquals(p,e.releaseDate),!1);const d=fieldByLabel(["Number of pages","Page count","Pages"]);r("Page count "+e.pages,!!d&&parseInt(d.value,10)===Number(e.pages),!!d),await goSection(["Review"]),await sleep(1500);const b=pageText(),f=t&&t.ggkey||extractGGKEY()||"";r("Identifier ("+(f||"GGKEY")+")",!!f&&(b.includes(f.replace("GGKEY:",""))||b.includes(f)),!0),r("Title",b.includes(e.title),!0);const g=b.toLowerCase();r("Genres",e.genres.every(e=>{if(g.includes(e.toLowerCase()))return!0;const t=genreSegments(e);return t.length>1&&g.includes(t[0].toLowerCase())&&g.includes(t[t.length-1].toLowerCase())}),!1),r("Author",b.includes(e.author),!1),r("Publisher",b.includes(e.publisher||e.author),!1);let m=b.includes(String(e.price));if(!m){let n=await goSection(["Pricing","Price"],6e3);if(!n){const e=pricingPageUrl(t||{});e&&!location.href.startsWith(e)&&(location.href=e,await sleep(2500),n=!0)}if(n){await sleep(800);const t=fieldByLabel(["Amount","Price"]);m=!!t&&norm(t.value).includes(String(e.price))||pageText().includes(String(e.price)),m&&L("Verify Price: not shown on the Review page — confirmed on the Pricing page instead."),await goSection(["Review"],6e3),await sleep(800)}}r("Price "+e.currency+" "+e.price,m,!0);const h=findErrorText();h&&L("Review shows a message: "+h,"error");const w=o.filter(e=>e.critical).map(e=>e.name);if(w.length)throw new Error("Review verification failed for: "+w.join(", ")+" — stopping before publish. Full check results are in the log.");const y=o.map(e=>e.name);return y.length&&L("Verify: non-critical items failed ("+y.join(", ")+") — continuing, but check them after the run.","error"),{bookUrl:location.href,log:[]}}async function stageProcessingCheck(e){await goSection(["Content"]);const t=detectBlocker();if(t)throw stopErr(t);await sleep(1500);const n=currentEpubRow(e&&e.ggkey);if(!n)return{ok:!0,done:!1,step:0};const o=n.text;if(/Failed step|Fix ePub/i.test(o))return{ok:!1,processingError:!0,error:'EPUB processing failed on the CURRENT file — its row shows: "'+o.slice(0,220)+'"'};const r=o.match(/step\s+(\d)\s+of\s+6/i),a=r?parseInt(r[1],10):0;return 6===a?{ok:!0,done:!0,step:6}:{ok:!0,done:!1,step:a}}function findPublishButton(){const e=[...document.querySelectorAll('button, [role="button"]')].filter(isVisible);return e.find(e=>/publish to google play/i.test(norm(e.innerText||e.textContent)))||e.find(e=>exactTextEq(e.innerText||e.textContent,"Publish"))||e.find(e=>/sell on google play/i.test(norm(e.innerText||e.textContent)))||null}function exactStatusChip(){const e=["Live","Published","Preorder","Pre-order","Needs action","Needs approval","Draft","Removed","Not live","Deactivated"],t=[...document.querySelectorAll('span, div, td, [class*="status"], [class*="chip"], [class*="badge"]')].filter(isVisible);for(const n of e)if(t.some(e=>exactTextEq(e.innerText||e.textContent,n)))return n;return null}async function readOwnBookStatus(e,t){if(await goSection(["Summary","Book status","Status"],6e3)){await sleep(1200);const e=pageText();if(/your book is not live/i.test(e))return"Not live";if(/this book is deactivated/i.test(e))return"Deactivated";if(/your book is live/i.test(e))return"Live";const t=exactStatusChip();if(t)return t}await clickByText(["Book Catalog","Catalog","Back to catalog"],8e3),await sleep(2e3);const n=(t&&t.ggkey||"").replace("GGKEY:",""),o=[...document.querySelectorAll('tr, [role="row"], li, [class*="row"]')].filter(isVisible).map(e=>norm(e.innerText||e.textContent)).filter(t=>t&&(n&&t.includes(n)||e.title&&t.includes(e.title)));for(const e of o){const t=e.match(/\b(Live|Published|Preorder|Pre-order|Needs action|Needs approval|Draft|Removed|Not live|Deactivated)\b/i);if(t)return t[1]}return"unknown"}async function stagePublish(e,t){const n=detectBlocker();if(n)throw stopErr(n);if(await goSection(["Review","Publish"]),await sleep(1e3),await clickByText(["Ready to publish"],1e4)){await sleep(1200);const e=findErrorText();if(e)throw new Error('Publish: the "Ready to publish" checklist reports a problem: '+e)}const o=await waitFor(()=>findPublishButton(),2e4);if(!o)throw new Error("Publish: the publish button was not found on the Review/Publish tab.");clickEl(o),await sleep(2e3);const r=[...document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container')].find(e=>isVisible(e));if(r){const e=[...r.querySelectorAll("button")].find(e=>isVisible(e)&&/^(publish|sell|confirm|activate)$/i.test(norm(e.innerText||e.textContent)));e&&(clickEl(e),await sleep(2500))}const a=detectBlocker();if(a)throw stopErr(a);const i=await waitFor(()=>{const e=[...document.querySelectorAll(".mat-snack-bar-container, mat-snack-bar-container, .mat-mdc-snack-bar-container")].filter(isVisible)[0],t=e?norm(e.innerText||e.textContent):"";return/publish|live|success/i.test(t)?t:/your book is live|book was published|successfully published/i.test(pageText())?"banner":null},12e3,500);i&&L('Publish: confirmation seen ("'+String(i).slice(0,80)+'").');const s=await readOwnBookStatus(e,t||{});return L(`Publish clicked. This book's status: ${s}.`),{catalogStatus:s,bookUrl:location.href}}const STAGES={create:e=>stageCreate(e),about:e=>stageAbout(e.meta),genres:e=>stageGenres(e.meta),contributors:e=>stageContributors(e.meta),settings:e=>stageSettings(e.meta),content:()=>stageContent(),pricing:e=>stagePricing(e.meta,e),verify:e=>stageVerify(e.meta,e),processing_check:e=>stageProcessingCheck(e),publish:e=>stagePublish(e.meta,e)};let stageBusy=!1;async function runStage(e,t){stageLog.length=0;await dismissInfoDialogs();const n=detectBlocker();if(n)return{ok:!1,stopCondition:!0,error:n,log:stageLog.slice()};const o=STAGES[e];if(!o)return{ok:!1,error:"Unknown stage: "+e};let r=null;for(let e=1;e<=2;e++)try{await dismissInfoDialogs();const n=await o(Object.assign({},t,{_attempt:e}));return Object.assign({ok:!0},n||{},{log:stageLog.slice()})}catch(t){if(r=t,t&&t.stopCondition)return{ok:!1,stopCondition:!0,error:t.message,log:stageLog.slice()};e<2&&(await sleep(2500),stageLog.length=0)}return{ok:!1,error:r?r.message:"Stage failed",log:stageLog.slice()}}function parseMonthDate(e){const t=new Date(e);return isNaN(t.getTime())?null:t}function formatISODate(e){const t=e=>String(e).padStart(2,"0");return`${e.getFullYear()}-${t(e.getMonth()+1)}-${t(e.getDate())}`}const META_HEADINGS=["FULL DESCRIPTION","SHORT DESCRIPTION","DESCRIPTION","AUTHOR BIOGRAPHY","AUTHOR BIO","AUTHOR","PUBLICATION TYPE","PUBLICATION DATE","RELEASE DATE","SUGGESTED PRICE","PRICE SUGGESTION","PRICE","PAGE COUNT","WORD COUNT","PAGES","LENGTH","MINIMUM AGE","MAXIMUM AGE","CATEGORIES","KEYWORDS","TITLE","SUBTITLE","LANGUAGE","FORMAT","ISBN","FILES","CONTENTS","COPYRIGHT NOTE","TARGET READER","COMPARABLE TITLES"].sort((e,t)=>t.length-e.length);const PBU_VERBATIM_SECTIONS=["FULL DESCRIPTION","SHORT DESCRIPTION","DESCRIPTION","AUTHOR BIOGRAPHY","AUTHOR BIO"];const PBU_CURRENCY_CODES=["USD","EUR","GBP","CAD","AUD","NZD","INR","JPY","BRL","MXN","ZAR","SGD","CHF","SEK","NOK","DKK","PLN","TRY","RUB","KRW","HKD","IDR","MYR","PHP","THB","VND","AED","SAR","EGP","NGN","PKR","LKR","BDT","NPR","CNY","TWD","ILS","CZK","HUF","RON","CLP","COP","ARS","PEN","UAH","KES"];function matchMetaHeading(e,s){const t=String(e||"").trim();if(!t)return null;const n=t.toUpperCase();for(const e of META_HEADINGS){if(!n.startsWith(e))continue;if(s&&!t.startsWith(e))continue;const o=t.slice(e.length);if(""===o)return{name:e,inline:""};const r=o.match(/^\s*(?:\([^)]*\)\s*)?:\s*(.*)$/);if(r)return{name:e,inline:r[1].trim()};if(/^\s*\([^)]*\)\s*$/.test(o))return{name:e,inline:""}}return null}function parseMetadata(e){const t=String(e||"").replace(/\r\n?/g,"\n").split("\n"),n={title:"",subtitle:"",author:"",language:"English",pages:null,description:"",genres:[],price:null,currency:"USD",biography:"",releaseDate:null,publicationDate:null,minAge:18,maxAge:"",mature:"No",warnings:[]},o={};let r=null;for(const e of t){if(/^[-=]{3,}$/.test(e.trim()))continue;const t=matchMetaHeading(e,PBU_VERBATIM_SECTIONS.includes(r));t?(r=t.name,o[r]||(o[r]=[]),t.inline&&o[r].push(t.inline)):r&&o[r].push(e)}const a=e=>o[e]||[],i=e=>a(e).map(e=>e.trim()).filter(Boolean).join(" ");n.title=i("TITLE"),n.subtitle=i("SUBTITLE"),n.author=i("AUTHOR"),n.language=i("LANGUAGE")||"English",n.biography=i("AUTHOR BIOGRAPHY")||i("AUTHOR BIO");let s=i("PAGE COUNT").match(/(\d[\d,]*)/);if(s||(s=i("PAGES").match(/(\d[\d,]*)/)),s&&(n.pages=parseInt(s[1].replace(/,/g,""),10)),!n.pages){const e=i("LENGTH")||i("WORD COUNT"),t=e.match(/([\d,]+)\s*words/i)||e.match(/([\d,]{3,})/);if(t){const e=parseInt(t[1].replace(/,/g,""),10);e>0&&(n.pages=Math.round(e/250))}}const l=e=>{const t=[];let n=[];const o=()=>{n.length&&(t.push(n.join(" ")),n=[])};for(const r of e){const e=r.trim();e?/^[-•*]\s+/.test(e)?(o(),t.push(e)):n.push(e):o()}return o(),t.join("\n").trim()};n.description=l(a("FULL DESCRIPTION"))||l(a("DESCRIPTION"))||l(a("SHORT DESCRIPTION"));for(const e of a("CATEGORIES")){const t=e.trim();if(!t)continue;let o=null;const r=t.match(/^\d+\.\s*(.+)$/);if(r?o=r[1]:0===n.genres.length&&/^[A-Z][A-Z &]+\s*\//.test(t)&&(o=t),null!==o&&(o=o.replace(/^[A-Z]{3}\d{6}\b[\s—–:.-]*/,"").replace(/\s*\((?:BUS|SEL|FAM|REL|HEA|SOC)[A-Z0-9]*\)\s*$/i,"").trim(),o&&n.genres.push(o),n.genres.length>=3))break}const c=i("SUGGESTED PRICE")||i("PRICE SUGGESTION")||i("PRICE");if(c){const e=c.match(/ebook[^0-9]*([0-9]+(?:\.[0-9]{1,2})?)/i)||c.match(/(?:USD|\$)\s*([0-9]+(?:\.[0-9]{1,2})?)/i)||c.match(/([0-9]+(?:\.[0-9]{1,2})?)/);e&&(n.price=e[1]);const t=c.toUpperCase().match(/\b([A-Z]{3})\b/g)||[],o=t.find(e=>PBU_CURRENCY_CODES.includes(e));o?(n.currency=o,"USD"!==o&&n.warnings.push(`Price currency read as ${o} ${n.price||""} — the Partner Center currency list must contain ${o}, otherwise fix the price line or the run will stop at Pricing.`)):/\$/.test(c)||n.warnings.push(`No currency code found in the price line ("${c}") — assuming USD ${n.price||""}.`)}const MON="January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept|Sep|Oct|Nov|Dec",u=e=>{const t=String(e||"").trim();if(!t)return null;let o=t.match(/\b(\d{4})-(\d{1,2})-(\d{1,2})\b/);if(o)return parseMonthDate(`${o[1]}-${String(o[2]).padStart(2,"0")}-${String(o[3]).padStart(2,"0")}T00:00:00`);if(o=t.match(new RegExp("\\b("+MON+")\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s*(\\d{4})","i")),o)return parseMonthDate(`${o[1]} ${o[2]}, ${o[3]}`);if(o=t.match(new RegExp("\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+("+MON+")\\.?,?\\s*(\\d{4})","i")),o)return parseMonthDate(`${o[2]} ${o[1]}, ${o[3]}`);return null},pbuBlank=e=>{const t=String(e||"").trim();return/^\(.*\)$/.test(t)?"":t},relRaw=pbuBlank(i("RELEASE DATE")),pubRaw=pbuBlank(i("PUBLICATION DATE")),p=u(relRaw),d=u(pubRaw);relRaw&&!p&&n.warnings.push(`RELEASE DATE "${relRaw}" could not be read (use 2026-11-15 or November 15, 2026) — today + 4 days will be used instead.`),pubRaw&&!d&&n.warnings.push(`PUBLICATION DATE "${pubRaw}" could not be read (use 2026-11-15 or November 15, 2026) — today will be used instead.`),p&&(n.releaseDate=formatISODate(p)),d&&(n.publicationDate=formatISODate(d));const b=i("MINIMUM AGE");b&&/^\d+$/.test(b)&&(n.minAge=parseInt(b,10));const f=new Date;f.setHours(0,0,0,0),n.publicationDate||(n.publicationDate=formatISODate(f));const g=new Date(f);if(g.setDate(g.getDate()+4),n.releaseDate){const e=parseMonthDate(n.releaseDate+"T00:00:00");(!e||e<g)&&(n.warnings.push(`Release date ${n.releaseDate} is not more than 3 days away — using ${formatISODate(g)} instead (Partner Center rule).`),n.releaseDate=formatISODate(g))}else n.releaseDate=formatISODate(g);return n.publisher=n.author,n}function readFileAsText(e){return new Promise((t,n)=>{const o=new FileReader;o.onload=()=>t(String(o.result||"")),o.onerror=()=>n(o.error||new Error("Could not read "+e.name)),o.readAsText(e)})}function readFileAsBase64(e){return new Promise((t,n)=>{const o=new FileReader;o.onload=()=>{const e=String(o.result||""),n=e.indexOf(",");t(n>=0?e.slice(n+1):e)},o.onerror=()=>n(o.error||new Error("Could not read "+e.name)),o.readAsDataURL(e)})}
/* ================================================================== *
 * v5.0 — minimal, dependency-free ZIP reader.
 *
 * Parses the End Of Central Directory record + the central directory
 * (sizes and offsets are taken from the central directory, so entries
 * written without data descriptors work), and extracts entries with
 * compression method 0 (stored) or 8 (deflate, inflated through
 * DecompressionStream('deflate-raw')). Only standard web globals are
 * used (ArrayBuffer/DataView/TextDecoder/Blob/Response/
 * DecompressionStream), so this exact code also runs in Node for the
 * offline tests. Everything between the ZIPREADER markers is kept
 * free of chrome.* and DOM APIs for that reason.
 * ================================================================== */
/* ZIPREADER-BEGIN */function pbuZipReadEntries(e){if(!e||"number"!=typeof e.byteLength)throw new Error("ZIP: no data to read.");const t=e.byteLength;if(t<22)throw new Error("That file is too small to be a ZIP archive.");const n=new DataView(e);let o=-1;const r=Math.max(0,t-22-65535);for(let e=t-22;e>=r;e--)if(101010256===n.getUint32(e,!0)){o=e;break}if(o<0)throw new Error("Not a ZIP file (no end-of-central-directory record found).");const a=n.getUint16(o+10,!0),i=n.getUint32(o+16,!0),s=new TextDecoder("utf-8"),l=[];let c=i;for(let o=0;o<a&&!(c+46>t||33639248!==n.getUint32(c,!0));o++){const t=n.getUint16(c+28,!0),o=n.getUint16(c+30,!0),r=n.getUint16(c+32,!0);l.push({name:s.decode(new Uint8Array(e,c+46,t)),method:n.getUint16(c+10,!0),compSize:n.getUint32(c+20,!0),size:n.getUint32(c+24,!0),localOffset:n.getUint32(c+42,!0),_buf:e}),c+=46+t+o+r}if(!l.length)throw new Error("ZIP archive contains no readable entries.");return l}async function pbuZipExtract(e){const t=e._buf,n=new DataView(t),o=e.localOffset;if(o+30>n.byteLength||67324752!==n.getUint32(o,!0))throw new Error(`ZIP entry "${e.name}": bad local file header.`);const r=o+30+n.getUint16(o+26,!0)+n.getUint16(o+28,!0),a=new Uint8Array(t,r,e.compSize);if(0===e.method)return new Uint8Array(a);if(8===e.method){const e=new Blob([a]).stream().pipeThrough(new DecompressionStream("deflate-raw")),t=await new Response(e).arrayBuffer();return new Uint8Array(t)}throw new Error(`ZIP entry "${e.name}": unsupported compression method ${e.method} (only stored and deflate are supported).`)}function pbuZipDetectParts(e){const t=(e||[]).filter(e=>!e.name.endsWith("/")&&!e.name.startsWith("__MACOSX/")&&!/(^|\/)\.DS_Store$/.test(e.name)),n=e=>e.split("/").pop().toLowerCase(),o=e=>e.slice().sort((e,t)=>t.size-e.size)[0]||null,r=o(t.filter(e=>/\.epub$/i.test(e.name))),a=t.filter(e=>/\.(jpe?g|png)$/i.test(e.name)),i=o(a.filter(e=>n(e.name).includes("cover")))||o(a),s=t.filter(e=>/\.txt$/i.test(e.name)),l=o(s.filter(e=>n(e.name).includes("metadata")))||o(s),c=[];if(r||c.push("an EPUB (.epub file)"),l||c.push("a metadata .txt file"),c.length)throw new Error("ZIP detection failed — missing "+c.join(" and ")+" inside the ZIP.");return{epub:r,cover:i,meta:l}}
/* ZIPREADER-END */const FORM_STAGES=["create","about","genres","contributors","settings","content","pricing","verify"];async function csGetJob(){const{job:e}=await chrome.storage.local.get("job");return e||null}async function csSaveJob(e){await chrome.storage.local.set({job:e})}function csNowTime(){return(new Date).toLocaleTimeString([],{hour12:!1})}async function csLog(e,t="info"){let n=await csGetJob();n||(n={status:"idle",log:[]}),n.log=n.log||[],n.log.push({t:csNowTime(),level:t,text:e}),n.log.length>600&&(n.log=n.log.slice(-600)),await csSaveJob(n)}function csSetResumeFlag(e){try{e?sessionStorage.setItem("pbu-autoresume","1"):sessionStorage.removeItem("pbu-autoresume")}catch(e){}}function csResumeFlagSet(){try{return"1"===sessionStorage.getItem("pbu-autoresume")}catch(e){return!1}}function csNotify(e,t){chrome.runtime.sendMessage({type:"NOTIFY",title:e,message:t}).catch(()=>{})}function csNextStage(e){const t=FORM_STAGES.indexOf(e);return t>=0&&t<FORM_STAGES.length-1?FORM_STAGES[t+1]:"processing"}async function csFailJob(e){const t=await csGetJob();t&&(t.status="error",t.error=e,await csSaveJob(t)),csSetResumeFlag(!1),await csLog("✖ "+e,"error"),csNotify("Play Books upload failed",e)}async function csStopCondition(e){const t=await csGetJob();t&&(t.status="stop_condition",t.error=e,await csSaveJob(t)),csSetResumeFlag(!1),await csLog("⛔ Stopped — your action is needed: "+e,"error"),csNotify("Play Books: action needed",e)}let flowRunning=!1,flowNavDone=!1;async function startInPageFlow(e={}){if(flowRunning)return;let t=await csGetJob();if(t&&"running"===t.status){if(e.fromPanel&&!flowNavDone&&"create"!==t.stage&&t.bookUrl){const e=e=>String(e||"").split("#")[0];if(e(location.href)!==e(t.bookUrl))return flowNavDone=!0,csSetResumeFlag(!0),void(location.href=t.bookUrl)}flowRunning=!0,csSetResumeFlag(!0);try{for(t=await csGetJob();t&&"running"===t.status&&FORM_STAGES.includes(t.stage);){const e=t.stage;let n;await csLog(`Stage: ${e}`,"stage");try{n=await runStage(e,{meta:t.meta,ggkey:t.ggkey,bookUrl:t.bookUrl})}catch(e){n={ok:!1,error:"Internal stage error: "+(e&&e.message||e)}}if(t=await csGetJob(),!t||"running"!==t.status)return;if(!n||!n.ok){if(n&&n.log)for(const e of n.log)await csLog(e.text,e.level||"info");const t=n&&n.error||"Unknown error";return void(n&&n.stopCondition?await csStopCondition(t):await csFailJob(`Stage "${e}" failed: ${t}`))}if(n.ggkey&&!t.ggkey&&(t.ggkey=n.ggkey,await csLog(`New Book ID: ${n.ggkey}`,"ok"),t=await csGetJob()||t,t.ggkey!==n.ggkey&&(t.ggkey=n.ggkey)),n.bookUrl&&(t.bookUrl=n.bookUrl),n.log)for(const e of n.log)await csLog(e.text,e.level||"info");if(t=await csGetJob()||t,!t||"running"!==t.status)return;n.ggkey&&!t.ggkey&&(t.ggkey=n.ggkey),n.bookUrl&&(t.bookUrl=n.bookUrl),t.stage=csNextStage(e),t.status="processing"===t.stage?"processing":"running",await csSaveJob(t),await csLog(`Stage "${e}" complete.`,"ok"),t=await csGetJob()}if(t&&"processing"===t.stage&&"processing"===t.status){csSetResumeFlag(!1);try{await chrome.runtime.sendMessage({type:"ARM_POLL"})}catch(e){}}}finally{flowRunning=!1}}}const PBU_HOST_ID="pbu-panel-host";let pbuShadow=null,pbuPanelOpen=!1,pbuPanelReadyLogged=!1,pbuParsedMeta=null,pbuZipParts=null,pbuEls=null;const PBU_PANEL_CSS="\n:host { position: fixed; inset: 0; z-index: 2147483647; pointer-events: none;\n        font-family: system-ui, -apple-system, \"Segoe UI\", Roboto, sans-serif; }\n\n/* ---------- Floating button (compact) ---------- */\n#fab { pointer-events: auto; position: absolute; right: 16px; bottom: 16px;\n       padding: 8px 14px; font-size: 12px; font-weight: 700; color: #fff;\n       background: #000; border: 1px solid rgba(255,255,255,.22);\n       border-radius: 999px; cursor: pointer;\n       box-shadow: 0 6px 18px rgba(0,0,0,.6);\n       transition: transform .16s ease, border-color .16s ease; }\n#fab:hover { transform: translateY(-1px); border-color: rgba(168,85,247,.75); }\n#fab:active { transform: scale(.97); }\n\n/* ---------- Panel: small card, bottom-right, auto height ---------- */\n#panel { pointer-events: auto; position: absolute; right: 12px; bottom: 60px;\n         width: 300px; max-width: 92vw; max-height: 78vh; box-sizing: border-box;\n         background: #000; color: #e4e4e7;\n         border: 1px solid rgba(255,255,255,.14); border-radius: 14px;\n         box-shadow: 0 16px 40px rgba(0,0,0,.8);\n         padding: 11px 12px 10px; overflow-y: auto;\n         transform: translateY(10px) scale(.97); opacity: 0;\n         transition: transform .26s cubic-bezier(.22,.9,.3,1), opacity .2s ease;\n         display: flex; flex-direction: column; gap: 2px; }\n#panel.open { transform: none; opacity: 1; }\n#panel::-webkit-scrollbar { width: 6px; }\n#panel::-webkit-scrollbar-thumb { background: rgba(255,255,255,.18); border-radius: 999px; }\n#panel::-webkit-scrollbar-track { background: transparent; }\n\nheader { display: flex; align-items: center; gap: 6px;\n         padding-bottom: 8px; border-bottom: 1px solid rgba(255,255,255,.10); }\nh1 { font-size: 12.5px; font-weight: 700; margin: 0; color: #fff; flex: 1 1 auto;\n     white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }\n#versionLabel { flex: 0 0 auto; display: inline-block; margin-left: 0; padding: 1px 6px;\n                border-radius: 999px; vertical-align: middle; background: #000;\n                border: 1px solid rgba(168,85,247,.55); color: #c4b5fd;\n                font-size: 9px; font-weight: 700; letter-spacing: .04em; }\nh2 { font-size: 9.5px; text-transform: uppercase; letter-spacing: .07em;\n     color: #71717a; margin: 9px 0 4px; }\n#closeBtn, #minBtn { flex: 0 0 auto; width: 22px; height: 22px; border-radius: 50%;\n            background: #000; border: 1px solid rgba(255,255,255,.18);\n            color: #d4d4d8; font-size: 11px; line-height: 1; cursor: pointer;\n            transition: background .15s ease, color .15s ease; }\n#closeBtn:hover, #minBtn:hover { background: #141418; color: #fff; }\n\n.badge { font-size: 9.5px; font-weight: 600; padding: 2px 7px; border-radius: 999px;\n         background: #000; border: 1px solid rgba(255,255,255,.18);\n         color: #d4d4d8; white-space: nowrap; }\n.badge.running { border-color: rgba(168,85,247,.75); color: #d8b4fe; }\n.badge.done    { border-color: rgba(34,197,94,.65);  color: #86efac; }\n.badge.error   { border-color: rgba(244,63,94,.65);  color: #fda4af; }\n.badge.stopped { border-color: rgba(245,158,11,.65); color: #fcd34d; }\n\n/* ---------- File pickers (tight rows) ---------- */\n.zipbox { margin-top: 9px; padding: 0 9px 8px; background: #000;\n          border: 1px dashed rgba(255,255,255,.26); border-radius: 11px; }\n.zipbox label { display: block; font-size: 11px; font-weight: 700; margin: 7px 0 0; color: #fff; }\n.files label { display: block; font-size: 10.5px; font-weight: 600; margin: 6px 0 0;\n               color: #d4d4d8; background: #000;\n               border: 1px solid rgba(255,255,255,.12); border-radius: 10px;\n               padding: 6px 9px; }\n.files input[type=\"file\"], .zipbox input[type=\"file\"] {\n       display: block; width: 100%; font-size: 10.5px; margin-top: 5px;\n       color: #8b8b93; background: transparent; border: 0; }\n.files input[type=\"file\"]::file-selector-button,\n.zipbox input[type=\"file\"]::file-selector-button {\n       border-radius: 999px; border: 1px solid rgba(255,255,255,.22);\n       background: #000; color: #f4f4f5;\n       padding: 3px 10px; font-size: 10.5px; font-weight: 600;\n       cursor: pointer; margin-right: 7px;\n       transition: background .15s ease, border-color .15s ease; }\n.files input[type=\"file\"]::file-selector-button:hover,\n.zipbox input[type=\"file\"]::file-selector-button:hover {\n       background: #141418; border-color: rgba(168,85,247,.7); }\n.zipinfo { margin-top: 6px; padding: 7px 9px; background: #000;\n           border: 1px solid rgba(255,255,255,.14); border-radius: 9px;\n           font-size: 10.5px; line-height: 1.5; color: #e4e4e7; word-break: break-word; }\n.ordiv { text-align: center; font-size: 9.5px; color: #71717a; margin: 9px 0 0; }\n\n/* ---------- Summary ---------- */\n.summary { margin-top: 8px; padding: 8px 10px; background: #000;\n           border: 1px solid rgba(255,255,255,.14); border-radius: 10px;\n           font-size: 10.5px; line-height: 1.5; color: #f4f4f5; word-break: break-word; }\n.summary strong { color: #8b8b93; font-weight: 600; }\n.summary.hidden, .hidden { display: none; }\n.warn { margin-top: 7px; padding: 6px 8px; border-radius: 8px; background: #000;\n        border: 1px solid rgba(245,158,11,.55); color: #fcd34d;\n        font-size: 10px; line-height: 1.45; white-space: pre-wrap; }\n\n/* ---------- Controls ---------- */\n.controls { display: flex; gap: 6px; margin-top: 10px; }\n.controls button { flex: 1; padding: 7px 6px; font-size: 11px; font-weight: 700;\n                   border-radius: 999px; cursor: pointer; border: 1px solid transparent;\n                   transition: transform .14s ease, filter .14s ease, background .14s ease; }\n.controls button:disabled { opacity: .4; cursor: default; box-shadow: none; }\nbutton.run   { background: linear-gradient(135deg, #8b5cf6, #6d28d9 60%, #4c1d95);\n               color: #fff; border-color: rgba(168,85,247,.55); }\nbutton.run:hover:not(:disabled) { transform: translateY(-1px); filter: brightness(1.15); }\nbutton.run:active:not(:disabled) { transform: translateY(0) scale(.98); }\nbutton.stop  { background: #000; color: #fda4af; border-color: rgba(244,63,94,.55); }\nbutton.stop:hover:not(:disabled) { background: #180a0e; }\nbutton.clear { background: #000; color: #d4d4d8; flex: 0 0 68px;\n               border-color: rgba(255,255,255,.18); }\nbutton.clear:hover:not(:disabled) { background: #141418; }\n.hint { font-size: 9.5px; color: #71717a; line-height: 1.45; margin: 8px 0 0; }\n\n/* ---------- Log ---------- */\n#logWrap { display: flex; flex-direction: column; flex: 1 1 auto; min-height: 96px; }\n.log { flex: 1 1 auto; min-height: 88px; max-height: 190px; overflow-y: auto;\n       background: #000; border: 1px solid rgba(255,255,255,.12);\n       border-radius: 10px; padding: 7px 9px; color: #e4e4e7;\n       font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;\n       font-size: 10px; line-height: 1.5; white-space: pre-wrap; word-break: break-word; }\n.log::-webkit-scrollbar { width: 6px; }\n.log::-webkit-scrollbar-thumb { background: rgba(255,255,255,.18); border-radius: 999px; }\n.log::-webkit-scrollbar-track { background: transparent; }\n.log .t { color: #71717a; }\n.log .err { color: #fb7185; }\n.log .ok { color: #4ade80; }\n.log .stage { color: #c084fc; }\n\n/* ---------- Narrow screens ---------- */\n@media (max-width: 520px) {\n  #panel { right: 8px; left: 8px; width: auto; bottom: 56px; max-height: 72vh; }\n}\n",PBU_PANEL_HTML='\n<button id="fab" title="Play Books Auto Uploader">📚 Auto Upload</button>\n<section id="panel" aria-label="Play Books Auto Uploader panel">\n  <header>\n    <h1>📚 Auto Uploader</h1>\n    <span id="versionLabel"></span>\n    <div id="statusBadge" class="badge idle">Idle</div>\n    <button id="minBtn" title="Minimize panel">–</button> <button id="closeBtn" title="Close panel">✕</button>\n  </header>\n\n  <div class="zipbox">\n    <label>📦 OR drop everything in one ZIP\n      <input type="file" id="zipFile" accept=".zip,application/zip">\n    </label>\n    <div id="zipInfo" class="zipinfo hidden"></div>\n  </div>\n\n  <div class="ordiv">— or pick the three files separately —</div>\n\n  <div class="files">\n    <label>EPUB file\n      <input type="file" id="epubFile" accept=".epub">\n    </label>\n    <label>Cover image\n      <input type="file" id="coverFile" accept=".jpg,.jpeg,.png,.tif,.tiff">\n    </label>\n    <label>metadata.txt\n      <input type="file" id="metaFile" accept=".txt,text/plain">\n    </label>\n  </div>\n\n  <div id="summary" class="summary hidden">\n    <div><strong>Title:</strong> <span id="sumTitle">—</span></div>\n    <div><strong>Author:</strong> <span id="sumAuthor">—</span></div>\n    <div><strong>Price:</strong> <span id="sumPrice">—</span></div>\n    <div><strong>Pages:</strong> <span id="sumPages">—</span></div>\n    <div><strong>Genres:</strong> <span id="sumGenres">—</span></div>\n    <div id="sumWarn" class="warn hidden"></div>\n  </div>\n\n  <div class="controls">\n    <button id="runBtn" class="run">▶ Run upload</button>\n    <button id="stopBtn" class="stop" disabled>■ Stop</button>\n    <button id="clearBtn" class="clear">Clear log</button>\n  </div>\n\n  <p class="hint">\n    Runs in this tab. Uploads \u2192 waits for processing \u2192 publishes.</p>\n\n  <div id="logWrap">\n    <h2>Log</h2>\n    <div id="log" class="log"></div>\n  </div>\n</section>\n';function pbuBuildPanel(){if(pbuShadow||document.getElementById(PBU_HOST_ID))return;const e=document.createElement("div");e.id=PBU_HOST_ID,(document.documentElement||document.body).appendChild(e),pbuShadow=e.attachShadow({mode:"open"});const t=document.createElement("style");t.textContent=PBU_PANEL_CSS,pbuShadow.appendChild(t);const n=document.createElement("div");for(n.innerHTML=PBU_PANEL_HTML;n.firstChild;)pbuShadow.appendChild(n.firstChild);const o=e=>pbuShadow.getElementById(e);pbuEls={fab:o("fab"),panel:o("panel"),close:o("closeBtn"),zip:o("zipFile"),zipInfo:o("zipInfo"),epub:o("epubFile"),cover:o("coverFile"),meta:o("metaFile"),run:o("runBtn"),stop:o("stopBtn"),clear:o("clearBtn"),log:o("log"),badge:o("statusBadge"),summary:o("summary"),sumTitle:o("sumTitle"),sumAuthor:o("sumAuthor"),sumPrice:o("sumPrice"),sumPages:o("sumPages"),sumGenres:o("sumGenres"),sumWarn:o("sumWarn"),version:o("versionLabel")};const r=chrome.runtime.getManifest&&chrome.runtime.getManifest().version||"";pbuEls.version&&(pbuEls.version.textContent=r?"v"+r:""),pbuEls.fab.addEventListener("click",()=>pbuTogglePanel()),pbuEls.close.addEventListener("click",()=>pbuTogglePanel(!1)),pbuEls.minBtn=pbuShadow.getElementById("minBtn"),pbuEls.minBtn&&pbuEls.minBtn.addEventListener("click",()=>pbuSetMinimized(!pbuMinimized)),pbuEls.zip.addEventListener("change",pbuOnZipChange),pbuEls.meta.addEventListener("change",pbuRefreshSummary),pbuEls.run.addEventListener("click",pbuOnRun),pbuEls.stop.addEventListener("click",pbuOnStop),pbuEls.clear.addEventListener("click",pbuOnClear),chrome.storage.onChanged.addListener((e,t)=>{"local"===t&&e.job&&pbuRenderJob(e.job.newValue||null)}),pbuRefreshFromStorage()}function pbuTogglePanel(e){if(pbuEls&&(pbuPanelOpen="boolean"==typeof e?e:!pbuPanelOpen,pbuEls.panel.classList.toggle("open",pbuPanelOpen),pbuPanelOpen&&(pbuRefreshFromStorage(),!pbuPanelReadyLogged))){pbuPanelReadyLogged=!0;csLog(`Extension v${chrome.runtime.getManifest&&chrome.runtime.getManifest().version||""} — panel ready`,"stage").then(()=>pbuRefreshFromStorage())}}function pbuShowSummary(e){pbuParsedMeta=e,pbuEls.sumTitle.textContent=e.title||"(missing TITLE)",pbuEls.sumAuthor.textContent=e.author||"(missing AUTHOR)",pbuEls.sumPrice.textContent=e.price?`${e.currency} ${e.price}`:"(missing price)",pbuEls.sumPages.textContent=e.pages||"(missing pages)",pbuEls.sumGenres.textContent=e.genres.length?e.genres.join(" | "):"(none found)",pbuEls.sumWarn&&(e.warnings&&e.warnings.length?(pbuEls.sumWarn.textContent="⚠ "+e.warnings.join("\n⚠ "),pbuEls.sumWarn.classList.remove("hidden")):(pbuEls.sumWarn.textContent="",pbuEls.sumWarn.classList.add("hidden"))),pbuEls.summary.classList.remove("hidden")}async function pbuRefreshSummary(){pbuParsedMeta=null,pbuEls.summary.classList.add("hidden");const e=pbuEls.meta.files&&pbuEls.meta.files[0];if(e)try{pbuShowSummary(parseMetadata(await readFileAsText(e)))}catch(e){}}function pbuFmtSize(e){return e>=1048576?(e/1048576).toFixed(2)+" MB":e>=1024?(e/1024).toFixed(1)+" KB":e+" B"}function pbuEsc(e){return String(e).replace(/&/g,"&amp;").replace(/</g,"&lt;")}async function pbuOnZipChange(){pbuZipParts=null,pbuEls.zipInfo.classList.add("hidden"),pbuEls.zipInfo.textContent="";const e=pbuEls.zip.files&&pbuEls.zip.files[0];if(e){try{const t=pbuZipReadEntries(await e.arrayBuffer()),n=pbuZipDetectParts(t),[o,r,a]=await Promise.all([pbuZipExtract(n.epub),pbuZipExtract(n.meta),n.cover?pbuZipExtract(n.cover):Promise.resolve(null)]),i=new TextDecoder("utf-8").decode(r),s=e=>e.split("/").pop(),l=new File([o],s(n.epub.name),{type:"application/epub+zip"}),c=n.cover?new File([a],s(n.cover.name),{type:/\.png$/i.test(n.cover.name)?"image/png":"image/jpeg"}):null;pbuZipParts={zipName:e.name,epubName:n.epub.name,coverName:n.cover?n.cover.name:null,metaName:n.meta.name,epubFile:l,coverFile:c,metaText:i},pbuEls.zipInfo.innerHTML=`<div>📖 <strong>EPUB:</strong> ${pbuEsc(n.epub.name)} (${pbuFmtSize(n.epub.size)})</div>`+(n.cover?`<div>🖼 <strong>Cover:</strong> ${pbuEsc(n.cover.name)} (${pbuFmtSize(n.cover.size)})</div>`:"<div>🖼 <strong>Cover:</strong> not found in the ZIP — pick one below</div>")+`<div>📝 <strong>Metadata:</strong> ${pbuEsc(n.meta.name)} (${pbuFmtSize(n.meta.size)})</div>`,pbuEls.zipInfo.classList.remove("hidden"),await csLog(`ZIP "${e.name}": ${t.length} entries — detected EPUB: ${n.epub.name} · Cover: ${n.cover?n.cover.name:"NOT FOUND"} · Metadata: ${n.meta.name}`,"stage"),pbuShowSummary(parseMetadata(i))}catch(e){pbuZipParts=null,pbuEls.zipInfo.innerHTML=`<div>⚠ ${pbuEsc(String(e&&e.message||e))}</div>`,pbuEls.zipInfo.classList.remove("hidden"),await csLog("ZIP problem: "+String(e&&e.message||e),"error")}pbuRefreshFromStorage()}}function pbuBadgeFor(e){const t=e&&e.status,[n,o]={idle:["Idle","idle"],running:["Running…","running"],processing:["Processing…","running"],publishing:["Publishing…","running"],done:["Done ✔","done"],error:["Failed ✖","error"],stopped:["Stopped","stopped"],stop_condition:["Stopped — action needed","error"]}[t]||[t||"Idle","idle"];pbuEls.badge.textContent=n,pbuEls.badge.className="badge "+o;const r="running"===t||"processing"===t||"publishing"===t,a="running"===t&&!flowRunning;pbuEls.run.disabled=r&&!a,pbuEls.run.textContent=a?"▶ Resume upload":"▶ Run upload",pbuEls.stop.disabled=!r}function pbuRenderJob(e){pbuEls&&(pbuBadgeFor(e),e&&Array.isArray(e.log)?(pbuEls.log.innerHTML=e.log.map(e=>{const t="error"===e.level?"err":"ok"===e.level?"ok":"stage"===e.level?"stage":"",n=String(e.text).replace(/&/g,"&amp;").replace(/</g,"&lt;");return`<div class="${t}"><span class="t">${e.t}</span> ${n}</div>`}).join(""),pbuEls.log.scrollTop=pbuEls.log.scrollHeight):pbuEls.log.textContent="")}async function pbuRefreshFromStorage(){pbuRenderJob(await csGetJob())}async function pbuOnRun(){const e=pbuEls.epub.files&&pbuEls.epub.files[0]||pbuZipParts&&pbuZipParts.epubFile||null,t=pbuEls.cover.files&&pbuEls.cover.files[0]||pbuZipParts&&pbuZipParts.coverFile||null,n=pbuEls.meta.files&&pbuEls.meta.files[0];let o=null;if(n)try{o=await readFileAsText(n)}catch(e){o=null}else pbuZipParts&&(o=pbuZipParts.metaText);if(!e||!t||!o){const n=await csGetJob();return n&&"running"===n.status&&n.files&&n.meta?(await csLog("Resuming the upload in this tab from the stored job data.","stage"),void startInPageFlow({fromPanel:!0})):(e&&o&&!t?await csLog("No cover image — pick a cover file, or use a ZIP that contains one.","error"):await csLog("Please choose all three files: EPUB, cover and metadata.txt — or one ZIP containing all three.","error"),void pbuRefreshFromStorage())}pbuEls.run.disabled=!0;try{const r=parseMetadata(o);if(!r.title)throw new Error("metadata.txt: TITLE not found — check the file format (see template).");if(!r.author)throw new Error("metadata.txt: AUTHOR not found.");if(!r.price)throw new Error("metadata.txt: SUGGESTED PRICE (ebook) not found.");if(!r.description)throw new Error("metadata.txt: DESCRIPTION block not found.");if(!r.genres.length)throw new Error("metadata.txt: no BISAC categories found under CATEGORIES.");if(r.warnings&&r.warnings.length)for(const w of r.warnings)await csLog("⚠ metadata: "+w,"error");const[a,i]=await Promise.all([readFileAsBase64(e),readFileAsBase64(t)]),s=chrome.runtime.getManifest&&chrome.runtime.getManifest().version||"",l={status:"running",stage:"create",startedAt:Date.now(),ggkey:null,bookUrl:null,lastStep:0,escalationSent:!1,meta:r,files:{epub:{name:e.name,type:e.type||"application/epub+zip",base64:a},cover:{name:t.name,type:t.type||"image/jpeg",base64:i}},log:[{t:csNowTime(),level:"stage",text:`Extension v${s} — starting run`},...!pbuZipParts||e!==pbuZipParts.epubFile&&t!==pbuZipParts.coverFile&&n?[]:[{t:csNowTime(),level:"info",text:`Files from ZIP "${pbuZipParts.zipName}": EPUB ${pbuZipParts.epubName} · Cover ${pbuZipParts.coverName||"—"} · Metadata ${pbuZipParts.metaName}`}]]};await csSaveJob(l);try{await chrome.runtime.sendMessage({type:"START_JOB"})}catch(e){}startInPageFlow({fromPanel:!0})}catch(e){await csLog(String(e&&e.message||e),"error"),pbuEls.run.disabled=!1}pbuRefreshFromStorage()}async function pbuOnStop(){const e=await csGetJob();e&&(e.status="stopped",await csSaveJob(e)),csSetResumeFlag(!1);try{await chrome.runtime.sendMessage({type:"STOP_JOB"})}catch(e){}pbuRefreshFromStorage()}async function pbuOnClear(){const e=await csGetJob();e&&(e.log=[],await csSaveJob(e)),pbuRefreshFromStorage()}if(!window.__pbuV6Loaded){window.__pbuV6Loaded=!0;const e=()=>{pbuBuildPanel(),csResumeFlagSet()&&(async()=>{const e=await csGetJob();e&&"running"===e.status?(await sleep(2500),startInPageFlow()):csSetResumeFlag(!1)})()};"loading"===document.readyState?document.addEventListener("DOMContentLoaded",e,{once:!0}):e(),chrome.runtime.onMessage.addListener((e,t,n)=>{if(e&&e.type){if("PING"!==e.type)return"TOGGLE_PANEL"===e.type?(pbuTogglePanel(),void n({ok:!0})):"RUN_STAGE"===e.type?stageBusy?void n({ok:!1,error:"Another stage is already running on this page."}):(stageBusy=!0,runStage(e.stage,e.payload||{}).then(e=>{stageBusy=!1,n(e)}).catch(e=>{stageBusy=!1,n({ok:!1,error:String(e&&e.message||e)})}),!0):void 0;n({ok:!0,url:location.href})}})}

/* ================= v9.4 content-stage override =================
 * In this console version the Content tab's upload UI is a MODAL
 * ("Upload content and cover", with a drag & drop zone and a Browse
 * button): with no files yet, the tab itself has NO <input
 * type="file"> anywhere — the input exists only inside the dialog,
 * which an "Upload" button on the tab opens. The stock stage looked
 * for the input on the tab, found none, and failed with "no file
 * input found for the epub upload" (live screenshot, 2026-10-23).
 * The functions below REPLACE revealFileInputs / uploadOne /
 * stageContent (a later declaration wins in the same scope): they
 * open the dialog, use its input when it has one, fall back to a
 * real drag & drop event on the drop zone, and verify the files on
 * the tab after the dialog closes. */
function uploadDialogEl() {
  return [...document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container')]
    .filter(isVisible)
    .find((d) => /upload content and cover|drag and drop/i.test(norm(d.innerText || d.textContent))) || null;
}

async function openUploadDialog() {
  if (uploadDialogEl()) return true;
  const clicked = await clickByText(
    ['Upload content and cover', 'Upload content', 'Upload files', 'Upload file', 'Upload new file', 'Upload', 'Add files'],
    10000);
  if (!clicked) return false;
  return !!(await waitFor(() => uploadDialogEl() || document.querySelector('input[type="file"]'), 10000));
}

async function revealFileInputs() {
  if (document.querySelector('input[type="file"]')) return true;
  await openUploadDialog();
  if (document.querySelector('input[type="file"]')) return true;
  const dlg = uploadDialogEl();
  if (dlg) {
    // Some builds create the input only when "Browse" is clicked.
    const browse = [...dlg.querySelectorAll('button, [role="button"]')].filter(isVisible)
      .find((b) => exactTextEq(b.innerText || b.textContent, 'Browse'));
    if (browse) { clickEl(browse); await sleep(600); }
  }
  return !!document.querySelector('input[type="file"]');
}

function dropFileOnto(el, file) {
  const dt = new DataTransfer();
  dt.items.add(file);
  for (const type of ['dragenter', 'dragover', 'drop']) {
    el.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, composed: true, dataTransfer: dt }));
  }
}

async function uploadOne(kind, file, successTimeout = 180000) {
  let kinds = inputsByKind();
  let input = (kind === 'cover' ? kinds.cover : kinds.epub)[0] || kinds.all[0];
  if (!input) {
    await revealFileInputs();
    kinds = inputsByKind();
    input = (kind === 'cover' ? kinds.cover : kinds.epub)[0] || kinds.all[0];
  }

  const beforeRows = new Set(fileRows().map((r) => r.text));
  const bannerBefore = /Successfully uploaded/i.test(pageText());
  let inDialog = false;

  if (input) {
    assignFileToInput(input, file);
    if (!input.files || !input.files[0] || input.files[0].name !== file.name) {
      L(`Content: warning — after assigning, the ${kind} input does not show "${file.name}".`, 'error');
    }
    await sleep(1000);
    const dlg = uploadDialogEl() || input.closest('[role="dialog"], .mat-dialog-container, mat-dialog-container');
    inDialog = !!dlg;
    if (dlg) {
      const btn = [...dlg.querySelectorAll('button')].find((b) =>
        isVisible(b) && /^(upload|add|done|save)$/i.test(norm(b.innerText || b.textContent)));
      if (btn) clickEl(btn);
    }
  } else {
    const dlg = uploadDialogEl();
    if (!dlg) {
      throw new Error(`Content: no file input found for the ${kind} upload, and the upload dialog could not be opened.`);
    }
    inDialog = true;
    const zone = [...dlg.querySelectorAll('*')].filter(isVisible)
      .find((e) => /drag and drop/i.test(norm(e.innerText || e.textContent)) && e.querySelectorAll('*').length < 12) || dlg;
    L('Content: the upload dialog has no file input — dropping the file onto its drag & drop zone.');
    dropFileOnto(zone, file);
    await sleep(1000);
    const btn = [...dlg.querySelectorAll('button')].find((b) =>
      isVisible(b) && /^(upload|add|done|save)$/i.test(norm(b.innerText || b.textContent)));
    if (btn) clickEl(btn);
  }

  const rowMatchesKind = (text) => kind === 'epub'
    ? /\.epub/i.test(text)
    : /frontcover|front cover/i.test(text) || (/\.(jpe?g|png)/i.test(text) && /cover/i.test(text));

  const outcome = await waitFor(() => {
    const rows = fileRows();
    for (const r of rows) {
      if (beforeRows.has(r.text)) continue;
      if (/failed|epubcheck|invalid|corrupt|not a valid/i.test(r.text)) {
        return { fail: r.text.slice(0, 220) };
      }
    }
    const newRow = rows.find((r) => !beforeRows.has(r.text) && rowMatchesKind(r.text));
    if (newRow) return { ok: true, via: 'row' };
    if (!bannerBefore && /Successfully uploaded/i.test(pageText())) return { ok: true, via: 'banner' };
    if (inDialog) {
      // Inside the dialog, this file's entry (name + progress/size)
      // is the confirmation; tab rows are verified after Close.
      const d = uploadDialogEl();
      const dt2 = d ? norm(d.innerText || d.textContent) : '';
      const kb = String(Math.max(1, Math.round(file.size / 1024)));
      if (dt2.includes(file.name) && (/\d+\s*%/.test(dt2) || /complete|uploaded/i.test(dt2) || dt2.includes(kb))) {
        return { ok: true, via: 'dialog' };
      }
    }
    return null;
  }, inDialog ? Math.min(successTimeout, 120000) : successTimeout, 1200);

  if (!outcome) {
    const errText = findErrorText();
    throw new Error(`Content: "${file.name}" upload did not confirm` +
      (errText ? ': ' + errText : ' (timed out waiting for its file row / success banner).'));
  }
  if (outcome.fail) {
    throw new Error(`Content: "${file.name}" upload failed — the console reports: "${outcome.fail}"`);
  }
  L(`Uploaded ${file.name} — confirmed via its ${outcome.via === 'row' ? 'file row' : outcome.via === 'dialog' ? 'dialog entry' : 'success banner'}.`);
}

async function stageContent() {
  await goSection(['Content']);
  const blocker = detectBlocker(); if (blocker) throw stopErr(blocker);

  const { job } = await chrome.storage.local.get('job');
  if (!job || !job.files) throw new Error('Content: stored files are missing (job data not found).');
  const epubFile = base64ToFile(job.files.epub.base64, job.files.epub.name, job.files.epub.type);
  const coverFile = base64ToFile(job.files.cover.base64, job.files.cover.name, job.files.cover.type);

  await uploadOne('epub', epubFile);
  await sleep(1500);
  await uploadOne('cover', coverFile);
  await sleep(1500);

  // Close the upload dialog if it is still open, then verify the
  // files actually landed on the Content tab.
  const dlg = uploadDialogEl();
  if (dlg) {
    const close = [...dlg.querySelectorAll('button')].filter(isVisible)
      .find((b) => exactTextEq(b.innerText || b.textContent, 'Close'));
    if (close) { clickEl(close); await sleep(1500); }
  }
  const epubRow = await waitFor(() => currentEpubRow(job.ggkey), 90000, 2000);
  if (!epubRow) {
    throw new Error('Content: the EPUB did not appear on the Content tab after uploading — the upload may not have registered.');
  }
  const stepM = epubRow.text.match(/step\s+(\d)\s+of\s+6/i);
  if (stepM) L(`EPUB processing started: completed step ${stepM[1]} of 6 (current version).`);
  const rows = fileRows();
  const coverRow = rows.find((r) => /front cover|frontcover/i.test(r.text));
  if (coverRow) L('Cover registered (a "front cover" row is shown on the Content tab).');
  else L('Cover upload confirmed, but "front cover" registration was not visible — check on Review.', 'error');
  return { bookUrl: location.href };
}


/* ================= v9.5 navigation-guard override =================
 * The console guards tab navigation with a "Continue without saving?"
 * modal when it considers the current step dirty — it fired right
 * after the Genres stage (picks on screen and verified) when the
 * flow navigated to Contributors: the stage's save raced the
 * console's saved-state flag. Two defences: (1) saves now prefer the
 * plain "Save" button — the flow navigates by itself via goSection —
 * instead of "Save & Continue"; (2) goSection recognises the guard
 * dialog, clicks CANCEL (never "Continue": that discards the
 * changes), presses Save itself, and retries the navigation. These
 * re-declarations replace findSaveButton / goSection. */
function findSaveButton() {
  const btns = [...document.querySelectorAll('button, [role="button"]')].filter(isVisible);
  const byText = (t) => btns.filter((b) => exactTextEq(b.innerText || b.textContent, t));
  for (const t of ['Save', 'Save changes', 'Save & continue']) {
    const matches = byText(t);
    const enabled = matches.find((b) => !btnDisabled(b));
    if (enabled) return enabled;
    if (matches.length) return matches[0];
  }
  return null;
}

function unsavedChangesDialog() {
  return [...document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container')]
    .filter(isVisible)
    .find((d) => /continue without saving|changes will be lost/i.test(norm(d.innerText || d.textContent))) || null;
}

async function handleUnsavedChangesDialog() {
  const dlg = unsavedChangesDialog();
  if (!dlg) return false;
  const cancel = [...dlg.querySelectorAll('button')].filter(isVisible)
    .find((b) => exactTextEq(b.innerText || b.textContent, 'Cancel'));
  if (cancel) clickEl(cancel);
  await sleep(700);
  L('Navigation guard ("Continue without saving?") appeared — clicked Cancel, then saved this page before navigating.');
  const btn = findSaveButton();
  if (btn && !btnDisabled(btn)) {
    clickEl(btn);
    await sleep(1800);
    await dismissInfoDialogs();
  }
  return true;
}

async function goSection(names, timeout = 15000) {
  const navSel = '[role="tab"], [role="navigation"] a, [role="navigation"] button, nav a, nav button, aside a, aside button, [class*="sidenav"] a, [class*="side-nav"] a';
  let ok = await clickByText(names, timeout, navSel);
  if (!ok) ok = await clickByText(names, 4000);
  if (ok) {
    await sleep(1200);
    await dismissInfoDialogs();
    if (await handleUnsavedChangesDialog()) {
      let again = await clickByText(names, 8000, navSel);
      if (!again) again = await clickByText(names, 4000);
      if (again) {
        await sleep(1200);
        await dismissInfoDialogs();
        await handleUnsavedChangesDialog();
      }
    }
  }
  return ok;
}


/* ================= v9.6 content-stage hardening =================
 * Live run (2026-10-23): the content stage died with
 * "e.getBoundingClientRect is not a function" after the drop
 * fallback — some lookup handed a non-element to isVisible — and
 * the console's upload dialog exposes no <input type="file"> to a
 * plain document search (it may live in a shadow root or a frame).
 * Fixes: (1) isVisible is hardened — a non-element simply reads as
 * not visible instead of crashing the whole run; (2) file inputs
 * are searched DEEP: shadow roots and same-origin frames included
 * (the extension's own panel host is explicitly pruned), and after
 * "Browse" is clicked the search polls for a few seconds because
 * some builds create the input only then; (3) the drop fallback is
 * bounded, and on failure the stage reports a DOM census (inputs
 * found, frames, dialog buttons) so the log shows exactly what
 * this console build exposes. These re-declarations replace
 * isVisible / revealFileInputs / dropFileOnto / uploadOne. */
function isVisible(el) {
  if (!el || typeof el.getBoundingClientRect !== 'function') return false;
  try {
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none';
  } catch (e) { return false; }
}

function deepFindFileInputs() {
  const out = [];
  const walk = (root) => {
    if (!root || !root.querySelectorAll) return;
    let els;
    try { els = root.querySelectorAll('*'); } catch (e) { return; }
    for (const el of els) {
      if (el.id === 'pbu-panel-host') continue; // our own panel — never page UI
      if (el.tagName === 'INPUT' && String(el.type).toLowerCase() === 'file') out.push(el);
      if (el.shadowRoot) walk(el.shadowRoot);
      if (el.tagName === 'IFRAME') {
        try { if (el.contentDocument) walk(el.contentDocument); } catch (e) { /* cross-origin */ }
      }
    }
  };
  walk(document);
  return out;
}

function uploadCensus() {
  let deep = 0;
  try { deep = deepFindFileInputs().length; } catch (e) { /* ignore */ }
  const top = document.querySelectorAll('input[type="file"]').length;
  const frames = document.querySelectorAll('iframe').length;
  const dlg = uploadDialogEl();
  const btns = dlg
    ? [...dlg.querySelectorAll('button')].map((b) => norm(b.innerText || b.textContent)).filter(Boolean).join(', ')
    : '(upload dialog not open)';
  return `file inputs: ${top} in page / ${deep} incl. shadow+frames; iframes: ${frames}; dialog buttons: ${btns || '(none)'}`;
}

function findUploadInput(kind) {
  const kinds = inputsByKind();
  const direct = (kind === 'cover' ? kinds.cover : kinds.epub)[0] || null;
  if (direct) return direct;
  const deep = deepFindFileInputs();
  if (deep.length) {
    const acceptOf = (i) => String(i.getAttribute('accept') || '').toLowerCase();
    return deep.find((i) => kind === 'cover'
      ? /image|jpe?g|png|tif/.test(acceptOf(i))
      : /epub|pdf/.test(acceptOf(i))) || deep[0];
  }
  return kinds.all[0] || null;
}

async function revealFileInputs() {
  if (deepFindFileInputs().length) return true;
  await openUploadDialog();
  if (deepFindFileInputs().length) return true;
  const dlg = uploadDialogEl();
  if (dlg) {
    const browse = [...dlg.querySelectorAll('button, [role="button"]')].filter(isVisible)
      .find((b) => exactTextEq(b.innerText || b.textContent, 'Browse'));
    if (browse) {
      clickEl(browse);
      // Some builds create the input only now (possibly inside a
      // shadow root) — poll the deep search for a few seconds.
      const t0 = Date.now();
      while (Date.now() - t0 < 4000) {
        if (deepFindFileInputs().length) return true;
        await sleep(250);
      }
    }
  }
  return deepFindFileInputs().length > 0;
}

function dropFileOnto(el, file) {
  if (!el || typeof el.dispatchEvent !== 'function') return;
  try {
    const dt = new DataTransfer();
    dt.items.add(file);
    for (const type of ['dragenter', 'dragover', 'drop']) {
      el.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, composed: true, dataTransfer: dt }));
    }
  } catch (e) { /* the caller's confirmation wait decides */ }
}

async function uploadOne(kind, file, successTimeout = 180000) {
  const beforeRows = new Set(fileRows().map((r) => r.text));
  const bannerBefore = /Successfully uploaded/i.test(pageText());
  const rowMatchesKind = (text) => kind === 'epub'
    ? /\.epub/i.test(text)
    : /frontcover|front cover/i.test(text) || (/\.(jpe?g|png)/i.test(text) && /cover/i.test(text));
  const finish = (outcome) => {
    if (!outcome) return false;
    if (outcome.fail) {
      throw new Error(`Content: "${file.name}" upload failed — the console reports: "${outcome.fail}"`);
    }
    L(`Uploaded ${file.name} — confirmed via its ${outcome.via === 'row' ? 'file row' : outcome.via === 'dialog' ? 'dialog entry' : 'success banner'}.`);
    return true;
  };
  const pollOutcome = (ms) => waitFor(() => {
    const rows = fileRows();
    for (const r of rows) {
      if (beforeRows.has(r.text)) continue;
      if (/failed|epubcheck|invalid|corrupt|not a valid/i.test(r.text)) return { fail: r.text.slice(0, 220) };
    }
    const newRow = rows.find((r) => !beforeRows.has(r.text) && rowMatchesKind(r.text));
    if (newRow) return { ok: true, via: 'row' };
    if (!bannerBefore && /Successfully uploaded/i.test(pageText())) return { ok: true, via: 'banner' };
    const d = uploadDialogEl();
    if (d) {
      const dt2 = norm(d.innerText || d.textContent);
      const kb = String(Math.max(1, Math.round(file.size / 1024)));
      if (dt2.includes(file.name) && (/\d+\s*%/.test(dt2) || /complete|uploaded/i.test(dt2) || dt2.includes(kb))) {
        return { ok: true, via: 'dialog' };
      }
    }
    return null;
  }, ms, 1200);

  let input = findUploadInput(kind);
  if (!input) {
    await revealFileInputs();
    input = findUploadInput(kind);
  }
  let inDialog = !!uploadDialogEl();

  if (input) {
    assignFileToInput(input, file);
    if (!input.files || !input.files[0] || input.files[0].name !== file.name) {
      L(`Content: warning — after assigning, the ${kind} input does not show "${file.name}".`, 'error');
    }
    await sleep(1000);
    const dlg = uploadDialogEl() || (input.closest ? input.closest('[role="dialog"], .mat-dialog-container, mat-dialog-container') : null);
    inDialog = !!dlg;
    if (dlg) {
      const btn = [...dlg.querySelectorAll('button')].find((b) =>
        isVisible(b) && /^(upload|add|done|save)$/i.test(norm(b.innerText || b.textContent)));
      if (btn) clickEl(btn);
    }
    if (finish(await pollOutcome(inDialog ? 90000 : successTimeout))) return;
    if (!inDialog) {
      const errText = findErrorText();
      throw new Error(`Content: "${file.name}" upload did not confirm` +
        (errText ? ': ' + errText : ' (timed out waiting for its file row / success banner).'));
    }
    L('Content: the dialog input did not confirm the upload — trying drag & drop as well.');
  }

  const dlg2 = uploadDialogEl();
  if (!dlg2) {
    throw new Error(`Content: no file input found for the ${kind} upload, and the upload dialog could not be opened. Census: ${uploadCensus()}`);
  }
  const zone = [...dlg2.querySelectorAll('*')].filter(isVisible)
    .find((e) => /drag and drop/i.test(norm(e.innerText || e.textContent)) && e.querySelectorAll('*').length < 12) || dlg2;
  L(`Content: dropping "${file.name}" onto the upload dialog's drag & drop zone.`);
  dropFileOnto(zone, file);
  dropFileOnto(dlg2, file);
  await sleep(1000);
  const btn2 = [...dlg2.querySelectorAll('button')].find((b) =>
    isVisible(b) && /^(upload|add|done|save)$/i.test(norm(b.innerText || b.textContent)));
  if (btn2) clickEl(btn2);
  if (finish(await pollOutcome(60000))) return;
  throw new Error(`Content: "${file.name}" did not register in the upload dialog (no input accepted it and drag & drop was ignored). Census: ${uploadCensus()}`);
}


/* ================= v9.7 panel minimize =================
 * A "–" button in the panel header collapses the panel to just
 * its header bar — title, version and the live status badge stay
 * visible while a run is in progress — and the same button (now
 * "▢") restores the full panel. Only the body sections are
 * hidden; the header is a direct child and is never touched. */
let pbuMinimized = false;
function pbuSetMinimized(min) {
  if (!pbuEls || !pbuEls.panel) return;
  pbuMinimized = !!min;
  for (const ch of [...pbuEls.panel.children]) {
    if (ch.tagName !== 'HEADER') ch.style.display = pbuMinimized ? 'none' : '';
  }
  const btn = pbuEls.minBtn || (pbuShadow && pbuShadow.getElementById('minBtn'));
  if (btn) {
    btn.textContent = pbuMinimized ? '▢' : '–';
    btn.title = pbuMinimized ? 'Restore panel' : 'Minimize panel';
  }
}


/* ================= v9.8 upload bridge client =================
 * The v9.6 census proved this console's upload dialog has no file
 * input at all and ignores isolated-world drag & drop. So the
 * content stage now ARMS a main-world bridge (background.js ->
 * chrome.scripting, world "MAIN") with the job's two files BEFORE
 * opening the dialog: when the page then asks for files — via
 * showOpenFilePicker, a transient <input type="file"> it clicks
 * itself, or a drop listener — the bridge hands it our file from
 * inside the page's own world. uploadOne tries, in order: a normal
 * input, the bridge-fed Browse click, main-world drag & drop, and
 * finally the old isolated-world drop. */
async function pbuMainBridge(action, extra) {
  try {
    const res = await chrome.runtime.sendMessage(Object.assign({ type: 'PBU_MAIN', action }, extra || {}));
    return res || { ok: false, error: 'no response from background' };
  } catch (e) {
    return { ok: false, error: String((e && e.message) || e) };
  }
}

let pbuArmedOnce = false;
async function armMainWorld(jobFiles) {
  if (pbuArmedOnce) return true;
  const payload = {
    files: [
      { key: 'epub', name: jobFiles.epub.name, type: jobFiles.epub.type, base64: jobFiles.epub.base64 },
      { key: 'cover', name: jobFiles.cover.name, type: jobFiles.cover.type, base64: jobFiles.cover.base64 }
    ]
  };
  const res = await pbuMainBridge('stage', { payload });
  if (res.ok) {
    pbuArmedOnce = true;
    L('Content: upload bridge armed in the page world — Browse/picker requests will be served the staged files.');
    return true;
  }
  L('Content: could not arm the upload bridge (' + (res.error || 'unknown') + ') — continuing with direct methods.', 'error');
  return false;
}

async function uploadOne(kind, file, successTimeout = 180000) {
  const beforeRows = new Set(fileRows().map((r) => r.text));
  const bannerBefore = /Successfully uploaded/i.test(pageText());
  const rowMatchesKind = (text) => kind === 'epub'
    ? /\.epub/i.test(text)
    : /frontcover|front cover/i.test(text) || (/\.(jpe?g|png)/i.test(text) && /cover/i.test(text));
  const finish = (outcome) => {
    if (!outcome) return false;
    if (outcome.fail) {
      throw new Error(`Content: "${file.name}" upload failed — the console reports: "${outcome.fail}"`);
    }
    L(`Uploaded ${file.name} — confirmed via its ${outcome.via === 'row' ? 'file row' : outcome.via === 'dialog' ? 'dialog entry' : 'success banner'}.`);
    return true;
  };
  const pollOutcome = (ms) => waitFor(() => {
    const rows = fileRows();
    for (const r of rows) {
      if (beforeRows.has(r.text)) continue;
      if (/failed|epubcheck|invalid|corrupt|not a valid/i.test(r.text)) return { fail: r.text.slice(0, 220) };
    }
    const newRow = rows.find((r) => !beforeRows.has(r.text) && rowMatchesKind(r.text));
    if (newRow) return { ok: true, via: 'row' };
    if (!bannerBefore && /Successfully uploaded/i.test(pageText())) return { ok: true, via: 'banner' };
    const d = uploadDialogEl();
    if (d) {
      const dt2 = norm(d.innerText || d.textContent);
      const kb = String(Math.max(1, Math.round(file.size / 1024)));
      if (dt2.includes(file.name) && (/\d+\s*%/.test(dt2) || /complete|uploaded/i.test(dt2) || dt2.includes(kb))) {
        return { ok: true, via: 'dialog' };
      }
    }
    return null;
  }, ms, 1200);

  let input = findUploadInput(kind);
  if (!input) {
    await revealFileInputs();
    input = findUploadInput(kind);
  }

  if (input) {
    assignFileToInput(input, file);
    if (!input.files || !input.files[0] || input.files[0].name !== file.name) {
      L(`Content: warning — after assigning, the ${kind} input does not show "${file.name}".`, 'error');
    }
    await sleep(1000);
    const dlg0 = uploadDialogEl() || (input.closest ? input.closest('[role="dialog"], .mat-dialog-container, mat-dialog-container') : null);
    if (dlg0) {
      const btn = [...dlg0.querySelectorAll('button')].find((b) =>
        isVisible(b) && /^(upload|add|done|save)$/i.test(norm(b.innerText || b.textContent)));
      if (btn) clickEl(btn);
    }
    if (finish(await pollOutcome(dlg0 ? 90000 : successTimeout))) return;
    if (!dlg0) {
      const errText = findErrorText();
      throw new Error(`Content: "${file.name}" upload did not confirm` +
        (errText ? ': ' + errText : ' (timed out waiting for its file row / success banner).'));
    }
    L('Content: the dialog input did not confirm the upload — trying the bridge routes.');
  } else if (uploadDialogEl()) {
    // The Browse click inside revealFileInputs may already have
    // fed this file through the armed bridge.
    if (finish(await pollOutcome(3000))) return;
  }

  const dlg = uploadDialogEl();
  if (!dlg) {
    throw new Error(`Content: no file input found for the ${kind} upload, and the upload dialog could not be opened. Census: ${uploadCensus()}`);
  }

  // Bridge route 1: a fresh Browse click, served by the armed
  // picker/input interceptors in the page's main world.
  const browseBtn = [...dlg.querySelectorAll('button, [role="button"]')].filter(isVisible)
    .find((b) => exactTextEq(b.innerText || b.textContent, 'Browse'));
  if (browseBtn) {
    L(`Content: clicking "Browse" — the armed bridge supplies "${file.name}" to the picker.`);
    clickEl(browseBtn);
    await sleep(800);
    if (finish(await pollOutcome(45000))) return;
  }

  // Bridge route 2: drag & drop dispatched in the main world.
  const dropRes = await pbuMainBridge('drop', { kind });
  if (dropRes.ok) {
    L(`Content: main-world drag & drop dispatched for "${file.name}" (${dropRes.result || 'ok'}).`);
    await sleep(800);
    if (finish(await pollOutcome(45000))) return;
  } else {
    L('Content: main-world drop unavailable (' + (dropRes.error || 'no response') + ').', 'error');
  }

  // Route 3: isolated-world drag & drop (previous behaviour).
  const zone = [...dlg.querySelectorAll('*')].filter(isVisible)
    .find((e) => /drag and drop/i.test(norm(e.innerText || e.textContent)) && e.querySelectorAll('*').length < 12) || dlg;
  L(`Content: dropping "${file.name}" onto the upload dialog's drag & drop zone.`);
  dropFileOnto(zone, file);
  dropFileOnto(dlg, file);
  await sleep(1000);
  const btn2 = [...dlg.querySelectorAll('button')].find((b) =>
    isVisible(b) && /^(upload|add|done|save)$/i.test(norm(b.innerText || b.textContent)));
  if (btn2) clickEl(btn2);
  if (finish(await pollOutcome(60000))) return;
  throw new Error(`Content: "${file.name}" did not register in the upload dialog (no input, picker bridge and drag & drop all failed). Census: ${uploadCensus()}`);
}

async function stageContent() {
  await goSection(['Content']);
  const blocker = detectBlocker(); if (blocker) throw stopErr(blocker);

  const { job } = await chrome.storage.local.get('job');
  if (!job || !job.files) throw new Error('Content: stored files are missing (job data not found).');
  const epubFile = base64ToFile(job.files.epub.base64, job.files.epub.name, job.files.epub.type);
  const coverFile = base64ToFile(job.files.cover.base64, job.files.cover.name, job.files.cover.type);

  // Arm the main-world bridge BEFORE any Browse click happens, so
  // the very first picker/input request is already served.
  await armMainWorld(job.files);

  await uploadOne('epub', epubFile);
  await sleep(1500);
  await uploadOne('cover', coverFile);
  await sleep(1500);

  const dlg = uploadDialogEl();
  if (dlg) {
    const close = [...dlg.querySelectorAll('button')].filter(isVisible)
      .find((b) => exactTextEq(b.innerText || b.textContent, 'Close'));
    if (close) { clickEl(close); await sleep(1500); }
  }
  const epubRow = await waitFor(() => currentEpubRow(job.ggkey), 90000, 2000);
  if (!epubRow) {
    throw new Error('Content: the EPUB did not appear on the Content tab after uploading — the upload may not have registered.');
  }
  const stepM = epubRow.text.match(/step\s+(\d)\s+of\s+6/i);
  if (stepM) L(`EPUB processing started: completed step ${stepM[1]} of 6 (current version).`);
  const rows = fileRows();
  const coverRow = rows.find((r) => /front cover|frontcover/i.test(r.text));
  if (coverRow) L('Cover registered (a "front cover" row is shown on the Content tab).');
  else L('Cover upload confirmed, but "front cover" registration was not visible — check on Review.', 'error');
  return { bookUrl: location.href };
}


/* ================= v9.9 input-connection fix =================
 * The v9.8 census found exactly ONE file input on the page — yet
 * the upload never registered. Two connection problems explain it:
 * (1) the finder could latch onto a PRE-EXISTING, unrelated input
 * (present before the Content stage even started) and "upload" the
 * book into a field the console ignores; (2) the dialog's real
 * input is created TRANSIENTLY by the page's own code — appended,
 * clicked and removed inside a single task — so every poll misses
 * it, and label/dispatchEvent activation never calls the patched
 * click() method. Fixes: a baseline snapshot (inputs that existed
 * before the stage are ignored while the dialog flow runs; inputs
 * inside the dialog or created afterwards win), a MutationObserver
 * that captures every file input the moment it is added (a
 * captured element stays usable even after the page removes it),
 * a ping-verified bridge arming, a capture-phase click interceptor
 * in the main world (see background.js), and an input census that
 * says WHERE each input lives. */
let pbuBaselineInputs = new Set();
let pbuCapturedInputs = [];
let pbuObserverStarted = false;

function startInputCapture() {
  if (pbuObserverStarted) return;
  pbuObserverStarted = true;
  pbuCapturedInputs = [];
  try {
    const obs = new MutationObserver((muts) => {
      for (const m of muts) {
        for (const n of m.addedNodes) {
          if (!n || n.nodeType !== 1) continue;
          if (n.tagName === 'INPUT' && String(n.type).toLowerCase() === 'file') pbuCapturedInputs.push(n);
          if (n.querySelectorAll) {
            for (const q of n.querySelectorAll('input[type="file"]')) pbuCapturedInputs.push(q);
          }
          if (n.shadowRoot) {
            for (const q of n.shadowRoot.querySelectorAll('input[type="file"]')) pbuCapturedInputs.push(q);
          }
        }
      }
    });
    obs.observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) { /* capture is best-effort */ }
}

function inputInDialog(i, dlg) {
  if (!dlg || !i) return false;
  if (dlg.contains(i)) return true;
  try {
    const root = i.getRootNode && i.getRootNode();
    if (root && root.host && dlg.contains(root.host)) return true;
  } catch (e) { /* ignore */ }
  return false;
}

function describeInputs() {
  const deep = deepFindFileInputs();
  if (!deep.length) return 'file inputs: none found anywhere on the page';
  const dlg = uploadDialogEl();
  const parts = deep.map((i, ix) => {
    const where = inputInDialog(i, dlg) ? 'INSIDE the upload dialog'
      : pbuBaselineInputs.has(i) ? 'pre-existing before this stage (ignored)'
      : 'outside the dialog, created during this stage';
    return `#${ix + 1} accept="${i.getAttribute('accept') || ''}" — ${where}${i.isConnected ? '' : ', DETACHED from the page'}`;
  });
  return 'file inputs found: ' + parts.join(' ; ');
}

function findUploadInput(kind) {
  const dlg = uploadDialogEl();
  const deep = deepFindFileInputs();
  if (!deep.length) return null;
  const inDlg = dlg ? deep.filter((i) => inputInDialog(i, dlg)) : [];
  let pool;
  if (inDlg.length) pool = inDlg;
  else if (dlg) pool = deep.filter((i) => !pbuBaselineInputs.has(i));
  else pool = deep;
  if (!pool.length) return null;
  const acceptOf = (i) => String(i.getAttribute('accept') || '').toLowerCase();
  return pool.find((i) => kind === 'cover'
    ? /image|jpe?g|png|tif/.test(acceptOf(i))
    : /epub|pdf/.test(acceptOf(i))) || pool[0];
}

async function armMainWorld(jobFiles) {
  if (pbuArmedOnce) return true;
  const payload = {
    files: [
      { key: 'epub', name: jobFiles.epub.name, type: jobFiles.epub.type, base64: jobFiles.epub.base64 },
      { key: 'cover', name: jobFiles.cover.name, type: jobFiles.cover.type, base64: jobFiles.cover.base64 }
    ]
  };
  let res = await pbuMainBridge('stage', { payload });
  if (!res.ok) {
    L('Content: could not arm the upload bridge (' + (res.error || 'unknown') + ') — continuing with direct methods.', 'error');
    return false;
  }
  let ping = await pbuMainBridge('ping');
  if (!ping.ok || !ping.result || !(ping.result.staged || []).includes('epub')) {
    res = await pbuMainBridge('stage', { payload });
    ping = await pbuMainBridge('ping');
  }
  if (ping.ok && ping.result && (ping.result.staged || []).length) {
    pbuArmedOnce = true;
    L(`Content: upload bridge armed and VERIFIED in the page world (staged: ${ping.result.staged.join(', ')}; click interception: ${ping.result.clickArmed ? 'on' : 'off'}).`);
    return true;
  }
  L('Content: the upload bridge did not verify in the page world — continuing with direct methods.', 'error');
  return false;
}

async function uploadOne(kind, file, successTimeout = 180000) {
  const beforeRows = new Set(fileRows().map((r) => r.text));
  const bannerBefore = /Successfully uploaded/i.test(pageText());
  const rowMatchesKind = (text) => kind === 'epub'
    ? /\.epub/i.test(text)
    : /frontcover|front cover/i.test(text) || (/\.(jpe?g|png)/i.test(text) && /cover/i.test(text));
  const finish = (outcome) => {
    if (!outcome) return false;
    if (outcome.fail) {
      throw new Error(`Content: "${file.name}" upload failed — the console reports: "${outcome.fail}"`);
    }
    L(`Uploaded ${file.name} — confirmed via its ${outcome.via === 'row' ? 'file row' : outcome.via === 'dialog' ? 'dialog entry' : 'success banner'}.`);
    return true;
  };
  const pollOutcome = (ms) => waitFor(() => {
    const rows = fileRows();
    for (const r of rows) {
      if (beforeRows.has(r.text)) continue;
      if (/failed|epubcheck|invalid|corrupt|not a valid/i.test(r.text)) return { fail: r.text.slice(0, 220) };
    }
    const newRow = rows.find((r) => !beforeRows.has(r.text) && rowMatchesKind(r.text));
    if (newRow) return { ok: true, via: 'row' };
    if (!bannerBefore && /Successfully uploaded/i.test(pageText())) return { ok: true, via: 'banner' };
    const d = uploadDialogEl();
    if (d) {
      const dt2 = norm(d.innerText || d.textContent);
      const kb = String(Math.max(1, Math.round(file.size / 1024)));
      if (dt2.includes(file.name) && (/\d+\s*%/.test(dt2) || /complete|uploaded/i.test(dt2) || dt2.includes(kb))) {
        return { ok: true, via: 'dialog' };
      }
    }
    return null;
  }, ms, 1200);

  let input = findUploadInput(kind);
  if (!input) {
    await revealFileInputs();
    input = findUploadInput(kind);
  }
  if (!input && pbuCapturedInputs.length) {
    // An input the page created (and may already have removed)
    // during this stage — its change handler is still attached.
    const captured = pbuCapturedInputs.filter((i) => !pbuBaselineInputs.has(i));
    if (captured.length) {
      input = captured[captured.length - 1];
      L(`Content: using a file input the page itself created during this stage for the ${kind} upload.`);
    }
  }

  if (input) {
    assignFileToInput(input, file);
    if (!input.files || !input.files[0] || input.files[0].name !== file.name) {
      L(`Content: warning — after assigning, the ${kind} input does not show "${file.name}".`, 'error');
    }
    await sleep(1000);
    const dlg0 = uploadDialogEl() || (input.closest ? input.closest('[role="dialog"], .mat-dialog-container, mat-dialog-container') : null);
    if (dlg0) {
      const btn = [...dlg0.querySelectorAll('button')].find((b) =>
        isVisible(b) && /^(upload|add|done|save)$/i.test(norm(b.innerText || b.textContent)));
      if (btn) clickEl(btn);
    }
    if (finish(await pollOutcome(dlg0 ? 90000 : successTimeout))) return;
    if (!dlg0) {
      const errText = findErrorText();
      throw new Error(`Content: "${file.name}" upload did not confirm` +
        (errText ? ': ' + errText : ' (timed out waiting for its file row / success banner).'));
    }
    L('Content: the dialog input did not confirm the upload — trying the bridge routes.');
  } else if (uploadDialogEl()) {
    if (finish(await pollOutcome(3000))) return;
  }

  const dlg = uploadDialogEl();
  if (!dlg) {
    throw new Error(`Content: no usable file input for the ${kind} upload, and the upload dialog could not be opened. ${describeInputs()}`);
  }

  const browseBtn = [...dlg.querySelectorAll('button, [role="button"]')].filter(isVisible)
    .find((b) => exactTextEq(b.innerText || b.textContent, 'Browse'));
  if (browseBtn) {
    L(`Content: clicking "Browse" — the armed bridge supplies "${file.name}" to the picker.`);
    clickEl(browseBtn);
    await sleep(800);
    if (finish(await pollOutcome(45000))) return;
    // The Browse click may have created the transient input just
    // now — if the capture net caught it, serve the file on it.
    const fresh = pbuCapturedInputs.filter((i) => !pbuBaselineInputs.has(i));
    if (fresh.length) {
      const cap = fresh[fresh.length - 1];
      assignFileToInput(cap, file);
      await sleep(800);
      if (finish(await pollOutcome(30000))) return;
    }
  }

  const dropRes = await pbuMainBridge('drop', { kind });
  if (dropRes.ok) {
    L(`Content: main-world drag & drop dispatched for "${file.name}" (${dropRes.result || 'ok'}).`);
    await sleep(800);
    if (finish(await pollOutcome(45000))) return;
  } else {
    L('Content: main-world drop unavailable (' + (dropRes.error || 'no response') + ').', 'error');
  }

  const zone = [...dlg.querySelectorAll('*')].filter(isVisible)
    .find((e) => /drag and drop/i.test(norm(e.innerText || e.textContent)) && e.querySelectorAll('*').length < 12) || dlg;
  L(`Content: dropping "${file.name}" onto the upload dialog's drag & drop zone.`);
  dropFileOnto(zone, file);
  dropFileOnto(dlg, file);
  await sleep(1000);
  const btn2 = [...dlg.querySelectorAll('button')].find((b) =>
    isVisible(b) && /^(upload|add|done|save)$/i.test(norm(b.innerText || b.textContent)));
  if (btn2) clickEl(btn2);
  if (finish(await pollOutcome(60000))) return;
  throw new Error(`Content: "${file.name}" did not register in the upload dialog (input, picker bridge and drag & drop all failed). ${describeInputs()}`);
}

async function stageContent() {
  await goSection(['Content']);
  const blocker = detectBlocker(); if (blocker) throw stopErr(blocker);

  const { job } = await chrome.storage.local.get('job');
  if (!job || !job.files) throw new Error('Content: stored files are missing (job data not found).');
  const epubFile = base64ToFile(job.files.epub.base64, job.files.epub.name, job.files.epub.type);
  const coverFile = base64ToFile(job.files.cover.base64, job.files.cover.name, job.files.cover.type);

  // Snapshot whatever file inputs already exist BEFORE we touch
  // anything, start the capture net, then arm the bridge — all
  // before the first Browse click.
  pbuBaselineInputs = new Set(deepFindFileInputs());
  startInputCapture();
  await armMainWorld(job.files);
  L('Content: input census at stage start — ' + describeInputs() + '.');

  await uploadOne('epub', epubFile);
  await sleep(1500);
  await uploadOne('cover', coverFile);
  await sleep(1500);

  const dlg = uploadDialogEl();
  if (dlg) {
    const close = [...dlg.querySelectorAll('button')].filter(isVisible)
      .find((b) => exactTextEq(b.innerText || b.textContent, 'Close'));
    if (close) { clickEl(close); await sleep(1500); }
  }
  const epubRow = await waitFor(() => currentEpubRow(job.ggkey), 90000, 2000);
  if (!epubRow) {
    throw new Error('Content: the EPUB did not appear on the Content tab after uploading — the upload may not have registered.');
  }
  const stepM = epubRow.text.match(/step\s+(\d)\s+of\s+6/i);
  if (stepM) L(`EPUB processing started: completed step ${stepM[1]} of 6 (current version).`);
  const rows = fileRows();
  const coverRow = rows.find((r) => /front cover|frontcover/i.test(r.text));
  if (coverRow) L('Cover registered (a "front cover" row is shown on the Content tab).');
  else L('Cover upload confirmed, but "front cover" registration was not visible — check on Review.', 'error');
  return { bookUrl: location.href };
}

/* ================= v9.10 dialog-cycle fix =================
 * Live run of v9.9 (2026-10-23, new wizard book GGKEY:PDJF89RNYTC):
 * the EPUB finally uploaded — the dialog showed its entry at
 * 100%, its row landed on the Content tab — but the COVER then
 * failed with "file inputs: none found anywhere on the page".
 * The user's screenshot shows why: this console's "Upload content
 * and cover" dialog is ONE-SHOT. While it is accepting a file it
 * offers a drop zone and a Browse button; the moment the file
 * completes, both vanish and the dialog becomes a receipt — the
 * file's name, its size, "100%", and a single Close button. There
 * is no way to add a second file to that dialog session, yet v9.9
 * kept trying its routes inside the finished dialog (even feeding
 * the cover to a detached input left over from the EPUB).
 * The user's instruction: upload EPUB and cover in one run; when
 * each upload finishes, click Close; at the end, Save. So every
 * file now gets its OWN dialog cycle:
 *   open a FRESH dialog -> serve the file (dialog input / bridge-
 *   fed Browse / main-world drop / isolated drop) -> wait until
 *   the entry shows 100% -> click Close.
 * After both files, stageContent verifies the tab rows and then
 * saves the step. Two guards keep retries honest: a file already
 * uploaded earlier in this page session is not uploaded again
 * (a stage retry only fetches what is missing), and the capture-
 * net fallback only uses inputs created during THIS file's cycle,
 * never a previous file's leftovers. */
const pbuDoneUploads = new Set();

function pbuDialogCloseButton(dlg) {
  if (!dlg) return null;
  return [...dlg.querySelectorAll('button')].filter(isVisible)
    .find((b) => exactTextEq(b.innerText || b.textContent, 'Close')) || null;
}

async function pbuCloseUploadDialog(why) {
  const dlg = uploadDialogEl();
  if (!dlg) return true;
  const btn = pbuDialogCloseButton(dlg);
  if (!btn) {
    L('Content: the upload dialog is open but shows no Close button' + (why ? ' (' + why + ')' : '') + '.', 'error');
    return false;
  }
  L('Content: clicking "Close" on the upload dialog' + (why ? ' — ' + why : '') + '.');
  clickEl(btn);
  const gone = await waitFor(() => !uploadDialogEl(), 10000, 400);
  if (!gone) L('Content: the upload dialog stayed open after Close was clicked.', 'error');
  return !!gone;
}

function pbuDialogText() {
  const d = uploadDialogEl();
  return d ? norm(d.innerText || d.textContent) : '';
}

async function pbuWaitDialogComplete(file, ms = 90000) {
  // Registration alone is not enough: wait until the dialog entry
  // reports the transfer itself as finished (100%, "complete", or
  // equal up/down sizes) before closing — closing mid-transfer
  // can cancel the file.
  const res = await waitFor(() => {
    const t = pbuDialogText();
    if (!t) return 'dialog-gone';
    if (!t.includes(file.name)) return null;
    if (/100\s*%/.test(t) || /complete|completed/i.test(t)) return 'done';
    const m = t.match(/([\d.]+)\s*(KB|MB|GB)\s*\/\s*([\d.]+)\s*(KB|MB|GB)/i);
    if (m && parseFloat(m[1]) === parseFloat(m[3]) && m[2].toUpperCase() === m[4].toUpperCase()) return 'done';
    return null;
  }, ms, 1000);
  if (!res) {
    L(`Content: "${file.name}" is registered in the dialog but did not show 100% within ${Math.round(ms / 1000)}s — closing anyway; the Content tab rows are verified next.`, 'error');
  }
  return res;
}

function pbuDialogActionable(dlg) {
  // A fresh dialog can accept a file: it has a Browse button, a
  // drag & drop zone, or a file input inside it. A completed
  // (receipt) dialog has none of these — only Close.
  if (!dlg) return false;
  const hasBrowse = [...dlg.querySelectorAll('button, [role="button"]')].filter(isVisible)
    .some((b) => exactTextEq(b.innerText || b.textContent, 'Browse'));
  if (hasBrowse) return true;
  if ([...dlg.querySelectorAll('*')].some((e) => /drag and drop/i.test(norm(e.innerText || e.textContent)))) return true;
  return deepFindFileInputs().some((i) => inputInDialog(i, dlg));
}

async function pbuOpenFreshDialog() {
  // Close whatever dialog state is lying around (typically the
  // previous file's receipt), then open a new dialog and wait
  // until it can actually accept a file.
  await pbuCloseUploadDialog('a fresh dialog is needed for the next file');
  for (let attempt = 1; attempt <= 2; attempt++) {
    const opened = await openUploadDialog();
    if (!opened) return null;
    const dlg = await waitFor(() => {
      const d = uploadDialogEl();
      return d && pbuDialogActionable(d) ? d : null;
    }, 12000, 500);
    if (dlg) return dlg;
    await pbuCloseUploadDialog('the dialog opened without a way to add a file');
  }
  return null;
}

async function uploadOne(kind, file, successTimeout = 180000) {
  const beforeRows = new Set(fileRows().map((r) => r.text));
  const bannerBefore = /Successfully uploaded/i.test(pageText());
  const rowMatchesKind = (text) => kind === 'epub'
    ? /\.epub/i.test(text)
    : /frontcover|front cover/i.test(text) || (/\.(jpe?g|png)/i.test(text) && /cover/i.test(text));
  const finish = (outcome) => {
    if (!outcome) return false;
    if (outcome.fail) {
      throw new Error(`Content: "${file.name}" upload failed — the console reports: "${outcome.fail}"`);
    }
    L(`Uploaded ${file.name} — confirmed via its ${outcome.via === 'row' ? 'file row' : outcome.via === 'dialog' ? 'dialog entry' : 'success banner'}.`);
    return true;
  };
  const pollOutcome = (ms) => waitFor(() => {
    const rows = fileRows();
    for (const r of rows) {
      if (beforeRows.has(r.text)) continue;
      if (/failed|epubcheck|invalid|corrupt|not a valid/i.test(r.text)) return { fail: r.text.slice(0, 220) };
    }
    const newRow = rows.find((r) => !beforeRows.has(r.text) && rowMatchesKind(r.text));
    if (newRow) return { ok: true, via: 'row' };
    if (!bannerBefore && /Successfully uploaded/i.test(pageText())) return { ok: true, via: 'banner' };
    const d = uploadDialogEl();
    if (d) {
      const dt2 = norm(d.innerText || d.textContent);
      const kb = String(Math.max(1, Math.round(file.size / 1024)));
      if (dt2.includes(file.name) && (/\d+\s*%/.test(dt2) || /complete|uploaded/i.test(dt2) || dt2.includes(kb))) {
        return { ok: true, via: 'dialog' };
      }
    }
    return null;
  }, ms, 1200);

  const doneKey = kind + ':' + file.name + ':' + file.size;
  if (pbuDoneUploads.has(doneKey)) {
    L(`Content: "${file.name}" was already uploaded earlier in this session — skipping it and moving to the next file.`);
    await pbuCloseUploadDialog('that file is already uploaded');
    return;
  }
  // The run was interrupted after this file completed inside an
  // open dialog but before Close — just finish its cycle.
  if (pbuDialogText().includes(file.name)) {
    await pbuWaitDialogComplete(file);
    await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
    pbuDoneUploads.add(doneKey);
    L(`Uploaded ${file.name} — confirmed via its dialog entry.`);
    return;
  }

  const captureMark = pbuCapturedInputs.length;
  const freshCaptured = () => pbuCapturedInputs.slice(captureMark)
    .filter((i) => !pbuBaselineInputs.has(i));

  // ---- Dialog route: one fresh dialog per file. ----
  const dlg = await pbuOpenFreshDialog();
  if (dlg) {
    let confirmed = false;

    // Route A: an input that belongs to THIS dialog, or one the
    // page created inside it during this file's cycle.
    let input = findUploadInput(kind);
    if (input && !inputInDialog(input, dlg)) input = null;
    if (!input) {
      const cap = freshCaptured();
      if (cap.length) input = cap[cap.length - 1];
    }
    if (input) {
      assignFileToInput(input, file);
      if (!input.files || !input.files[0] || input.files[0].name !== file.name) {
        L(`Content: warning — after assigning, the ${kind} input does not show "${file.name}".`, 'error');
      }
      await sleep(1000);
      const btn = [...dlg.querySelectorAll('button')].find((b) =>
        isVisible(b) && /^(upload|add|done|save)$/i.test(norm(b.innerText || b.textContent)));
      if (btn) clickEl(btn);
      confirmed = finish(await pollOutcome(90000));
    }

    // Route B: Browse, fed by the armed main-world bridge. The
    // bridge serves the next unserved staged file, so on the
    // cover's cycle this hands over the cover, not the EPUB again.
    if (!confirmed) {
      const browseBtn = [...dlg.querySelectorAll('button, [role="button"]')].filter(isVisible)
        .find((b) => exactTextEq(b.innerText || b.textContent, 'Browse'));
      if (browseBtn) {
        L(`Content: clicking "Browse" — the armed bridge supplies "${file.name}" to the picker.`);
        clickEl(browseBtn);
        await sleep(800);
        confirmed = finish(await pollOutcome(45000));
        if (!confirmed) {
          const cap = freshCaptured();
          if (cap.length) {
            assignFileToInput(cap[cap.length - 1], file);
            await sleep(800);
            confirmed = finish(await pollOutcome(30000));
          }
        }
      }
    }

    // Route C: main-world drag & drop.
    if (!confirmed) {
      const dropRes = await pbuMainBridge('drop', { kind });
      if (dropRes.ok) {
        L(`Content: main-world drag & drop dispatched for "${file.name}" (${dropRes.result || 'ok'}).`);
        await sleep(800);
        confirmed = finish(await pollOutcome(45000));
      } else {
        L('Content: main-world drop unavailable (' + (dropRes.error || 'no response') + ').', 'error');
      }
    }

    // Route D: isolated-world drag & drop onto the fresh zone.
    if (!confirmed) {
      const liveDlg = uploadDialogEl() || dlg;
      const zone = [...liveDlg.querySelectorAll('*')].filter(isVisible)
        .find((e) => /drag and drop/i.test(norm(e.innerText || e.textContent)) && e.querySelectorAll('*').length < 12) || liveDlg;
      L(`Content: dropping "${file.name}" onto the upload dialog's drag & drop zone.`);
      dropFileOnto(zone, file);
      dropFileOnto(liveDlg, file);
      await sleep(1000);
      confirmed = finish(await pollOutcome(60000));
    }

    if (!confirmed) {
      throw new Error(`Content: "${file.name}" did not register in the upload dialog (input, picker bridge and drag & drop all failed). ${describeInputs()}`);
    }
    // The file registered — wait for its transfer to reach 100%,
    // then Close this dialog so the next file gets a fresh one.
    await pbuWaitDialogComplete(file);
    await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
    pbuDoneUploads.add(doneKey);
    return;
  }

  // ---- Classic route: this console build has no upload dialog —
  // the Content tab carries its own file inputs. ----
  let input = findUploadInput(kind);
  if (!input) {
    await revealFileInputs();
    input = findUploadInput(kind);
  }
  if (!input) {
    const cap = pbuCapturedInputs.filter((i) => !pbuBaselineInputs.has(i));
    if (cap.length) input = cap[cap.length - 1];
  }
  if (!input) {
    throw new Error(`Content: no usable file input for the ${kind} upload, and the upload dialog could not be opened. ${describeInputs()}`);
  }
  assignFileToInput(input, file);
  await sleep(1000);
  if (finish(await pollOutcome(successTimeout))) {
    pbuDoneUploads.add(doneKey);
    return;
  }
  const errText = findErrorText();
  throw new Error(`Content: "${file.name}" upload did not confirm` +
    (errText ? ': ' + errText : ' (timed out waiting for its file row / success banner).'));
}

async function pbuSaveContentStep() {
  // The user's rule: uploads finished and dialog closed — now
  // Save the Content step. Never fail the stage here; the files
  // themselves are already verified on the tab.
  try {
    let btn = null;
    try { btn = findSaveButton(); } catch (e) { btn = null; }
    if (btn) {
      const res = await saveAndWait({});
      if (res && res.saved) {
        L('Content: saved — the Save button was clicked after both uploads.');
        return;
      }
      L('Content: the save click did not confirm (' + ((res && res.error) || 'unknown') + ') — the uploaded files themselves are registered on the tab above.', 'error');
      return;
    }
    const cont = [...document.querySelectorAll('button')].filter(isVisible)
      .find((b) => exactTextEq(b.innerText || b.textContent, 'Continue'));
    if (cont) {
      clickEl(cont);
      await sleep(2000);
      await dismissInfoDialogs();
      L('Content: no separate Save button on this page — clicked "Continue" to save the step.');
      return;
    }
    L('Content: no Save button on this page — the console keeps the uploaded files automatically.');
  } catch (e) {
    L('Content: the save step hit a problem (' + String((e && e.message) || e) + ') — the uploads themselves are done.', 'error');
  }
}

async function stageContent() {
  await goSection(['Content']);
  const blocker = detectBlocker(); if (blocker) throw stopErr(blocker);

  const { job } = await chrome.storage.local.get('job');
  if (!job || !job.files) throw new Error('Content: stored files are missing (job data not found).');
  const epubFile = base64ToFile(job.files.epub.base64, job.files.epub.name, job.files.epub.type);
  const coverFile = base64ToFile(job.files.cover.base64, job.files.cover.name, job.files.cover.type);

  // Snapshot whatever file inputs already exist BEFORE we touch
  // anything, start the capture net, then arm the bridge — all
  // before the first dialog opens.
  pbuBaselineInputs = new Set(deepFindFileInputs());
  startInputCapture();
  await armMainWorld(job.files);
  L('Content: input census at stage start — ' + describeInputs() + '.');

  // One dialog cycle per file (v9.10): each uploadOne opens a
  // fresh dialog, waits for the entry to reach 100%, and clicks
  // Close — the dialog accepts only one file per session.
  await uploadOne('epub', epubFile);
  await sleep(1000);
  await uploadOne('cover', coverFile);
  await sleep(1000);
  await pbuCloseUploadDialog('both files are uploaded');

  const epubRow = await waitFor(() => currentEpubRow(job.ggkey), 90000, 2000);
  if (!epubRow) {
    throw new Error('Content: the EPUB did not appear on the Content tab after uploading — the upload may not have registered.');
  }
  const stepM = epubRow.text.match(/step\s+(\d)\s+of\s+6/i);
  if (stepM) L(`EPUB processing started: completed step ${stepM[1]} of 6 (current version).`);
  const rows = fileRows();
  const coverRow = rows.find((r) => /front cover|frontcover/i.test(r.text));
  if (coverRow) L('Cover registered (a "front cover" row is shown on the Content tab).');
  else L('Cover upload confirmed, but "front cover" registration was not visible — check on Review.', 'error');

  // Dialog closed, files verified — now Save the step.
  await pbuSaveContentStep();
  return { bookUrl: location.href };
}

/* ================= v9.11 ground-truth dialog fix =================
 * Built from the upload dialog's ACTUAL source, captured from the
 * user's Chrome on 2026-10-23 in both states (at the user's
 * direction — no more guessing):
 *
 * FRESH dialog: mat-dialog-content holds ONE component —
 *   <div xapuploaderdropzone class="xap-uploader-dropzone upload-area">
 *     <div class="upload-area-items">
 *       icon, "Drag and drop", "or",
 *       <button xapuploadertrigger>Browse</button>
 *       <input type="file" name="Filedata" multiple
 *              accept=".pdf,.epub,.zip,.jpg,.jpeg,.png,.tiff"
 *              aria-hidden="true" tabindex="-1"
 *              style="position:absolute; 81x36px; opacity:0; display:none">
 *     </div>
 *   </div>
 * The dialog HAS its own file input — hidden (display:none) and
 * rendered inside the component — and it accepts MULTIPLE files.
 * Earlier finders failed because they searched the tab (no input
 * there), searched before the component rendered its input, or
 * searched in the receipt state where the input no longer exists.
 *
 * RECEIPT dialog (after files are accepted): the dropzone, the
 * Browse button AND the input are ALL removed; mat-dialog-content
 * holds one <upload-file> card per file:
 *   <upload-file><mat-card>
 *     <div class="name">The-Book.epub</div>
 *     <div class="progress">264.01KB / 264.01KB</div>
 *     <div class="status">100%</div>
 *   </mat-card></upload-file>
 * and the actions bar keeps only Close. So the console's intended
 * flow is: select ALL files at once, watch the cards fill, Close.
 *
 * v9.11 therefore leads with the console's own design:
 *   1. open the dialog, WAIT for its input[name="Filedata"] to
 *      render (poll — it appears a beat after the dialog opens);
 *   2. assign EPUB + cover TOGETHER in one change (multiple);
 *   3. confirm via the real receipt selectors — an upload-file
 *      card per file, .status at 100% (or .progress sizes equal);
 *   4. Close. Anything that did not complete falls back to the
 *      v9.10 per-file dialog cycle, then to the bridge/drop
 *      routes, so no previously-working path is lost. */
function pbuDialogFileInput() {
  const d = uploadDialogEl();
  if (!d) return null;
  return d.querySelector('input[type="file"][name="Filedata"]') || d.querySelector('input[type="file"]');
}

async function pbuWaitForDialogInput(ms = 20000) {
  return waitFor(() => pbuDialogFileInput(), ms, 400);
}

function assignFilesToInput(input, files) {
  const dt = new DataTransfer();
  for (const f of files) dt.items.add(f);
  input.files = dt.files;
  input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
  input.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
}

function pbuDialogEntry(file) {
  const d = uploadDialogEl();
  if (!d) return null;
  for (const c of d.querySelectorAll('upload-file')) {
    const nm = c.querySelector('.name');
    if (nm && norm(nm.textContent).includes(file.name)) {
      const st = c.querySelector('.status');
      const pr = c.querySelector('.progress');
      return {
        el: c,
        text: norm(c.innerText || c.textContent),
        status: st ? norm(st.textContent) : '',
        progress: pr ? norm(pr.textContent) : ''
      };
    }
  }
  return null;
}

function pbuEntryComplete(file) {
  const e = pbuDialogEntry(file);
  if (!e) return false;
  if (/100\s*%/.test(e.status)) return true;
  const m = e.progress.match(/([\d.]+)\s*(KB|MB|GB)\s*\/\s*([\d.]+)\s*(KB|MB|GB)/i);
  return !!(m && parseFloat(m[1]) === parseFloat(m[3]) && m[2].toUpperCase() === m[4].toUpperCase());
}

async function pbuWaitEntryComplete(file, ms = 120000) {
  const res = await waitFor(() => {
    const e = pbuDialogEntry(file);
    if (e) {
      if (pbuEntryComplete(file)) return 'done';
      if (/fail|error/i.test(e.text)) return 'error:' + e.text.slice(0, 200);
      return null;
    }
    const t = pbuDialogText();
    if (!t) return 'dialog-gone';
    if (t.includes(file.name) && (/100\s*%/.test(t) || /complete/i.test(t))) return 'done';
    return null;
  }, ms, 1000);
  if (!res) {
    L(`Content: "${file.name}" is registered in the dialog but did not reach 100% within ${Math.round(ms / 1000)}s — closing anyway; the Content tab rows are verified next.`, 'error');
  } else if (String(res).startsWith('error:')) {
    L(`Content: the dialog reports a problem for "${file.name}": ${String(res).slice(6)}`, 'error');
  }
  return res;
}

async function pbuUploadTogether(epubFile, coverFile) {
  // The console's intended flow: ONE dialog, BOTH files in a
  // single selection (the input is multiple), both cards to
  // 100%, then Close. Returns which files completed.
  const result = { epub: false, cover: false };
  const dlg = await pbuOpenFreshDialog();
  if (!dlg) return result;
  const input = await pbuWaitForDialogInput(20000);
  if (!input) {
    L('Content: the dialog\'s own file input did not appear for the combined upload — falling back to one file at a time.');
    await pbuCloseUploadDialog('combined upload not possible in this dialog');
    return result;
  }
  L('Content: uploading the EPUB and the cover TOGETHER in one dialog (the console\'s input accepts multiple files).');
  assignFilesToInput(input, [epubFile, coverFile]);
  await sleep(1000);
  const bothIn = await waitFor(() => {
    const e1 = pbuDialogEntry(epubFile);
    const e2 = pbuDialogEntry(coverFile);
    if (e1 && /fail|error/i.test(e1.text)) return 'epub-error';
    if (e2 && /fail|error/i.test(e2.text)) return 'cover-error';
    return e1 && e2 ? 'both' : null;
  }, 30000, 800);
  if (bothIn === 'both') {
    await pbuWaitEntryComplete(epubFile, 150000);
    await pbuWaitEntryComplete(coverFile, 150000);
    result.epub = pbuEntryComplete(epubFile);
    result.cover = pbuEntryComplete(coverFile);
    if (result.epub && result.cover) {
      L(`Uploaded BOTH files together — "${epubFile.name}" and "${coverFile.name}" both reached 100% in a single dialog.`);
    }
  } else {
    // One (or neither) file registered — settle whichever did,
    // close, and let the per-file cycle fetch whatever is missing.
    if (pbuDialogEntry(epubFile)) {
      await pbuWaitEntryComplete(epubFile, 90000);
      result.epub = pbuEntryComplete(epubFile);
    }
    if (pbuDialogEntry(coverFile)) {
      await pbuWaitEntryComplete(coverFile, 90000);
      result.cover = pbuEntryComplete(coverFile);
    }
    if (!result.epub && !result.cover) {
      L('Content: the combined assignment did not register — falling back to one file at a time.', 'error');
    }
  }
  await pbuCloseUploadDialog('the combined upload finished');
  if (result.epub) pbuDoneUploads.add('epub:' + epubFile.name + ':' + epubFile.size);
  if (result.cover) pbuDoneUploads.add('cover:' + coverFile.name + ':' + coverFile.size);
  return result;
}

async function uploadOne(kind, file, successTimeout = 180000) {
  const beforeRows = new Set(fileRows().map((r) => r.text));
  const bannerBefore = /Successfully uploaded/i.test(pageText());
  const rowMatchesKind = (text) => kind === 'epub'
    ? /\.epub/i.test(text)
    : /frontcover|front cover/i.test(text) || (/\.(jpe?g|png)/i.test(text) && /cover/i.test(text));
  const finish = (outcome) => {
    if (!outcome) return false;
    if (outcome.fail) {
      throw new Error(`Content: "${file.name}" upload failed — the console reports: "${outcome.fail}"`);
    }
    L(`Uploaded ${file.name} — confirmed via its ${outcome.via === 'row' ? 'file row' : outcome.via === 'dialog' ? 'dialog entry' : 'success banner'}.`);
    return true;
  };
  const pollOutcome = (ms) => waitFor(() => {
    const rows = fileRows();
    for (const r of rows) {
      if (beforeRows.has(r.text)) continue;
      if (/failed|epubcheck|invalid|corrupt|not a valid/i.test(r.text)) return { fail: r.text.slice(0, 220) };
    }
    const newRow = rows.find((r) => !beforeRows.has(r.text) && rowMatchesKind(r.text));
    if (newRow) return { ok: true, via: 'row' };
    if (!bannerBefore && /Successfully uploaded/i.test(pageText())) return { ok: true, via: 'banner' };
    if (pbuDialogEntry(file)) return { ok: true, via: 'dialog' };
    return null;
  }, ms, 1200);

  const doneKey = kind + ':' + file.name + ':' + file.size;
  if (pbuDoneUploads.has(doneKey)) {
    L(`Content: "${file.name}" was already uploaded earlier in this session — skipping it and moving to the next file.`);
    await pbuCloseUploadDialog('that file is already uploaded');
    return;
  }
  // Interrupted after this file completed inside an open dialog
  // but before Close — just finish its cycle.
  if (pbuDialogEntry(file) || pbuDialogText().includes(file.name)) {
    const r = await pbuWaitEntryComplete(file);
    if (r === 'done' || r === 'dialog-gone') {
      await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
      pbuDoneUploads.add(doneKey);
      L(`Uploaded ${file.name} — confirmed via its dialog entry.`);
      return;
    }
  }

  const captureMark = pbuCapturedInputs.length;
  const freshCaptured = () => pbuCapturedInputs.slice(captureMark)
    .filter((i) => !pbuBaselineInputs.has(i));

  // ---- Dialog route: one fresh dialog per file. ----
  const dlg = await pbuOpenFreshDialog();
  if (dlg) {
    let confirmed = false;

    // Route A (primary): the dialog's OWN input[name="Filedata"],
    // waited for — the ground-truth route from the captured
    // dialog source.
    const dlgInput = await pbuWaitForDialogInput(20000);
    if (dlgInput) {
      L(`Content: the dialog's own file input is ready — assigning "${file.name}" to it directly.`);
      assignFilesToInput(dlgInput, [file]);
      await sleep(800);
      confirmed = finish(await pollOutcome(60000));
      if (confirmed) {
        await pbuWaitEntryComplete(file);
        await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
        pbuDoneUploads.add(doneKey);
        return;
      }
      L('Content: the direct input assignment did not confirm — trying the remaining routes.');
    }

    // Route B: Browse, fed by the armed main-world bridge.
    if (!confirmed) {
      const browseBtn = [...dlg.querySelectorAll('button, [role="button"]')].filter(isVisible)
        .find((b) => exactTextEq(b.innerText || b.textContent, 'Browse'));
      if (browseBtn) {
        L(`Content: clicking "Browse" — the armed bridge supplies "${file.name}" to the picker.`);
        clickEl(browseBtn);
        await sleep(800);
        confirmed = finish(await pollOutcome(45000));
        if (!confirmed) {
          const cap = freshCaptured();
          if (cap.length) {
            assignFilesToInput(cap[cap.length - 1], [file]);
            await sleep(800);
            confirmed = finish(await pollOutcome(30000));
          }
        }
      }
    }

    // Route C: main-world drag & drop.
    if (!confirmed) {
      const dropRes = await pbuMainBridge('drop', { kind });
      if (dropRes.ok) {
        L(`Content: main-world drag & drop dispatched for "${file.name}" (${dropRes.result || 'ok'}).`);
        await sleep(800);
        confirmed = finish(await pollOutcome(45000));
      } else {
        L('Content: main-world drop unavailable (' + (dropRes.error || 'no response') + ').', 'error');
      }
    }

    // Route D: isolated-world drag & drop onto the drop zone.
    if (!confirmed) {
      const liveDlg = uploadDialogEl() || dlg;
      const zone = [...liveDlg.querySelectorAll('*')].filter(isVisible)
        .find((e) => /drag and drop/i.test(norm(e.innerText || e.textContent)) && e.querySelectorAll('*').length < 12) || liveDlg;
      L(`Content: dropping "${file.name}" onto the upload dialog's drag & drop zone.`);
      dropFileOnto(zone, file);
      dropFileOnto(liveDlg, file);
      await sleep(1000);
      confirmed = finish(await pollOutcome(60000));
    }

    if (!confirmed) {
      throw new Error(`Content: "${file.name}" did not register in the upload dialog (dialog input, picker bridge and drag & drop all failed). ${describeInputs()}`);
    }
    await pbuWaitEntryComplete(file);
    await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
    pbuDoneUploads.add(doneKey);
    return;
  }

  // ---- Classic route: this console build has no upload dialog —
  // the Content tab carries its own file inputs. ----
  let input = findUploadInput(kind);
  if (!input) {
    await revealFileInputs();
    input = findUploadInput(kind);
  }
  if (!input) {
    const cap = pbuCapturedInputs.filter((i) => !pbuBaselineInputs.has(i));
    if (cap.length) input = cap[cap.length - 1];
  }
  if (!input) {
    throw new Error(`Content: no usable file input for the ${kind} upload, and the upload dialog could not be opened. ${describeInputs()}`);
  }
  assignFilesToInput(input, [file]);
  await sleep(1000);
  if (finish(await pollOutcome(successTimeout))) {
    pbuDoneUploads.add(doneKey);
    return;
  }
  const errText = findErrorText();
  throw new Error(`Content: "${file.name}" upload did not confirm` +
    (errText ? ': ' + errText : ' (timed out waiting for its file row / success banner).'));
}

async function stageContent() {
  await goSection(['Content']);
  const blocker = detectBlocker(); if (blocker) throw stopErr(blocker);

  const { job } = await chrome.storage.local.get('job');
  if (!job || !job.files) throw new Error('Content: stored files are missing (job data not found).');
  const epubFile = base64ToFile(job.files.epub.base64, job.files.epub.name, job.files.epub.type);
  const coverFile = base64ToFile(job.files.cover.base64, job.files.cover.name, job.files.cover.type);

  // Snapshot whatever file inputs already exist BEFORE we touch
  // anything, start the capture net, then arm the bridge — all
  // before the first dialog opens.
  pbuBaselineInputs = new Set(deepFindFileInputs());
  startInputCapture();
  await armMainWorld(job.files);
  L('Content: input census at stage start — ' + describeInputs() + '.');

  // First try the console's own design (v9.11): both files
  // together in ONE dialog via its multiple-file input. Whatever
  // is still missing afterwards gets its own dialog cycle. Files
  // already uploaded earlier in this session are never fetched
  // again (the combined attempt only runs when both are missing).
  const epubKey = 'epub:' + epubFile.name + ':' + epubFile.size;
  const coverKey = 'cover:' + coverFile.name + ':' + coverFile.size;
  let together = { epub: pbuDoneUploads.has(epubKey), cover: pbuDoneUploads.has(coverKey) };
  if (!together.epub && !together.cover) {
    together = await pbuUploadTogether(epubFile, coverFile);
  }
  if (!together.epub) { await uploadOne('epub', epubFile); await sleep(1000); }
  if (!together.cover) { await uploadOne('cover', coverFile); await sleep(1000); }
  await pbuCloseUploadDialog('both files are uploaded');

  const epubRow = await waitFor(() => currentEpubRow(job.ggkey), 90000, 2000);
  if (!epubRow) {
    throw new Error('Content: the EPUB did not appear on the Content tab after uploading — the upload may not have registered.');
  }
  const stepM = epubRow.text.match(/step\s+(\d)\s+of\s+6/i);
  if (stepM) L(`EPUB processing started: completed step ${stepM[1]} of 6 (current version).`);
  const rows = fileRows();
  const coverRow = rows.find((r) => /front cover|frontcover/i.test(r.text));
  if (coverRow) L('Cover registered (a "front cover" row is shown on the Content tab).');
  else L('Cover upload confirmed, but "front cover" registration was not visible — check on Review.', 'error');

  // Dialog closed, files verified — now Save the step.
  await pbuSaveContentStep();
  return { bookUrl: location.href };
}

/* ================= v9.12 evidence-preserving + page-world assign =================
 * Post-mortem of the v9.11 live run (2026-10-23, GGKEY:GK4ZA7GQC0Q;
 * full log supplied by the user): every metadata stage passed, then
 * the content stage burned ~7 minutes and failed. Two structural
 * defects made that run both fragile and undiagnosable:
 *   (1) runStage CLEARS stageLog between its two attempts — the
 *       first attempt's log (the one containing the original
 *       failure) is thrown away, so the panel only ever shows the
 *       second attempt's cascade. The runStage override below keeps
 *       ONE cumulative log across attempts, with a marker line.
 *   (2) The confirmations relied on wall-clock (Date.now) deadlines
 *       while the tab sat in the background — a throttled/frozen
 *       tab wakes to find every deadline already blown, so each
 *       route "gave up" instantly. The v9.12 confirmations use
 *       pbuPoll: a guaranteed MINIMUM number of real checks, spaced
 *       by sleeps, on top of the time budget.
 * And one route upgrade, from the same evidence: the bridge WAS
 * alive in the page world (its drop action answered), so the lead
 * route is now a PAGE-WORLD DIRECT ASSIGN (background.js,
 * pbuMainAssign): the page world itself sets the dialog input's
 * files from the staged page-world Files and dispatches the
 * change — byte-for-byte the picker's own end result, with a
 * read-back of how many files the input holds afterwards. Key
 * content-stage lines carry an embedded clock time (pbuStamp),
 * because the panel stamps stage lines only when a stage's log is
 * flushed, which blurred the v9.11 timing evidence. */
function pbuStamp() {
  try { return new Date().toLocaleTimeString([], { hour12: false }); } catch (e) { return ''; }
}
function CL(msg, lvl) { L('[' + pbuStamp() + '] ' + msg, lvl); }

async function pbuPoll(fn, opts = {}) {
  const minChecks = opts.minChecks != null ? opts.minChecks : 30;
  const interval = opts.interval != null ? opts.interval : 1000;
  const maxMs = opts.maxMs != null ? opts.maxMs : 90000;
  const hardMs = opts.hardMs != null ? opts.hardMs : maxMs * 3;
  const t0 = Date.now();
  let checks = 0;
  for (;;) {
    let r = null;
    try { r = fn(); } catch (e) { r = null; }
    checks++;
    if (r) return r;
    const elapsed = Date.now() - t0;
    if (elapsed >= hardMs) return null;
    if (checks >= minChecks && elapsed >= maxMs) return null;
    await sleep(interval);
  }
}

/* runStage override — identical dispatch to the stock runner, but
 * the log is cumulative across the two attempts (an attempt marker
 * line is added instead of wiping the first attempt's evidence). */
async function runStage(stage, payload) {
  stageLog.length = 0;
  await dismissInfoDialogs();
  const blocker = detectBlocker();
  if (blocker) return { ok: false, stopCondition: true, error: blocker, log: stageLog.slice() };
  const fn = STAGES[stage];
  if (!fn) return { ok: false, error: 'Unknown stage: ' + stage, log: stageLog.slice() };
  let lastErr = null;
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      await dismissInfoDialogs();
      const res = await fn(Object.assign({}, payload, { _attempt: attempt }));
      return Object.assign({ ok: true }, res || {}, { log: stageLog.slice() });
    } catch (err) {
      if (err && err.stopCondition) {
        return { ok: false, stopCondition: true, error: err.message, log: stageLog.slice() };
      }
      lastErr = err;
      if (attempt < 2) {
        stageLog.push({
          text: `Stage "${stage}" — attempt 1 failed (${(err && err.message) || err}); retrying with the log kept.`,
          level: 'error'
        });
        await sleep(2500);
      }
    }
  }
  return { ok: false, error: lastErr ? lastErr.message : 'Stage failed', log: stageLog.slice() };
}

async function pbuEnsureBridge(jobFiles) {
  // Verify the bridge in the page world on EVERY content-stage
  // attempt and log what is actually staged — never trust a
  // silent "armed once" flag (its silence hid the state in v9.11).
  const want = ['epub', 'cover'];
  let ping = await pbuMainBridge('ping');
  let staged = (ping.ok && ping.result && ping.result.staged) || [];
  if (want.every((k) => staged.includes(k))) {
    CL(`Content: upload bridge verified in the page world (staged: ${staged.join(', ')}).`);
    return true;
  }
  const payload = {
    files: [
      { key: 'epub', name: jobFiles.epub.name, type: jobFiles.epub.type, base64: jobFiles.epub.base64 },
      { key: 'cover', name: jobFiles.cover.name, type: jobFiles.cover.type, base64: jobFiles.cover.base64 }
    ]
  };
  const res = await pbuMainBridge('stage', { payload });
  ping = await pbuMainBridge('ping');
  staged = (ping.ok && ping.result && ping.result.staged) || [];
  if (want.every((k) => staged.includes(k))) {
    pbuArmedOnce = true;
    CL(`Content: upload bridge armed and verified in the page world (staged: ${staged.join(', ')}).`);
    return true;
  }
  CL('Content: the upload bridge could not be verified in the page world (' +
    ((res && res.error) || 'staging did not stick') + ') — continuing with direct routes only.', 'error');
  return false;
}

async function pbuWaitComplete2(file, opts = {}) {
  const res = await pbuPoll(() => {
    const e = pbuDialogEntry(file);
    if (e) {
      if (pbuEntryComplete(file)) return 'done';
      if (/fail|error/i.test(e.text)) return 'error:' + e.text.slice(0, 200);
      return null;
    }
    if (!uploadDialogEl()) return 'dialog-gone';
    const t = pbuDialogText();
    if (t.includes(file.name) && (/100\s*%/.test(t) || /complete/i.test(t))) return 'done';
    return null;
  }, Object.assign({ minChecks: 60, interval: 1000, maxMs: 120000, hardMs: 300000 }, opts));
  if (!res) {
    CL(`Content: "${file.name}" is registered in the dialog but did not reach 100% in the time allowed — closing anyway; the Content tab rows are verified next.`, 'error');
  } else if (String(res).startsWith('error:')) {
    CL(`Content: the dialog reports a problem for "${file.name}": ${String(res).slice(6)}`, 'error');
  }
  return res;
}

async function pbuAssignInPageWorld(keys, fallbackFiles, inputEl) {
  // Lead delivery: the page world assigns the staged files to the
  // dialog's own input (see background.js pbuMainAssign). Falls
  // back to the content-script assignment when the bridge route
  // is unavailable.
  const res = await pbuMainBridge('assign', { keys });
  if (res.ok && res.result && String(res.result).startsWith('assigned:')) {
    CL('Content: page-world assignment — ' + res.result + '.');
    return true;
  }
  CL('Content: page-world assignment unavailable (' +
    ((res && (res.result || res.error)) || 'no response') +
    ') — assigning from the content script instead.', 'error');
  if (inputEl && fallbackFiles && fallbackFiles.length) {
    assignFilesToInput(inputEl, fallbackFiles);
    await sleep(600);
    CL(`Content: content-script assignment done — the dialog input now holds ${inputEl.files ? inputEl.files.length : 0} file(s).`);
    return true;
  }
  return false;
}

async function pbuUploadTogether(epubFile, coverFile) {
  const result = { epub: false, cover: false };
  const dlg = await pbuOpenFreshDialog();
  if (!dlg) return result;
  const input = await pbuPoll(() => pbuDialogFileInput(),
    { minChecks: 30, interval: 400, maxMs: 20000, hardMs: 60000 });
  if (!input) {
    CL('Content: the dialog\'s own file input did not appear for the combined upload — falling back to one file at a time.');
    await pbuCloseUploadDialog('combined upload not possible in this dialog');
    return result;
  }
  CL('Content: uploading the EPUB and the cover TOGETHER in one dialog (the console\'s input accepts multiple files).');
  await pbuAssignInPageWorld(['epub', 'cover'], [epubFile, coverFile], input);
  await sleep(800);
  const bothIn = await pbuPoll(() => {
    const e1 = pbuDialogEntry(epubFile);
    const e2 = pbuDialogEntry(coverFile);
    if (e1 && /fail|error/i.test(e1.text)) return 'epub-error';
    if (e2 && /fail|error/i.test(e2.text)) return 'cover-error';
    return e1 && e2 ? 'both' : null;
  }, { minChecks: 40, interval: 1000, maxMs: 60000, hardMs: 180000 });
  if (bothIn === 'both') {
    await pbuWaitComplete2(epubFile);
    await pbuWaitComplete2(coverFile);
    result.epub = pbuEntryComplete(epubFile);
    result.cover = pbuEntryComplete(coverFile);
    if (result.epub && result.cover) {
      CL(`Uploaded BOTH files together — "${epubFile.name}" and "${coverFile.name}" both reached 100% in a single dialog.`);
    }
  } else {
    if (pbuDialogEntry(epubFile)) {
      await pbuWaitComplete2(epubFile);
      result.epub = pbuEntryComplete(epubFile);
    }
    if (pbuDialogEntry(coverFile)) {
      await pbuWaitComplete2(coverFile);
      result.cover = pbuEntryComplete(coverFile);
    }
    if (!result.epub && !result.cover) {
      CL('Content: the combined assignment did not register — falling back to one file at a time.', 'error');
    }
  }
  await pbuCloseUploadDialog('the combined upload finished');
  if (result.epub) pbuDoneUploads.add('epub:' + epubFile.name + ':' + epubFile.size);
  if (result.cover) pbuDoneUploads.add('cover:' + coverFile.name + ':' + coverFile.size);
  return result;
}

async function uploadOne(kind, file, successTimeout = 180000) {
  const beforeRows = new Set(fileRows().map((r) => r.text));
  const bannerBefore = /Successfully uploaded/i.test(pageText());
  const rowMatchesKind = (text) => kind === 'epub'
    ? /\.epub/i.test(text)
    : /frontcover|front cover/i.test(text) || (/\.(jpe?g|png)/i.test(text) && /cover/i.test(text));
  const finish = (outcome) => {
    if (!outcome) return false;
    if (outcome.fail) {
      throw new Error(`Content: "${file.name}" upload failed — the console reports: "${outcome.fail}"`);
    }
    CL(`Uploaded ${file.name} — confirmed via its ${outcome.via === 'row' ? 'file row' : outcome.via === 'dialog' ? 'dialog entry' : 'success banner'}.`);
    return true;
  };
  const pollConfirm = (opts) => pbuPoll(() => {
    const rows = fileRows();
    for (const r of rows) {
      if (beforeRows.has(r.text)) continue;
      if (/failed|epubcheck|invalid|corrupt|not a valid/i.test(r.text)) return { fail: r.text.slice(0, 220) };
    }
    const newRow = rows.find((r) => !beforeRows.has(r.text) && rowMatchesKind(r.text));
    if (newRow) return { ok: true, via: 'row' };
    if (!bannerBefore && /Successfully uploaded/i.test(pageText())) return { ok: true, via: 'banner' };
    if (pbuDialogEntry(file)) return { ok: true, via: 'dialog' };
    return null;
  }, opts);
  const pollOutcome = (ms) => waitFor(() => {
    const rows = fileRows();
    for (const r of rows) {
      if (beforeRows.has(r.text)) continue;
      if (/failed|epubcheck|invalid|corrupt|not a valid/i.test(r.text)) return { fail: r.text.slice(0, 220) };
    }
    const newRow = rows.find((r) => !beforeRows.has(r.text) && rowMatchesKind(r.text));
    if (newRow) return { ok: true, via: 'row' };
    if (!bannerBefore && /Successfully uploaded/i.test(pageText())) return { ok: true, via: 'banner' };
    if (pbuDialogEntry(file)) return { ok: true, via: 'dialog' };
    return null;
  }, ms, 1200);

  const doneKey = kind + ':' + file.name + ':' + file.size;
  if (pbuDoneUploads.has(doneKey)) {
    CL(`Content: "${file.name}" was already uploaded earlier in this session — skipping it and moving to the next file.`);
    await pbuCloseUploadDialog('that file is already uploaded');
    return;
  }
  if (pbuDialogEntry(file) || pbuDialogText().includes(file.name)) {
    const r = await pbuWaitComplete2(file);
    if (r === 'done' || r === 'dialog-gone') {
      await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
      pbuDoneUploads.add(doneKey);
      CL(`Uploaded ${file.name} — confirmed via its dialog entry.`);
      return;
    }
  }

  const captureMark = pbuCapturedInputs.length;
  const freshCaptured = () => pbuCapturedInputs.slice(captureMark)
    .filter((i) => !pbuBaselineInputs.has(i));

  // ---- Dialog route: one fresh dialog per file. ----
  const dlg = await pbuOpenFreshDialog();
  if (dlg) {
    let confirmed = false;

    // Route A (primary): the dialog's OWN input[name="Filedata"],
    // waited for with guaranteed checks, fed by the PAGE WORLD
    // (the picker's own end result) — see pbuMainAssign.
    const dlgInput = await pbuPoll(() => pbuDialogFileInput(),
      { minChecks: 30, interval: 400, maxMs: 20000, hardMs: 60000 });
    if (dlgInput) {
      CL(`Content: the dialog's own file input is ready — assigning "${file.name}" via the page world.`);
      await pbuAssignInPageWorld([kind], [file], dlgInput);
      await sleep(800);
      confirmed = finish(await pollConfirm({ minChecks: 45, interval: 1000, maxMs: 90000, hardMs: 240000 }));
      if (confirmed) {
        await pbuWaitComplete2(file);
        await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
        pbuDoneUploads.add(doneKey);
        return;
      }
      CL('Content: the direct assignment did not confirm — trying the remaining routes.');
    }

    // Route B: Browse, fed by the armed main-world bridge.
    if (!confirmed) {
      const browseBtn = [...dlg.querySelectorAll('button, [role="button"]')].filter(isVisible)
        .find((b) => exactTextEq(b.innerText || b.textContent, 'Browse'));
      if (browseBtn) {
        CL(`Content: clicking "Browse" — the armed bridge supplies "${file.name}" to the picker.`);
        clickEl(browseBtn);
        await sleep(800);
        confirmed = finish(await pollOutcome(45000));
        if (!confirmed) {
          const cap = freshCaptured();
          if (cap.length) {
            assignFilesToInput(cap[cap.length - 1], [file]);
            await sleep(800);
            confirmed = finish(await pollOutcome(30000));
          }
        }
      }
    }

    // Route C: main-world drag & drop.
    if (!confirmed) {
      const dropRes = await pbuMainBridge('drop', { kind });
      if (dropRes.ok) {
        CL(`Content: main-world drag & drop dispatched for "${file.name}" (${dropRes.result || 'ok'}).`);
        await sleep(800);
        confirmed = finish(await pollOutcome(45000));
      } else {
        CL('Content: main-world drop unavailable (' + (dropRes.error || 'no response') + ').', 'error');
      }
    }

    // Route D: isolated-world drag & drop onto the drop zone.
    if (!confirmed) {
      const liveDlg = uploadDialogEl() || dlg;
      const zone = [...liveDlg.querySelectorAll('*')].filter(isVisible)
        .find((e) => /drag and drop/i.test(norm(e.innerText || e.textContent)) && e.querySelectorAll('*').length < 12) || liveDlg;
      CL(`Content: dropping "${file.name}" onto the upload dialog's drag & drop zone.`);
      dropFileOnto(zone, file);
      dropFileOnto(liveDlg, file);
      await sleep(1000);
      confirmed = finish(await pollOutcome(60000));
    }

    if (!confirmed) {
      throw new Error(`Content: "${file.name}" did not register in the upload dialog (dialog input, picker bridge and drag & drop all failed). ${describeInputs()}`);
    }
    await pbuWaitComplete2(file);
    await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
    pbuDoneUploads.add(doneKey);
    return;
  }

  // ---- Classic route: this console build has no upload dialog —
  // the Content tab carries its own file inputs. ----
  let input = findUploadInput(kind);
  if (!input) {
    await revealFileInputs();
    input = findUploadInput(kind);
  }
  if (!input) {
    const cap = pbuCapturedInputs.filter((i) => !pbuBaselineInputs.has(i));
    if (cap.length) input = cap[cap.length - 1];
  }
  if (!input) {
    throw new Error(`Content: no usable file input for the ${kind} upload, and the upload dialog could not be opened. ${describeInputs()}`);
  }
  assignFilesToInput(input, [file]);
  await sleep(1000);
  if (finish(await pollOutcome(successTimeout))) {
    pbuDoneUploads.add(doneKey);
    return;
  }
  const errText = findErrorText();
  throw new Error(`Content: "${file.name}" upload did not confirm` +
    (errText ? ': ' + errText : ' (timed out waiting for its file row / success banner).'));
}

async function stageContent() {
  await goSection(['Content']);
  const blocker = detectBlocker(); if (blocker) throw stopErr(blocker);

  const { job } = await chrome.storage.local.get('job');
  if (!job || !job.files) throw new Error('Content: stored files are missing (job data not found).');
  const epubFile = base64ToFile(job.files.epub.base64, job.files.epub.name, job.files.epub.type);
  const coverFile = base64ToFile(job.files.cover.base64, job.files.cover.name, job.files.cover.type);

  CL('Content: stage started — snapshotting inputs, starting the capture net, verifying the upload bridge.');
  pbuBaselineInputs = new Set(deepFindFileInputs());
  startInputCapture();
  await pbuEnsureBridge(job.files);
  CL('Content: input census at stage start — ' + describeInputs() + '.');

  // First try the console's own design: both files together in
  // ONE dialog via its multiple-file input. Whatever is still
  // missing afterwards gets its own dialog cycle. Files already
  // uploaded earlier in this session are never fetched again
  // (the combined attempt only runs when both are missing).
  const epubKey = 'epub:' + epubFile.name + ':' + epubFile.size;
  const coverKey = 'cover:' + coverFile.name + ':' + coverFile.size;
  let together = { epub: pbuDoneUploads.has(epubKey), cover: pbuDoneUploads.has(coverKey) };
  if (!together.epub && !together.cover) {
    together = await pbuUploadTogether(epubFile, coverFile);
  }
  if (!together.epub) { await uploadOne('epub', epubFile); await sleep(1000); }
  if (!together.cover) { await uploadOne('cover', coverFile); await sleep(1000); }
  await pbuCloseUploadDialog('both files are uploaded');

  const epubRow = await waitFor(() => currentEpubRow(job.ggkey), 90000, 2000);
  if (!epubRow) {
    throw new Error('Content: the EPUB did not appear on the Content tab after uploading — the upload may not have registered.');
  }
  const stepM = epubRow.text.match(/step\s+(\d)\s+of\s+6/i);
  if (stepM) CL(`EPUB processing started: completed step ${stepM[1]} of 6 (current version).`);
  const rows = fileRows();
  const coverRow = rows.find((r) => /front cover|frontcover/i.test(r.text));
  if (coverRow) CL('Cover registered (a "front cover" row is shown on the Content tab).');
  else CL('Cover upload confirmed, but "front cover" registration was not visible — check on Review.', 'error');

  // Dialog closed, files verified — now Save the step.
  await pbuSaveContentStep();
  return { bookUrl: location.href };
}

/* ================= v9.13 dialog census + assisted pick =================
 * Post-mortem of the v9.12 live run (2026-10-23, GGKEY:87Y9L56SRCJ;
 * full log with true embedded timestamps supplied by the user):
 * the bridge verified cleanly in the page world on BOTH attempts
 * and every wait genuinely elapsed (the tab was in the foreground
 * this time) — yet the upload dialog's own input[name="Filedata"]
 * NEVER appeared: not in the combined attempt's 20-second wait,
 * not in the per-file route's 20-second wait, not after Browse,
 * not after either drop; the throw-time census found no file
 * input anywhere on the page. Contrast the user's own manual
 * capture (2026-10-23 ~18:26), where a manually opened dialog
 * contained the input from the start. The remaining difference is
 * the open itself: the console's uploader component apparently
 * creates its file input only on a flow a synthetic open does not
 * reproduce. Two responses:
 *   (1) pbuDialogCensus — whenever the waited input times out, the
 *       log now records the dialog's actual subtree (element
 *       census, dropzone presence, every input, shadow hosts,
 *       text head), so the next diagnosis reads the live DOM
 *       instead of guessing at it.
 *   (2) pbuAssistedPick — when every automatic route is exhausted,
 *       the stage no longer just fails: it opens the dialog,
 *       writes a LIVE instruction into the panel log (csLog, which
 *       the panel renders immediately, plus a desktop
 *       notification) asking the user to click Browse and pick
 *       the file(s) — one real pick, exactly the flow that is
 *       proven to work — and then waits (up to ~4 minutes per
 *       round) for the receipt cards to reach 100%, closes the
 *       dialog and continues the stage automatically (tab-row
 *       verification + Save). One manual pick per book salvages
 *       the whole run instead of a fifth failed upload. */
function pbuDialogCensus() {
  try {
    const dlg = uploadDialogEl();
    if (!dlg) return 'dialog census: no upload dialog is open';
    const tags = {};
    dlg.querySelectorAll('*').forEach((e) => {
      const t = e.tagName.toLowerCase();
      tags[t] = (tags[t] || 0) + 1;
    });
    const top = Object.entries(tags).sort((a, b) => b[1] - a[1])
      .slice(0, 10).map(([t, n]) => t + '×' + n).join(', ');
    const inputs = [...dlg.querySelectorAll('input')]
      .map((i) => (i.getAttribute('type') || '?') + '/' + (i.getAttribute('name') || '-'));
    const hosts = [...dlg.querySelectorAll('*')].filter((e) => e.shadowRoot).length;
    const txt = norm(dlg.innerText || dlg.textContent).slice(0, 160);
    return `dialog census: elements[${top}]; dropzone=${!!dlg.querySelector('[xapuploaderdropzone]')}; ` +
      `inputs in dialog=[${inputs.join(', ') || 'none'}]; shadow hosts=${hosts}; text="${txt}"`;
  } catch (e) {
    return 'dialog census failed: ' + String((e && e.message) || e);
  }
}

async function pbuLiveLog(text, level = 'info') {
  // csLog writes straight into the stored job log, which the
  // panel renders live — L() alone would only surface when the
  // stage ends, far too late for an instruction the user must
  // act on mid-stage. The line is also kept in the stage log.
  try { await csLog(text, level); } catch (e) { /* panel storage unavailable */ }
  try { L(text, level); } catch (e) { /* ignore */ }
}

async function pbuAssistedPick(missing) {
  let remaining = missing.slice();
  await pbuLiveLog('🖐 MANUAL PICK NEEDED — the console\'s uploader is not accepting files from the extension in this session. ' +
    'A dialog is open on the Content tab: click "Browse" in it and select ' +
    remaining.map((m) => '"' + m.file.name + '"').join(' and ') +
    ' (both at once is fine). The extension waits here and continues automatically as soon as the upload reaches 100%.', 'stage');
  try {
    csNotify('Play Books: one manual pick needed',
      'Click Browse in the upload dialog and select: ' + remaining.map((m) => m.file.name).join(', '));
  } catch (e) { /* notifications unavailable */ }

  for (let round = 0; round < 2 && remaining.length; round++) {
    if (!uploadDialogEl()) await pbuOpenFreshDialog();
    let firstDoneAt = 0;
    const outcome = await pbuPoll(() => {
      const doneNow = remaining.filter((m) => {
        const e = pbuDialogEntry(m.file);
        return e && pbuEntryComplete(m.file);
      });
      if (doneNow.length === remaining.length) return { state: 'all', doneNow };
      if (doneNow.length) {
        // One file is in; give a second picked file a short
        // grace period to finish too, then move on with what
        // we have (the receipt view has no Browse button, so
        // a remaining file needs a fresh dialog anyway).
        if (!firstDoneAt) firstDoneAt = Date.now();
        if (!uploadDialogEl() || Date.now() - firstDoneAt > 15000) return { state: 'some', doneNow };
      }
      return null;
    }, { minChecks: 230, interval: 1000, maxMs: 230000, hardMs: 250000 });
    if (!outcome) break;
    for (const m of outcome.doneNow) {
      pbuDoneUploads.add(m.kind + ':' + m.file.name + ':' + m.file.size);
      CL(`Content: assisted upload confirmed at 100% — "${m.file.name}".`);
    }
    remaining = remaining.filter((m) => !outcome.doneNow.includes(m));
    if (remaining.length) {
      await pbuCloseUploadDialog('one assisted file received');
      await pbuLiveLog('🖐 Got that file — one more: in the new dialog, click "Browse" and select ' +
        remaining.map((m) => '"' + m.file.name + '"').join(', ') + '.', 'stage');
    }
  }
  await pbuCloseUploadDialog('the assisted upload finished');
  return remaining;
}

async function pbuUploadTogether(epubFile, coverFile) {
  const result = { epub: false, cover: false };
  const dlg = await pbuOpenFreshDialog();
  if (!dlg) return result;
  const input = await pbuPoll(() => pbuDialogFileInput(),
    { minChecks: 30, interval: 400, maxMs: 20000, hardMs: 60000 });
  if (!input) {
    CL('Content: the dialog\'s own file input did not appear for the combined upload — falling back to one file at a time.');
    CL('Content: ' + pbuDialogCensus() + '.', 'error');
    await pbuCloseUploadDialog('combined upload not possible in this dialog');
    return result;
  }
  CL('Content: uploading the EPUB and the cover TOGETHER in one dialog (the console\'s input accepts multiple files).');
  await pbuAssignInPageWorld(['epub', 'cover'], [epubFile, coverFile], input);
  await sleep(800);
  const bothIn = await pbuPoll(() => {
    const e1 = pbuDialogEntry(epubFile);
    const e2 = pbuDialogEntry(coverFile);
    if (e1 && /fail|error/i.test(e1.text)) return 'epub-error';
    if (e2 && /fail|error/i.test(e2.text)) return 'cover-error';
    return e1 && e2 ? 'both' : null;
  }, { minChecks: 40, interval: 1000, maxMs: 60000, hardMs: 180000 });
  if (bothIn === 'both') {
    await pbuWaitComplete2(epubFile);
    await pbuWaitComplete2(coverFile);
    result.epub = pbuEntryComplete(epubFile);
    result.cover = pbuEntryComplete(coverFile);
    if (result.epub && result.cover) {
      CL(`Uploaded BOTH files together — "${epubFile.name}" and "${coverFile.name}" both reached 100% in a single dialog.`);
    }
  } else {
    if (pbuDialogEntry(epubFile)) {
      await pbuWaitComplete2(epubFile);
      result.epub = pbuEntryComplete(epubFile);
    }
    if (pbuDialogEntry(coverFile)) {
      await pbuWaitComplete2(coverFile);
      result.cover = pbuEntryComplete(coverFile);
    }
    if (!result.epub && !result.cover) {
      CL('Content: the combined assignment did not register — falling back to one file at a time.', 'error');
    }
  }
  await pbuCloseUploadDialog('the combined upload finished');
  if (result.epub) pbuDoneUploads.add('epub:' + epubFile.name + ':' + epubFile.size);
  if (result.cover) pbuDoneUploads.add('cover:' + coverFile.name + ':' + coverFile.size);
  return result;
}
async function uploadOne(kind, file, successTimeout = 180000) {
  const beforeRows = new Set(fileRows().map((r) => r.text));
  const bannerBefore = /Successfully uploaded/i.test(pageText());
  const rowMatchesKind = (text) => kind === 'epub'
    ? /\.epub/i.test(text)
    : /frontcover|front cover/i.test(text) || (/\.(jpe?g|png)/i.test(text) && /cover/i.test(text));
  const finish = (outcome) => {
    if (!outcome) return false;
    if (outcome.fail) {
      throw new Error(`Content: "${file.name}" upload failed — the console reports: "${outcome.fail}"`);
    }
    CL(`Uploaded ${file.name} — confirmed via its ${outcome.via === 'row' ? 'file row' : outcome.via === 'dialog' ? 'dialog entry' : 'success banner'}.`);
    return true;
  };
  const pollConfirm = (opts) => pbuPoll(() => {
    const rows = fileRows();
    for (const r of rows) {
      if (beforeRows.has(r.text)) continue;
      if (/failed|epubcheck|invalid|corrupt|not a valid/i.test(r.text)) return { fail: r.text.slice(0, 220) };
    }
    const newRow = rows.find((r) => !beforeRows.has(r.text) && rowMatchesKind(r.text));
    if (newRow) return { ok: true, via: 'row' };
    if (!bannerBefore && /Successfully uploaded/i.test(pageText())) return { ok: true, via: 'banner' };
    if (pbuDialogEntry(file)) return { ok: true, via: 'dialog' };
    return null;
  }, opts);
  const pollOutcome = (ms) => waitFor(() => {
    const rows = fileRows();
    for (const r of rows) {
      if (beforeRows.has(r.text)) continue;
      if (/failed|epubcheck|invalid|corrupt|not a valid/i.test(r.text)) return { fail: r.text.slice(0, 220) };
    }
    const newRow = rows.find((r) => !beforeRows.has(r.text) && rowMatchesKind(r.text));
    if (newRow) return { ok: true, via: 'row' };
    if (!bannerBefore && /Successfully uploaded/i.test(pageText())) return { ok: true, via: 'banner' };
    if (pbuDialogEntry(file)) return { ok: true, via: 'dialog' };
    return null;
  }, ms, 1200);

  const doneKey = kind + ':' + file.name + ':' + file.size;
  if (pbuDoneUploads.has(doneKey)) {
    CL(`Content: "${file.name}" was already uploaded earlier in this session — skipping it and moving to the next file.`);
    await pbuCloseUploadDialog('that file is already uploaded');
    return;
  }
  if (pbuDialogEntry(file) || pbuDialogText().includes(file.name)) {
    const r = await pbuWaitComplete2(file);
    if (r === 'done' || r === 'dialog-gone') {
      await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
      pbuDoneUploads.add(doneKey);
      CL(`Uploaded ${file.name} — confirmed via its dialog entry.`);
      return;
    }
  }

  const captureMark = pbuCapturedInputs.length;
  const freshCaptured = () => pbuCapturedInputs.slice(captureMark)
    .filter((i) => !pbuBaselineInputs.has(i));

  // ---- Dialog route: one fresh dialog per file. ----
  const dlg = await pbuOpenFreshDialog();
  if (dlg) {
    let confirmed = false;

    // Route A (primary): the dialog's OWN input[name="Filedata"],
    // waited for with guaranteed checks, fed by the PAGE WORLD
    // (the picker's own end result) — see pbuMainAssign.
    const dlgInput = await pbuPoll(() => pbuDialogFileInput(),
      { minChecks: 30, interval: 400, maxMs: 20000, hardMs: 60000 });
    if (!dlgInput) {
      CL(`Content: the dialog's file input never appeared for "${file.name}". ` + pbuDialogCensus() + '.', 'error');
    }
    if (dlgInput) {
      CL(`Content: the dialog's own file input is ready — assigning "${file.name}" via the page world.`);
      await pbuAssignInPageWorld([kind], [file], dlgInput);
      await sleep(800);
      confirmed = finish(await pollConfirm({ minChecks: 45, interval: 1000, maxMs: 90000, hardMs: 240000 }));
      if (confirmed) {
        await pbuWaitComplete2(file);
        await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
        pbuDoneUploads.add(doneKey);
        return;
      }
      CL('Content: the direct assignment did not confirm — trying the remaining routes.');
    }

    // Route B: Browse, fed by the armed main-world bridge.
    if (!confirmed) {
      const browseBtn = [...dlg.querySelectorAll('button, [role="button"]')].filter(isVisible)
        .find((b) => exactTextEq(b.innerText || b.textContent, 'Browse'));
      if (browseBtn) {
        CL(`Content: clicking "Browse" — the armed bridge supplies "${file.name}" to the picker.`);
        clickEl(browseBtn);
        await sleep(800);
        confirmed = finish(await pollOutcome(45000));
        if (!confirmed) {
          const cap = freshCaptured();
          if (cap.length) {
            assignFilesToInput(cap[cap.length - 1], [file]);
            await sleep(800);
            confirmed = finish(await pollOutcome(30000));
          }
        }
      }
    }

    // Route C: main-world drag & drop.
    if (!confirmed) {
      const dropRes = await pbuMainBridge('drop', { kind });
      if (dropRes.ok) {
        CL(`Content: main-world drag & drop dispatched for "${file.name}" (${dropRes.result || 'ok'}).`);
        await sleep(800);
        confirmed = finish(await pollOutcome(45000));
      } else {
        CL('Content: main-world drop unavailable (' + (dropRes.error || 'no response') + ').', 'error');
      }
    }

    // Route D: isolated-world drag & drop onto the drop zone.
    if (!confirmed) {
      const liveDlg = uploadDialogEl() || dlg;
      const zone = [...liveDlg.querySelectorAll('*')].filter(isVisible)
        .find((e) => /drag and drop/i.test(norm(e.innerText || e.textContent)) && e.querySelectorAll('*').length < 12) || liveDlg;
      CL(`Content: dropping "${file.name}" onto the upload dialog's drag & drop zone.`);
      dropFileOnto(zone, file);
      dropFileOnto(liveDlg, file);
      await sleep(1000);
      confirmed = finish(await pollOutcome(60000));
    }

    if (!confirmed) {
      throw new Error(`Content: "${file.name}" did not register in the upload dialog (dialog input, picker bridge and drag & drop all failed). ${describeInputs()} — ${pbuDialogCensus()}`);
    }
    await pbuWaitComplete2(file);
    await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
    pbuDoneUploads.add(doneKey);
    return;
  }

  // ---- Classic route: this console build has no upload dialog —
  // the Content tab carries its own file inputs. ----
  let input = findUploadInput(kind);
  if (!input) {
    await revealFileInputs();
    input = findUploadInput(kind);
  }
  if (!input) {
    const cap = pbuCapturedInputs.filter((i) => !pbuBaselineInputs.has(i));
    if (cap.length) input = cap[cap.length - 1];
  }
  if (!input) {
    throw new Error(`Content: no usable file input for the ${kind} upload, and the upload dialog could not be opened. ${describeInputs()}`);
  }
  assignFilesToInput(input, [file]);
  await sleep(1000);
  if (finish(await pollOutcome(successTimeout))) {
    pbuDoneUploads.add(doneKey);
    return;
  }
  const errText = findErrorText();
  throw new Error(`Content: "${file.name}" upload did not confirm` +
    (errText ? ': ' + errText : ' (timed out waiting for its file row / success banner).'));
}
async function stageContent() {
  await goSection(['Content']);
  const blocker = detectBlocker(); if (blocker) throw stopErr(blocker);

  const { job } = await chrome.storage.local.get('job');
  if (!job || !job.files) throw new Error('Content: stored files are missing (job data not found).');
  const epubFile = base64ToFile(job.files.epub.base64, job.files.epub.name, job.files.epub.type);
  const coverFile = base64ToFile(job.files.cover.base64, job.files.cover.name, job.files.cover.type);

  CL('Content: stage started — snapshotting inputs, starting the capture net, verifying the upload bridge.');
  pbuBaselineInputs = new Set(deepFindFileInputs());
  startInputCapture();
  await pbuEnsureBridge(job.files);
  CL('Content: input census at stage start — ' + describeInputs() + '.');

  // First try the console's own design: both files together in
  // ONE dialog via its multiple-file input. Whatever is still
  // missing afterwards gets its own dialog cycle. Files already
  // uploaded earlier in this session are never fetched again
  // (the combined attempt only runs when both are missing).
  const epubKey = 'epub:' + epubFile.name + ':' + epubFile.size;
  const coverKey = 'cover:' + coverFile.name + ':' + coverFile.size;
  let together = { epub: pbuDoneUploads.has(epubKey), cover: pbuDoneUploads.has(coverKey) };
  if (!together.epub && !together.cover) {
    try { together = await pbuUploadTogether(epubFile, coverFile); }
    catch (e) { CL('Content: the combined upload attempt errored (' + ((e && e.message) || e) + ') — continuing one file at a time.', 'error'); }
  }
  if (!together.epub && !pbuDoneUploads.has(epubKey)) {
    try { await uploadOne('epub', epubFile); }
    catch (e) { CL('Content: automatic EPUB upload did not succeed (' + ((e && e.message) || e) + ').', 'error'); }
    await sleep(1000);
  }
  if (!together.cover && !pbuDoneUploads.has(coverKey)) {
    try { await uploadOne('cover', coverFile); }
    catch (e) { CL('Content: automatic cover upload did not succeed (' + ((e && e.message) || e) + ').', 'error'); }
    await sleep(1000);
  }
  const stillMissing = [];
  if (!pbuDoneUploads.has(epubKey)) stillMissing.push({ kind: 'epub', file: epubFile });
  if (!pbuDoneUploads.has(coverKey)) stillMissing.push({ kind: 'cover', file: coverFile });
  if (stillMissing.length) {
    CL('Content: automatic routes are exhausted — switching to the assisted pick for: ' +
      stillMissing.map((m) => m.file.name).join(', ') + '.', 'error');
    const left = await pbuAssistedPick(stillMissing);
    if (left.length) {
      throw new Error('Content: the assisted pick timed out — still missing: ' +
        left.map((m) => m.file.name).join(', ') + '. ' + pbuDialogCensus());
    }
  }
  await pbuCloseUploadDialog('both files are uploaded');

  const epubRow = await waitFor(() => currentEpubRow(job.ggkey), 90000, 2000);
  if (!epubRow) {
    throw new Error('Content: the EPUB did not appear on the Content tab after uploading — the upload may not have registered.');
  }
  const stepM = epubRow.text.match(/step\s+(\d)\s+of\s+6/i);
  if (stepM) CL(`EPUB processing started: completed step ${stepM[1]} of 6 (current version).`);
  const rows = fileRows();
  const coverRow = rows.find((r) => /front cover|frontcover/i.test(r.text));
  if (coverRow) CL('Cover registered (a "front cover" row is shown on the Content tab).');
  else CL('Cover upload confirmed, but "front cover" registration was not visible — check on Review.', 'error');

  // Dialog closed, files verified — now Save the step.
  await pbuSaveContentStep();
  return { bookUrl: location.href };
}

/* ================= v9.14 fast fail-over + cancel-guard =================
 * From the v9.13 live run (2026-10-23 21:46, GGKEY:UBPY65KQH43):
 * progress at last — the EPUB uploaded AUTOMATICALLY (its row was
 * on the Content tab), but the cover fell through to the assisted
 * pick, and the run still took ~5 minutes to get there because
 * every dead route sat out its full 45–90 second confirmation
 * window. The user also hit the console's "Cancel all uploads?
 * Some uploads are still in progress" guard — shown when a close
 * is attempted over an in-progress upload — which the extension
 * did not know. v9.14 changes:
 *   (1) SPEED: all content-stage probes are short now. A receipt
 *       card appears within a second or two when the console
 *       accepts a file (proven in every manual flow), so the
 *       input waits drop to ~8s, registration confirms to ~25s,
 *       and the Browse/drop fallbacks to 12–20s each. A file that
 *       no route can place reaches the assisted pick in about a
 *       minute instead of five — and when a route works, nothing
 *       waits longer than it has to.
 *   (2) pbuUploadInProgress + a pbuCloseUploadDialog override:
 *       the dialog is never closed while an <upload-file> card
 *       shows less than 100%; the close waits for the upload to
 *       finish first.
 *   (3) pbuHandleCancelGuard: if the "Cancel all uploads?" guard
 *       appears anyway (e.g. a card reads 100% while the console
 *       still finalises), the ONLY button ever clicked is
 *       "Continue upload" — an upload is never cancelled. The
 *       guard is also swept inside the completion/assisted
 *       waits. */
function pbuUploadInProgress() {
  const dlg = uploadDialogEl();
  if (!dlg) return false;
  for (const card of dlg.querySelectorAll('upload-file')) {
    const st = card.querySelector('.status');
    const pr = card.querySelector('.progress');
    const stT = st ? norm(st.innerText || st.textContent) : '';
    const prT = pr ? norm(pr.innerText || pr.textContent) : '';
    const sizes = prT.match(/([\d.]+)\s*(KB|MB|B)\s*\/\s*([\d.]+)\s*(KB|MB|B)/i);
    const doneBySize = !!sizes && parseFloat(sizes[1]) >= parseFloat(sizes[3]) && parseFloat(sizes[3]) > 0;
    if (!/100\s*%/.test(stT) && !doneBySize) return true;
  }
  return false;
}

function pbuHandleCancelGuard() {
  try {
    const dialogs = [...document.querySelectorAll('[role="dialog"], .mat-dialog-container, mat-dialog-container, .cdk-overlay-pane')];
    for (const d of dialogs) {
      if (!isVisible(d)) continue;
      if (!/cancel all uploads/i.test(norm(d.innerText || d.textContent))) continue;
      const btn = [...d.querySelectorAll('button, [role="button"]')].filter(isVisible)
        .find((b) => exactTextEq(b.innerText || b.textContent, 'Continue upload'));
      if (btn) {
        L('Content: the console asked "Cancel all uploads?" — clicked "Continue upload" (an upload is never cancelled).');
        clickEl(btn);
        return true;
      }
    }
  } catch (e) { /* never break the flow */ }
  return false;
}

async function pbuCloseUploadDialog(why) {
  for (let i = 0; i < 80; i++) {
    pbuHandleCancelGuard();
    if (!pbuUploadInProgress()) break;
    if (i === 0) CL('Content: an upload is still in progress in the dialog — waiting for it to finish before closing.');
    await sleep(1500);
  }
  pbuHandleCancelGuard();
  const dlg = uploadDialogEl();
  if (!dlg) return true;
  const btn = pbuDialogCloseButton(dlg);
  if (!btn) {
    L('Content: the upload dialog is open but shows no Close button' + (why ? ' (' + why + ')' : '') + '.', 'error');
    return false;
  }
  L('Content: clicking "Close" on the upload dialog' + (why ? ' — ' + why : '') + '.');
  clickEl(btn);
  let gone = false;
  for (let i = 0; i < 25 && !gone; i++) {
    await sleep(400);
    if (pbuHandleCancelGuard()) {
      // The close was intercepted by the cancel guard and we
      // chose "Continue upload": wait the upload out, then
      // close the dialog again.
      for (let j = 0; j < 80 && pbuUploadInProgress(); j++) await sleep(1500);
      const d2 = uploadDialogEl();
      if (!d2) { gone = true; break; }
      const b2 = pbuDialogCloseButton(d2);
      if (b2) { clickEl(b2); await sleep(600); }
    }
    if (!uploadDialogEl()) gone = true;
  }
  if (!gone) L('Content: the upload dialog stayed open after Close was clicked.', 'error');
  return gone;
}

async function pbuWaitComplete2(file, opts = {}) {
  const res = await pbuPoll(() => {
    pbuHandleCancelGuard();
    const e = pbuDialogEntry(file);
    if (e) {
      if (pbuEntryComplete(file)) return 'done';
      if (/fail|error/i.test(e.text)) return 'error:' + e.text.slice(0, 200);
      return null;
    }
    if (!uploadDialogEl()) return 'dialog-gone';
    const t = pbuDialogText();
    if (t.includes(file.name) && (/100\s*%/.test(t) || /complete/i.test(t))) return 'done';
    return null;
  }, Object.assign({ minChecks: 24, interval: 800, maxMs: 40000, hardMs: 90000 }, opts));
  if (!res) {
    CL(`Content: "${file.name}" is registered in the dialog but did not reach 100% in the time allowed — closing anyway; the Content tab rows are verified next.`, 'error');
  } else if (String(res).startsWith('error:')) {
    CL(`Content: the dialog reports a problem for "${file.name}": ${String(res).slice(6)}`, 'error');
  }
  return res;
}

async function pbuAssistedPick(missing) {
  let remaining = missing.slice();
  await pbuLiveLog('🖐 MANUAL PICK NEEDED — the console\'s uploader is not accepting files from the extension in this session. ' +
    'A dialog is open on the Content tab: click "Browse" in it and select ' +
    remaining.map((m) => '"' + m.file.name + '"').join(' and ') +
    ' (both at once is fine). The extension waits here and continues automatically as soon as the upload reaches 100%.', 'stage');
  try {
    csNotify('Play Books: one manual pick needed',
      'Click Browse in the upload dialog and select: ' + remaining.map((m) => m.file.name).join(', '));
  } catch (e) { /* notifications unavailable */ }

  for (let round = 0; round < 2 && remaining.length; round++) {
    if (!uploadDialogEl()) await pbuOpenFreshDialog();
    let firstDoneAt = 0;
    const outcome = await pbuPoll(() => {
      pbuHandleCancelGuard();
      const doneNow = remaining.filter((m) => {
        const e = pbuDialogEntry(m.file);
        return e && pbuEntryComplete(m.file);
      });
      if (doneNow.length === remaining.length) return { state: 'all', doneNow };
      if (doneNow.length) {
        // One file is in; give a second picked file a short
        // grace period to finish too, then move on with what
        // we have (the receipt view has no Browse button, so
        // a remaining file needs a fresh dialog anyway).
        if (!firstDoneAt) firstDoneAt = Date.now();
        if (!uploadDialogEl() || Date.now() - firstDoneAt > 15000) return { state: 'some', doneNow };
      }
      return null;
    }, { minChecks: 230, interval: 1000, maxMs: 230000, hardMs: 250000 });
    if (!outcome) break;
    for (const m of outcome.doneNow) {
      pbuDoneUploads.add(m.kind + ':' + m.file.name + ':' + m.file.size);
      CL(`Content: assisted upload confirmed at 100% — "${m.file.name}".`);
    }
    remaining = remaining.filter((m) => !outcome.doneNow.includes(m));
    if (remaining.length) {
      await pbuCloseUploadDialog('one assisted file received');
      await pbuLiveLog('🖐 Got that file — one more: in the new dialog, click "Browse" and select ' +
        remaining.map((m) => '"' + m.file.name + '"').join(', ') + '.', 'stage');
    }
  }
  await pbuCloseUploadDialog('the assisted upload finished');
  return remaining;
}

async function pbuUploadTogether(epubFile, coverFile) {
  const result = { epub: false, cover: false };
  const dlg = await pbuOpenFreshDialog();
  if (!dlg) return result;
  const input = await pbuPoll(() => pbuDialogFileInput(),
    { minChecks: 12, interval: 400, maxMs: 8000, hardMs: 15000 });
  if (!input) {
    CL('Content: the dialog\'s own file input did not appear for the combined upload — falling back to one file at a time.');
    CL('Content: ' + pbuDialogCensus() + '.', 'error');
    await pbuCloseUploadDialog('combined upload not possible in this dialog');
    return result;
  }
  CL('Content: uploading the EPUB and the cover TOGETHER in one dialog (the console\'s input accepts multiple files).');
  await pbuAssignInPageWorld(['epub', 'cover'], [epubFile, coverFile], input);
  await sleep(800);
  const bothIn = await pbuPoll(() => {
    const e1 = pbuDialogEntry(epubFile);
    const e2 = pbuDialogEntry(coverFile);
    if (e1 && /fail|error/i.test(e1.text)) return 'epub-error';
    if (e2 && /fail|error/i.test(e2.text)) return 'cover-error';
    return e1 && e2 ? 'both' : null;
  }, { minChecks: 16, interval: 800, maxMs: 25000, hardMs: 60000 });
  if (bothIn === 'both') {
    await pbuWaitComplete2(epubFile);
    await pbuWaitComplete2(coverFile);
    result.epub = pbuEntryComplete(epubFile);
    result.cover = pbuEntryComplete(coverFile);
    if (result.epub && result.cover) {
      CL(`Uploaded BOTH files together — "${epubFile.name}" and "${coverFile.name}" both reached 100% in a single dialog.`);
    }
  } else {
    if (pbuDialogEntry(epubFile)) {
      await pbuWaitComplete2(epubFile);
      result.epub = pbuEntryComplete(epubFile);
    }
    if (pbuDialogEntry(coverFile)) {
      await pbuWaitComplete2(coverFile);
      result.cover = pbuEntryComplete(coverFile);
    }
    if (!result.epub && !result.cover) {
      CL('Content: the combined assignment did not register — falling back to one file at a time.', 'error');
    }
  }
  await pbuCloseUploadDialog('the combined upload finished');
  if (result.epub) pbuDoneUploads.add('epub:' + epubFile.name + ':' + epubFile.size);
  if (result.cover) pbuDoneUploads.add('cover:' + coverFile.name + ':' + coverFile.size);
  return result;
}
async function uploadOne(kind, file, successTimeout = 180000) {
  const beforeRows = new Set(fileRows().map((r) => r.text));
  const bannerBefore = /Successfully uploaded/i.test(pageText());
  const rowMatchesKind = (text) => kind === 'epub'
    ? /\.epub/i.test(text)
    : /frontcover|front cover/i.test(text) || (/\.(jpe?g|png)/i.test(text) && /cover/i.test(text));
  const finish = (outcome) => {
    if (!outcome) return false;
    if (outcome.fail) {
      throw new Error(`Content: "${file.name}" upload failed — the console reports: "${outcome.fail}"`);
    }
    CL(`Uploaded ${file.name} — confirmed via its ${outcome.via === 'row' ? 'file row' : outcome.via === 'dialog' ? 'dialog entry' : 'success banner'}.`);
    return true;
  };
  const pollConfirm = (opts) => pbuPoll(() => {
    const rows = fileRows();
    for (const r of rows) {
      if (beforeRows.has(r.text)) continue;
      if (/failed|epubcheck|invalid|corrupt|not a valid/i.test(r.text)) return { fail: r.text.slice(0, 220) };
    }
    const newRow = rows.find((r) => !beforeRows.has(r.text) && rowMatchesKind(r.text));
    if (newRow) return { ok: true, via: 'row' };
    if (!bannerBefore && /Successfully uploaded/i.test(pageText())) return { ok: true, via: 'banner' };
    if (pbuDialogEntry(file)) return { ok: true, via: 'dialog' };
    return null;
  }, opts);
  const pollOutcome = (ms) => waitFor(() => {
    const rows = fileRows();
    for (const r of rows) {
      if (beforeRows.has(r.text)) continue;
      if (/failed|epubcheck|invalid|corrupt|not a valid/i.test(r.text)) return { fail: r.text.slice(0, 220) };
    }
    const newRow = rows.find((r) => !beforeRows.has(r.text) && rowMatchesKind(r.text));
    if (newRow) return { ok: true, via: 'row' };
    if (!bannerBefore && /Successfully uploaded/i.test(pageText())) return { ok: true, via: 'banner' };
    if (pbuDialogEntry(file)) return { ok: true, via: 'dialog' };
    return null;
  }, ms, 1200);

  const doneKey = kind + ':' + file.name + ':' + file.size;
  if (pbuDoneUploads.has(doneKey)) {
    CL(`Content: "${file.name}" was already uploaded earlier in this session — skipping it and moving to the next file.`);
    await pbuCloseUploadDialog('that file is already uploaded');
    return;
  }
  if (pbuDialogEntry(file) || pbuDialogText().includes(file.name)) {
    const r = await pbuWaitComplete2(file);
    if (r === 'done' || r === 'dialog-gone') {
      await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
      pbuDoneUploads.add(doneKey);
      CL(`Uploaded ${file.name} — confirmed via its dialog entry.`);
      return;
    }
  }

  const captureMark = pbuCapturedInputs.length;
  const freshCaptured = () => pbuCapturedInputs.slice(captureMark)
    .filter((i) => !pbuBaselineInputs.has(i));

  // ---- Dialog route: one fresh dialog per file. ----
  const dlg = await pbuOpenFreshDialog();
  if (dlg) {
    let confirmed = false;

    // Route A (primary): the dialog's OWN input[name="Filedata"],
    // waited for with guaranteed checks, fed by the PAGE WORLD
    // (the picker's own end result) — see pbuMainAssign.
    const dlgInput = await pbuPoll(() => pbuDialogFileInput(),
      { minChecks: 12, interval: 400, maxMs: 8000, hardMs: 15000 });
    if (!dlgInput) {
      CL(`Content: the dialog's file input never appeared for "${file.name}". ` + pbuDialogCensus() + '.', 'error');
    }
    if (dlgInput) {
      CL(`Content: the dialog's own file input is ready — assigning "${file.name}" via the page world.`);
      await pbuAssignInPageWorld([kind], [file], dlgInput);
      await sleep(800);
      confirmed = finish(await pollConfirm({ minChecks: 18, interval: 800, maxMs: 25000, hardMs: 60000 }));
      if (confirmed) {
        await pbuWaitComplete2(file);
        await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
        pbuDoneUploads.add(doneKey);
        return;
      }
      CL('Content: the direct assignment did not confirm — trying the remaining routes.');
    }

    // Route B: Browse, fed by the armed main-world bridge.
    if (!confirmed) {
      const browseBtn = [...dlg.querySelectorAll('button, [role="button"]')].filter(isVisible)
        .find((b) => exactTextEq(b.innerText || b.textContent, 'Browse'));
      if (browseBtn) {
        CL(`Content: clicking "Browse" — the armed bridge supplies "${file.name}" to the picker.`);
        clickEl(browseBtn);
        await sleep(800);
        confirmed = finish(await pollOutcome(15000));
        if (!confirmed) {
          const cap = freshCaptured();
          if (cap.length) {
            assignFilesToInput(cap[cap.length - 1], [file]);
            await sleep(800);
            confirmed = finish(await pollOutcome(12000));
          }
        }
      }
    }

    // Route C: main-world drag & drop.
    if (!confirmed) {
      const dropRes = await pbuMainBridge('drop', { kind });
      if (dropRes.ok) {
        CL(`Content: main-world drag & drop dispatched for "${file.name}" (${dropRes.result || 'ok'}).`);
        await sleep(800);
        confirmed = finish(await pollOutcome(15000));
      } else {
        CL('Content: main-world drop unavailable (' + (dropRes.error || 'no response') + ').', 'error');
      }
    }

    // Route D: isolated-world drag & drop onto the drop zone.
    if (!confirmed) {
      const liveDlg = uploadDialogEl() || dlg;
      const zone = [...liveDlg.querySelectorAll('*')].filter(isVisible)
        .find((e) => /drag and drop/i.test(norm(e.innerText || e.textContent)) && e.querySelectorAll('*').length < 12) || liveDlg;
      CL(`Content: dropping "${file.name}" onto the upload dialog's drag & drop zone.`);
      dropFileOnto(zone, file);
      dropFileOnto(liveDlg, file);
      await sleep(1000);
      confirmed = finish(await pollOutcome(20000));
    }

    if (!confirmed) {
      throw new Error(`Content: "${file.name}" did not register in the upload dialog (dialog input, picker bridge and drag & drop all failed). ${describeInputs()} — ${pbuDialogCensus()}`);
    }
    await pbuWaitComplete2(file);
    await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
    pbuDoneUploads.add(doneKey);
    return;
  }

  // ---- Classic route: this console build has no upload dialog —
  // the Content tab carries its own file inputs. ----
  let input = findUploadInput(kind);
  if (!input) {
    await revealFileInputs();
    input = findUploadInput(kind);
  }
  if (!input) {
    const cap = pbuCapturedInputs.filter((i) => !pbuBaselineInputs.has(i));
    if (cap.length) input = cap[cap.length - 1];
  }
  if (!input) {
    throw new Error(`Content: no usable file input for the ${kind} upload, and the upload dialog could not be opened. ${describeInputs()}`);
  }
  assignFilesToInput(input, [file]);
  await sleep(1000);
  if (finish(await pollOutcome(successTimeout))) {
    pbuDoneUploads.add(doneKey);
    return;
  }
  const errText = findErrorText();
  throw new Error(`Content: "${file.name}" upload did not confirm` +
    (errText ? ': ' + errText : ' (timed out waiting for its file row / success banner).'));
}
/* ================= v9.15 patient input wait + NO manual pick =================
 * Kept from v9.15: (a) PATIENT INPUT WAIT (~25s, census logged at
 * 10s) — the user's console shows "Slow network is detected", so a
 * short wait starves a late-rendering input; (b) DIALOG-VANISH
 * RETRY — reopen once if the dialog disappears mid-wait; (c) NO
 * assisted manual pick — the user ordered this outright
 * (2026-10-24): if every automatic route fails, the stage fails
 * with a clear error and the full census; it never asks the user to
 * pick files by hand. The CDP trusted-click channel that v9.15
 * added was REMOVED in v9.19 at the user's order (their custom
 * browser does not support it): the click helpers in this block
 * are plain synthetic clicks now. */
let pbuTrustedWarned = false;

async function pbuTrustedClickEl(el, what) {
    // v9.19: the CDP trusted-click channel was REMOVED at the user's
    // order (their custom browser does not support that API). This
    // helper — kept under its old name only because the stage code
    // calls it — is now a plain synthetic click, nothing more.
    if (!el) return false;
    try { el.scrollIntoView({ block: 'center', inline: 'center' }); } catch (e) { /* ignore */ }
    await sleep(200);
    clickEl(el);
    await sleep(400);
    return true;
}

async function pbuOpenDialogTrusted() {
    await pbuCloseUploadDialog('a fresh dialog is needed');
    const existing = uploadDialogEl();
    if (existing && pbuDialogActionable(existing)) return existing;
    const btn = await waitFor(() => findByText(['Upload content and cover', 'Upload content', 'Upload files', 'Upload file', 'Upload new file', 'Upload', 'Add files'])[0], 10000, 400);
    if (btn) {
        const ok = await pbuTrustedClickEl(btn, 'the "Upload content and cover" button');
        if (!ok) { clickEl(btn); await sleep(600); }
    } else {
        const opened = await openUploadDialog();
        if (!opened) return null;
    }
    const dlg = await waitFor(() => {
        const d = uploadDialogEl();
        return d && pbuDialogActionable(d) ? d : null;
    }, 15000, 500);
    return dlg || uploadDialogEl() || null;
}

async function pbuWaitInputPatient(label) {
    const start = Date.now();
    let censused = false;
    let goneChecks = 0;
    return pbuPoll(() => {
        const i = pbuDialogFileInput();
        if (i) return i;
        if (!uploadDialogEl()) {
            goneChecks++;
            if (goneChecks >= 4) return 'dialog-gone';
            return null;
        }
        goneChecks = 0;
        if (!censused && Date.now() - start > 10000) {
            censused = true;
            CL('Content: still no file input in the dialog after 10s' + (label ? ' (' + label + ')' : '') + ' — ' + pbuDialogCensus() + '.', 'error');
        }
        return null;
    }, { minChecks: 40, interval: 500, maxMs: 25000, hardMs: 45000 });
}

async function pbuSettleTogether(epubFile, coverFile, result) {
    const seen = await pbuPoll(() => {
        const e1 = pbuDialogEntry(epubFile);
        const e2 = pbuDialogEntry(coverFile);
        if (e1 && /fail|error/i.test(e1.text)) return 'epub-error';
        if (e2 && /fail|error/i.test(e2.text)) return 'cover-error';
        if (e1 && e2) return 'both';
        if (e1 || e2) return 'one';
        return null;
    }, { minChecks: 16, interval: 800, maxMs: 25000, hardMs: 60000 });
    if (!seen) {
        CL('Content: no file registered in the dialog.', 'error');
        return result;
    }
    if (pbuDialogEntry(epubFile)) { await pbuWaitComplete2(epubFile); result.epub = pbuEntryComplete(epubFile); }
    if (pbuDialogEntry(coverFile)) { await pbuWaitComplete2(coverFile); result.cover = pbuEntryComplete(coverFile); }
    if (result.epub && result.cover) {
        CL(`Uploaded BOTH files together — "${epubFile.name}" and "${coverFile.name}" both reached 100% in a single dialog.`);
    }
    return result;
}

async function pbuTrustedBrowse(files) {
    // v9.19: the Browse route is REMOVED at the user's order — this
    // browser must never try to open the native file dialog. Files
    // are placed only by finding the popup's hidden file input (DOM
    // + every Shadow DOM) and assigning a DataTransfer to it, or by
    // the drag & drop simulation. Returning false moves the flow
    // straight to those routes.
    if (!window.__pbu919BrowseLogged) {
        window.__pbu919BrowseLogged = true;
        CL('Content: the Browse route is disabled in this version — files are placed via the hidden input / drag & drop simulation only.');
    }
    return false;
}

async function pbuUploadTogether(epubFile, coverFile) {
    const result = { epub: false, cover: false };
    for (let cycle = 0; cycle < 2; cycle++) {
        const dlg = await pbuOpenDialogTrusted();
        if (!dlg) {
            CL('Content: the upload dialog could not be opened for the combined upload.', 'error');
            return result;
        }
        const input = await pbuWaitInputPatient('combined upload');
        if (input === 'dialog-gone') {
            CL('Content: the upload dialog closed on its own during the combined attempt — reopening it.', 'error');
            continue;
        }
        if (input) {
            CL('Content: uploading the EPUB and the cover TOGETHER in one dialog (the console\'s input accepts multiple files).');
            await pbuAssignInPageWorld(['epub', 'cover'], [epubFile, coverFile], input);
            await sleep(800);
            await pbuSettleTogether(epubFile, coverFile, result);
            await pbuCloseUploadDialog('the combined upload finished');
            break;
        }
        CL('Content: the dialog\'s own file input did not appear for the combined upload. ' + pbuDialogCensus() + '.', 'error');
        if (await pbuTrustedBrowse([epubFile, coverFile])) {
            await pbuSettleTogether(epubFile, coverFile, result);
            await pbuCloseUploadDialog('the combined upload finished');
            break;
        }
        await pbuCloseUploadDialog('no route could place the files in this dialog');
        break;
    }
    if (result.epub) pbuDoneUploads.add('epub:' + epubFile.name + ':' + epubFile.size);
    if (result.cover) pbuDoneUploads.add('cover:' + coverFile.name + ':' + coverFile.size);
    return result;
}

async function uploadOne(kind, file, successTimeout = 180000) {
    const beforeRows = new Set(fileRows().map((r) => r.text));
    const bannerBefore = /Successfully uploaded/i.test(pageText());
    const rowMatchesKind = (text) => kind === 'epub' ?
        /\.epub/i.test(text) :
        /frontcover|front cover/i.test(text) || (/\.(jpe?g|png)/i.test(text) && /cover/i.test(text));
    const finish = (outcome) => {
        if (!outcome) return false;
        if (outcome.fail) {
            throw new Error(`Content: "${file.name}" upload failed — the console reports: "${outcome.fail}"`);
        }
        CL(`Uploaded ${file.name} — confirmed via its ${outcome.via === 'row' ? 'file row' : outcome.via === 'dialog' ? 'dialog entry' : 'success banner'}.`);
        return true;
    };
    const pollConfirm = (opts) => pbuPoll(() => {
        const rows = fileRows();
        for (const r of rows) {
            if (beforeRows.has(r.text)) continue;
            if (/failed|epubcheck|invalid|corrupt|not a valid/i.test(r.text)) return { fail: r.text.slice(0, 220) };
        }
        const newRow = rows.find((r) => !beforeRows.has(r.text) && rowMatchesKind(r.text));
        if (newRow) return { ok: true, via: 'row' };
        if (!bannerBefore && /Successfully uploaded/i.test(pageText())) return { ok: true, via: 'banner' };
        if (pbuDialogEntry(file)) return { ok: true, via: 'dialog' };
        return null;
    }, opts);
    const pollOutcome = (ms) => waitFor(() => {
        const rows = fileRows();
        for (const r of rows) {
            if (beforeRows.has(r.text)) continue;
            if (/failed|epubcheck|invalid|corrupt|not a valid/i.test(r.text)) return { fail: r.text.slice(0, 220) };
        }
        const newRow = rows.find((r) => !beforeRows.has(r.text) && rowMatchesKind(r.text));
        if (newRow) return { ok: true, via: 'row' };
        if (!bannerBefore && /Successfully uploaded/i.test(pageText())) return { ok: true, via: 'banner' };
        if (pbuDialogEntry(file)) return { ok: true, via: 'dialog' };
        return null;
    }, ms, 1200);

    const doneKey = kind + ':' + file.name + ':' + file.size;
    if (pbuDoneUploads.has(doneKey)) {
        CL(`Content: "${file.name}" was already uploaded earlier in this session — skipping it and moving to the next file.`);
        await pbuCloseUploadDialog('that file is already uploaded');
        return;
    }
    if (pbuDialogEntry(file) || pbuDialogText().includes(file.name)) {
        const r = await pbuWaitComplete2(file);
        if (r === 'done' || r === 'dialog-gone') {
            await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
            pbuDoneUploads.add(doneKey);
            CL(`Uploaded ${file.name} — confirmed via its dialog entry.`);
            return;
        }
    }

    const captureMark = pbuCapturedInputs.length;
    const freshCaptured = () => pbuCapturedInputs.slice(captureMark)
        .filter((i) => !pbuBaselineInputs.has(i));

    // ---- Dialog route: one fresh dialog per file, opened with a
    // synthetic click, with a patient wait for the dialog's input. ----
    for (let cycle = 0; cycle < 2; cycle++) {
        const dlg = await pbuOpenDialogTrusted();
        if (!dlg) break;
        let confirmed = false;

        // Route A (primary): the dialog's OWN input[name="Filedata"],
        // fed by the PAGE WORLD (the picker's own end result).
        const dlgInput = await pbuWaitInputPatient(`"${file.name}"`);
        if (dlgInput === 'dialog-gone') {
            CL(`Content: the upload dialog closed on its own — reopening it for "${file.name}".`, 'error');
            continue;
        }
        if (dlgInput) {
            CL(`Content: the dialog's own file input is ready — assigning "${file.name}" via the page world.`);
            await pbuAssignInPageWorld([kind], [file], dlgInput);
            await sleep(800);
            confirmed = finish(await pollConfirm({
                minChecks: 18, interval: 800, maxMs: 25000, hardMs: 60000
            }));
            if (confirmed) {
                await pbuWaitComplete2(file);
                await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
                pbuDoneUploads.add(doneKey);
                return;
            }
            CL('Content: the direct assignment did not confirm — trying the remaining routes.');
        } else {
            CL(`Content: the dialog's file input never appeared for "${file.name}". ` + pbuDialogCensus() + '.', 'error');
        }

        // Route B: REMOVED in v9.19 (the Browse route is disabled —
        // no native file dialog is ever opened; the stub returns
        // false and the flow moves straight to the drop routes).
        if (!confirmed) {
            if (await pbuTrustedBrowse([file])) {
                confirmed = finish(await pollConfirm({
                    minChecks: 14, interval: 800, maxMs: 15000, hardMs: 30000
                }));
            }
            if (!confirmed) {
                const cap = freshCaptured();
                if (cap.length) {
                    assignFilesToInput(cap[cap.length - 1], [file]);
                    await sleep(800);
                    confirmed = finish(await pollConfirm({
                        minChecks: 12, interval: 800, maxMs: 12000, hardMs: 25000
                    }));
                }
            }
        }

        // Route C: main-world drag & drop.
        if (!confirmed) {
            const dropRes = await pbuMainBridge('drop', { kind });
            if (dropRes.ok) {
                CL(`Content: main-world drag & drop dispatched for "${file.name}" (${dropRes.result || 'ok'}).`);
                await sleep(800);
                confirmed = finish(await pollConfirm({
                    minChecks: 14, interval: 800, maxMs: 15000, hardMs: 30000
                }));
            } else {
                CL('Content: main-world drop unavailable (' + (dropRes.error || 'no response') + ').', 'error');
            }
        }

        // Route D: isolated-world drag & drop onto the drop zone.
        if (!confirmed) {
            const liveDlg = uploadDialogEl() || dlg;
            const zone = [...liveDlg.querySelectorAll('*')].filter(isVisible)
                .find((e) => /drag and drop/i.test(norm(e.innerText || e.textContent)) && e.querySelectorAll('*').length < 12) || liveDlg;
            CL(`Content: dropping "${file.name}" onto the upload dialog's drag & drop zone.`);
            dropFileOnto(zone, file);
            dropFileOnto(liveDlg, file);
            await sleep(1000);
            confirmed = finish(await pollConfirm({
                minChecks: 16, interval: 800, maxMs: 20000, hardMs: 40000
            }));
        }

        if (!confirmed) {
            throw new Error(`Content: "${file.name}" did not register in the upload dialog (dialog input, hidden-input assignment and drag & drop all failed). ${describeInputs()} — ${pbuDialogCensus()}`);
        }
        await pbuWaitComplete2(file);
        await pbuCloseUploadDialog(`"${file.name}" finished uploading`);
        pbuDoneUploads.add(doneKey);
        return;
    }

    // ---- Classic route: the dialog could not be opened at all —
    // the Content tab may carry its own file inputs. ----
    let input = findUploadInput(kind);
    if (!input) {
        await revealFileInputs();
        input = findUploadInput(kind);
    }
    if (!input) {
        const cap = pbuCapturedInputs.filter((i) => !pbuBaselineInputs.has(i));
        if (cap.length) input = cap[cap.length - 1];
    }
    if (!input) {
        throw new Error(`Content: no usable file input for the ${kind} upload, and the upload dialog could not be opened. ${describeInputs()}`);
    }
    assignFilesToInput(input, [file]);
    await sleep(1000);
    if (finish(await pollOutcome(successTimeout))) {
        pbuDoneUploads.add(doneKey);
        return;
    }
    const errText = findErrorText();
    throw new Error(`Content: "${file.name}" upload did not confirm` +
        (errText ? ': ' + errText : ' (timed out waiting for its file row / success banner).'));
}

async function stageContent() {
    await goSection(['Content']);
    const blocker = detectBlocker();
    if (blocker) throw stopErr(blocker);

    const { job } = await chrome.storage.local.get('job');
    if (!job || !job.files) throw new Error('Content: stored files are missing (job data not found).');
    const epubFile = base64ToFile(job.files.epub.base64, job.files.epub.name, job.files.epub.type);
    const coverFile = base64ToFile(job.files.cover.base64, job.files.cover.name, job.files.cover.type);

    try {
        CL('Content: stage started — snapshotting inputs, starting the capture net, verifying the upload bridge.');
        pbuBaselineInputs = new Set(deepFindFileInputs());
        startInputCapture();
        await pbuEnsureBridge(job.files);
        CL('Content: input census at stage start — ' + describeInputs() + '.');

        // First try the console's own design: both files together in
        // ONE dialog via its multiple-file input. Whatever is still
        // missing afterwards gets its own dialog cycle. Files already
        // uploaded earlier in this session are never fetched again
        // (the combined attempt only runs when both are missing).
        const epubKey = 'epub:' + epubFile.name + ':' + epubFile.size;
        const coverKey = 'cover:' + coverFile.name + ':' + coverFile.size;
        let together = {
            epub: pbuDoneUploads.has(epubKey),
            cover: pbuDoneUploads.has(coverKey)
        };
        if (!together.epub && !together.cover) {
            try {
                together = await pbuUploadTogether(epubFile, coverFile);
            } catch (e) {
                CL('Content: the combined upload attempt errored (' + ((e && e.message) || e) + ') — continuing one file at a time.', 'error');
            }
        }
        if (!together.epub && !pbuDoneUploads.has(epubKey)) {
            try {
                await uploadOne('epub', epubFile);
            } catch (e) {
                CL('Content: automatic EPUB upload did not succeed (' + ((e && e.message) || e) + ').', 'error');
            }
            await sleep(1000);
        }
        if (!together.cover && !pbuDoneUploads.has(coverKey)) {
            try {
                await uploadOne('cover', coverFile);
            } catch (e) {
                CL('Content: automatic cover upload did not succeed (' + ((e && e.message) || e) + ').', 'error');
            }
            await sleep(1000);
        }
        const stillMissing = [];
        if (!pbuDoneUploads.has(epubKey)) stillMissing.push(epubFile.name);
        if (!pbuDoneUploads.has(coverKey)) stillMissing.push(coverFile.name);
        if (stillMissing.length) {
            await pbuCloseUploadDialog('automatic upload could not place every file');
            // v9.15: NO assisted manual pick — the user cannot and
            // will not pick files by hand. Fail clearly, with the
            // evidence attached, instead of waiting on a human.
            throw new Error('Content: automatic upload could not place: ' + stillMissing.join(', ') +
                '. Every automatic route was tried (dialog open + the dialog\'s own input, ' +
                'page-world direct assignment, drag & drop in both worlds). ' +
                'The manual pick is disabled in this version by your order, so the run stops here instead of asking you to pick files. ' +
                pbuDialogCensus());
        }
        await pbuCloseUploadDialog('both files are uploaded');

        const epubRow = await waitFor(() => currentEpubRow(job.ggkey), 90000, 2000);
        if (!epubRow) {
            throw new Error('Content: the EPUB did not appear on the Content tab after uploading — the upload may not have registered.');
        }
        const stepM = epubRow.text.match(/step\s+(\d)\s+of\s+6/i);
        if (stepM) CL(`EPUB processing started: completed step ${stepM[1]} of 6 (current version).`);
        const rows = fileRows();
        const coverRow = rows.find((r) => /front cover|frontcover/i.test(r.text));
        if (coverRow) CL('Cover registered (a "front cover" row is shown on the Content tab).');
        else CL('Cover upload confirmed, but "front cover" registration was not visible — check on Review.', 'error');

        // Dialog closed, files verified — now Save the step.
        await pbuSaveContentStep();
        return { bookUrl: location.href };
    } finally {
        // (v9.19: no channel to release at stage end.)
        /* v9.19: no debug channel exists, so there is nothing to detach at stage end. */
    }
}

/* =====================================================================
 * v9.16 — auto-OK for the console's "Error saving changes" message +
 * a hardened Settings stage.
 *
 * Live evidence (user screenshot, 2026-10-24 ~09:11 +06, run on
 * GGKEY:GNLF9UCJO2L): the Settings save was rejected by a bottom-left
 * Material snackbar — "Error saving changes. Please address the
 * errors. [OK]" — which nothing in the extension dismissed (the
 * existing dismissInfoDialogs only handles [role=dialog] info
 * dialogs, never snackbars), and saveAndWait read the snackbar's
 * text (button label included) as the save error, failing the stage
 * on both attempts while the snackbar sat on screen. All three
 * Settings values were visibly correct in the screenshot (DRM
 * "No (recommended)", Preview "20% (recommended)", Copy/paste 0%),
 * so the field the console wants fixed is NOT one of the three —
 * most likely a field inside the collapsed "Show advanced settings"
 * / "Show accessibility settings" sections, whose error element is
 * invisible to findErrorText/saveAndWait (isVisible() fails on
 * elements inside collapsed sections).
 *
 * The user's order (2026-10-24): "etao fix koro jekane ata asbe
 * sathe sathe ok kore dibe" — wherever this message appears, press
 * OK immediately.
 *
 * What this block adds (append-only; everything above is untouched):
 *  1. pbuStartSaveErrorWatch — a page-lifetime watcher (Mutation-
 *     Observer + 700ms sweep) that finds a visible snackbar/dialog
 *     whose text matches /error saving changes/i and clicks its OK
 *     button at once, logging the dismissal to the stage log AND
 *     the live panel log (csLog). Scoped to that exact message
 *     only: the "Cancel all uploads?" guard (Continue/Cancel), tax/
 *     payment/identity dialogs and every other dialog are never
 *     touched by it.
 *  2. stageSettings (override) — same standing-rule values and the
 *     same read-back verification as before, plus:
 *       - expands "Show advanced settings" / "Show accessibility
 *         settings" first, so hidden fields and their errors become
 *         visible and checkable;
 *       - sets "For mature audiences" = No if that control lives on
 *         this page (standing rule);
 *       - when a save fails OR the error snackbar had to be auto-
 *         dismissed during the stage, it runs a field-error census
 *         (pbuFieldErrors: every mat-error / form-field error on
 *         the page with its field label, hidden ones marked),
 *         logs the exact fields, fixes a flagged mature control,
 *         re-sets the three values and saves again (up to 2 repair
 *         rounds);
 *       - if the save still fails, the thrown error names the
 *         specific field errors instead of the generic snackbar
 *         text, so the next log is diagnostic;
 *       - final gate: the read-back verify cannot distinguish
 *         "saved" from "the form still shows the values but the
 *         server rejected the save", so if the snackbar appeared
 *         during the stage AND the census still flags a field at
 *         the end, the stage fails with those field names rather
 *         than trusting the form's appearance. (Caught by the
 *         jsdom suite, scenario C, before this version shipped.)
 *     The Verify stage still re-reads the Settings values after a
 *     fresh navigation later in the run, as a second safety net.
 * ===================================================================== */

if (typeof window.__pbuSaveErrDismissals !== 'number') window.__pbuSaveErrDismissals = 0;
const PBU_SAVE_ERR_TEXT = /error saving changes/i;
const __pbuOkDismissedEls = new WeakSet();

function pbuFindSaveErrorOk() {
    const snackbars = [...document.querySelectorAll('.mat-mdc-snack-bar-container, .mat-snack-bar-container, mat-snack-bar-container')];
    for (const c of snackbars) {
        if (!isVisible(c)) continue;
        const t = norm(c.innerText || c.textContent);
        if (!PBU_SAVE_ERR_TEXT.test(t)) continue;
        const btn = [...c.querySelectorAll('button')].find((b) => isVisible(b) && /^ok$/i.test(norm(b.innerText || b.textContent)));
        if (btn) return { box: c, btn, text: t };
    }
    const dialogs = [...document.querySelectorAll('[role="dialog"], mat-dialog-container, .mat-dialog-container')].filter(isVisible);
    for (const d of dialogs) {
        const t = norm(d.innerText || d.textContent);
        if (!PBU_SAVE_ERR_TEXT.test(t)) continue;
        const btn = [...d.querySelectorAll('button')].find((b) => isVisible(b) && /^ok$/i.test(norm(b.innerText || b.textContent)));
        if (btn) return { box: d, btn, text: t };
    }
    return null;
}

function pbuDismissSaveError() {
    let hit = null;
    try { hit = pbuFindSaveErrorOk(); } catch (e) { return false; }
    if (!hit || __pbuOkDismissedEls.has(hit.box)) return false;
    __pbuOkDismissedEls.add(hit.box);
    window.__pbuSaveErrDismissals++;
    clickEl(hit.btn);
    const msg = 'Auto-OK: the "Error saving changes" message appeared — pressed OK immediately (your standing order).';
    try { L(msg, 'error'); } catch (e) { /* stage log unavailable */ }
    try { csLog(msg, 'error'); } catch (e) { /* panel log unavailable */ }
    return true;
}

let __pbuSaveErrWatchStarted = false;
function pbuStartSaveErrorWatch() {
    if (__pbuSaveErrWatchStarted) return;
    __pbuSaveErrWatchStarted = true;
    const sweep = () => { try { pbuDismissSaveError(); } catch (e) { /* never let the watcher break the page */ } };
    try {
        const mo = new MutationObserver(sweep);
        mo.observe(document.documentElement, { childList: true, subtree: true });
    } catch (e) { /* the interval sweep below still covers it */ }
    setInterval(sweep, 700);
}
pbuStartSaveErrorWatch();

/* --- field-error census: which field does the console want fixed? --- */
function pbuFieldLabelFor(el) {
    let node = el;
    for (let i = 0; i < 8 && node; i++) {
        node = node.parentElement;
        if (!node || node === document.body) break;
        const lab = node.querySelector(':scope > mat-label, :scope > label, :scope > legend, :scope mat-label');
        if (lab) {
            const t = norm(lab.innerText || lab.textContent);
            if (t) return t.slice(0, 60);
        }
        if (/form-field|field|group|section/i.test(String(node.className || '')) || /^(MAT-FORM-FIELD|FIELDSET)$/i.test(node.tagName)) {
            const first = (node.textContent || '').split('\n').map((s) => s.trim()).filter(Boolean)[0];
            if (first) return first.slice(0, 60);
        }
    }
    return '';
}

function pbuFieldErrors() {
    const out = [];
    const seen = new Set();
    const push = (label, msg, hidden) => {
        const line = (label ? label + ' — ' : '') + msg + (hidden ? ' (hidden inside a collapsed section)' : '');
        if (!seen.has(line)) { seen.add(line); out.push(line); }
    };
    const errEls = [...document.querySelectorAll('mat-error, .mat-error, .mat-mdc-form-field-error, [class*="form-field-error"]')];
    for (const el of errEls) {
        const msg = norm(el.innerText || el.textContent);
        if (!msg) continue;
        push(pbuFieldLabelFor(el), msg, !isVisible(el));
    }
    if (!out.length) {
        const invalid = [...document.querySelectorAll('[aria-invalid="true"]')].filter((el) =>
            /^(INPUT|SELECT|TEXTAREA)$/.test(el.tagName) || el.getAttribute('role') === 'combobox');
        for (const el of invalid.slice(0, 4)) {
            push(pbuFieldLabelFor(el) || el.getAttribute('aria-label') || el.getAttribute('placeholder') || el.tagName,
                'the field is flagged invalid (aria-invalid)', !isVisible(el));
        }
    }
    return out;
}

async function pbuExpandSettingsSections() {
    for (const label of ['Show advanced settings', 'Show accessibility settings']) {
        const btn = [...document.querySelectorAll('button, [role="button"], a')]
            .filter(isVisible)
            .find((e) => exactTextEq(e.innerText || e.textContent, label));
        if (btn) {
            clickEl(btn);
            L('Settings: expanded "' + label + '" so hidden fields can be checked.');
            await sleep(500);
        }
    }
}

/* --- Settings stage (v9.16 override) --- */
async function stageSettings(meta) {
    await goSection(['Settings']);
    const blocker = detectBlocker();
    if (blocker) throw stopErr(blocker);
    await pbuExpandSettingsSections();

    const setThree = async () => {
        const drm = await chooseInGroup(['DRM', 'encryption'], ['No (recommended)', 'No'], 1e4);
        if (!drm.ok) throw new Error('Settings: DRM could not be verified as "No" (the control shows "' + (drm.value || 'nothing') + '").');
        const prev = await chooseInGroup(['Preview', 'Google Books preview'], ['20% (recommended)', '20%'], 1e4);
        if (!prev.ok) throw new Error('Settings: preview limit could not be verified as "20%" (the control shows "' + (prev.value || 'nothing') + '").');
        let cp = await chooseInGroup(['Copy', 'paste', 'Copy/paste'], ['0%'], 1e4);
        if (!cp.ok) {
            const f = fieldByLabel(['Copy', 'Copy and paste']);
            if (f) {
                await typeInto(f, '0');
                const v = norm(f.value);
                if (v === '0' || v === '0%') cp = { ok: true, value: v };
            }
        }
        if (!cp.ok) throw new Error('Settings: copy/paste limit could not be verified as "0%" (the control shows "' + (cp.value || 'nothing') + '").');
    };
    await setThree();

    // Standing rule, if this book's Settings page carries the control.
    const mat = await chooseInGroup(['mature'], ['No'], 5e3);
    if (mat.ok) L('Settings: "For mature audiences" verified as No (standing rule).');

    const verify = () => {
        const pairs = [
            ['No', readGroupValue(findGroupContainer(['DRM', 'encryption']))],
            ['20%', readGroupValue(findGroupContainer(['Preview', 'Google Books preview']))],
            ['0%', readGroupValue(findGroupContainer(['Copy', 'paste', 'Copy/paste']))],
        ];
        const present = pairs.filter(([, v]) => null != v);
        return !present.length || pairs.every(([want, v]) => null != v && exactTextEq(v, want));
    };

    const dismissalsBefore = window.__pbuSaveErrDismissals || 0;
    let res = await saveAndWait({ verify });
    // Did the console raise its save-error snackbar during this stage?
    // (Seen via the watcher's dismissal count, or via the error text
    // saveAndWait itself captured when it won the race to read it.)
    let snackbarSeen = (window.__pbuSaveErrDismissals || 0) > dismissalsBefore
        || /error saving changes/i.test(res.error || '');

    // Repair rounds: a failed save — or a "saved" verdict that still
    // needed the error snackbar auto-dismissed — gets a census, a fix
    // for any standing-rule field, and a fresh save.
    for (let round = 1; round <= 2; round++) {
        const dismissed = (window.__pbuSaveErrDismissals || 0) > dismissalsBefore;
        if (res.saved && !dismissed) break;
        pbuDismissSaveError();
        await pbuExpandSettingsSections();
        const errs = pbuFieldErrors();
        if (res.saved && !errs.length) {
            L('Settings: the "Error saving changes" message appeared during the save (auto-OK pressed), but no field on the page is flagged and all three values verify as saved — continuing.', 'error');
            break;
        }
        if (errs.length) L('Settings: the console flags these fields — ' + errs.join(' | '), 'error');
        else L('Settings: save failed ("' + (res.error || 'no reason given') + '") with no field error visible — retrying the save.', 'error');
        if (errs.some((e) => /mature/i.test(e))) {
            const m2 = await chooseInGroup(['mature'], ['No'], 5e3);
            if (m2.ok) L('Settings: fixed the flagged field — "For mature audiences" set to No.');
        }
        await setThree().catch(() => {});
        await sleep(600);
        res = await saveAndWait({ verify });
        snackbarSeen = snackbarSeen
            || (window.__pbuSaveErrDismissals || 0) > dismissalsBefore
            || /error saving changes/i.test(res.error || '');
    }

    if (!res.saved) {
        const errs = pbuFieldErrors();
        throw new Error('Settings save failed' + (errs.length ? ' — the console flags: ' + errs.join('; ') : (res.error ? ': ' + res.error : '.')));
    }
    // The read-back verify alone cannot tell "saved" from "the form
    // still shows the values but the server rejected the save". If
    // the console raised the save-error snackbar during this stage
    // AND still flags a field, the save did not persist — fail with
    // the field names instead of trusting the form's appearance.
    if (snackbarSeen) {
        const errs = pbuFieldErrors();
        if (errs.length) {
            throw new Error('Settings save failed — the console flags: ' + errs.join('; '));
        }
    }
    if ((window.__pbuSaveErrDismissals || 0) > dismissalsBefore) {
        L('Settings: note — the "Error saving changes" message appeared during this stage and was dismissed with OK; the values below were re-read from the page after saving.', 'error');
    }
    L('Settings saved: DRM No / Preview 20% / Copy-paste 0% (all three read back and verified).');
    return { bookUrl: location.href };
}

/* =====================================================================
 * v9.16 (second fix) — the settings repair round (expand the advanced
 * sections, census the flagged fields, re-save) lives in this block.
 * Its old companion piece, a diagnostic for the missing-CDP-channel
 * case, was REMOVED in v9.19 together with that channel itself, at
 * the user's order: their custom browser does not support the API,
 * so clicks in this extension are synthetic only, the Browse button
 * is never pressed, and files are placed via the hidden file input
 * (DOM + Shadow DOM) or the drag & drop simulation.
 * ===================================================================== */

async function pbuTrustedClickEl(el, what) {
    // v9.19: the CDP trusted-click channel was REMOVED at the user's
    // order (their custom browser does not support that API). This
    // helper — kept under its old name only because the stage code
    // calls it — is now a plain synthetic click, nothing more.
    if (!el) return false;
    try { el.scrollIntoView({ block: 'center', inline: 'center' }); } catch (e) { /* ignore */ }
    await sleep(200);
    clickEl(el);
    await sleep(400);
    return true;
}

async function pbuWaitInputPatient(label) {
    const fast = !!window.__pbuTrustedApiMissing;
    const start = Date.now();
    let censused = false;
    let goneChecks = 0;
    return pbuPoll(() => {
        const i = pbuDialogFileInput();
        if (i) return i;
        if (!uploadDialogEl()) {
            goneChecks++;
            if (goneChecks >= 4) return 'dialog-gone';
            return null;
        }
        goneChecks = 0;
        if (!censused && Date.now() - start > (fast ? 4000 : 10000)) {
            censused = true;
            CL('Content: still no file input in the dialog after ' + (fast ? '4s' : '10s') + (label ? ' (' + label + ')' : '') + ' — ' + pbuDialogCensus() + '.', 'error');
        }
        return null;
    }, fast
        ? { minChecks: 10, interval: 400, maxMs: 5000, hardMs: 9000 }
        : { minChecks: 40, interval: 500, maxMs: 25000, hardMs: 45000 });
}

async function pbuTrustedBrowse(files) {
    // v9.19: the Browse route is REMOVED at the user's order — this
    // browser must never try to open the native file dialog. Files
    // are placed only by finding the popup's hidden file input (DOM
    // + every Shadow DOM) and assigning a DataTransfer to it, or by
    // the drag & drop simulation. Returning false moves the flow
    // straight to those routes.
    if (!window.__pbu919BrowseLogged) {
        window.__pbu919BrowseLogged = true;
        CL('Content: the Browse route is disabled in this version — files are placed via the hidden input / drag & drop simulation only.');
    }
    return false;
}

/* =====================================================================
 * v9.17 — the hidden-input hunter (the user's requested mechanism,
 * widened to every place an input can hide).
 *
 * The user (2026-10-24): fix the extension to upload WITHOUT
 * depending on drag & drop or the Browse dialog — find the page's
 * hidden file input, set the File objects on it directly, fire the
 * change events. That direct assignment has been the lead route
 * since v9.12 (page-world pbuMainAssign onto the dialog's
 * input[name="Filedata"], input/change dispatched in the page
 * world, read-back verified) and it works whenever the input
 * EXISTS — but every live census since v9.12 found NO input
 * anywhere in extension-opened dialogs. The hunter (page-world
 * half in background.js) closes the remaining detection gaps: it
 * is armed at bridge-verify time, BEFORE the dialog opens, records
 * every shadow root via an attachShadow hook (closed roots
 * included — the only way to ever reach their inputs), keeps a
 * MutationObserver net over the document and every root, and
 * registers any input[type=file] the moment it appears, anywhere
 * on the page. This block wires it into the flow:
 *   - pbuEnsureBridge (override): also arms the hunter, every
 *     attempt, and logs its census once.
 *   - pbuWaitInputPatient (override): while waiting for the
 *     dialog's own input, it also polls the hunter census; a
 *     registered input found ANYWHERE (closed shadow root, page
 *     body, a corner of the dialog the isolated search cannot
 *     reach) ends the wait with a hunted handle.
 *   - pbuAssignInPageWorld (override): a hunted handle is served
 *     by the page world's "assign-any" route (DataTransfer built
 *     in the page world, files set, input+change fired, read-back
 *     verified); a normal dialog input keeps the proven v9.12
 *     route and its content-script fallback.
 * There is no HTML form to submit in this console — the uploader
 * component starts the upload on the input's "change" event, and
 * the stage's existing completion checks (receipt cards → rows →
 * the step's Save via pbuSaveContentStep) finish the job, exactly
 * as before.
 * ===================================================================== */

let __pbuHuntLogged = false;

async function pbuEnsureHunter() {
    const res = await pbuMainBridge('hunt-install');
    if (res && res.ok) {
        if (!__pbuHuntLogged) {
            __pbuHuntLogged = true;
            CL('Content: hidden-input hunter armed in the page world — ' + res.result +
                '. It registers any file input the moment it appears anywhere on the page, including inside closed shadow roots.');
        }
        return true;
    }
    CL('Content: the hidden-input hunter could not be armed (' + ((res && res.error) || 'no response') + ') — continuing with the dialog routes.', 'error');
    return false;
}

async function pbuHuntCensus() {
    const res = await pbuMainBridge('hunt-census');
    return res && res.ok ? res.result : null;
}

function pbuPickHunted(census) {
    if (!census || !census.inputs || !census.inputs.length) return null;
    const usable = census.inputs.filter((x) => !(x.where === 'preexisting' && !x.inDialog));
    const pool = usable.length ? usable : census.inputs;
    const score = (x) =>
        (x.name === 'Filedata' ? 40 : 0) +
        (x.inDialog ? 30 : 0) +
        (String(x.where).indexOf('shadow') === 0 ? 20 : 0) +
        (x.connected ? 10 : 0) +
        (x.holds === 0 ? 5 : 0);
    const best = pool.slice().sort((a, b) => score(b) - score(a) || b.idx - a.idx)[0];
    return best || null;
}

/* --- pbuEnsureBridge (v9.17 override: v9.12 body + hunter arming) --- */
async function pbuEnsureBridge(jobFiles) {
    // Arm the hidden-input hunter FIRST, on every attempt: its
    // attachShadow hook must be in place before the upload dialog
    // (and its uploader component) is created.
    await pbuEnsureHunter();
    // Verify the bridge in the page world on EVERY content-stage
    // attempt and log what is actually staged — never trust a
    // silent "armed once" flag (its silence hid the state in v9.11).
    const want = ['epub', 'cover'];
    let ping = await pbuMainBridge('ping');
    let staged = (ping.ok && ping.result && ping.result.staged) || [];
    if (want.every((k) => staged.includes(k))) {
        CL(`Content: upload bridge verified in the page world (staged: ${staged.join(', ')}).`);
        return true;
    }
    const payload = {
        files: [{
                key: 'epub',
                name: jobFiles.epub.name,
                type: jobFiles.epub.type,
                base64: jobFiles.epub.base64
            },
            {
                key: 'cover',
                name: jobFiles.cover.name,
                type: jobFiles.cover.type,
                base64: jobFiles.cover.base64
            }
        ]
    };
    const res = await pbuMainBridge('stage', {
        payload
    });
    ping = await pbuMainBridge('ping');
    staged = (ping.ok && ping.result && ping.result.staged) || [];
    if (want.every((k) => staged.includes(k))) {
        pbuArmedOnce = true;
        CL(`Content: upload bridge armed and verified in the page world (staged: ${staged.join(', ')}).`);
        return true;
    }
    CL('Content: the upload bridge could not be verified in the page world (' +
        ((res && res.error) || 'staging did not stick') + ') — continuing with direct routes only.', 'error');
    return false;
}

/* --- pbuWaitInputPatient (v9.17 override: dialog input OR hunted input) --- */
async function pbuWaitInputPatient(label) {
    const fast = !!window.__pbuTrustedApiMissing;
    const maxMs = fast ? 5000 : 25000;
    const start = Date.now();
    let censused = false;
    let goneChecks = 0;
    let lastHuntAt = 0;
    let huntedLogged = false;
    for (;;) {
        const own = pbuDialogFileInput();
        if (own) return own;
        if (Date.now() - lastHuntAt >= 1200) {
            lastHuntAt = Date.now();
            const census = await pbuHuntCensus().catch(() => null);
            const cand = pbuPickHunted(census);
            if (cand) {
                if (!huntedLogged) {
                    huntedLogged = true;
                    CL('Content: the page-world hunter found a hidden file input (where: ' + cand.where +
                        (cand.name ? ', name: "' + cand.name + '"' : '') +
                        (cand.inDialog ? ', inside the dialog' : ', outside the dialog') +
                        ') — the file(s) will be set on it directly, no Browse, no drag & drop.');
                }
                return { __pbuHunted: cand.idx, __pbuWhere: cand.where, __pbuName: cand.name };
            }
        }
        if (!uploadDialogEl()) {
            goneChecks++;
            if (goneChecks >= 4) return 'dialog-gone';
        } else {
            goneChecks = 0;
        }
        if (!censused && Date.now() - start > (fast ? 4000 : 10000)) {
            censused = true;
            CL('Content: still no file input in the dialog after ' + (fast ? '4s' : '10s') + (label ? ' (' + label + ')' : '') + ' — ' + pbuDialogCensus() + '.', 'error');
        }
        if (Date.now() - start >= maxMs) return null;
        await sleep(fast ? 400 : 500);
    }
}

/* --- pbuAssignInPageWorld (v9.17 override: hunted handles go to assign-any) --- */
async function pbuAssignInPageWorld(keys, fallbackFiles, inputEl) {
    // A hunted input lives only in the page world (e.g. inside a
    // closed shadow root) — the page world's assign-any route sets
    // the staged files on it directly and fires input+change there.
    if (inputEl && typeof inputEl.__pbuHunted === 'number') {
        const res = await pbuMainBridge('assign-any', { keys });
        if (res.ok && res.result && String(res.result).startsWith('assigned-anywhere')) {
            CL('Content: page-world assignment — ' + res.result + '.');
            return true;
        }
        CL('Content: page-world assignment to the hunted input unavailable (' +
            ((res && (res.result || res.error)) || 'no response') + ').', 'error');
        return false;
    }
    // Lead delivery: the page world assigns the staged files to the
    // dialog's own input (see background.js pbuMainAssign). Falls
    // back to the content-script assignment when the bridge route
    // is unavailable.
    const res = await pbuMainBridge('assign', {
        keys
    });
    if (res.ok && res.result && String(res.result).startsWith('assigned:')) {
        CL('Content: page-world assignment — ' + res.result + '.');
        return true;
    }
    CL('Content: page-world assignment unavailable (' +
        ((res && (res.result || res.error)) || 'no response') +
        ') — assigning from the content script instead.', 'error');
    if (inputEl && fallbackFiles && fallbackFiles.length) {
        assignFilesToInput(inputEl, fallbackFiles);
        await sleep(600);
        CL(`Content: content-script assignment done — the dialog input now holds ${inputEl.files ? inputEl.files.length : 0} file(s).`);
        return true;
    }
    return false;
}

/* =====================================================================
 * v9.18 — JSZip file management (the user's requested flow, exactly):
 *
 *   1. ZIP-FIRST CHECK: whenever files are resolved (ZIP picked, or
 *      Run pressed), look at the panel's ZIP field FIRST. If a ZIP
 *      file is there, it wins over the separate fields.
 *   2. JSZip EXTRACTION: the ZIP is opened with the JSZip library
 *      (vendored locally as jszip.min.js — JSZip 3.10.1 — and loaded
 *      before content.js; Manifest V3 forbids remotely hosted code,
 *      so the "@latest" CDN build cannot be used). Entries are
 *      classified by type — .epub → EPUB, .jpg/.jpeg/.png → cover
 *      (a name containing "cover" wins), .txt → metadata (a name
 *      containing "metadata" wins) — turned into real File objects,
 *      PLACED INTO the panel's corresponding input fields
 *      (#epubFile / #coverFile / #metaFile) with a DataTransfer, and
 *      `input` + `change` events are fired on each field, so the
 *      panel behaves exactly as if the user had picked the three
 *      files by hand. pbuZipParts is set as before, so every later
 *      stage keeps working unchanged. If JSZip is somehow missing,
 *      the built-in dependency-free reader (stored/deflate) is the
 *      fallback and produces the identical result.
 *   3. NO ZIP: the separately picked EPUB / JPG / TXT files are used
 *      directly, and `input` + `change` events are fired on those
 *      fields before submit, exactly as the spec asks.
 *   4. SUBMIT: once the files are in place, Run proceeds into the
 *      original submit pipeline (job creation → create/about/genres/
 *      contributors/settings → content stage, which sets the files
 *      on the console dialog's hidden input, fires change, waits for
 *      100% and Saves the step → pricing → verify → processing →
 *      auto-publish). Nothing else in the flow changes.
 *
 * Wiring note: the panel binds its ZIP `change` and Run `click`
 * listeners when it is built, which can happen before this block
 * runs — so the originals are captured, the globals are replaced
 * (covering a panel built later), and a short poll swaps the actual
 * listeners on the built panel (removeEventListener with the
 * captured original + addEventListener with the new handler; the
 * DOM de-duplicates an identical listener, so it can never double).
 * ===================================================================== */

function pbu918ZipKey(f) { return f ? (f.name + ':' + f.size + ':' + (f.lastModified || 0)) : ''; }

function pbu918BaseName(n) { return String(n || '').split('/').pop(); }

function pbu918AssignToInput(input, file) {
    if (!input || !file) return false;
    const dt = new DataTransfer();
    dt.items.add(file);
    input.files = dt.files;
    input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
    input.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
    return !!(input.files && input.files[0] && input.files[0].name === file.name);
}

function pbu918ClassifyNames(names) {
    const clean = (names || []).filter((n) => n && !n.endsWith('/') && !n.startsWith('__MACOSX/') && !/(^|\/)\.DS_Store$/.test(n));
    const base = (n) => pbu918BaseName(n).toLowerCase();
    const pick = (list, prefer) => {
        if (!list.length) return null;
        const p = prefer ? list.filter((n) => base(n).includes(prefer)) : [];
        return (p.length ? p : list).slice().sort((a, b) => a.length - b.length)[0];
    };
    return {
        epub: pick(clean.filter((n) => /\.epub$/i.test(n)), null),
        cover: pick(clean.filter((n) => /\.(jpe?g|png)$/i.test(n)), 'cover'),
        meta: pick(clean.filter((n) => /\.txt$/i.test(n)), 'metadata'),
    };
}

async function pbu918ExtractZip(zipFile) {
    const Z = (typeof window !== 'undefined' && window.JSZip) || (typeof JSZip !== 'undefined' ? JSZip : null);
    if (Z) {
        const zip = await Z.loadAsync(zipFile);
        const names = [];
        zip.forEach((rel) => { names.push(rel); });
        const sel = pbu918ClassifyNames(names);
        const missing = [];
        if (!sel.epub) missing.push('an EPUB (.epub file)');
        if (!sel.meta) missing.push('a metadata .txt file');
        if (missing.length) throw new Error('ZIP detection failed — missing ' + missing.join(' and ') + ' inside the ZIP.');
        const toFile = async (name, type) => {
            const blob = await zip.file(name).async('blob');
            return new File([blob], pbu918BaseName(name), { type });
        };
        const [epubFile, metaFile, coverFile] = await Promise.all([
            toFile(sel.epub, 'application/epub+zip'),
            toFile(sel.meta, 'text/plain'),
            sel.cover ? toFile(sel.cover, /\.png$/i.test(sel.cover) ? 'image/png' : 'image/jpeg') : Promise.resolve(null),
        ]);
        return { engine: 'JSZip', epubFile, coverFile, metaFile, metaText: await metaFile.text(), epubName: sel.epub, coverName: sel.cover, metaName: sel.meta };
    }
    // Fallback: the built-in reader from v5.0 (stored + deflate only).
    const entries = pbuZipReadEntries(await zipFile.arrayBuffer());
    const parts = pbuZipDetectParts(entries);
    const [epubBytes, metaBytes, coverBytes] = await Promise.all([
        pbuZipExtract(parts.epub), pbuZipExtract(parts.meta), parts.cover ? pbuZipExtract(parts.cover) : Promise.resolve(null),
    ]);
    const epubFile = new File([epubBytes], pbu918BaseName(parts.epub.name), { type: 'application/epub+zip' });
    const metaFile = new File([metaBytes], pbu918BaseName(parts.meta.name), { type: 'text/plain' });
    const coverFile = parts.cover ? new File([coverBytes], pbu918BaseName(parts.cover.name), { type: /\.png$/i.test(parts.cover.name) ? 'image/png' : 'image/jpeg' }) : null;
    return { engine: 'built-in reader (JSZip unavailable)', epubFile, coverFile, metaFile, metaText: new TextDecoder('utf-8').decode(metaBytes), epubName: parts.epub.name, coverName: parts.cover ? parts.cover.name : null, metaName: parts.meta.name };
}

async function pbu918OnZipChange() {
    const zipFile = pbuEls && pbuEls.zip && pbuEls.zip.files && pbuEls.zip.files[0];
    if (!zipFile) { pbuZipParts = null; if (pbuEls && pbuEls.zipInfo) { pbuEls.zipInfo.classList.add('hidden'); pbuEls.zipInfo.textContent = ''; } return null; }
    try {
        const ex = await pbu918ExtractZip(zipFile);
        const placed = [];
        if (pbu918AssignToInput(pbuEls.epub, ex.epubFile)) placed.push('EPUB → EPUB field');
        if (ex.coverFile && pbu918AssignToInput(pbuEls.cover, ex.coverFile)) placed.push('cover → Cover field');
        if (pbu918AssignToInput(pbuEls.meta, ex.metaFile)) placed.push('metadata.txt → metadata field');
        pbuZipParts = {
            zipName: zipFile.name, epubName: ex.epubName, coverName: ex.coverName, metaName: ex.metaName,
            epubFile: ex.epubFile, coverFile: ex.coverFile, metaText: ex.metaText,
            __pbu918ZipKey: pbu918ZipKey(zipFile), __pbu918Engine: ex.engine,
        };
        if (pbuEls.zipInfo) {
            pbuEls.zipInfo.innerHTML =
                `<div>📖 <strong>EPUB:</strong> ${pbuEsc(ex.epubName)} (${pbuFmtSize(ex.epubFile.size)})</div>` +
                (ex.coverFile ? `<div>🖼 <strong>Cover:</strong> ${pbuEsc(ex.coverName)} (${pbuFmtSize(ex.coverFile.size)})</div>` : '<div>🖼 <strong>Cover:</strong> not found in the ZIP — pick one below</div>') +
                `<div>📝 <strong>Metadata:</strong> ${pbuEsc(ex.metaName)} (${pbuFmtSize(ex.metaFile.size)})</div>` +
                `<div>✅ Extracted with ${pbuEsc(ex.engine)} and placed into the fields below — change events fired.</div>`;
            pbuEls.zipInfo.classList.remove('hidden');
        }
        await csLog(`ZIP-first: "${zipFile.name}" opened with ${ex.engine} — extracted and placed into the input fields (${placed.join(' · ')}) with change events fired.`, 'stage');
        try { pbuShowSummary(parseMetadata(ex.metaText)); } catch (e) {}
        return pbuZipParts;
    } catch (e) {
        pbuZipParts = null;
        if (pbuEls && pbuEls.zipInfo) { pbuEls.zipInfo.innerHTML = `<div>⚠ ${pbuEsc(String(e && e.message || e))}</div>`; pbuEls.zipInfo.classList.remove('hidden'); }
        await csLog('ZIP problem: ' + String(e && e.message || e), 'error');
        return null;
    } finally {
        try { pbuRefreshFromStorage(); } catch (e) {}
    }
}

const pbu918OrigZipChange = pbuOnZipChange;
const pbu918OrigRun = pbuOnRun;

async function pbu918OnRun() {
    const zipFile = pbuEls && pbuEls.zip && pbuEls.zip.files && pbuEls.zip.files[0];
    if (zipFile) {
        const ready = pbuZipParts && pbuZipParts.__pbu918ZipKey === pbu918ZipKey(zipFile) && pbuEls.epub && pbuEls.epub.files && pbuEls.epub.files[0];
        if (!ready) {
            await csLog('ZIP-first check on Run: a ZIP is selected — extracting it with JSZip and placing the files into the fields before submit.', 'stage');
            const parts = await pbu918OnZipChange();
            if (!parts) { try { pbuRefreshFromStorage(); } catch (e) {} return; }
        } else {
            await csLog('ZIP-first check on Run: ZIP already extracted with ' + (pbuZipParts.__pbu918Engine || 'JSZip') + ' and the fields are filled — submitting.', 'stage');
        }
    } else if (pbuEls) {
        const fired = [];
        for (const [label, el] of [['EPUB', pbuEls.epub], ['cover', pbuEls.cover], ['metadata.txt', pbuEls.meta]]) {
            if (el && el.files && el.files[0]) {
                el.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
                el.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
                fired.push(label);
            }
        }
        if (fired.length) await csLog('No ZIP selected — using the separate files directly (' + fired.join(', ') + '); change events fired, now submitting the form.', 'stage');
    }
    return pbu918OrigRun();
}

pbuOnZipChange = pbu918OnZipChange;
pbuOnRun = pbu918OnRun;

function pbu918WirePanel() {
    if (!pbuEls || !pbuEls.zip || pbuEls.zip.__pbu918Wired) return false;
    try { pbuEls.zip.removeEventListener('change', pbu918OrigZipChange); } catch (e) {}
    pbuEls.zip.addEventListener('change', pbu918OnZipChange);
    if (pbuEls.run) {
        try { pbuEls.run.removeEventListener('click', pbu918OrigRun); } catch (e) {}
        pbuEls.run.addEventListener('click', pbu918OnRun);
    }
    pbuEls.zip.__pbu918Wired = true;
    return true;
}
if (!pbu918WirePanel()) {
    const pbu918WireTimer = setInterval(() => { if (pbu918WirePanel()) clearInterval(pbu918WireTimer); }, 500);
    setTimeout(() => clearInterval(pbu918WireTimer), 30000);
}


/* =====================================================================
 * v9.19 — the CDP channel is REMOVED; hidden-input + DataTransfer
 * only. The user's order (2026-10-24, Bengali): they run their own
 * custom browser, which does not support that extension API at
 * all — remove its permission from manifest.json and ALL of its
 * logic from the code. No trusted clicks anywhere, and the Browse
 * button is never pressed (no attempt to open the native file
 * dialog). Uploads must work with no such channel at all.
 *
 * What was removed (textually, verifiable by searching the shipped
 * files for the API's name: zero hits):
 *   - manifest.json: the permission for that API is gone.
 *   - background.js: the whole v9.15 trusted-click listener block
 *     (attach / mouse-event dispatch / detach) and the v9.16
 *     availability-diagnostic override were excised verbatim.
 *   - content.js: both generations of the trusted-click helper now
 *     do a plain synthetic click and never message the background;
 *     both Browse helpers are stubs that return false at once; the
 *     stage-end detach call is gone; stale route comments updated.
 *
 * The upload mechanism that remains is exactly the one the user
 * specified:
 *   1. When the upload popup opens, FIND the hidden
 *      <input type="file"> by searching the popup's DOM and every
 *      Shadow DOM (the deep search + the v9.17 page-world hunter,
 *      which also reaches CLOSED shadow roots and inputs parked
 *      outside the dialog).
 *   2. Put the user's EPUB and cover JPG into a new DataTransfer(),
 *      set fileInput.files = dataTransfer.files directly, and
 *      dispatch `input` and `change` events with
 *      { bubbles: true, composed: true } (composed so the events
 *      cross shadow boundaries) — in the page world for the
 *      dialog's own input, with the isolated-world assign as the
 *      fallback; both were upgraded to composed events in v9.19.
 *   3. As the alternative route, simulate dragenter -> dragover ->
 *      drop on the drag & drop box with that same DataTransfer
 *      (page-world drop first, isolated-world drop second; both
 *      composed as well).
 *
 * This block only adds the stage-level mode log below, so every
 * run states plainly which mechanism placed the files.
 * ===================================================================== */

const pbu919EnsureBridgeInner = pbuEnsureBridge;
let pbu919ModeLogged = false;
pbuEnsureBridge = async function (files) {
    const r = await pbu919EnsureBridgeInner(files);
    if (!pbu919ModeLogged) {
        pbu919ModeLogged = true;
        CL('Content: v9.19 CDP-free mode — the popup\'s hidden file input is searched in the DOM and every Shadow DOM; files are placed with a DataTransfer (input/change, composed) or the drag & drop simulation. No trusted clicks, no Browse press.');
    }
    return r;
};

/* =====================================================================
 * v9.20 — Browse re-enabled, fed by the page-world interceptors.
 *
 * The user's diagnosis (2026-10-24): the dialog has NO file input
 * beforehand ("inputs in dialog=[none]") — Angular creates it in
 * memory only when "Browse" is clicked (.click() on a fresh
 * createElement('input'), or window.showOpenFilePicker()). v9.19
 * stopped pressing Browse, so nothing was ever created. The fix
 * (background.js, armed by pbuEnsureBridge BEFORE the dialog
 * opens): the page world intercepts the input's click, tracks
 * createElement('input'), and answers showOpenFilePicker with the
 * staged files — so pressing Browse now injects the EPUB + cover
 * instantly, and no native file dialog can open. No CDP channel
 * is involved anywhere (v9.19's removal stands).
 *
 * This block:
 *   - pbuTrustedBrowse (3rd generation — the name is kept for the
 *     older call sites): really presses Browse with the full event
 *     sequence (pointerdown -> mousedown -> mouseup -> click, plus
 *     .click()), then waits for the files to register. The two
 *     earlier generations (CDP click, disabled stub) are replaced.
 *   - pbuUploadTogether (override): quick probe for a pre-existing
 *     input first (~3s — a manually primed dialog can have one);
 *     if none, Browse is pressed FIRST (it is what creates the
 *     input), and only if that registers nothing does the flow
 *     fall back to the patient hunter-aware wait + assignment.
 *   - dropFileOnto (override): the isolated-world drag & drop now
 *     fires dragenter/dragover/drop on the zone, its parent, its
 *     children, mat-dialog-content and the dialog, with the
 *     DataTransfer force-bound via Object.defineProperty (the
 *     page-world drop route in background.js does the same).
 * ===================================================================== */

async function pbuTrustedBrowse(files) {
    const dlg = uploadDialogEl();
    if (!dlg) return false;
    const browseBtn = [...dlg.querySelectorAll('button, [role="button"]')].filter(isVisible)
        .find((b) => exactTextEq(b.innerText || b.textContent, 'Browse'));
    if (!browseBtn) return false;
    CL('Content: pressing "Browse" — the armed page-world interceptors supply "' +
        files.map((f) => f.name).join('", "') + '" to the file request (no native dialog can open).');
    try { browseBtn.scrollIntoView({ block: 'center', inline: 'center' }); } catch (e) { /* ignore */ }
    await sleep(150);
    for (const type of ['pointerdown', 'mousedown', 'mouseup', 'click']) {
        try { browseBtn.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, composed: true, view: window })); } catch (e) { /* ignore */ }
        await sleep(60);
    }
    try { browseBtn.click(); } catch (e) { /* ignore */ }
    const hit = await pbuPoll(() => {
        for (const f of files) { if (pbuDialogEntry(f)) return f.name; }
        return null;
    }, { minChecks: 16, interval: 700, maxMs: 15000, hardMs: 30000 });
    if (hit) return true;
    CL('Content: the Browse press did not register a file — the interceptors may not be armed, or the console triggered the picker another way.', 'error');
    return false;
}

async function pbu920ProbeInput(ms) {
    const start = Date.now();
    let lastHuntAt = 0;
    while (Date.now() - start < ms) {
        const own = pbuDialogFileInput();
        if (own) return own;
        if (Date.now() - lastHuntAt >= 1000) {
            lastHuntAt = Date.now();
            const census = await pbuHuntCensus().catch(() => null);
            const cand = pbuPickHunted(census);
            if (cand) {
                CL('Content: the page-world hunter found a hidden file input (where: ' + cand.where +
                    (cand.name ? ', name: "' + cand.name + '"' : '') +
                    (cand.inDialog ? ', inside the dialog' : ', outside the dialog') +
                    ') — the file(s) will be set on it directly.');
                return { __pbuHunted: cand.idx, __pbuWhere: cand.where, __pbuName: cand.name };
            }
        }
        if (!uploadDialogEl()) return 'dialog-gone';
        await sleep(400);
    }
    return null;
}

async function pbuUploadTogether(epubFile, coverFile) {
    const result = { epub: false, cover: false };
    const assignBoth = async (input) => {
        CL('Content: uploading the EPUB and the cover TOGETHER in one dialog (the console\'s input accepts multiple files).');
        await pbuAssignInPageWorld(['epub', 'cover'], [epubFile, coverFile], input);
        await sleep(800);
        await pbuSettleTogether(epubFile, coverFile, result);
    };
    for (let cycle = 0; cycle < 2; cycle++) {
        const dlg = await pbuOpenDialogTrusted();
        if (!dlg) {
            CL('Content: the upload dialog could not be opened for the combined upload.', 'error');
            return result;
        }
        // Quick probe: a pre-existing input (some dialogs render
        // one as soon as they open) is still the fastest route.
        let input = await pbu920ProbeInput(3000);
        if (input === 'dialog-gone') {
            CL('Content: the upload dialog closed on its own during the combined attempt — reopening it.', 'error');
            continue;
        }
        if (input) {
            await assignBoth(input);
            await pbuCloseUploadDialog('the combined upload finished');
            break;
        }
        // Per the logs the input is only CREATED when Browse is
        // pressed — press it now; the interceptors serve both files.
        if (await pbuTrustedBrowse([epubFile, coverFile])) {
            await pbuSettleTogether(epubFile, coverFile, result);
            await pbuCloseUploadDialog('the combined upload finished');
            break;
        }
        // Browse registered nothing — one patient, hunter-aware
        // wait (an input may still render late on a slow network),
        // then assignment if one shows up.
        input = await pbuWaitInputPatient('combined upload');
        if (input === 'dialog-gone') {
            CL('Content: the upload dialog closed on its own during the combined attempt — reopening it.', 'error');
            continue;
        }
        if (input) {
            await assignBoth(input);
            await pbuCloseUploadDialog('the combined upload finished');
            break;
        }
        CL('Content: no route placed the files in this dialog. ' + pbuDialogCensus() + '.', 'error');
        await pbuCloseUploadDialog('no route could place the files in this dialog');
        break;
    }
    if (result.epub) pbuDoneUploads.add('epub:' + epubFile.name + ':' + epubFile.size);
    if (result.cover) pbuDoneUploads.add('cover:' + coverFile.name + ':' + coverFile.size);
    return result;
}

function dropFileOnto(el, file) {
    if (!el) return;
    const dt = new DataTransfer();
    dt.items.add(file);
    const dlg = uploadDialogEl();
    const content = dlg ? (dlg.querySelector('mat-dialog-content') || dlg) : null;
    const targets = [];
    const add = (t) => { if (t && !targets.includes(t)) targets.push(t); };
    add(el);
    add(el.parentElement);
    for (const ch of el.children || []) add(ch);
    add(content);
    add(dlg);
    const fire = (t, type) => {
        let ev;
        try { ev = new DragEvent(type, { bubbles: true, cancelable: true, composed: true, dataTransfer: dt }); }
        catch (e) { ev = new Event(type, { bubbles: true, cancelable: true, composed: true }); }
        try { Object.defineProperty(ev, 'dataTransfer', { value: dt }); } catch (e) { /* keep the ctor value */ }
        t.dispatchEvent(ev);
    };
    for (const type of ['dragenter', 'dragover', 'drop']) {
        for (const t of targets) fire(t, type);
    }
}

const pbu920EnsureBridgeInner = pbuEnsureBridge;
let pbu920ModeLogged = false;
pbuEnsureBridge = async function (files) {
    try { pbu919ModeLogged = true; } catch (e) { /* the v9.19 note is simply superseded */ }
    const r = await pbu920EnsureBridgeInner(files);
    if (!pbu920ModeLogged) {
        pbu920ModeLogged = true;
        CL('Content: v9.20 page-world interception mode — Browse is pressed and the armed interceptors (input click / createElement tracking / showOpenFilePicker) supply the staged EPUB + cover; no native file dialog, no CDP channel.');
    }
    return r;
};
/* =====================================================================
 * v9.21 — Early interception + Browse is ALWAYS pressed + detailed
 * Browse/interceptor logging. The user's correction (2026-10-24):
 * the console creates its hidden <input type="file"> in memory at
 * PAGE LOAD and only calls .click() on it when "Browse" is pressed
 * — so (1) the hooks must be installed at document_start in the
 * MAIN world, before Angular loads (manifest entry for
 * early-intercept.js, world: "MAIN", run_at: "document_start";
 * the background stage cooperates and never re-patches over them),
 * (2) every file-input .click() / .showPicker() / showOpenFilePicker()
 * call is intercepted in the page world — DOM or detached — with
 * no native picker ever opening while files are staged, and
 * (3) the "Browse" button is pressed on EVERY dialog, first,
 * never skipped, never stubbed. This block:
 *   - pbuTrustedBrowse (4th generation): finds the dialog's Browse
 *     button, logs (a) found/clicked explicitly, presses it with
 *     the full event sequence + .click(), then polls for dialog
 *     entries AND for new page-world intercept hits, and logs (b)
 *     whether the input-click interceptor actually fired, with the
 *     file names it served. Returns true only if a file registered.
 *   - pbuUploadTogether (override): Browse FIRST — the old ~3s
 *     pre-existing-input probe is gone, because pressing Browse is
 *     what triggers the console's own hidden-input click. Only if
 *     the Browse press registers nothing does the flow fall back
 *     to the patient hunter-aware wait + direct assignment.
 *   - pbuEnsureBridge wrapper: logs the v9.21 mode line and whether
 *     the document_start hooks are armed (or the Run-time fallback
 *     patches are active instead), once per stage.
 * No CDP channel is involved anywhere (v9.19's removal stands);
 * the manual pick stays removed (v9.15) — a failed stage throws
 * a clear error with the census, it never asks the user to pick.
 * ===================================================================== */

async function pbuInterceptState921() {
    try {
        const r = await pbuMainBridge('ping');
        return (r && r.ok && r.result) || null;
    } catch (e) { return null; }
}

async function pbuTrustedBrowse(files) {
    const dlg = uploadDialogEl();
    if (!dlg) {
        CL('Content: [Browse check] dialog Browse button found: NO — no upload dialog is open.', 'error');
        return false;
    }
    const browseBtn = [...dlg.querySelectorAll('button, [role="button"]')].filter(isVisible)
        .find((b) => exactTextEq(b.innerText || b.textContent, 'Browse'));
    if (!browseBtn) {
        CL('Content: [Browse check] dialog Browse button found: NO — the open dialog has no visible Browse button. ' + pbuDialogCensus() + '.', 'error');
        return false;
    }
    const before = await pbuInterceptState921();
    const beforeCount = before ? (before.interceptCount || 0) : 0;
    CL('Content: [Browse check] dialog Browse button found: YES — clicking it now (pointerdown, mousedown, mouseup, click + .click()). Browse is NEVER skipped in this version.');
    try { browseBtn.scrollIntoView({ block: 'center', inline: 'center' }); } catch (e) { /* ignore */ }
    await sleep(150);
    for (const type of ['pointerdown', 'mousedown', 'mouseup', 'click']) {
        try { browseBtn.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, composed: true, view: window })); } catch (e) { /* ignore */ }
        await sleep(60);
    }
    try { browseBtn.click(); } catch (e) { /* ignore */ }
    CL('Content: [Browse check] Browse button clicked: YES.');
    // Poll for BOTH signals: a dialog receipt entry, or a new
    // page-world intercept hit (the hidden input's click was
    // intercepted and the files were set on it).
    let registered = null;
    let newHits = [];
    const deadline = Date.now() + 15000;
    for (let checks = 0; Date.now() < deadline || checks < 4; checks++) {
        for (const f of files) {
            if (pbuDialogEntry(f)) { registered = f.name; break; }
        }
        if (registered) break;
        const st = await pbuInterceptState921();
        if (st && (st.interceptCount || 0) > beforeCount) {
            newHits = (st.interceptHits || []).slice(beforeCount);
            break;
        }
        await sleep(700);
    }
    const after = await pbuInterceptState921();
    if (after && (after.interceptCount || 0) > beforeCount) {
        newHits = (after.interceptHits || []).slice(beforeCount);
    }
    if (newHits.length) {
        const served = [];
        for (const h of newHits) for (const n of (h.names || [])) if (n && !served.includes(n)) served.push(n);
        CL('Content: [Browse check] after the Browse click, the HTMLInputElement.prototype.click interceptor triggered: YES — served: "' + served.join('", "') + '" (via: ' + newHits.map((h) => h.via).join(', ') + ').');
    } else {
        CL('Content: [Browse check] after the Browse click, the HTMLInputElement.prototype.click interceptor triggered: NO — no new intercept hit was recorded (early document_start hooks armed: ' + (after ? (after.earlyArmed ? 'YES' : 'NO — Run-time fallback patches active') : 'unknown') + ').', 'error');
    }
    if (registered) return true;
    if (newHits.length) {
        // The interceptor served the files; give the console a
        // moment to turn them into receipt entries.
        const hit = await pbuPoll(() => {
            for (const f of files) { if (pbuDialogEntry(f)) return f.name; }
            return null;
        }, { minChecks: 8, interval: 700, maxMs: 10000, hardMs: 20000 });
        return !!hit;
    }
    CL('Content: the Browse press did not register a file — the interceptors may not be armed, or the console triggered the picker another way.', 'error');
    return false;
}

async function pbuUploadTogether(epubFile, coverFile) {
    const result = { epub: false, cover: false };
    const assignBoth = async (input) => {
        CL('Content: uploading the EPUB and the cover TOGETHER in one dialog (the console\'s input accepts multiple files).');
        await pbuAssignInPageWorld(['epub', 'cover'], [epubFile, coverFile], input);
        await sleep(800);
        await pbuSettleTogether(epubFile, coverFile, result);
    };
    for (let cycle = 0; cycle < 2; cycle++) {
        const dlg = await pbuOpenDialogTrusted();
        if (!dlg) {
            CL('Content: the upload dialog could not be opened for the combined upload.', 'error');
            return result;
        }
        // Browse FIRST, always: pressing Browse is what makes the
        // console call .click() on its hidden in-memory input, and
        // the armed page-world interceptors serve both files into
        // that click. No pre-existing-input probe comes before it.
        if (await pbuTrustedBrowse([epubFile, coverFile])) {
            await pbuSettleTogether(epubFile, coverFile, result);
            await pbuCloseUploadDialog('the combined upload finished');
            break;
        }
        // Browse registered nothing — one patient, hunter-aware
        // wait (an input may still render late on a slow network),
        // then assignment if one shows up.
        const input = await pbuWaitInputPatient('combined upload');
        if (input === 'dialog-gone') {
            CL('Content: the upload dialog closed on its own during the combined attempt — reopening it.', 'error');
            continue;
        }
        if (input) {
            await assignBoth(input);
            await pbuCloseUploadDialog('the combined upload finished');
            break;
        }
        CL('Content: no route placed the files in this dialog. ' + pbuDialogCensus() + '.', 'error');
        await pbuCloseUploadDialog('no route could place the files in this dialog');
        break;
    }
    if (result.epub) pbuDoneUploads.add('epub:' + epubFile.name + ':' + epubFile.size);
    if (result.cover) pbuDoneUploads.add('cover:' + coverFile.name + ':' + coverFile.size);
    return result;
}

const pbu921EnsureBridgeInner = pbuEnsureBridge;
let pbu921ModeLogged = false;
pbuEnsureBridge = async function (files) {
    try { pbu920ModeLogged = true; } catch (e) { /* the v9.20 note is simply superseded */ }
    const r = await pbu921EnsureBridgeInner(files);
    if (!pbu921ModeLogged) {
        pbu921ModeLogged = true;
        const st = await pbuInterceptState921();
        CL('Content: v9.21 early interception mode — document_start MAIN hooks (input click / showPicker / showOpenFilePicker) were installed at page load, before Angular; Browse is pressed on every dialog and the interceptor serves the staged EPUB + cover; no native file dialog, no CDP channel.');
        CL('Content: [interceptor] early document_start hooks armed: ' + (st ? (st.earlyArmed ? 'YES' : 'NO — Run-time fallback patches are active instead') : 'unknown') + '; staged: ' + (st ? (st.staged || []).join(', ') : 'unknown') + '; intercept hits so far: ' + (st ? (st.interceptCount || 0) : 'unknown') + '.');
    }
    return r;
};
/* =====================================================================
 * v9.22 — isTrusted bypass + every-route fallbacks + diagnostic log.
 * Live evidence from the v9.21 run: Browse produced ZERO intercept
 * hits and a dispatched DragEvent registered nothing — the console
 * ignores untrusted events. The document_start hooks (early-
 * intercept.js, all_frames) now proxy every watched listener's
 * event so isTrusted always reads true, capture the callbacks,
 * hook dispatchEvent('click') on file inputs, and track every
 * created input in window.__allCreatedInputs. This block wires
 * the content stage to the new page-world drivers (background.js
 * listener 5) and prints the diagnostic log the user asked for:
 *   - pbuDiag922 / pbuLogDiag922: (a) created-input counts,
 *     (b) captured click/drop listener counts on dialog
 *     elements, (c) Angular methods found in ng-component.
 *   - pbuUploadTogether (override): Browse FIRST, always (gen4
 *     Browse press, unchanged). If Browse registers nothing, it
 *     falls through IN ORDER, in the SAME open dialog:
 *     assign-created (serve any created file input directly,
 *     even without .click()) -> direct-drop (spoofed
 *     dataTransfer + direct invocation of captured drop
 *     callbacks the dispatch missed) -> ng-inject (call the
 *     Angular onFileSelected/onDrop/handleFiles/uploadFiles
 *     method with the staged FileList) -> the patient
 *     hunter-aware wait + direct assignment. Direct invocation
 *     never re-fires a callback the dispatch already invoked
 *     (invocation counts prove it), so no file is uploaded twice.
 *   - pbuEnsureBridge wrapper: ensures the early script is
 *     injected (best effort) before staging, and logs the v9.22
 *     mode line + early-armed state once per stage.
 * No CDP channel is involved anywhere; the manual pick stays
 * removed — a failed stage throws a clear error with the census.
 * ===================================================================== */

async function pbuDiag922() {
    try {
        const r = await pbuMainBridge('diag');
        return (r && r.ok && r.result) || null;
    } catch (e) { return null; }
}

function pbuLogDiag922(diag, label) {
    if (!diag) {
        CL('Content: [diag ' + label + '] diagnostic report unavailable (bridge diag did not answer).', 'error');
        return;
    }
    const createdDetail = (diag.created || []).filter((c) => c.type === 'file')
        .map((c) => (c.name || 'unnamed') + ' accept="' + c.accept + '"' + (c.inDialog ? ' in-dialog' : '') + (c.connected ? '' : ' detached')).join('; ');
    CL('Content: [diag ' + label + '] created inputs: ' + diag.createdTotal + ' (' + diag.createdFile + ' file type)' +
        (createdDetail ? ' — ' + createdDetail : '') + '; dialog open: ' + (diag.dialogOpen ? 'YES' : 'NO') + '.');
    CL('Content: [diag ' + label + '] captured listeners on dialog elements: click=' + diag.captured.click +
        ', drop=' + diag.captured.drop + ', change=' + diag.captured.change + ' (' + diag.captured.elements + ' element(s)).');
    const methods = (diag.ng && diag.ng.methods) || [];
    CL('Content: [diag ' + label + '] ng-component methods: ' + (methods.length ?
        methods.map((m) => m.tag + '.' + m.name + ' (' + m.source + ')').join(', ') : 'none found') +
        ' (scanned ' + (diag.ng ? diag.ng.scanned : 0) + ' element(s)).');
}

async function pbuDirectDrop922() {
    try {
        const r = await pbuMainBridge('direct-drop');
        return (r && r.ok) ? r.result : null;
    } catch (e) { return null; }
}

async function pbuAssignCreated922() {
    try {
        const r = await pbuMainBridge('assign-created');
        return (r && r.ok) ? r.result : null;
    } catch (e) { return null; }
}

async function pbuNgInject922() {
    try {
        const r = await pbuMainBridge('ng-inject');
        return (r && r.ok) ? r.result : null;
    } catch (e) { return null; }
}

async function pbuPollEntries922(files, ms) {
    const deadline = Date.now() + (ms || 12000);
    for (;;) {
        for (const f of files) { if (pbuDialogEntry(f)) return f.name; }
        if (Date.now() >= deadline) return null;
        await sleep(700);
    }
}

async function pbuUploadTogether(epubFile, coverFile) {
    const result = { epub: false, cover: false };
    const assignBoth = async (input) => {
        CL('Content: uploading the EPUB and the cover TOGETHER in one dialog (the console\'s input accepts multiple files).');
        await pbuAssignInPageWorld(['epub', 'cover'], [epubFile, coverFile], input);
        await sleep(800);
        await pbuSettleTogether(epubFile, coverFile, result);
    };
    const bothDone = () => result.epub && result.cover;
    for (let cycle = 0; cycle < 2; cycle++) {
        const dlg = await pbuOpenDialogTrusted();
        if (!dlg) {
            CL('Content: the upload dialog could not be opened for the combined upload.', 'error');
            return result;
        }
        pbuLogDiag922(await pbuDiag922(), 'before Browse');
        // Browse FIRST, always: with the isTrusted proxy in place,
        // the console's Browse handler can no longer ignore the
        // programmatic click, and its hidden input's .click() (or
        // dispatchEvent click) is intercepted and served.
        if (await pbuTrustedBrowse([epubFile, coverFile])) {
            await pbuSettleTogether(epubFile, coverFile, result);
            if (bothDone()) {
                await pbuCloseUploadDialog('the combined upload finished');
                break;
            }
        }
        pbuLogDiag922(await pbuDiag922(), 'after Browse');
        // Route 2: serve any created file input directly, even if
        // .click() was never called on it.
        const createdRes = await pbuAssignCreated922();
        CL('Content: [assign-created] ' + (createdRes || 'no answer') + '.');
        if (createdRes && createdRes.indexOf('assigned:') === 0) {
            await pbuSettleTogether(epubFile, coverFile, result);
            if (bothDone()) {
                await pbuCloseUploadDialog('the combined upload finished');
                break;
            }
        }
        // Route 3: spoofed drop + direct captured-callback calls.
        const dropRes = await pbuDirectDrop922();
        CL('Content: [direct-drop] ' + (dropRes || 'no answer') + '.');
        if (dropRes && dropRes.indexOf('dropped') === 0) {
            await pbuPollEntries922([epubFile, coverFile], 12000);
            await pbuSettleTogether(epubFile, coverFile, result);
            if (bothDone()) {
                await pbuCloseUploadDialog('the combined upload finished');
                break;
            }
        }
        // Route 4: call the Angular component method directly.
        const ngRes = await pbuNgInject922();
        CL('Content: [ng-inject] ' + (ngRes || 'no answer') + '.');
        if (ngRes && ngRes.indexOf('ng-inject:') === 0) {
            await pbuPollEntries922([epubFile, coverFile], 12000);
            await pbuSettleTogether(epubFile, coverFile, result);
            if (bothDone()) {
                await pbuCloseUploadDialog('the combined upload finished');
                break;
            }
        }
        // Route 5 (last resort): patient hunter-aware wait + assign.
        const input = await pbuWaitInputPatient('combined upload');
        if (input === 'dialog-gone') {
            CL('Content: the upload dialog closed on its own during the combined attempt — reopening it.', 'error');
            continue;
        }
        if (input) {
            await assignBoth(input);
            await pbuCloseUploadDialog('the combined upload finished');
            break;
        }
        CL('Content: no route placed the files in this dialog. ' + pbuDialogCensus() + '.', 'error');
        await pbuCloseUploadDialog('no route could place the files in this dialog');
        break;
    }
    if (result.epub) pbuDoneUploads.add('epub:' + epubFile.name + ':' + epubFile.size);
    if (result.cover) pbuDoneUploads.add('cover:' + coverFile.name + ':' + coverFile.size);
    return result;
}

const pbu922EnsureBridgeInner = pbuEnsureBridge;
let pbu922ModeLogged = false;
pbuEnsureBridge = async function (files) {
    try { pbu921ModeLogged = true; } catch (e) { /* the v9.21 note is simply superseded */ }
    // Safety net: if the manifest document_start injection did not
    // run for this tab (e.g. the tab predates the extension
    // update), inject the early script now via the background.
    // It is idempotent (armed guard) and never hurts a tab where
    // the hooks are already armed at page load.
    let earlyInfo = null;
    try {
        const er = await pbuMainBridge('ensure-early');
        earlyInfo = (er && er.ok && er.result) || null;
    } catch (e) { /* fall through to the normal stage flow */ }
    const r = await pbu922EnsureBridgeInner(files);
    if (!pbu922ModeLogged) {
        pbu922ModeLogged = true;
        const st = await pbuInterceptState921();
        CL('Content: v9.22 early interception mode — document_start MAIN hooks in all frames (isTrusted proxy listeners, dispatchEvent hook, created-input tracking); Browse-first + assign-created + direct-drop + ng-inject fallbacks; no native file dialog, no CDP channel.');
        CL('Content: [interceptor] early document_start hooks armed: ' + (st ? (st.earlyArmed ? 'YES' : 'NO — Run-time fallback patches are active instead') : (earlyInfo && earlyInfo.ping ? (earlyInfo.ping.earlyArmed ? 'YES' : 'NO — fallback patches active') : 'unknown')) +
            '; staged: ' + (st ? (st.staged || []).join(', ') : 'unknown') +
            '; created inputs: ' + (st ? (st.createdTotal + ' (' + st.createdFile + ' file)') : 'unknown') +
            '; intercept hits so far: ' + (st ? (st.interceptCount || 0) : 'unknown') + '.');
    }
    return r;
};
/* =====================================================================
 * v9.23 content side — wires the self-contained page-world drivers
 * (background listener 6) into the content stage and adds two new
 * routes the v9.22 log proved are needed:
 *   - direct-browse: call the Browse button's CAPTURED click
 *     callbacks directly, instead of dispatching an untrusted
 *     click the console may ignore. Runs right after the normal
 *     Browse press, in the SAME open dialog.
 *   - ng-browse: call an Angular component's own open/trigger
 *     method directly (no event at all) — its input.click() is
 *     then served by the prototype override, which works no
 *     matter when the handler was registered.
 * Also: every driver wrapper now prints the background ERROR
 * instead of a silent "no answer", and the ensure-bridge wrapper
 * prints whether the manifest document_start entry armed the
 * hooks or only the Run-time injection did (armedBefore).
 * No CDP channel; manual pick stays removed.
 * ===================================================================== */

async function pbuBridge923(action, extra) {
    try {
        const r = await pbuMainBridge(action, extra || {});
        return r;
    } catch (e) { return { ok: false, error: String((e && e.message) || e) }; }
}

async function pbuDiag923() {
    const r = await pbuBridge923('diag923');
    if (r && r.ok && r.result) return r.result;
    return { __error: (r && (r.error || 'no response from background')) || 'no response' };
}

function pbuLogDiag923(diag, label) {
    if (!diag || diag.__error) {
        CL('Content: [diag ' + label + '] FAILED: ' + (diag && diag.__error ? diag.__error : 'no report') + ' (background error, not a silent no-answer).', 'error');
        return;
    }
    const createdDetail = (diag.created || []).filter((c) => c.type === 'file')
        .map((c) => (c.name || 'unnamed') + ' accept="' + c.accept + '"' + (c.inDialog ? ' in-dialog' : '') + (c.connected ? '' : ' detached') + ' [' + c.where + ']').join('; ');
    CL('Content: [diag ' + label + '] created inputs: ' + diag.createdTotal + ' (' + diag.createdFile + ' file type)' +
        (createdDetail ? ' — ' + createdDetail : '') + '; dialog open: ' + (diag.dialogOpen ? 'YES' : 'NO') + '; Browse: ' + diag.browse + '.');
    CL('Content: [diag ' + label + '] captured listeners on dialog elements: click=' + diag.captured.click +
        ', drop=' + diag.captured.drop + ', change=' + diag.captured.change + ' (' + diag.captured.elements + ' element(s)).');
    CL('Content: [diag ' + label + '] ng-component methods: ' + (diag.ngMethods && diag.ngMethods.length ? diag.ngMethods.join(', ') : 'none found') +
        ' (scanned ' + diag.ngScanned + ' element(s)).');
    CL('Content: [diag ' + label + '] hunter inputs: ' + (diag.hunter && diag.hunter.length ?
        diag.hunter.map((h) => (h.name || 'unnamed') + ' [' + h.where + ', connected=' + h.connected + ', inDialog=' + h.inDialog + ']').join('; ') : 'none') +
        '; early armed: ' + (diag.earlyArmed ? 'YES' : 'NO') + ' (armed at readyState=' + diag.earlyReadyState + ', perfMs=' + diag.earlyPerfMs + ').');
}

async function pbuDirectDrop923() {
    const r = await pbuBridge923('direct-drop923');
    return (r && r.ok) ? r.result : ('ERROR: ' + ((r && (r.error || r.result)) || 'no response'));
}
async function pbuNgInject923() {
    const r = await pbuBridge923('ng-inject923');
    return (r && r.ok) ? r.result : ('ERROR: ' + ((r && (r.error || r.result)) || 'no response'));
}
async function pbuDirectBrowse923() {
    const r = await pbuBridge923('direct-browse923');
    return (r && r.ok) ? r.result : ('ERROR: ' + ((r && (r.error || r.result)) || 'no response'));
}
async function pbuNgBrowse923() {
    const r = await pbuBridge923('ng-browse923');
    return (r && r.ok) ? r.result : ('ERROR: ' + ((r && (r.error || r.result)) || 'no response'));
}
async function pbuAssignCreated923() {
    const r = await pbuBridge923('assign-created');
    return (r && r.ok) ? r.result : ('ERROR: ' + ((r && (r.error || r.result)) || 'no response'));
}

async function pbuUploadTogether(epubFile, coverFile) {
    const result = { epub: false, cover: false };
    const assignBoth = async (input) => {
        CL('Content: uploading the EPUB and the cover TOGETHER in one dialog (the console\'s input accepts multiple files).');
        await pbuAssignInPageWorld(['epub', 'cover'], [epubFile, coverFile], input);
        await sleep(800);
        await pbuSettleTogether(epubFile, coverFile, result);
    };
    const bothDone = () => result.epub && result.cover;
    for (let cycle = 0; cycle < 2; cycle++) {
        const dlg = await pbuOpenDialogTrusted();
        if (!dlg) {
            CL('Content: the upload dialog could not be opened for the combined upload.', 'error');
            return result;
        }
        pbuLogDiag923(await pbuDiag923(), 'before Browse');
        if (await pbuTrustedBrowse([epubFile, coverFile])) {
            await pbuSettleTogether(epubFile, coverFile, result);
            if (bothDone()) {
                await pbuCloseUploadDialog('the combined upload finished');
                break;
            }
        }
        pbuLogDiag923(await pbuDiag923(), 'after Browse');
        // Route 2a (NEW): direct-call the Browse button's captured
        // click callbacks — no untrusted dispatch involved.
        const browseRes = await pbuDirectBrowse923();
        CL('Content: [direct-browse] ' + browseRes + '.');
        if (browseRes && browseRes.indexOf('direct-browse: called') === 0) {
            await sleep(1500);
            await pbuSettleTogether(epubFile, coverFile, result);
            if (bothDone()) {
                await pbuCloseUploadDialog('the combined upload finished');
                break;
            }
        }
        // Route 2b: serve any created file input directly.
        const createdRes = await pbuAssignCreated923();
        CL('Content: [assign-created] ' + (createdRes || 'no answer') + '.');
        if (createdRes && createdRes.indexOf('assigned:') === 0) {
            await pbuSettleTogether(epubFile, coverFile, result);
            if (bothDone()) {
                await pbuCloseUploadDialog('the combined upload finished');
                break;
            }
        }
        // Route 3: spoofed drop + direct captured-callback calls.
        const dropRes = await pbuDirectDrop923();
        CL('Content: [direct-drop] ' + (dropRes || 'no answer') + '.');
        if (dropRes && dropRes.indexOf('dropped') === 0) {
            await pbuPollEntries922([epubFile, coverFile], 12000);
            await pbuSettleTogether(epubFile, coverFile, result);
            if (bothDone()) {
                await pbuCloseUploadDialog('the combined upload finished');
                break;
            }
        }
        // Route 4: call the Angular component method directly.
        const ngRes = await pbuNgInject923();
        CL('Content: [ng-inject] ' + (ngRes || 'no answer') + '.');
        if (ngRes && ngRes.indexOf('ng-inject:') === 0) {
            await pbuPollEntries922([epubFile, coverFile], 12000);
            await pbuSettleTogether(epubFile, coverFile, result);
            if (bothDone()) {
                await pbuCloseUploadDialog('the combined upload finished');
                break;
            }
        }
        // Route 4b (NEW): call the component's own open/trigger
        // method directly, then let the click override serve it.
        const ngBrowseRes = await pbuNgBrowse923();
        CL('Content: [ng-browse] ' + (ngBrowseRes || 'no answer') + '.');
        if (ngBrowseRes && ngBrowseRes.indexOf('ng-browse: tried') === 0 && /intercept hits \d+ -> [1-9]/.test(ngBrowseRes)) {
            await sleep(1500);
            await pbuSettleTogether(epubFile, coverFile, result);
            if (bothDone()) {
                await pbuCloseUploadDialog('the combined upload finished');
                break;
            }
        }
        // Route 5 (last resort): patient hunter-aware wait + assign.
        const input = await pbuWaitInputPatient('combined upload');
        if (input === 'dialog-gone') {
            CL('Content: the upload dialog closed on its own during the combined attempt — reopening it.', 'error');
            continue;
        }
        if (input) {
            await assignBoth(input);
            await pbuCloseUploadDialog('the combined upload finished');
            break;
        }
        CL('Content: no route placed the files in this dialog. ' + pbuDialogCensus() + '.', 'error');
        await pbuCloseUploadDialog('no route could place the files in this dialog');
        break;
    }
    if (result.epub) pbuDoneUploads.add('epub:' + epubFile.name + ':' + epubFile.size);
    if (result.cover) pbuDoneUploads.add('cover:' + coverFile.name + ':' + coverFile.size);
    return result;
}

async function pbuAssignInPageWorld(keys, fallbackFiles, inputEl) {
    if (inputEl && typeof inputEl.__pbuHunted === 'number') {
        const res = await pbuBridge923('assign-any923', { keys });
        if (res && res.ok && res.result && String(res.result).startsWith('assigned923')) {
            CL('Content: page-world assignment — ' + res.result + '.');
            return true;
        }
        CL('Content: page-world assignment v9.23 (' +
            ((res && (res.result || res.error)) || 'no response') + ') — falling back to the v9.17 assign-any route.', 'error');
        const old = await pbuMainBridge('assign-any', { keys });
        if (old.ok && old.result && String(old.result).startsWith('assigned-anywhere')) {
            CL('Content: page-world assignment — ' + old.result + '.');
            return true;
        }
        CL('Content: page-world assignment to the hunted input unavailable (' +
            ((old && (old.result || old.error)) || 'no response') + ').', 'error');
        return false;
    }
    const res = await pbuMainBridge('assign', { keys });
    if (res.ok && res.result && String(res.result).startsWith('assigned:')) {
        CL('Content: page-world assignment — ' + res.result + '.');
        return true;
    }
    CL('Content: page-world assignment unavailable (' +
        ((res && (res.result || res.error)) || 'no response') +
        ') — assigning from the content script instead.', 'error');
    if (inputEl && fallbackFiles && fallbackFiles.length) {
        assignFilesToInput(inputEl, fallbackFiles);
        await sleep(600);
        CL(`Content: content-script assignment done — the dialog input now holds ${inputEl.files ? inputEl.files.length : 0} file(s).`);
        return true;
    }
    return false;
}

const pbu923EnsureBridgeInner = pbuEnsureBridge;
let pbu923ModeLogged = false;
pbuEnsureBridge = async function (files) {
    let early923 = null;
    try {
        const er = await pbuMainBridge('ensure-early923');
        early923 = (er && er.ok && er.result) || null;
    } catch (e) { /* fall through */ }
    const r = await pbu923EnsureBridgeInner(files);
    if (!pbu923ModeLogged) {
        pbu923ModeLogged = true;
        CL('Content: v9.23 early interception mode — self-contained drivers (diag/direct-drop/ng-inject/direct-browse/ng-browse/assign-any923; no helper references, errors surfaced, not silent).');
        if (early923) {
            CL('Content: [early-arm] manifest document_start armed before Run injection: ' + (early923.armedBefore ? 'YES' : 'NO — the bridge injected it late, AFTER Angular registered its handlers') +
                '; armed after: ' + (early923.armedAfter ? 'YES' : 'NO') +
                '; arm readyState=' + (early923.after ? early923.after.readyState : '?') + ', perfMs=' + (early923.after ? early923.after.perfMs : '?') + '.');
        } else {
            CL('Content: [early-arm] ensure-early923 did not answer — see the v9.22 mode line below for the armed state.', 'error');
        }
    }
    return r;
};
/* =====================================================================
 * v9.24 — pricing-stage 404 recovery (live evidence 2026-10-24
 * ~14:51 +06, book GGKEY:Y1BAWT39J2R).
 * What happened: the v9.23 run's content stage SUCCEEDED (EPUB
 * 264KB step 1 of 6 + cover 295KB, both registered), then the
 * moment the flow reached "Stage: pricing" the Partner Center
 * showed its own "Page not found — Check that the url you
 * entered is correct" page. The files were never the problem;
 * the pricing navigation was.
 * Why the old code could land on a 404: stagePricing built its
 * direct URL from CURRENT location.href (pricingPageUrl uses
 * location.href.split('#')[0]) and, if the wizard's Continue
 * click had already moved the tab off the editor (or onto a
 * route the console does not recognise), that base — or the
 * jc=true/pricing pattern itself for a wizard-stage book — can
 * be a dead route. The old code then waited blindly (Retry /
 * 15s / 12s) on the dead page instead of recovering.
 * v9.24 stagePricing (override, last definition wins):
 *   1. 404 FIRST: if the page already shows "Page not found",
 *       it is named in the log with the exact current URL, and
 *       the stage navigates back to a KNOWN-GOOD editor URL
 *       (the book's Content URL, built from the stored bookUrl
 *       — never from the dead page's location) before doing
 *       anything else.
 *   2. Pricing URLS ARE BUILT FROM THE STORED bookUrl, not
 *       from current location: base = bookUrl.split('#')[0],
 *       section URLs = base + '#book/<GGKEY>/jc=true/<section>'.
 *       The stored bookUrl is the editor URL the earlier stages
 *       actually used, so its base always carries the account
 *       segment the console's router needs.
 *   3. ROUTES IN ORDER, each logged with its exact URL, and a
 *       404 after any navigation immediately moves to the next
 *       route instead of waiting it out:
 *         (a) amount field already on this page -> fill it;
 *         (b) editor section nav "Pricing" (goSection);
 *         (c) direct URL variants: jc=true/pricing,
 *             pricing (no jc=true), jc=true/price;
 *         (d) wizard Continue from the Content page (the
 *             wizard's own next-step navigation).
 *   4. If every route fails, the stage throws an error that
 *       LISTS every URL tried plus the current URL — so the
 *       next panel log is decisive instead of another mystery.
 *       Content/files are untouched by all of this: pricing
 *       never re-uploads anything, and the run can resume on
 *       the SAME book (no new book is created by retrying the
 *       pricing stage alone).
 * No CDP channel; manual pick stays removed.
 * ===================================================================== */

function pbuIs404Page() {
    try {
        const t = (typeof pageText === 'function' ? pageText() : (document.body ? document.body.innerText || '' : ''));
        return /Page not found/i.test(t) && /Check that the url you entered is correct/i.test(t);
    } catch (e) { return false; }
}

function pbuPricingGgkey(payload) {
    if (payload && payload.ggkey) return String(payload.ggkey).replace(/^GGKEY:/i, '');
    try {
        const g = (typeof editorGGKEY === 'function' ? editorGGKEY() : null) || (typeof extractGGKEY === 'function' ? extractGGKEY() : null);
        if (g) return String(g).replace(/^GGKEY:/i, '');
    } catch (e) { /* ignore */ }
    return '';
}

function pbuPricingEditorUrl(payload, section) {
    const gg = pbuPricingGgkey(payload);
    if (!gg) return null;
    let base = null;
    if (payload && payload.bookUrl && String(payload.bookUrl).indexOf('#book/') >= 0) {
        base = String(payload.bookUrl).split('#')[0];
    } else if (location.href.indexOf('#book/') >= 0 && !pbuIs404Page()) {
        base = location.href.split('#')[0];
    } else if (location.href.indexOf('/books/publish/a/') >= 0) {
        base = location.href.split('#')[0];
    }
    if (!base) return null;
    return base + '#book/GGKEY:' + gg + '/jc=true/' + section;
}

async function pbuPricingEnsureAmount() {
    // The pricing page sometimes shows a price list first and only
    // opens the amount editor after "Add price" is clicked.
    let addClicked = false;
    for (let i = 0; i < 20; i++) {
        if (pbuIs404Page()) return false;
        const f = (typeof fieldByLabel === 'function' ? fieldByLabel(['Amount', 'Price']) : null) ||
            (typeof pricingNumberInput === 'function' ? pricingNumberInput() : null);
        if (f) return true;
        if (!addClicked && i >= 4) {
            addClicked = true;
            try { await clickByText(['Add price', 'Add a price', 'Set price', 'Add territory pricing', 'Edit'], 8000); } catch (e) { /* ignore */ }
            await sleep(1000);
        }
        await sleep(500);
    }
    return false;
}

async function pbuPricingFill(meta) {
    const amount = (typeof fieldByLabel === 'function' ? fieldByLabel(['Amount', 'Price']) : null) ||
        (typeof pricingNumberInput === 'function' ? pricingNumberInput() : null);
    if (!amount) return false;
    await typeInto(amount, String(meta.price));
    const cur = (typeof fieldByLabel === 'function' ? fieldByLabel(['Currency']) : null);
    if (cur) {
        const r = await operateSelect(cur, meta.currency || 'USD', 8000);
        if (!r.ok) throw new Error(`Pricing: the currency could not be verified as ${meta.currency || 'USD'} (the control shows "${r.value || '—'}").`);
    }
    if (!(await chooseInGroup(['Territor', 'Countries', 'Sales territories'], ['Worldwide', 'World', 'All countries'], 8000)).ok) {
        await clickByText(['Worldwide', 'World', 'Select all'], 4000) && L('Pricing: territories set via a "Worldwide" click (no read-back available) — verify on Review.', 'error');
    }
    const saved = await saveAndWait({ verify: () => {
        const f = (typeof fieldByLabel === 'function' ? fieldByLabel(['Amount', 'Price']) : null);
        return f ? norm(f.value).includes(String(meta.price)) : pageText().includes(String(meta.price));
    } });
    if (!saved.saved) throw new Error('Pricing save failed' + (saved.error ? ': ' + saved.error : '.'));
    if (!pageText().includes(String(meta.price))) throw new Error(`Pricing: saved, but "${meta.price}" is not visible on the Pricing tab afterwards.`);
    return true;
}

async function stagePricing(meta, payload) {
    const blocker = detectBlocker();
    if (blocker) throw stopErr(blocker);
    const tried = [];
    const navTo = async (url, why) => {
        if (!url) return false;
        tried.push(url);
        CL('Content: Pricing: navigating (' + why + ') to ' + url + '.');
        if (location.href !== url) location.href = url;
        await sleep(3000);
        await dismissInfoDialogs();
        if (pbuIs404Page()) {
            CL('Content: Pricing: that URL returned "Page not found" — trying the next route.', 'error');
            return false;
        }
        return true;
    };
    const amountHere = () => {
        if (pbuIs404Page()) return null;
        return (typeof fieldByLabel === 'function' ? fieldByLabel(['Amount', 'Price']) : null) ||
            (typeof pricingNumberInput === 'function' ? pricingNumberInput() : null);
    };
    // Route 0: already on a 404 page — recover to the known-good
    // Content editor URL first, so every later step starts from
    // a real editor page instead of the dead route.
    if (pbuIs404Page()) {
        CL('Content: Pricing: started on a "Page not found" page (' + location.href + ') — recovering to the book editor first.', 'error');
        const contentUrl = pbuPricingEditorUrl(payload, 'content');
        if (contentUrl) await navTo(contentUrl, '404 recovery to Content');
    }
    // Route (a): amount field already here (or behind "Add price").
    if (await pbuPricingEnsureAmount()) {
        if (await pbuPricingFill(meta)) {
            CL(`Pricing saved: ${meta.currency} ${meta.price} (Worldwide).`);
            return { bookUrl: location.href };
        }
    }
    // Route (b): the editor's own Pricing section nav.
    if (await goSection(['Pricing', 'Price'], 8000)) {
        await sleep(800);
        if (!pbuIs404Page() && await pbuPricingEnsureAmount()) {
            if (await pbuPricingFill(meta)) {
                CL(`Pricing saved: ${meta.currency} ${meta.price} (Worldwide).`);
                return { bookUrl: location.href };
            }
        }
    }
    // Route (c): direct URL variants, built from the STORED
    // bookUrl (never from a dead page's location).
    const gg = pbuPricingGgkey(payload);
    let urlBase = null;
    if (payload && payload.bookUrl && String(payload.bookUrl).indexOf('#book/') >= 0) {
        urlBase = String(payload.bookUrl).split('#')[0] + '#book/GGKEY:' + gg + '/';
    } else {
        const ed = pbuPricingEditorUrl(payload, 'pricing');
        if (ed) urlBase = ed.replace(/\/jc=true\/pricing$/, '/');
    }
    const variantSuffix = ['jc=true/pricing', 'pricing', 'jc=true/price'];
    for (let vi = 0; vi < variantSuffix.length; vi++) {
        if (!urlBase || !gg) continue;
        const url = urlBase + variantSuffix[vi];
        if (!url) continue;
        const ok = await navTo(url, 'direct URL variant ' + (vi + 1) + '/' + variantSuffix.length);
        if (!ok) continue;
        if (await pbuPricingEnsureAmount() && await pbuPricingFill(meta)) {
            CL(`Pricing saved: ${meta.currency} ${meta.price} (Worldwide).`);
            return { bookUrl: location.href };
        }
        // A pricing page that renders an error screen offers Retry.
        const retry = [...document.querySelectorAll('a, button, [role="button"]')].filter(isVisible)
            .find((b) => exactTextEq(b.innerText || b.textContent, 'Retry'));
        if (retry) {
            CL('Content: Pricing: the pricing page showed an error screen — clicking "Retry".');
            clickEl(retry);
            await sleep(2800);
            if (!pbuIs404Page() && await pbuPricingEnsureAmount() && await pbuPricingFill(meta)) {
                CL(`Pricing saved: ${meta.currency} ${meta.price} (Worldwide).`);
                return { bookUrl: location.href };
            }
        }
    }
    // Route (d): wizard Continue from the Content page.
    const contentUrl2 = pbuPricingEditorUrl(payload, 'content');
    if (contentUrl2) {
        await navTo(contentUrl2, 'wizard Continue from Content');
        if (!pbuIs404Page()) {
            const cont = [...document.querySelectorAll('button, [role="button"]')].filter(isVisible)
                .find((b) => exactTextEq(b.innerText || b.textContent, 'Continue'));
            if (cont) {
                clickEl(cont);
                await sleep(2500);
                await dismissInfoDialogs();
                if (!pbuIs404Page() && await pbuPricingEnsureAmount() && await pbuPricingFill(meta)) {
                    CL(`Pricing saved: ${meta.currency} ${meta.price} (Worldwide).`);
                    return { bookUrl: location.href };
                }
            }
        }
    }
    throw new Error('Pricing: the Pricing section could not be opened — every route landed on "Page not found" or showed no amount field. URLs tried: ' +
        (tried.length ? tried.join(' | ') : 'none (no bookUrl/ggkey available)') +
        '. Current URL: ' + location.href +
        '. The EPUB + cover on this book are safe and untouched — pricing can be retried on this same book.');
}

/* v9.24 mode line (logged once, at the first ensure-bridge call). */
const pbu924EnsureBridgeInner = pbuEnsureBridge;
let pbu924ModeLogged = false;
pbuEnsureBridge = async function (files) {
    const r = await pbu924EnsureBridgeInner(files);
    if (!pbu924ModeLogged) {
        pbu924ModeLogged = true;
        CL('Content: v9.24 early interception mode — pricing 404 recovery (bookUrl-based URLs, direct-URL variants, wizard Continue fallback).');
    }
    return r;
};
/* =====================================================================
 * v9.25 — pricing WITHOUT hash navigation (live evidence 2026-10-24
 * 15:15 +06, book GGKEY:S7ZXNEPY7C8, v9.24 run).
 * The v9.24 log is decisive and changes the diagnosis: EVERY
 * hash URL it tried returned "Page not found" — including the
 * Content URL itself (jc=true/content) — and the tab ended on
 * #pageNotFound. So for a book still inside the Add-a-book
 * wizard, the editor hash routes are simply dead; it is not a
 * pricing-only problem and no other hash variant will fix it.
 * (By contrast, the earlier D0QK book, opened from the catalog
 * in edit mode, accepted a direct pricing URL — edit mode and
 * wizard mode do not share the same routes.)
 * v9.25 stagePricing (override, last definition wins) therefore
 * NEVER assigns location.href to a hash URL. It only moves by
 * clicks and browser history, in this order:
 *   1. 404 RECOVERY BY HISTORY: if the page is already a 404,
 *       go back with history.back() to the last real editor
 *       page (the wizard page the run was on before the dead
 *       navigation), instead of building another hash URL.
 *   2. EDITOR SECTION NAV: goSection "Pricing" on the editor
 *       page; if the amount field appears, fill it.
 *   3. WIZARD CONTINUE: click the wizard's Continue button on
 *       the current section and see where the wizard itself
 *       goes; if it lands on a 404, history.back() at once.
 *   4. CATALOG-OPEN ROUTE: click "Book catalog" in the global
 *       nav, find the row for this book (by GGKEY digits or by
 *       title), click it to open the book in EDIT mode (the
 *       mode whose routes are known to work), then goSection
 *       "Pricing" and fill.
 *   5. If every click route fails, throw an error listing the
 *       click routes tried and the current URL, and stating
 *       plainly that hash URLs are dead for this book — so the
 *       user can price this same book by hand from the catalog
 *       instead of running again (a new Run would only create
 *       another duplicate).
 * Pricing fill itself is unchanged (pbuPricingFill +
 * pbuPricingEnsureAmount from v9.24, including the "Add price"
 * editor opening). Pricing never re-uploads anything.
 * No CDP channel; manual pick stays removed.
 * ===================================================================== */

async function pbuPricingBackFrom404() {
    if (!pbuIs404Page()) return true;
    try { history.back(); } catch (e) { /* ignore */ }
    await sleep(2500);
    await dismissInfoDialogs();
    if (pbuIs404Page()) {
        try { history.back(); } catch (e) { /* ignore */ }
        await sleep(2500);
        await dismissInfoDialogs();
    }
    return !pbuIs404Page();
}

async function stagePricing(meta, payload) {
    const blocker = detectBlocker();
    if (blocker) throw stopErr(blocker);
    const tried = [];
    const ggDigits = pbuPricingGgkey(payload);
    // Route 1: recover from a 404 page by history, never by hash.
    if (pbuIs404Page()) {
        CL('Content: Pricing: started on a "Page not found" page — going back in history to the last editor page (no hash navigation).', 'error');
        tried.push('history.back() from 404');
        if (!(await pbuPricingBackFrom404())) {
            CL('Content: Pricing: history.back() did not leave the 404 page — trying the catalog route.', 'error');
        }
    }
    // Route 2: the editor's own Pricing section nav.
    if (!pbuIs404Page() && await goSection(['Pricing', 'Price'], 8000)) {
        tried.push('editor section nav Pricing');
        await sleep(800);
        if (!pbuIs404Page() && await pbuPricingEnsureAmount() && await pbuPricingFill(meta)) {
            CL(`Pricing saved: ${meta.currency} ${meta.price} (Worldwide).`);
            return { bookUrl: location.href };
        }
    }
    // Route 3: wizard Continue from the current section.
    if (!pbuIs404Page()) {
        const cont = [...document.querySelectorAll('button, [role="button"]')].filter(isVisible)
            .find((b) => exactTextEq(b.innerText || b.textContent, 'Continue'));
        if (cont) {
            tried.push('wizard Continue');
            clickEl(cont);
            await sleep(2500);
            await dismissInfoDialogs();
            if (pbuIs404Page()) {
                CL('Content: Pricing: wizard Continue landed on "Page not found" — going back at once.', 'error');
                await pbuPricingBackFrom404();
            } else if (await pbuPricingEnsureAmount() && await pbuPricingFill(meta)) {
                CL(`Pricing saved: ${meta.currency} ${meta.price} (Worldwide).`);
                return { bookUrl: location.href };
            }
        }
    }
    // Route 4: open the book from the Book catalog (edit mode).
    if (await clickByText(['Book catalog', 'Book Catalog', 'Catalog'], 8000)) {
        tried.push('Book catalog open');
        await sleep(2500);
        await dismissInfoDialogs();
        if (!pbuIs404Page()) {
            const rows = [...document.querySelectorAll('tr, [role="row"], li, a, [class*="row"]')].filter(isVisible);
            let target = null;
            if (ggDigits) target = rows.find((r) => norm(r.innerText || r.textContent).includes(ggDigits));
            if (!target && meta.title) target = rows.find((r) => norm(r.innerText || r.textContent).includes(meta.title));
            if (target) {
                const link = target.tagName === 'A' ? target : target.querySelector('a');
                if (link) clickEl(link); else clickEl(target);
                await sleep(3000);
                await dismissInfoDialogs();
                if (!pbuIs404Page() && await goSection(['Pricing', 'Price'], 8000)) {
                    await sleep(800);
                    if (!pbuIs404Page() && await pbuPricingEnsureAmount() && await pbuPricingFill(meta)) {
                        CL(`Pricing saved: ${meta.currency} ${meta.price} (Worldwide).`);
                        return { bookUrl: location.href };
                    }
                }
            } else {
                CL('Content: Pricing: the book row was not found in the catalog list (GGKEY digits/title not visible).', 'error');
            }
        }
    }
    throw new Error('Pricing: the Pricing section could not be opened by clicks. Routes tried: ' + tried.join(' | ') +
        '. Current URL: ' + location.href +
        '. NOTE: hash URLs are dead for this wizard book (v9.24 proved even the Content hash 404s), so this version deliberately did not try any. ' +
        'The EPUB + cover on this book are safe and untouched — open this same book from Book catalog by hand and set the price there instead of running again.');
}

/* v9.25 mode line (logged once, at the first ensure-bridge call). */
const pbu925EnsureBridgeInner = pbuEnsureBridge;
let pbu925ModeLogged = false;
pbuEnsureBridge = async function (files) {
    const r = await pbu925EnsureBridgeInner(files);
    if (!pbu925ModeLogged) {
        pbu925ModeLogged = true;
        CL('Content: v9.25 early interception mode — pricing WITHOUT hash navigation (history-back recovery, wizard nav, catalog-open route).');
    }
    return r;
};
/* =====================================================================
 * v9.26 — pricing field detection fix (live evidence 2026-10-24
 * 15:23-15:26 +06, book GGKEY:ZN3BNPG652N, v9.25 run).
 * What the user saw: on the open Pricing page the extension
 * kept clicking "Add price" over and over without ever setting
 * a price. The screenshot proves why: the page shows THREE
 * empty price rows (USD | $ Purchase price | WORLD), each one
 * created by an "Add price" click, and none of them ever filled.
 * Root cause: the old amount finder only recognised a field
 * with a <label>/mat-label reading "Amount" or "Price", or an
 * input[type=number]/inputmode=decimal. The real Pricing page
 * has neither: its purchase price inputs carry only the
 * placeholder "$ Purchase price" and sit in a row with a USD
 * currency dropdown and a WORLD territory dropdown. So
 * pbuPricingEnsureAmount concluded "no field", clicked "Add
 * price", still could not find the new row's input, failed the
 * stage — and the stage retry clicked "Add price" again. A
 * vicious cycle that pollutes the page with empty rows.
 * v9.26 (overrides, last definitions win):
 *   - pbuPurchasePriceInput(): finds the purchase price input
 *     by (a) placeholder/aria-label matching "purchase price",
 *     (b) row membership: an input whose ancestor row contains
 *     a USD currency control and a WORLD territory control.
 *     Prefers an EMPTY input (an unfilled row); otherwise the
 *     first row's input. Never returns a filled row when an
 *     empty one exists.
 *   - pbuPricingEnsureAmount(): if a purchase price input
 *     ALREADY exists, it is returned at once — "Add price" is
 *     NEVER clicked when rows exist. "Add price" is clicked
 *     exactly ONCE, and only when the page has no price row at
 *     all, after which the new row's input is waited for and
 *     returned. A stage retry therefore cannot add another row.
 *   - pbuPricingFill(): fills the found purchase price input
 *     (not fieldByLabel "Amount"); currency is taken from the
 *     same row's dropdown when present, and an already-USD row
 *     is accepted without error; territories already showing
 *     WORLD are accepted the same way. Save + read-back verify
 *     use the same input's value.
 * Side finding from the same screenshot (for the record, not
 * used by this version): the wizard Pricing page's own URL
 * uses a SEMICOLON — #book/GGKEY:...;jc=true/pricing — while
 * v9.24's hash attempts used a slash (/jc=true/pricing). That
 * format difference is a strong candidate for the earlier
 * hash 404s; v9.25/v9.26 need no hash at all, so it is noted
 * here rather than acted on.
 * No CDP channel; manual pick stays removed.
 * ===================================================================== */

function pbuPurchasePriceInput() {
    try {
        const all = [...document.querySelectorAll('input')].filter((el) => {
            try { return isVisible(el); } catch (e) { return true; }
        });
        const byPlaceholder = all.filter((el) =>
            /purchase price/i.test(el.placeholder || '') ||
            /purchase price/i.test(el.getAttribute && el.getAttribute('aria-label') || ''));
        if (byPlaceholder.length) {
            return byPlaceholder.find((el) => !String(el.value || '').trim()) || byPlaceholder[0];
        }
        const rowOf = (el) => {
            let n = el;
            for (let i = 0; i < 6 && n; i++) {
                n = n.parentElement;
                if (!n) break;
                const t = norm(n.innerText || n.textContent);
                if (/WORLD/i.test(t)) return n;
            }
            return null;
        };
        const rowCandidates = [];
        for (const el of all) {
            const row = rowOf(el);
            if (!row) continue;
            const rowText = norm(row.innerText || row.textContent);
            const hasUsd = /USD/i.test(rowText) && !!row.querySelector('select, mat-select, [role="combobox"], [role="listbox"]');
            if (hasUsd) rowCandidates.push(el);
        }
        if (rowCandidates.length) {
            return rowCandidates.find((el) => !String(el.value || '').trim()) || rowCandidates[0];
        }
        return null;
    } catch (e) { return null; }
}

async function pbuPricingEnsureAmount() {
    // Rows already exist -> return the input at once. NEVER click
    // "Add price" when a row exists: that was the v9.25 loop.
    const existing = pbuPurchasePriceInput();
    if (existing) return existing;
    // No price row at all -> click "Add price" exactly once, then
    // wait for the new row's input to appear.
    let clicked = false;
    try { clicked = !!(await clickByText(['Add price', 'Add a price'], 8000)); } catch (e) { clicked = false; }
    if (!clicked) return null;
    await sleep(1200);
    for (let i = 0; i < 20; i++) {
        const f = pbuPurchasePriceInput();
        if (f) return f;
        await sleep(500);
    }
    return null;
}

async function pbuPricingFill(meta) {
    const amount = pbuPurchasePriceInput() ||
        (typeof fieldByLabel === 'function' ? fieldByLabel(['Amount', 'Price']) : null) ||
        (typeof pricingNumberInput === 'function' ? pricingNumberInput() : null);
    if (!amount) return false;
    await typeInto(amount, String(meta.price));
    // Currency: prefer the same row's dropdown; an already-USD row
    // is accepted without forcing a select interaction.
    let cur = (typeof fieldByLabel === 'function' ? fieldByLabel(['Currency']) : null);
    if (!cur) {
        let n = amount;
        for (let i = 0; i < 6 && n && !cur; i++) {
            n = n.parentElement;
            if (!n) break;
            cur = n.querySelector('select, mat-select, [role="combobox"]') || null;
        }
    }
    if (cur) {
        const r = await operateSelect(cur, meta.currency || 'USD', 8000);
        if (!r.ok) {
            let rowText = '';
            let n = amount;
            for (let i = 0; i < 6 && n; i++) { n = n.parentElement; if (n) rowText = norm(n.innerText || n.textContent); }
            if (!/USD/i.test(rowText)) throw new Error(`Pricing: the currency could not be verified as ${meta.currency || 'USD'} (the control shows "${r.value || '—'}").`);
        }
    }
    if (!(await chooseInGroup(['Territor', 'Countries', 'Sales territories'], ['Worldwide', 'World', 'All countries'], 8000)).ok) {
        if (!/WORLD/i.test(pageText())) {
            await clickByText(['Worldwide', 'World', 'Select all'], 4000) && L('Pricing: territories set via a "Worldwide" click (no read-back available) — verify on Review.', 'error');
        }
    }
    const saved = await saveAndWait({ verify: () => {
        const v = String(amount.value || '').trim();
        return v ? v.includes(String(meta.price)) : pageText().includes(String(meta.price));
    } });
    if (!saved.saved) throw new Error('Pricing save failed' + (saved.error ? ': ' + saved.error : '.'));
    if (!pageText().includes(String(meta.price)) && !String(amount.value || '').includes(String(meta.price))) {
        throw new Error(`Pricing: saved, but "${meta.price}" is not visible on the Pricing tab afterwards.`);
    }
    return true;
}

/* v9.26 mode line (logged once, at the first ensure-bridge call). */
const pbu926EnsureBridgeInner = pbuEnsureBridge;
let pbu926ModeLogged = false;
pbuEnsureBridge = async function (files) {
    const r = await pbu926EnsureBridgeInner(files);
    if (!pbu926ModeLogged) {
        pbu926ModeLogged = true;
        CL('Content: v9.26 early interception mode — pricing fills the existing Purchase price row; Add price only when no row exists.');
    }
    return r;
};
