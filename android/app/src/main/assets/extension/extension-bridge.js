/**
 * Play Books Auto Uploader - Android Extension Polyfill & Bridge
 * Provides Chrome Extension APIs (chrome.storage, chrome.runtime, chrome.alarms,
 * chrome.notifications, chrome.tabs, chrome.scripting, chrome.action)
 * inside Android WebView.
 */
(function() {
    'use strict';

    if (window.__chrome_bridge_installed) {
        console.log('[PBU Bridge] Already installed.');
        return;
    }
    window.__chrome_bridge_installed = true;

    console.log('[PBU Bridge] Initializing Chrome Extension Polyfill for Android WebView...');

    const memoryStore = {};
    const storageListeners = [];
    const runtimeMessageListeners = [];
    const alarmsListeners = [];
    const alarmsIntervals = {};
    const alarmsTimeouts = {};

    // Restore any existing items from localStorage into memoryStore
    try {
        for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            if (key && key.startsWith('pbu_st_')) {
                const subKey = key.substring(7);
                try {
                    memoryStore[subKey] = JSON.parse(localStorage.getItem(key));
                } catch (e) {
                    memoryStore[subKey] = localStorage.getItem(key);
                }
            }
        }
    } catch (e) {
        console.warn('[PBU Bridge] localStorage access restricted:', e);
    }

    // 1. chrome.storage
    const storage = {
        local: {
            get: function(keys, callback) {
                return new Promise(function(resolve) {
                    const result = {};
                    if (!keys) {
                        for (const k in memoryStore) {
                            if (Object.prototype.hasOwnProperty.call(memoryStore, k)) {
                                result[k] = memoryStore[k];
                            }
                        }
                    } else if (typeof keys === 'string') {
                        if (memoryStore[keys] !== undefined) {
                            result[keys] = memoryStore[keys];
                        }
                    } else if (Array.isArray(keys)) {
                        keys.forEach(function(k) {
                            if (memoryStore[k] !== undefined) {
                                result[k] = memoryStore[k];
                            }
                        });
                    } else if (typeof keys === 'object') {
                        for (const k in keys) {
                            if (Object.prototype.hasOwnProperty.call(keys, k)) {
                                result[k] = memoryStore[k] !== undefined ? memoryStore[k] : keys[k];
                            }
                        }
                    }

                    if (typeof callback === 'function') {
                        try { callback(result); } catch (e) { console.error(e); }
                    }
                    resolve(result);
                });
            },

            set: function(items, callback) {
                return new Promise(function(resolve) {
                    const changes = {};
                    if (items && typeof items === 'object') {
                        for (const k in items) {
                            if (Object.prototype.hasOwnProperty.call(items, k)) {
                                const oldVal = memoryStore[k];
                                const newVal = items[k];
                                memoryStore[k] = newVal;

                                try {
                                    localStorage.setItem('pbu_st_' + k, JSON.stringify(newVal));
                                } catch (e) {
                                    // LocalStorage quota may be exceeded for large files; memoryStore remains valid
                                    console.warn('[PBU Bridge] localStorage save failed for ' + k + ' (kept in memory):', e);
                                }

                                changes[k] = { oldValue: oldVal, newValue: newVal };
                            }
                        }
                    }

                    if (Object.keys(changes).length > 0) {
                        storageListeners.forEach(function(l) {
                            try { l(changes, 'local'); } catch (e) { console.error(e); }
                        });
                    }

                    if (typeof callback === 'function') {
                        try { callback(); } catch (e) { console.error(e); }
                    }
                    resolve();
                });
            },

            remove: function(keys, callback) {
                return new Promise(function(resolve) {
                    const changes = {};
                    const list = Array.isArray(keys) ? keys : [keys];
                    list.forEach(function(k) {
                        const oldVal = memoryStore[k];
                        delete memoryStore[k];
                        try {
                            localStorage.removeItem('pbu_st_' + k);
                        } catch (e) {}
                        changes[k] = { oldValue: oldVal, newValue: undefined };
                    });

                    if (Object.keys(changes).length > 0) {
                        storageListeners.forEach(function(l) {
                            try { l(changes, 'local'); } catch (e) { console.error(e); }
                        });
                    }

                    if (typeof callback === 'function') {
                        try { callback(); } catch (e) { console.error(e); }
                    }
                    resolve();
                });
            },

            clear: function(callback) {
                return new Promise(function(resolve) {
                    for (const k in memoryStore) {
                        if (Object.prototype.hasOwnProperty.call(memoryStore, k)) {
                            delete memoryStore[k];
                        }
                    }
                    try {
                        for (let i = localStorage.length - 1; i >= 0; i--) {
                            const key = localStorage.key(i);
                            if (key && key.startsWith('pbu_st_')) {
                                localStorage.removeItem(key);
                            }
                        }
                    } catch (e) {}

                    if (typeof callback === 'function') {
                        try { callback(); } catch (e) { console.error(e); }
                    }
                    resolve();
                });
            }
        },

        onChanged: {
            addListener: function(l) {
                if (typeof l === 'function' && !storageListeners.includes(l)) {
                    storageListeners.push(l);
                }
            },
            removeListener: function(l) {
                const idx = storageListeners.indexOf(l);
                if (idx >= 0) storageListeners.splice(idx, 1);
            }
        }
    };

    // 2. chrome.runtime
    const runtime = {
        lastError: null,

        getManifest: function() {
            return {
                manifest_version: 3,
                name: "Play Books Auto Uploader",
                version: "9.26",
                description: "Automates Google Play Books Partner Center uploads in mobile WebView"
            };
        },

        onStartup: {
            addListener: function(l) {}
        },

        onMessage: {
            addListener: function(l) {
                if (typeof l === 'function' && !runtimeMessageListeners.includes(l)) {
                    runtimeMessageListeners.push(l);
                }
            },
            removeListener: function(l) {
                const idx = runtimeMessageListeners.indexOf(l);
                if (idx >= 0) runtimeMessageListeners.splice(idx, 1);
            }
        },

        sendMessage: function(msg, callback) {
            return new Promise(function(resolve) {
                let responded = false;
                const sendResponse = function(response) {
                    if (responded) return;
                    responded = true;
                    if (typeof callback === 'function') {
                        try { callback(response); } catch (e) {}
                    }
                    resolve(response);
                };

                const sender = {
                    id: "pbu-extension",
                    url: window.location.href,
                    tab: { id: 1, url: window.location.href, status: 'complete' }
                };

                let willWait = false;
                for (let i = 0; i < runtimeMessageListeners.length; i++) {
                    const listener = runtimeMessageListeners[i];
                    try {
                        const result = listener(msg, sender, sendResponse);
                        if (result === true) {
                            willWait = true;
                        }
                    } catch (err) {
                        console.error("[PBU Bridge] onMessage handler error:", err);
                    }
                }

                if (!willWait && !responded) {
                    sendResponse({ ok: true });
                }
            });
        }
    };

    // 3. chrome.alarms
    const alarms = {
        create: function(name, alarmInfo) {
            if (alarmsIntervals[name]) clearInterval(alarmsIntervals[name]);
            if (alarmsTimeouts[name]) clearTimeout(alarmsTimeouts[name]);

            const info = alarmInfo || {};
            const delayMinutes = info.delayInMinutes || 0.1;
            const periodMinutes = info.periodInMinutes || 2;

            const trigger = function() {
                alarmsListeners.forEach(function(l) {
                    try { l({ name: name }); } catch (e) { console.error(e); }
                });
            };

            alarmsTimeouts[name] = setTimeout(function() {
                trigger();
                alarmsIntervals[name] = setInterval(trigger, periodMinutes * 60 * 1000);
            }, delayMinutes * 60 * 1000);
        },

        clear: function(name, callback) {
            if (alarmsIntervals[name]) {
                clearInterval(alarmsIntervals[name]);
                delete alarmsIntervals[name];
            }
            if (alarmsTimeouts[name]) {
                clearTimeout(alarmsTimeouts[name]);
                delete alarmsTimeouts[name];
            }
            if (typeof callback === 'function') {
                try { callback(true); } catch (e) {}
            }
            return Promise.resolve(true);
        },

        onAlarm: {
            addListener: function(l) {
                if (typeof l === 'function' && !alarmsListeners.includes(l)) {
                    alarmsListeners.push(l);
                }
            },
            removeListener: function(l) {
                const idx = alarmsListeners.indexOf(l);
                if (idx >= 0) alarmsListeners.splice(idx, 1);
            }
        }
    };

    // 4. chrome.notifications
    const notifications = {
        create: function(id, opts, callback) {
            const title = (opts && opts.title) || "Play Books Auto Uploader";
            const message = (opts && opts.message) || "";
            const text = title + (message ? ": " + message : "");

            if (window.Android && window.Android.showToast) {
                window.Android.showToast(text);
            } else {
                console.log("[PBU Notification] " + text);
            }

            if (typeof callback === 'function') {
                try { callback(id || "pbu_notif"); } catch (e) {}
            }
            return Promise.resolve(id || "pbu_notif");
        }
    };

    // 5. chrome.tabs
    const tabs = {
        query: function(info, callback) {
            const res = [{ id: 1, active: true, url: window.location.href, status: 'complete' }];
            if (typeof callback === 'function') {
                try { callback(res); } catch (e) {}
            }
            return Promise.resolve(res);
        },

        create: function(info, callback) {
            if (info && info.url) {
                window.location.href = info.url;
            }
            const res = { id: 1, active: true, url: window.location.href, status: 'complete' };
            if (typeof callback === 'function') {
                try { callback(res); } catch (e) {}
            }
            return Promise.resolve(res);
        },

        sendMessage: function(tabId, msg, callback) {
            return runtime.sendMessage(msg, callback);
        },

        onUpdated: {
            addListener: function(l) {},
            removeListener: function(l) {}
        }
    };

    // 6. chrome.scripting
    const scripting = {
        executeScript: async function(details) {
            if (details && typeof details.func === 'function') {
                try {
                    const res = await details.func.apply(window, details.args || []);
                    return [{ result: res }];
                } catch (e) {
                    console.error("[PBU Bridge] executeScript error:", e);
                    throw e;
                }
            }
            return [{ result: true }];
        }
    };

    // 7. chrome.action
    const action = {
        onClicked: {
            addListener: function(l) {}
        }
    };

    // Install on window
    window.chrome = window.chrome || {};
    window.chrome.storage = storage;
    window.chrome.runtime = runtime;
    window.chrome.alarms = alarms;
    window.chrome.notifications = notifications;
    window.chrome.tabs = tabs;
    window.chrome.scripting = scripting;
    window.chrome.action = action;

    // Helper function for native Android app to toggle extension panel
    window.__pbuTogglePanel = function(forceOpen) {
        try {
            const host = document.getElementById('pbu-panel-host');
            if (host && host.shadowRoot) {
                const fab = host.shadowRoot.getElementById('fab');
                const panel = host.shadowRoot.getElementById('panel');
                if (typeof forceOpen === 'boolean') {
                    const isOpen = panel && panel.classList.contains('open');
                    if (forceOpen !== isOpen && fab) {
                        fab.click();
                    }
                } else if (fab) {
                    fab.click();
                }
                return true;
            }
        } catch (e) {
            console.error("[PBU Bridge] toggle error:", e);
        }
        return false;
    };

    console.log('[PBU Bridge] Chrome polyfill bridge loaded and armed.');
})();
