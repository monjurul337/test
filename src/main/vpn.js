// Proton VPN WireGuard manager using userspace wireproxy
const { spawn, exec } = require("child_process");
const path = require("path");
const fs = require("fs");
const net = require("net");
const { dialog, app } = require("electron");

let vpnProcess = null;
let currentPort = 10808;
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

function updateStatus(newStatus) {
  Object.assign(vpnStatus, newStatus);
  if (typeof statusCallback === "function") {
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

async function stopVpn() {
  logDebug("stopVpn called");
  updateStatus({ connecting: false });
  if (vpnProcess) {
    const proc = vpnProcess;
    vpnProcess = null;
    try {
      if (process.platform === "win32" && proc.pid) {
        exec(`taskkill /pid ${proc.pid} /f /t`, () => {});
      } else {
        proc.kill();
      }
    } catch (e) {}
  }
  updateStatus({ running: false, ip: null, country: null, city: null, error: null });
  return Object.assign({}, vpnStatus);
}

async function startVpn(rawConfig, fileName, port = 10808) {
  logDebug(`startVpn requested for file: ${fileName}, port: ${port}`);
  await stopVpn();

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
      logDebug(`Spawning: ${binPath} -c ${confPath}`);
      vpnProcess = spawn(binPath, ["-c", confPath], {
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
      vpnProcess = null;
      if (!settled) {
        settled = true;
        const detail = processLogs.trim() ? `\nDetails: ${processLogs.trim()}` : "";
        const msg = `WireGuard stopped unexpectedly (code ${code}).${detail}`;
        updateStatus({ running: false, connecting: false, error: msg });
        reject(new Error(msg));
      } else {
        updateStatus({ running: false, connecting: false, error: processLogs.trim() || null });
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
          const detail = processLogs.trim() ? " | " + processLogs.trim() : "";
          const msg = (err.message || String(err)) + detail;
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
      targetSession.fetch("http://ip-api.com/json", { cache: "no-store" }),
      new Promise((_, reject) => setTimeout(() => reject(new Error("IP test timed out after 10s")), 10000))
    ]);

    if (!response.ok) throw new Error("HTTP " + response.status);
    const data = await response.json();
    if (data.status === "success" || data.query) {
      const info = {
        ok: true,
        ip: data.query || data.ip,
        country: data.country || "",
        countryCode: data.countryCode || "",
        city: data.city || "",
        isp: data.isp || data.org || ""
      };
      updateStatus({ ip: info.ip, country: info.country, city: info.city });
      return info;
    } else {
      throw new Error(data.message || "Failed to parse IP info");
    }
  } catch (err) {
    // Fallback to ipify
    try {
      const fb = await targetSession.fetch("https://api.ipify.org?format=json", { cache: "no-store" });
      const fbData = await fb.json();
      if (fbData.ip) {
        updateStatus({ ip: fbData.ip });
        return { ok: true, ip: fbData.ip, country: "Active", city: "", isp: "" };
      }
    } catch (e2) {}
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
    stopVpn().catch(() => {});
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
  testVpn,
  importConfigFile,
  getStatus: () => Object.assign({}, vpnStatus)
};
