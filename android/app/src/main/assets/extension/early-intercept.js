/* ================= v9.22 early Main-world interception =================
 * Installed by the manifest itself at document_start in the MAIN
 * world, all_frames: true — BEFORE Google's Angular/Closure code
 * loads, in the top frame AND in every iframe. Live evidence from
 * the v9.21 run: after a programmatic Browse click the
 * input-click interceptor recorded ZERO hits, and a dispatched
 * DragEvent on the dropzone registered nothing. The console is
 * therefore ignoring untrusted (programmatic) events — it checks
 * event.isTrusted, or it never receives the event through the
 * path we simulated. v9.22 attacks all five trigger routes at
 * once, all from this document_start script:
 *
 *  1. EventTarget.prototype.addEventListener is wrapped: every
 *     'click' / 'mousedown' / 'pointerdown' / 'drop' / 'dragover'
 *     / 'dragenter' / 'change' listener the page registers is
 *     replaced by a wrapper that (a) is saved on the element as
 *     el.__capturedListeners[type] (records of {orig, wrapped}),
 *     (b) counts its invocations on the element
 *     (el.__pbuCalls[type]), and (c) delivers a Proxy of the
 *     event whose isTrusted ALWAYS reads true — so page code
 *     treats programmatic clicks/drops as 100% human input.
 *     removeEventListener is mapped back to the wrapper, and
 *     duplicate adds (same listener + capture) are deduped exactly
 *     like the native method, so no listener ever fires twice
 *     because of the wrap.
 *  2. (Drivers live in background.js, serialised into the page
 *     world: pbuMainDirectDrop builds a fully spoofed
 *     dataTransfer — real FileList files, array-like items with
 *     getAsFile(), types ['Files'], getData/setData,
 *     dropEffect 'copy', effectAllowed 'all' — dispatches
 *     dragenter/dragover/drop on the dialog elements, and then
 *     directly invokes only the captured drop callbacks that the
 *     dispatch did NOT already invoke (invocation counts prove
 *     it), so a working dispatch is never double-fired.)
 *  3. Every file-input trigger route is hooked: .click(),
 *     .showPicker(), window.showOpenFilePicker(), AND
 *     EventTarget.prototype.dispatchEvent('click') on a file
 *     input (a dispatched click is served the same way — it can
 *     never open the native picker while files are staged).
 *     Document.prototype.createElement AND createElementNS push
 *     EVERY created <input> into window.__allCreatedInputs
 *     (DOM or detached), a type-property trap + a setAttribute
 *     hook + a 2s sweep register it the moment its type becomes
 *     'file'. (The assign-created driver in background.js then
 *     serves any such input directly, even if .click() was never
 *     called on it.)
 *  4. (Driver in background.js: pbuMainNgInject scans the dialog's
 *     ng-component / dropzone for __ngContext__ and method names
 *     like onFileSelected / onDrop / handleFiles / uploadFiles and
 *     calls the best match with the staged FileList.)
 *  5. (Driver in background.js: pbuMainDiag reports (a) how many
 *     inputs __allCreatedInputs holds, (b) how many click/drop
 *     listeners were captured on dialog elements, (c) which
 *     Angular methods/properties were found — the content script
 *     prints all three in the panel log.)
 *
 * Behaviour when NO files are staged (the normal state before a
 * Run): every hook falls through to the original behaviour
 * untouched — manual use of the Partner Center is never broken.
 * When files ARE staged, the native picker is NEVER opened and
 * the staged EPUB + cover are served via DataTransfer + input/
 * change {bubbles: true, composed: true}. The extension's OWN
 * panel inputs (host #pbu-panel-host) are never intercepted; the
 * panel lives in the isolated world, whose prototypes this MAIN
 * world script does not touch. No CDP channel is involved. */
(function () {
    if (window.__pbuEarlyInterceptArmed) return;
    window.__pbuEarlyInterceptArmed = true;
    // v9.23: record WHEN this script armed, so the panel log can
    // prove whether the manifest document_start entry armed it
    // (readyState 'loading', small perfMs) or only the Run-time
    // bridge injection did (readyState 'complete', large perfMs).
    try { window.__pbuEarlyReadyState = document.readyState || ''; } catch (e) { window.__pbuEarlyReadyState = ''; }
    try { window.__pbuEarlyPerfMs = Math.round((window.performance && window.performance.now()) || 0); } catch (e) { window.__pbuEarlyPerfMs = 0; }
    window.__pbuServed = window.__pbuServed || {};
    window.__pbuInterceptHits = window.__pbuInterceptHits || [];
    window.__pbuInputReg = window.__pbuInputReg || [];
    window.__allCreatedInputs = window.__allCreatedInputs || [];

    function inPanel(el) {
        try {
            var root = el.getRootNode && el.getRootNode();
            if (root && root.host && root.host.id === 'pbu-panel-host') return true;
            if (el.closest && el.closest('#pbu-panel-host')) return true;
        } catch (e) { /* ignore */ }
        return false;
    }
    function acceptMatch(file, acc) {
        if (!acc) return true;
        var ext = '.' + String((file.name.split('.').pop() || '')).toLowerCase();
        if (acc.indexOf(ext) >= 0) return true;
        if (/image/.test(acc) && /^image\//.test(file.type)) return true;
        if (/epub/.test(acc) && /epub/i.test(file.type + ' ' + file.name)) return true;
        if (/pdf/.test(acc) && /pdf/i.test(file.type + ' ' + file.name)) return true;
        return false;
    }
    function serveKeys(acceptStr) {
        var staged = window.__pbuStaged || {};
        var keys = Object.keys(staged);
        if (!keys.length) return [];
        var acc = String(acceptStr || '').toLowerCase();
        var cands = keys.filter(function (k) { return acceptMatch(staged[k], acc); });
        if (!cands.length) cands = keys;
        var fresh = cands.filter(function (k) { return !window.__pbuServed[k]; });
        return fresh.length ? fresh : cands;
    }
    function recordHit(via, keys, extra) {
        var staged = window.__pbuStaged || {};
        var hit = {
            at: Date.now(), via: via, keys: keys.slice(),
            names: keys.map(function (k) { return staged[k] && staged[k].name; })
        };
        if (extra) { for (var p in extra) hit[p] = extra[p]; }
        window.__pbuInterceptHits.push(hit);
    }
    function alreadyHolds(input, keys) {
        try {
            if (!input.files || !input.files.length) return false;
            var have = {};
            for (var i = 0; i < input.files.length; i++) have[input.files[i].name] = true;
            var staged = window.__pbuStaged || {};
            return keys.every(function (k) { return staged[k] && have[staged[k].name]; });
        } catch (e) { return false; }
    }
    function serveInto(input, keys) {
        var staged = window.__pbuStaged || {};
        var dt = new DataTransfer();
        for (var i = 0; i < keys.length; i++) { dt.items.add(staged[keys[i]]); window.__pbuServed[keys[i]] = true; }
        input.files = dt.files;
        input.__pbuServed = true;
        input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
        input.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
        return keys.length;
    }
    // True when handled here (served, or already holds the files) —
    // the caller must NOT run the original. False = run original.
    function tryServe(input, via) {
        try {
            if (!input || input.type !== 'file' || inPanel(input)) return false;
            var staged = window.__pbuStaged || {};
            if (!Object.keys(staged).length) return false;
            var keys = serveKeys(input.getAttribute && input.getAttribute('accept'));
            if (!input.multiple) keys = keys.slice(0, 1);
            if (!keys.length) return false;
            if (alreadyHolds(input, keys)) { recordHit(via, keys, { alreadyHeld: true }); return true; }
            serveInto(input, keys);
            recordHit(via, keys, { detached: !input.isConnected });
            return true;
        } catch (e) { return false; }
    }

    /* ---- (1) isTrusted proxy + captured listeners ---- */
    var proxiedEvents = (typeof WeakSet !== 'undefined') ? new WeakSet() : null;
    function proxyEvent(ev) {
        try {
            if (!ev || typeof ev !== 'object') return ev;
            if (proxiedEvents && proxiedEvents.has(ev)) return ev;
            var proxy = new Proxy(ev, {
                get: function (target, prop) {
                    if (prop === 'isTrusted') return true;
                    var v = Reflect.get(target, prop, target);
                    if (typeof v === 'function') return v.bind(target);
                    return v;
                },
                set: function (target, prop, value) { return Reflect.set(target, prop, value); },
                has: function (target, prop) { return Reflect.has(target, prop); },
                getOwnPropertyDescriptor: function (target, prop) { return Reflect.getOwnPropertyDescriptor(target, prop); },
                ownKeys: function (target) { return Reflect.ownKeys(target); }
            });
            if (proxiedEvents) proxiedEvents.add(proxy);
            return proxy;
        } catch (e) { return ev; }
    }
    var WATCHED = ['click', 'mousedown', 'pointerdown', 'drop', 'dragover', 'dragenter', 'change'];
    function isWatched(type) { return WATCHED.indexOf(type) >= 0; }
    function captureOf(options) {
        return (typeof options === 'boolean') ? options : !!(options && options.capture);
    }
    var etProto = window.EventTarget && window.EventTarget.prototype;
    if (etProto && !etProto.__pbuListenerWrapped922) {
        var origAdd = etProto.addEventListener;
        var origRemove = etProto.removeEventListener;
        etProto.addEventListener = function (type, listener, options) {
            try {
                if (isWatched(type) && listener) {
                    var cap = captureOf(options);
                    var records = this.__pbuListenerRecords = this.__pbuListenerRecords || [];
                    for (var i = 0; i < records.length; i++) {
                        if (records[i].type === type && records[i].orig === listener && records[i].capture === cap) return; // native dedup
                    }
                    var el = this;
                    var record = { type: type, orig: listener, capture: cap, calls: 0, lastInvokedAt: 0 };
                    var wrapped = function (ev) {
                        try {
                            el.__pbuCalls = el.__pbuCalls || {};
                            el.__pbuCalls[type] = (el.__pbuCalls[type] || 0) + 1;
                            record.calls++;
                            record.lastInvokedAt = Date.now();
                        } catch (e) { /* never break delivery */ }
                        var prox = proxyEvent(ev);
                        if (listener && typeof listener.handleEvent === 'function') return listener.handleEvent.call(listener, prox);
                        return listener.call(el, prox);
                    };
                    record.wrapped = wrapped;
                    records.push(record);
                    var capList = this.__capturedListeners = this.__capturedListeners || {};
                    (capList[type] = capList[type] || []).push(record);
                    return origAdd.call(this, type, wrapped, options);
                }
            } catch (e) { /* fall through to the native call */ }
            return origAdd.apply(this, arguments);
        };
        etProto.removeEventListener = function (type, listener, options) {
            try {
                if (isWatched(type) && listener) {
                    var cap = captureOf(options);
                    var records = this.__pbuListenerRecords || [];
                    for (var i = records.length - 1; i >= 0; i--) {
                        if (records[i].type === type && records[i].orig === listener && records[i].capture === cap) {
                            var rec = records[i];
                            records.splice(i, 1);
                            var capList = this.__capturedListeners || {};
                            var list = capList[type] || [];
                            for (var j = list.length - 1; j >= 0; j--) { if (list[j] === rec) list.splice(j, 1); }
                            return origRemove.call(this, type, rec.wrapped, options);
                        }
                    }
                }
            } catch (e) { /* fall through */ }
            return origRemove.apply(this, arguments);
        };
        etProto.__pbuListenerWrapped922 = true;
    }

    /* ---- (3a) dispatchEvent hook: dispatched clicks on file inputs ---- */
    if (etProto && !etProto.__pbuDispatchHooked922) {
        var origDispatch = etProto.dispatchEvent;
        etProto.dispatchEvent = function (ev) {
            try {
                if (ev && ev.type === 'click' && this && this.tagName === 'INPUT' && this.type === 'file') {
                    if (tryServe(this, 'dispatch-click')) return true;
                }
            } catch (e) { /* fall through to native dispatch */ }
            return origDispatch.call(this, ev);
        };
        etProto.__pbuDispatchHooked922 = true;
    }

    /* ---- (3b) created-input tracking: createElement + createElementNS ---- */
    var createdSeen = (typeof WeakSet !== 'undefined') ? new WeakSet() : null;
    function registerFileInput(el, where) {
        try {
            if (!el || el.__pbuRegged || inPanel(el)) return;
            el.__pbuRegged = true;
            (window.__pbuInputReg = window.__pbuInputReg || []).push({ el: el, where: where, at: Date.now() });
        } catch (e) { /* ignore */ }
    }
    function trackCreated(el, where) {
        try {
            if (!el || (createdSeen && createdSeen.has(el))) return;
            if (createdSeen) createdSeen.add(el);
            window.__allCreatedInputs.push({ el: el, at: Date.now(), where: where });
            (window.__pbuCreatedInputs = window.__pbuCreatedInputs || []).push(el);
            var typeDesc = null;
            try { typeDesc = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'type'); } catch (e) { /* ignore */ }
            if (typeDesc && typeDesc.set && !el.__pbuTypeTrapped) {
                el.__pbuTypeTrapped = true;
                Object.defineProperty(el, 'type', {
                    configurable: true, enumerable: true,
                    get: function () { return typeDesc.get.call(this); },
                    set: function (v) {
                        typeDesc.set.call(this, v);
                        if (String(v).toLowerCase() === 'file') registerFileInput(this, 'created-input');
                    }
                });
            }
            if (el.type === 'file') registerFileInput(el, 'created-input');
        } catch (e) { /* never break creation */ }
    }
    var docProto = window.Document && window.Document.prototype;
    if (docProto && !docProto.__pbuEarlyCreatePatched922) {
        var origCreate = docProto.createElement;
        docProto.createElement = function (tag) {
            var el = origCreate.apply(this, arguments);
            try { if (el && String(tag).toLowerCase() === 'input') trackCreated(el, 'createElement'); } catch (e) { /* ignore */ }
            return el;
        };
        var origCreateNS = docProto.createElementNS;
        if (origCreateNS) {
            docProto.createElementNS = function (ns, name) {
                var el = origCreateNS.apply(this, arguments);
                try { if (el && String(name).toLowerCase() === 'input') trackCreated(el, 'createElementNS'); } catch (e) { /* ignore */ }
                return el;
            };
        }
        docProto.__pbuEarlyCreatePatched922 = true;
    }
    // setAttribute hook: type set via attribute, not property.
    var elProto = window.Element && window.Element.prototype;
    if (elProto && !elProto.__pbuSetAttrHooked922) {
        var origSetAttr = elProto.setAttribute;
        elProto.setAttribute = function (name, value) {
            var r = origSetAttr.apply(this, arguments);
            try {
                if (this && this.tagName === 'INPUT' && String(name).toLowerCase() === 'type' && String(value).toLowerCase() === 'file') {
                    registerFileInput(this, 'setAttribute-type');
                }
            } catch (e) { /* ignore */ }
            return r;
        };
        elProto.__pbuSetAttrHooked922 = true;
    }
    // Sweep: inputs whose type became 'file' by any other route.
    if (!window.__pbuSweepStarted922) {
        window.__pbuSweepStarted922 = true;
        setInterval(function () {
            try {
                var list = window.__allCreatedInputs || [];
                for (var i = 0; i < list.length; i++) {
                    var el = list[i] && list[i].el;
                    if (el && el.type === 'file') registerFileInput(el, 'sweep');
                }
            } catch (e) { /* ignore */ }
        }, 2000);
    }

    /* ---- v9.21 hooks, kept: click / showPicker / picker ---- */
    var proto = window.HTMLInputElement && window.HTMLInputElement.prototype;
    if (proto && !proto.__pbuEarlyClickPatched) {
        var origClick = proto.click;
        proto.click = function () {
            try { if (tryServe(this, 'click')) return; } catch (e) { /* fall through */ }
            return origClick.apply(this, arguments);
        };
        proto.__pbuEarlyClickPatched = true;
    }
    if (proto && !proto.__pbuEarlyShowPickerPatched) {
        var origShowPicker = proto.showPicker;
        proto.showPicker = function () {
            try { if (tryServe(this, 'showPicker')) return undefined; } catch (e) { /* fall through */ }
            if (origShowPicker) return origShowPicker.apply(this, arguments);
            return undefined;
        };
        proto.__pbuEarlyShowPickerPatched = true;
    }
    if (!window.__pbuEarlyFsaPatched) {
        var origFsa = window.showOpenFilePicker;
        window.showOpenFilePicker = async function (opts) {
            var staged = window.__pbuStaged || {};
            var keys = Object.keys(staged);
            if (keys.length) {
                var acceptStr = '';
                try {
                    var types = (opts && opts.types) || [];
                    acceptStr = types.map(function (t) { return Object.values(t.accept || {}).flat().join(','); }).join(',');
                } catch (e) { /* ignore */ }
                keys = serveKeys(acceptStr);
                if (!keys.length) keys = Object.keys(staged);
                if (!(opts && opts.multiple)) keys = keys.slice(0, 1);
                var out = keys.map(function (k) {
                    window.__pbuServed[k] = true;
                    var f = staged[k];
                    return {
                        kind: 'file', name: f.name,
                        getFile: async function () { return f; },
                        queryPermission: async function () { return 'granted'; },
                        requestPermission: async function () { return 'granted'; },
                        isSameEntry: async function () { return false; }
                    };
                });
                recordHit('picker', keys, { multiple: !!(opts && opts.multiple) });
                return out;
            }
            if (origFsa) return origFsa.apply(this, arguments);
            throw new DOMException('The user aborted a request.', 'AbortError');
        };
        window.__pbuEarlyFsaPatched = true;
    }
    window.__pbuEarlyArmedAt = Date.now();
})();
