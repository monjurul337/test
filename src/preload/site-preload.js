// Runs inside every web tab (sandboxed).
// Keep browser environment consistent with a regular Chrome build on Windows
const { webFrame } = require("electron");

try {
  webFrame.executeJavaScript(`(() => {
    try {
      // 1. Hide webdriver completely
      try {
        Object.defineProperty(Navigator.prototype, "webdriver", {
          get: () => false,
          configurable: true,
          enumerable: true
        });
      } catch (e) {}
      try { delete navigator.__proto__.webdriver; } catch (e) {}

      // 2. Ensure standard window.chrome APIs
      try {
        if (!window.chrome) {
          window.chrome = {};
        }
        if (!window.chrome.app) {
          window.chrome.app = {
            isInstalled: false,
            InstallState: { DISABLED: "disabled", INSTALLED: "installed", NOT_INSTALLED: "not_installed" },
            RunningState: { CANNOT_RUN: "cannot_run", READY_TO_RUN: "ready_to_run", RUNNING: "running" },
            getDetails: function () {},
            getIsInstalled: function () {},
            installState: function () {},
            runningState: function () {}
          };
        }
        if (!window.chrome.csi) {
          window.chrome.csi = function () {};
        }
        if (!window.chrome.loadTimes) {
          window.chrome.loadTimes = function () {
            return {
              requestTime: performance.timeOrigin / 1000,
              startLoadTime: performance.timeOrigin / 1000,
              commitLoadTime: performance.timeOrigin / 1000,
              finishDocumentLoadTime: performance.timeOrigin / 1000,
              finishLoadTime: performance.timeOrigin / 1000,
              firstPaintTime: performance.timeOrigin / 1000,
              firstPaintAfterLoadTime: 0,
              navigationType: "Other",
              wasFetchedViaSpdy: true,
              wasNpnNegotiated: true,
              npnNegotiatedProtocol: "h2",
              wasAlternateProtocolAvailable: false,
              connectionInfo: "h2"
            };
          };
        }
      } catch (e) {}

      // 3. Ensure navigator.plugins mimics Chrome
      try {
        if (!navigator.plugins || navigator.plugins.length === 0) {
          const fakePlugins = [
            { name: "PDF Viewer", filename: "internal-pdf-viewer", description: "Portable Document Format" },
            { name: "Chrome PDF Viewer", filename: "internal-pdf-viewer", description: "Portable Document Format" },
            { name: "Chromium PDF Viewer", filename: "internal-pdf-viewer", description: "Portable Document Format" },
            { name: "Microsoft Edge PDF Viewer", filename: "internal-pdf-viewer", description: "Portable Document Format" },
            { name: "WebKit built-in PDF", filename: "internal-pdf-viewer", description: "Portable Document Format" }
          ];
          Object.defineProperty(navigator, "plugins", {
            get: () => fakePlugins,
            configurable: true,
            enumerable: true
          });
        }
      } catch (e) {}

      // 4. Ensure navigator.userAgentData matches real Chrome without leaking patched tags
      try {
        const uad = navigator.userAgentData;
        if (uad) {
          const proto = Object.getPrototypeOf(uad);
          if (proto) {
            const major = "130";
            const fullVersion = "130.0.6723.117";
            const brands = [
              { brand: "Chromium", version: major },
              { brand: "Google Chrome", version: major },
              { brand: "Not?A_Brand", version: "99" }
            ];
            const fullBrands = [
              { brand: "Chromium", version: fullVersion },
              { brand: "Google Chrome", version: fullVersion },
              { brand: "Not?A_Brand", version: "99.0.0.0" }
            ];
            Object.defineProperty(proto, "brands", { get: () => brands.slice(), configurable: true });
            Object.defineProperty(proto, "platform", { get: () => "Windows", configurable: true });
            proto.getHighEntropyValues = function (hints) {
              return Promise.resolve({
                brands: brands.slice(),
                platform: "Windows",
                platformVersion: "10.0.0",
                architecture: "x86",
                model: "",
                uaFullVersion: fullVersion,
                fullVersionList: fullBrands.slice()
              });
            };
          }
        }
      } catch (e) {}
    } catch (e) {}
  })();`);
} catch (e) {}
