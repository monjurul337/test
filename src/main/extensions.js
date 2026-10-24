// Chrome Extensions Manager for Electron
const { dialog, app } = require("electron");
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

function copyFolderSync(from, to) {
  if (!fs.existsSync(from)) return;
  fs.mkdirSync(to, { recursive: true });
  const entries = fs.readdirSync(from, { withFileTypes: true });
  for (const entry of entries) {
    const srcPath = path.join(from, entry.name);
    const destPath = path.join(to, entry.name);
    if (entry.isDirectory()) {
      copyFolderSync(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

function getBuiltinExtensionPath() {
  const targetUserPath = path.join(app.getPath("userData"), "extensions", "playbooks-uploader-extension-v9.26");

  const candidateSources = [
    path.join(process.resourcesPath, "app.asar.unpacked", "extensions", "playbooks-uploader-extension-v9.26"),
    path.join(__dirname, "..", "..", "extensions", "playbooks-uploader-extension-v9.26"),
    path.join(process.cwd(), "extensions", "playbooks-uploader-extension-v9.26")
  ];

  // Clean up any old extension versions in userData
  try {
    const userExtDir = path.join(app.getPath("userData"), "extensions");
    if (fs.existsSync(userExtDir)) {
      const items = fs.readdirSync(userExtDir);
      for (const item of items) {
        if (item.startsWith("playbooks-uploader-extension-") && item !== "playbooks-uploader-extension-v9.26") {
          fs.rmSync(path.join(userExtDir, item), { recursive: true, force: true });
        }
      }
    }
  } catch (e) {}

  // If already copied in userData and valid manifest exists
  if (fs.existsSync(path.join(targetUserPath, "manifest.json"))) {
    return targetUserPath;
  }

  // Find source folder and copy to userData
  for (const src of candidateSources) {
    if (fs.existsSync(path.join(src, "manifest.json"))) {
      try {
        copyFolderSync(src, targetUserPath);
        if (fs.existsSync(path.join(targetUserPath, "manifest.json"))) {
          return targetUserPath;
        }
      } catch (e) {
        console.error("Failed to copy built-in extension to userData:", e);
      }
      return src;
    }
  }

  return targetUserPath;
}

function ensureBuiltinExtension(store) {
  const builtinPath = getBuiltinExtensionPath();
  if (!builtinPath || !fs.existsSync(builtinPath)) return null;

  const manifest = readManifest(builtinPath);
  const list = store.get("extensions") || [];

  // Filter out any old extension versions
  const cleanedList = list.filter(e => {
    if (e.id === "builtin_playbooks_uploader" && e.path !== builtinPath) return false;
    if (e.path && e.path.includes("playbooks-uploader-extension-") && !e.path.includes("playbooks-uploader-extension-v9.26")) return false;
    if (e.version && e.version !== "9.26" && (e.id === "builtin_playbooks_uploader" || (e.name && e.name.includes("Play Books Auto Uploader")))) return false;
    return true;
  });

  let existing = cleanedList.find(e => e.id === "builtin_playbooks_uploader" || e.path === builtinPath || (e.name && e.name.includes("Play Books Auto Uploader")));

  if (!existing) {
    existing = {
      id: "builtin_playbooks_uploader",
      name: (manifest && manifest.name) || "Play Books Auto Uploader",
      version: (manifest && manifest.version) || "9.26",
      description: (manifest && manifest.description) || "Play Books Auto Uploader built-in extension",
      path: builtinPath,
      enabled: true,
      isBuiltin: true
    };
    cleanedList.unshift(existing);
    store.set("extensions", cleanedList);
  } else {
    let changed = false;
    if (existing.id !== "builtin_playbooks_uploader") {
      existing.id = "builtin_playbooks_uploader";
      changed = true;
    }
    if (existing.path !== builtinPath) {
      existing.path = builtinPath;
      changed = true;
    }
    if (manifest && existing.version !== manifest.version) {
      existing.version = manifest.version;
      changed = true;
    }
    if (!existing.isBuiltin) {
      existing.isBuiltin = true;
      changed = true;
    }
    // Only set enabled: true if not defined yet, preserving user toggle
    if (existing.enabled === undefined) {
      existing.enabled = true;
      changed = true;
    }
    if (cleanedList.length !== list.length || changed) {
      store.set("extensions", cleanedList);
    }
  }
  return existing;
}

async function loadExtensionsIntoSession(ses, store) {
  ensureBuiltinExtension(store);
  const exts = store.get("extensions") || [];
  for (const ext of exts) {
    if (!ext.enabled || !ext.path) continue;
    if (!fs.existsSync(ext.path)) continue;
    try {
      await ses.loadExtension(ext.path, { allowFileAccess: true });
    } catch (err) {
      if (!String(err).includes("already loaded")) {
        console.error(`Failed to load extension "${ext.name}" from ${ext.path}:`, err);
      }
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
    enabled: true,
    isBuiltin: false
  };

  list.push(newEntry);
  store.set("extensions", list);

  return { ok: true, extensions: listExtensions(store) };
}

async function removeExtension(id, store, getAllSessions) {
  const list = store.get("extensions") || [];
  const target = list.find(e => e.id === id);
  if (target && target.isBuiltin) {
    return { ok: false, error: "Play Books Auto Uploader is a permanent built-in extension and cannot be removed. You can toggle it Off if you wish to disable it." };
  }

  const sessions = getAllSessions();
  for (const ses of sessions) {
    try {
      ses.removeExtension(id);
    } catch (e) {}
  }

  const updatedList = list.filter(e => e.id !== id);
  store.set("extensions", updatedList);
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
        const loadedExts = ses.getAllExtensions ? ses.getAllExtensions() : [];
        const loaded = loadedExts.find(e => e.id === id || e.path === target.path || e.name === target.name);
        if (loaded) {
          ses.removeExtension(loaded.id);
        } else {
          ses.removeExtension(id);
        }
      }
    } catch (e) {}
  }

  return { ok: true, extensions: listExtensions(store) };
}

function listExtensions(store) {
  ensureBuiltinExtension(store);
  const list = store.get("extensions") || [];
  return list.map(e => ({
    id: e.id,
    name: e.name,
    version: e.version,
    description: e.description || "",
    path: e.path,
    enabled: !!e.enabled,
    isBuiltin: !!e.isBuiltin,
    existsOnDisk: fs.existsSync(e.path)
  }));
}

module.exports = {
  loadExtensionsIntoSession,
  installFromFolder,
  removeExtension,
  toggleExtension,
  listExtensions,
  ensureBuiltinExtension
};
