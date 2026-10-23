const { ipcRenderer, contextBridge } = require("electron");
contextBridge.exposeInMainWorld("app", {
  init: () => ipcRenderer.invoke("shell:init"),
  newTab: (a) => ipcRenderer.send("tab:new", a || {}),
  closeTab: id => ipcRenderer.send("tab:close", id),
  activate: id => ipcRenderer.send("tab:activate", id),
  nav: (cmd, extra) => ipcRenderer.send("nav", Object.assign({ cmd }, extra || {})),
  win: cmd => ipcRenderer.send("win", cmd),
  overlay: on => ipcRenderer.send("overlay", on),
  saveSettings: s => ipcRenderer.invoke("settings:save", s),
  saveProfiles: l => ipcRenderer.invoke("profiles:save", l),
  testProxy: p => ipcRenderer.invoke("profiles:test-proxy", p),
  clearProfile: id => ipcRenderer.invoke("profiles:clear", id),
  resetPanel: () => ipcRenderer.invoke("panel:reset"),
  openData: () => ipcRenderer.send("open-data-folder"),
  vpnStatus: () => ipcRenderer.invoke("vpn:get-status"),
  vpnImport: () => ipcRenderer.invoke("vpn:import"),
  vpnConnect: opts => ipcRenderer.invoke("vpn:connect", opts),
  vpnDisconnect: () => ipcRenderer.invoke("vpn:disconnect"),
  vpnSaveConfig: opts => ipcRenderer.invoke("vpn:save-config", opts),
  vpnTest: () => ipcRenderer.invoke("vpn:test"),
  on: (ch, fn) => { const ok = ["tabs", "maximized", "focus-address", "vpn-status"]; if (ok.includes(ch)) ipcRenderer.on(ch, (e, d) => fn(d)); }
});
