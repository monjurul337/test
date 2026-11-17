import '../models/studio_models.dart';

class AntiDetectScripts {
  static String _esc(String v) => v.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  static String buildUserScript(
    FingerprintProfile fp, {
    bool blockWebRtc = true,
    double lat = 40.7128,
    double lng = -74.0060,
  }) {
    final chromeVer = RegExp(r'Chrome/(\d+)').firstMatch(fp.userAgent)?.group(1) ?? '130';
    final isMobile = fp.osType == 'Android';
    final scrW = isMobile ? 412 : 1920;
    final scrH = isMobile ? 915 : 1080;
    final touchPts = isMobile ? 5 : 0;
    final tz = _esc(fp.timezone);
    final vendor = _esc(fp.webglVendor);
    final renderer = _esc(fp.webglRenderer);
    final navPlat = _esc(fp.navPlatform);
    final osName = _esc(fp.osType);

    return '''
(function() {
  'use strict';
  const SEED = ${fp.seed};
  const noise = (i) => (((Math.sin(SEED * 9301 + i * 49297) * 233280) % 1) - 0.5) * 0.0001;
  const safeDef = (obj, prop, getter) => {
    try { Object.defineProperty(obj, prop, { get: getter, configurable: true }); } catch (_) {}
  };

  // 1. Strip automation / webdriver / headless markers
  try {
    safeDef(navigator, 'webdriver', () => undefined);
    for (const k of Object.keys(window)) {
      if (/^cdc_|__webdriver|__selenium|__fxdriver|domAutomation/i.test(k)) {
        try { delete window[k]; } catch (_) {}
      }
    }
  } catch (e) {}

  // 2. Spoof OS, Platform, Hardware, TouchPoints, Connection & Client Hints
  safeDef(navigator, 'platform', () => '$navPlat');
  safeDef(navigator, 'hardwareConcurrency', () => ${fp.hardwareConcurrency});
  safeDef(navigator, 'deviceMemory', () => ${fp.deviceMemory});
  safeDef(navigator, 'maxTouchPoints', () => $touchPts);
  safeDef(navigator, 'vendor', () => 'Google Inc.');
  safeDef(navigator, 'doNotTrack', () => null);
  safeDef(navigator, 'languages', () => ['en-US', 'en']);
  safeDef(navigator, 'language', () => 'en-US');
  safeDef(navigator, 'connection', () => ({
    effectiveType: '4g',
    rtt: 50 + (SEED % 35),
    downlink: 10 + (SEED % 8),
    saveData: false
  }));
  try {
    Object.defineProperty(navigator, 'userAgentData', {
      get: () => ({
        brands: [
          { brand: 'Chromium', version: '$chromeVer' },
          { brand: 'Google Chrome', version: '$chromeVer' },
          { brand: 'Not?A_Brand', version: '99' }
        ],
        mobile: ${isMobile ? 'true' : 'false'},
        platform: '$osName',
        getHighEntropyValues: async () => ({
          architecture: '${fp.osType == 'Android' || fp.osType == 'macOS' ? 'arm' : 'x86'}',
          bitness: '64',
          mobile: ${isMobile ? 'true' : 'false'},
          platform: '$osName',
          uaFullVersion: '$chromeVer.0.0.0'
        })
      }),
      configurable: true
    });
  } catch (_) {}

  // 3. Screen Resolution & Color Depth Masking (desktop vs mobile)
  try {
    if (!${isMobile ? 'true' : 'false'}) {
      safeDef(window.screen, 'width', () => $scrW);
      safeDef(window.screen, 'height', () => $scrH);
      safeDef(window.screen, 'availWidth', () => $scrW);
      safeDef(window.screen, 'availHeight', () => ${scrH - 40});
    }
    safeDef(window.screen, 'colorDepth', () => 24);
    safeDef(window.screen, 'pixelDepth', () => 24);
  } catch (_) {}

  // 4. WebRTC IP Leak Protection
  if (${blockWebRtc ? 'true' : 'false'}) {
    const noopRtc = function() {
      throw new DOMException('WebRTC disabled by Anti-Detect Shield', 'NotAllowedError');
    };
    try {
      window.RTCPeerConnection = noopRtc;
      window.webkitRTCPeerConnection = noopRtc;
      window.mozRTCPeerConnection = noopRtc;
      if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
        navigator.mediaDevices.getUserMedia = async () => {
          throw new DOMException('Permission denied', 'NotAllowedError');
        };
      }
    } catch (e) {}
  }

  // 5. Geolocation & Timezone + Date.getTimezoneOffset Synchronization
  try {
    if (navigator.geolocation) {
      const fakePos = {
        coords: { latitude: $lat, longitude: $lng, accuracy: 25, altitude: null, altitudeAccuracy: null, heading: null, speed: null },
        timestamp: Date.now()
      };
      navigator.geolocation.getCurrentPosition = (ok) => ok && ok(fakePos);
      navigator.geolocation.watchPosition = (ok) => { ok && ok(fakePos); return 1; };
    }
    const origDTF = Intl.DateTimeFormat.prototype.resolvedOptions;
    Intl.DateTimeFormat.prototype.resolvedOptions = function() {
      const res = origDTF.apply(this, arguments);
      res.timeZone = '$tz';
      return res;
    };
    const calcTzOffset = () => {
      try {
        const now = new Date();
        const utc = new Date(now.toLocaleString('en-US', { timeZone: 'UTC' }));
        const target = new Date(now.toLocaleString('en-US', { timeZone: '$tz' }));
        return Math.round((utc.getTime() - target.getTime()) / 60000);
      } catch (_) { return -360; }
    };
    const spoofedOffset = calcTzOffset();
    Date.prototype.getTimezoneOffset = function() { return spoofedOffset; };
  } catch (e) {}

  // 6. ClientRects Sub-pixel Fingerprint Noise
  try {
    const dRect = (SEED % 7 + 1) * 0.00001;
    const origGetRect = Element.prototype.getBoundingClientRect;
    Element.prototype.getBoundingClientRect = function() {
      const r = origGetRect.apply(this, arguments);
      return new DOMRect(r.x + dRect, r.y + dRect, r.width, r.height);
    };
  } catch (e) {}

  // 7. MediaDevices & Battery Spoofing
  try {
    if (navigator.mediaDevices && navigator.mediaDevices.enumerateDevices) {
      navigator.mediaDevices.enumerateDevices = async () => [
        { deviceId: 'default', kind: 'audioinput', label: '', groupId: 'g1' },
        { deviceId: 'default', kind: 'audiooutput', label: '', groupId: 'g1' },
        { deviceId: 'cam1', kind: 'videoinput', label: '', groupId: 'g2' }
      ];
    }
    if (navigator.getBattery) {
      navigator.getBattery = async () => ({
        charging: true, chargingTime: 0, dischargingTime: Infinity, level: 0.88 + (SEED % 10) * 0.01
      });
    }
  } catch (e) {}

  // 8. Clean window.chrome & Permissions
  if (!window.chrome) {
    window.chrome = { runtime: {}, app: {}, csi: function(){}, loadTimes: function(){} };
  }
  if (navigator.permissions && navigator.permissions.query) {
    const origQ = navigator.permissions.query.bind(navigator.permissions);
    navigator.permissions.query = (p) =>
      (p && p.name === 'notifications')
        ? Promise.resolve({ state: Notification.permission })
        : origQ(p);
  }

  // 9. Strong Canvas 2D Fingerprint Protection (toDataURL, toBlob, getImageData, measureText)
  if ('${fp.canvasMode}' === 'Block') {
    HTMLCanvasElement.prototype.toDataURL = function() { return 'data:,'; };
    HTMLCanvasElement.prototype.toBlob = function(cb) { if (cb) cb(new Blob()); };
  } else if ('${fp.canvasMode}' === 'Noise') {
    const shift = (SEED % 5) + 1;
    const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
    HTMLCanvasElement.prototype.toDataURL = function() {
      try {
        const ctx = this.getContext('2d');
        if (ctx && this.width > 0 && this.height > 0) {
          const img = ctx.getImageData(0, 0, 1, 1);
          img.data[0] = (img.data[0] + shift) & 255;
          ctx.putImageData(img, 0, 0);
        }
      } catch (e) {}
      return origToDataURL.apply(this, arguments);
    };
    const origToBlob = HTMLCanvasElement.prototype.toBlob;
    HTMLCanvasElement.prototype.toBlob = function() {
      try {
        const ctx = this.getContext('2d');
        if (ctx && this.width > 0 && this.height > 0) {
          const img = ctx.getImageData(0, 0, 1, 1);
          img.data[0] = (img.data[0] + shift) & 255;
          ctx.putImageData(img, 0, 0);
        }
      } catch (e) {}
      return origToBlob.apply(this, arguments);
    };
    const origGetImageData = CanvasRenderingContext2D.prototype.getImageData;
    CanvasRenderingContext2D.prototype.getImageData = function() {
      const data = origGetImageData.apply(this, arguments);
      if (data && data.data && data.data.length >= 4) {
        data.data[0] = (data.data[0] + shift) & 255;
      }
      return data;
    };
    const origMeasureText = CanvasRenderingContext2D.prototype.measureText;
    CanvasRenderingContext2D.prototype.measureText = function() {
      const m = origMeasureText.apply(this, arguments);
      const jitter = ((SEED % 9) - 4) * 0.0001;
      try {
        Object.defineProperty(m, 'width', { value: m.width + jitter });
      } catch (_) {}
      return m;
    };
  }

  // 10. Strong WebGL1 & WebGL2 Spoofing (Vendor, Renderer, Debug Extension, readPixels)
  const spoofWebGL = (proto) => {
    if (!proto || !proto.getParameter) return;
    const origGetParam = proto.getParameter;
    proto.getParameter = function(param) {
      if (param === 37445 || param === 7936) return '$vendor';
      if (param === 37446 || param === 7937) return '$renderer';
      return origGetParam.apply(this, arguments);
    };
    if (proto.readPixels) {
      const origRead = proto.readPixels;
      proto.readPixels = function() {
        origRead.apply(this, arguments);
        const buf = arguments[6];
        if (buf && buf.length > 0) {
          buf[0] = (buf[0] + (SEED % 3) + 1) & 255;
        }
      };
    }
  };
  if (window.WebGLRenderingContext) spoofWebGL(WebGLRenderingContext.prototype);
  if (window.WebGL2RenderingContext) spoofWebGL(WebGL2RenderingContext.prototype);

  // 11. AudioContext & AnalyserNode Fingerprint Noise
  if ('${fp.audioMode}' === 'Noise') {
    if (window.AudioBuffer && AudioBuffer.prototype.getChannelData) {
      const origGetChannelData = AudioBuffer.prototype.getChannelData;
      AudioBuffer.prototype.getChannelData = function() {
        const data = origGetChannelData.apply(this, arguments);
        if (data && data.length > 0) data[0] = data[0] + noise(1);
        return data;
      };
    }
    if (window.AnalyserNode && AnalyserNode.prototype.getFloatFrequencyData) {
      const origFreq = AnalyserNode.prototype.getFloatFrequencyData;
      AnalyserNode.prototype.getFloatFrequencyData = function(arr) {
        origFreq.apply(this, arguments);
        if (arr && arr.length > 0) arr[0] = arr[0] + noise(2);
      };
    }
  }
})();
''';
  }
}
