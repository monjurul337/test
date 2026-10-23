// Chrome Extensions Manager for Electron
const { dialog } = require("electron");
const path = require("path");
const fs = require("fs");

function readManifest(folder) {
  try {
    const p = path.join(folder, "manifest.json");
    if (!fs.existsSync(p)) return null;
    return JSON.parse(fs.readFileSync(p, "utf8"));
  } catch (e) {
    return null;
  }
}

async function loadExtensionsIntoSession(ses, store) {
  const exts = store.get("extensions") || [];
  for (const ext of exts) {
    if (!ext.enabled || !ext.path) continue;
    if (!fs.existsSync(ext.path)) continue;
    try {
      await ses.loadExtension(ext.path, { allowFileAccess: true });
    } catch (err) {
      console.error(`Failed to load extension "${ext.name}" from ${ext.path}:`, err);
    }
  }
}

async function installFromFolder(win, store, getAllSessions) {
  const res = await dialog.showOpenDialog(win, {
    title: "Select Unpacked Extension Folder (containing manifest.json)",
    properties: ["openDirectory"]
  });

  if (res.canceled || !res.filePaths.length) {
    return { canceled: true };
  }

  const folder = res.filePaths[0];
  const manifest = readManifest(folder);
  if (!manifest) {
    return { ok: false, error: "The selected folder does not contain a valid manifest.json file." };
  }

  const sessions = getAllSessions();
  let extInfo = null;

  for (const ses of sessions) {
    try {
      const ext = await ses.loadExtension(folder, { allowFileAccess: true });
      if (!extInfo) extInfo = ext;
    } catch (err) {
      return { ok: false, error: `Failed to load extension: ${err.message || err}` };
    }
  }

  const list = (store.get("extensions") || []).filter(e => e.path !== folder && (!extInfo || e.id !== extInfo.id));
  const newEntry = {
    id: (extInfo && extInfo.id) || ("ext_" + Date.now().toString(36)),
    name: (extInfo && extInfo.name) || manifest.name || "Chrome Extension",
    version: (extInfo && extInfo.version) || manifest.version || "1.0",
    description: manifest.description || "Unpacked Chrome extension",
    path: folder,
    enabled: true
  };

  list.push(newEntry);
  store.set("extensions", list);

  return { ok: true, extensions: listExtensions(store) };
}

async function removeExtension(id, store, getAllSessions) {
  const sessions = getAllSessions();
  for (const ses of sessions) {
    try {
      ses.removeExtension(id);
    } catch (e) {}
  }

  const list = (store.get("extensions") || []).filter(e => e.id !== id);
  store.set("extensions", list);
  return { ok: true, extensions: listExtensions(store) };
}

async function toggleExtension(id, enabled, store, getAllSessions) {
  const list = store.get("extensions") || [];
  const target = list.find(e => e.id === id);
  if (!target) return { ok: false, error: "Extension not found" };

  target.enabled = !!enabled;
  store.set("extensions", list);

  const sessions = getAllSessions();
  for (const ses of sessions) {
    try {
      if (enabled) {
        if (fs.existsSync(target.path)) {
          await ses.loadExtension(target.path, { allowFileAccess: true });
        }
      } else {
        ses.removeExtension(id);
      }
    } catch (e) {}
  }

  return { ok: true, extensions: listExtensions(store) };
}

function listExtensions(store) {
  const list = store.get("extensions") || [];
  return list.map(e => ({
    id: e.id,
    name: e.name,
    version: e.version,
    description: e.description || "",
    path: e.path,
    enabled: !!e.enabled,
    existsOnDisk: fs.existsSync(e.path)
  }));
}

module.exports = {
  loadExtensionsIntoSession,
  installFromFolder,
  removeExtension,
  toggleExtension,
  listExtensions
};
