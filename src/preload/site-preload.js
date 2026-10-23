// Runs inside every web tab (sandboxed).
// Keep navigator.userAgentData consistent with a regular Chrome build on Windows (no Electron brand).
const { webFrame } = require("electron");

try {
  webFrame.executeJavaScript(`(() => {
    try {
      const uad = navigator.userAgentData; if (!uad) return;
      const proto = Object.getPrototypeOf(uad);
      if (!proto || proto.__uadPatched) return;
      proto.__uadPatched = true;

      const major = (navigator.userAgent.match(/Chrome\\/(\\d+)/) || [])[1] || "130";
      const brands = [{ brand: "Chromium", version: major }, { brand: "Google Chrome", version: major }, { brand: "Not?A_Brand", version: "99" }];
      const orig = proto.getHighEntropyValues;
      Object.defineProperty(proto, "brands", { get: () => brands.map(b => Object.assign({}, b)), configurable: true });
      Object.defineProperty(proto, "platform", { get: () => "Windows", configurable: true });
      proto.getHighEntropyValues = function (h) {
        if (typeof orig === "function") {
          return orig.call(this, h).then(v => Object.assign(v || {}, {
            brands: brands.map(b => Object.assign({}, b)),
            platform: "Windows",
            fullVersionList: brands.map(b => ({ brand: b.brand, version: b.version + ".0.0.0" }))
          })).catch(() => ({
            brands: brands.map(b => Object.assign({}, b)),
            platform: "Windows",
            fullVersionList: brands.map(b => ({ brand: b.brand, version: b.version + ".0.0.0" }))
          }));
        }
        return Promise.resolve({
          brands: brands.map(b => Object.assign({}, b)),
          platform: "Windows",
          fullVersionList: brands.map(b => ({ brand: b.brand, version: b.version + ".0.0.0" }))
        });
      };
    } catch (e) {}
  })();`);
} catch (e) {}


