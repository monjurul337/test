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
    el.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: dt }));
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
      el.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: dt }));
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
