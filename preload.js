'use strict';
// Safe bridge between the dashboard UI and the main process.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('moxixo', {
  listProfiles: () => ipcRenderer.invoke('profiles:list'),
  saveProfile: (profile) => ipcRenderer.invoke('profiles:save', profile),
  cloneProfile: (id) => ipcRenderer.invoke('profiles:clone', id),
  deleteProfile: (id) => ipcRenderer.invoke('profiles:delete', id),
  launchProfile: (id) => ipcRenderer.invoke('profiles:launch', id),
  stopProfile: (id) => ipcRenderer.invoke('profiles:stop', id),
  checkIp: (id) => ipcRenderer.invoke('profiles:check-ip', id),
  vpnTools: () => ipcRenderer.invoke('vpn:tools'),
  vpnParse: (text) => ipcRenderer.invoke('vpn:parse', text),
  vpnPickFile: () => ipcRenderer.invoke('vpn:pick-file'),
  listRunning: () => ipcRenderer.invoke('running:list'),
  exportProfiles: () => ipcRenderer.invoke('profiles:export'),
  importProfiles: () => ipcRenderer.invoke('profiles:import'),
  getPresets: () => ipcRenderer.invoke('meta:presets'),
  onRunningChanged: (cb) =>
    ipcRenderer.on('running:changed', (event, ids) => cb(ids))
});
