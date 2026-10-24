// Proton VPN WireGuard manager using userspace wireproxy
const { spawn, exec } = require("child_process");
const path = require("path");
const fs = require("fs");
const net = require("net");
const { dialog, app } = require("electron");

let vpnProcess = null;
let currentPort = 10808;
let isIntentionalStop = false;
let vpnStatus = {
  running: false,
  connecting: false,
  port: 10808,
  fileName: "",
  ip: null,
  country: null,
  city: null,
  error: null
};

let storeRef = null;
let statusCallback = null;

function getWireproxyPath() {
  // In packaged mode, wireproxy MUST be executed from app.asar.unpacked or resources
  if (app.isPackaged || (process.resourcesPath && !__dirname.includes("generate-main"))) {
    const unpacked = path.join(process.resourcesPath, "app.asar.unpacked", "bin", "wireproxy.exe");
    if (fs.existsSync(unpacked)) return unpacked;
    const direct = path.join(process.resourcesPath, "bin", "wireproxy.exe");
    if (fs.existsSync(direct)) return direct;
  }

  // Development paths (must NOT be inside an asar archive)
  const devPath = path.join(__dirname, "..", "..", "bin", "wireproxy.exe");
  if (!devPath.includes("app.asar") && fs.existsSync(devPath)) return devPath;

  const appPath = path.join(app.getAppPath(), "bin", "wireproxy.exe");
  if (!appPath.includes("app.asar") && fs.existsSync(appPath)) return appPath;

  if (process.resourcesPath) {
    const unpackedFallback = path.join(process.resourcesPath, "app.asar.unpacked", "bin", "wireproxy.exe");
    if (fs.existsSync(unpackedFallback)) return unpackedFallback;
    const directFallback = path.join(process.resourcesPath, "bin", "wireproxy.exe");
    if (fs.existsSync(directFallback)) return directFallback;
  }

  return "wireproxy.exe";
}

function updateStatus(newStatus, notify = true) {
  Object.assign(vpnStatus, newStatus);
  if (notify && typeof statusCallback === "function") {
    try { statusCallback(Object.assign({}, vpnStatus)); } catch (e) {}
  }
}

function prepareWireproxyConf(rawText, port) {
  let text = (rawText || "").trim();
  if (!text) throw new Error("WireGuard config is empty.");

  // Check if [Socks5] section exists
  if (/\[socks5\]/i.test(text)) {
    // Replace existing BindAddress if any
    text = text.replace(/BindAddress\s*=\s*.*/gi, `BindAddress = 127.0.0.1:${port}`);
  } else {
    // Append Socks5 section
    text += `\n\n[Socks5]\nBindAddress = 127.0.0.1:${port}\n`;
  }
  return text;
}

function checkPortListening(port, host = "127.0.0.1", timeoutMs = 15000) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    function attempt() {
      const socket = net.createConnection({ port, host });
      socket.once("connect", () => {
        socket.destroy();
        resolve(true);
      });
      socket.once("error", () => {
        socket.destroy();
        if (Date.now() - start > timeoutMs) {
          reject(new Error("Timeout waiting for WireGuard proxy on port " + port));
        } else {
          setTimeout(attempt, 250);
        }
      });
    }
    attempt();
  });
}

function logDebug(msg) {
  try {
    const logPath = path.join(app.getPath("userData"), "vpn-debug.log");
    fs.appendFileSync(logPath, `[${new Date().toISOString()}] ${msg}\n`, "utf8");
  } catch (e) {}
}

function extractErrorMessage(logs, code) {
  if (!logs) {
    return code !== 0 && code !== null ? `WireGuard tunnel closed unexpectedly (code ${code}).` : null;
  }
  const lines = logs.split("\n")
    .map(l => l.trim())
    .filter(l => l && !l.startsWith("DEBUG:") && !l.startsWith("Routine:") && !l.startsWith("peer(") && !l.startsWith("UAPI:") && !l.startsWith("UDP bind") && !l.startsWith("Interface state"));
  
  if (lines.length > 0) {
    return lines.join("\n");
  }
  if (code !== 0 && code !== null) {
    return `WireGuard tunnel closed unexpectedly (exit code ${code}).`;
  }
  return null;
}

async function stopVpn() {
  logDebug("stopVpn called");
  isIntentionalStop = true;
  updateStatus({ connecting: false, running: false, error: null });

  if (vpnProcess) {
    const proc = vpnProcess;
    vpnProcess = null;
    try {
      if (process.platform === "win32" && proc.pid) {
        const { execSync } = require("child_process");
        try { execSync(`taskkill /pid ${proc.pid} /f /t`, { stdio: "ignore" }); } catch (e) {}
      } else {
        proc.kill();
      }
    } catch (e) {}
  }

  updateStatus({ running: false, ip: null, country: null, city: null, error: null });
  setTimeout(() => { isIntentionalStop = false; }, 800);
  return Object.assign({}, vpnStatus);
}

function stopVpnSync() {
  logDebug("stopVpnSync called");
  isIntentionalStop = true;
  if (vpnProcess) {
    const proc = vpnProcess;
    vpnProcess = null;
    try {
      if (process.platform === "win32" && proc.pid) {
        const { execSync } = require("child_process");
        execSync(`taskkill /pid ${proc.pid} /f /t`, { stdio: "ignore" });
      } else {
        proc.kill("SIGKILL");
      }
    } catch (e) {}
  }
  try {
    const { execSync } = require("child_process");
    execSync("taskkill /f /im wireproxy.exe", { stdio: "ignore" });
  } catch (e) {}
  updateStatus({ running: false, connecting: false, ip: null, country: null, city: null, error: null }, false);
  setTimeout(() => { isIntentionalStop = false; }, 800);
}

async function startVpn(rawConfig, fileName, port = 10808) {
  logDebug(`startVpn requested for file: ${fileName}, port: ${port}`);
  isIntentionalStop = true;
  stopVpnSync();
  isIntentionalStop = false;

  updateStatus({ connecting: true, error: null, fileName: fileName || vpnStatus.fileName || "ProtonVPN.conf", port });
  currentPort = port;

  const binPath = getWireproxyPath();
  logDebug(`Resolved wireproxy binPath: ${binPath}`);
  if (!fs.existsSync(binPath)) {
    const err = "wireproxy.exe not found at: " + binPath;
    logDebug("Error: " + err);
    updateStatus({ running: false, connecting: false, error: err });
    throw new Error(err);
  }

  const confContent = prepareWireproxyConf(rawConfig, port);
  const confDir = app.getPath("userData");
  const confPath = path.join(confDir, "active-wireguard.conf");

  try {
    fs.writeFileSync(confPath, confContent, "utf8");
    logDebug(`Wrote wireproxy config to: ${confPath}`);
  } catch (err) {
    logDebug(`Failed to write config: ${err.message}`);
    updateStatus({ running: false, connecting: false, error: "Failed to write config: " + err.message });
    throw err;
  }

  return new Promise((resolve, reject) => {
    let settled = false;
    let processLogs = "";
    const appendLog = (d) => {
      const s = d ? d.toString() : "";
      processLogs += s;
      logDebug(`[wireproxy output]: ${s.trim()}`);
      if (processLogs.length > 3000) processLogs = processLogs.slice(-3000);
    };

    try {
      logDebug(`Spawning: ${binPath} -s -c ${confPath}`);
      vpnProcess = spawn(binPath, ["-s", "-c", confPath], {
        windowsHide: true,
        stdio: ["ignore", "pipe", "pipe"]
      });
      logDebug(`Spawned process pid: ${vpnProcess.pid}`);
    } catch (spawnErr) {
      logDebug(`Spawn failed: ${spawnErr.message}`);
      updateStatus({ running: false, connecting: false, error: spawnErr.message });
      return reject(spawnErr);
    }

    vpnProcess.on("error", (err) => {
      logDebug(`Process error event: ${err.message}`);
      vpnProcess = null;
      if (!settled) {
        settled = true;
        const msg = `WireGuard proxy failed to launch: ${err.message || String(err)}`;
        updateStatus({ running: false, connecting: false, error: msg });
        reject(new Error(msg));
      }
    });

    vpnProcess.stderr?.on("data", appendLog);
    vpnProcess.stdout?.on("data", appendLog);

    vpnProcess.on("exit", (code) => {
      logDebug(`Process exit event: code ${code}`);
      const wasIntentional = isIntentionalStop;
      isIntentionalStop = false;
      vpnProcess = null;

      if (wasIntentional) {
        updateStatus({ running: false, connecting: false, error: null });
        return;
      }

      const cleanError = extractErrorMessage(processLogs, code);
      if (!settled) {
        settled = true;
        const msg = cleanError || `WireGuard stopped unexpectedly (code ${code})`;
        updateStatus({ running: false, connecting: false, error: msg });
        reject(new Error(msg));
      } else {
        updateStatus({ running: false, connecting: false, error: cleanError });
      }
    });

    // Wait for SOCKS5 port to be ready
    logDebug(`Waiting for port ${port} to listen...`);
    checkPortListening(port, "127.0.0.1", 15000)
      .then(() => {
        if (!settled) {
          settled = true;
          logDebug(`Successfully connected to port ${port}!`);
          updateStatus({ running: true, connecting: false, port, error: null });
          resolve(Object.assign({}, vpnStatus));
        }
      })
      .catch((err) => {
        if (!settled) {
          settled = true;
          logDebug(`checkPortListening failed: ${err.message}`);
          stopVpn().catch(() => {});
          const cleanErr = extractErrorMessage(processLogs, -1);
          const msg = cleanErr || (err.message || String(err));
          updateStatus({ running: false, connecting: false, error: msg });
          reject(new Error(msg));
        }
      });
  });
}

async function testVpn(targetSession) {
  if (!vpnStatus.running) {
    return { ok: false, error: "VPN is not connected." };
  }
  try {
    const response = await Promise.race([
      targetSession.fetch("https://api.ipify.org?format=json", { cache: "no-store" }),
      new Promise((_, reject) => setTimeout(() => reject(new Error("IP test timed out after 10s")), 10000))
    ]);

    if (!response.ok) throw new Error("HTTP " + response.status);
    const data = await response.json();
    if (data.ip) {
      let geo = { country: "United States", city: "" };
      try {
        const gRes = await targetSession.fetch(`https://ipwho.is/${data.ip}`, { cache: "no-store" });
        const gData = await gRes.json();
        if (gData.success) {
          geo.country = gData.country || "United States";
          geo.city = gData.city || "";
        }
      } catch (e) {}
      const info = {
        ok: true,
        ip: data.ip,
        country: geo.country,
        city: geo.city,
        isp: "Proton AG"
      };
      updateStatus({ ip: info.ip, country: info.country, city: info.city }, false);
      return info;
    } else {
      throw new Error("No IP found");
    }
  } catch (err) {
    logDebug(`testVpn error: ${err.message}`);
    return { ok: false, error: err.message || String(err) };
  }
}

async function importConfigFile(parentWindow) {
  const result = await dialog.showOpenDialog(parentWindow, {
    title: "Select Proton VPN WireGuard Configuration (.conf)",
    filters: [
      { name: "WireGuard Config", extensions: ["conf"] },
      { name: "All Files", extensions: ["*"] }
    ],
    properties: ["openFile"]
  });

  if (result.canceled || !result.filePaths.length) return null;
  const filePath = result.filePaths[0];
  const content = fs.readFileSync(filePath, "utf8");
  const fileName = path.basename(filePath);
  return { filePath, fileName, content };
}

function initVpn(store, onStatus) {
  storeRef = store;
  statusCallback = onStatus;

  // Cleanup on app exit
  app.on("before-quit", () => {
    stopVpnSync();
  });

  const saved = store.get("vpn") || {};
  if (saved.fileName) vpnStatus.fileName = saved.fileName;
  if (saved.port) vpnStatus.port = saved.port;

  // Auto-connect if enabled
  if (saved.autoConnect && saved.config) {
    setTimeout(() => {
      startVpn(saved.config, saved.fileName, saved.port || 10808).catch(e => {
        console.error("[WireGuard auto-connect failed]:", e.message);
      });
    }, 1000);
  }
}

module.exports = {
  initVpn,
  startVpn,
  stopVpn,
  stopVpnSync,
  testVpn,
  importConfigFile,
  getStatus: () => Object.assign({}, vpnStatus)
};
