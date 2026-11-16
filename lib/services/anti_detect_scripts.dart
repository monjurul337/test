import '../models/studio_models.dart';

class AntiDetectScripts {
  static String buildUserScript(
    FingerprintProfile fp, {
    bool blockWebRtc = true,
    double lat = 40.7128,
    double lng = -74.0060,
  }) {
    final chromeVer = RegExp(r'Chrome/(\d+)').firstMatch(fp.userAgent)?.group(1) ?? '130';
    return '''
(function() {
  'use strict';
  const SEED = ${fp.seed};
  const noise = (i) => (((Math.sin(SEED * 9301 + i * 49297) * 233280) % 1) - 0.5) * 0.0001;

  // 1. Strip automation / webdriver markers
  try {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
    for (const k of Object.keys(window)) {
      if (/^cdc_|__webdriver|__selenium|__fxdriver|domAutomation/i.test(k)) {
        try { delete window[k]; } catch (_) {}
      }
    }
  } catch (e) {}

  // 2. Spoof OS, Platform, Hardware & Client Hints (userAgentData)
  const safeDef = (obj, prop, getter) => {
    try { Object.defineProperty(obj, prop, { get: getter, configurable: true }); } catch (_) {}
  };
  safeDef(navigator, 'platform', () => '${fp.navPlatform}');
  safeDef(navigator, 'hardwareConcurrency', () => ${fp.hardwareConcurrency});
  safeDef(navigator, 'deviceMemory', () => ${fp.deviceMemory});
  safeDef(navigator, 'languages', () => ['en-US', 'en']);
  try {
    Object.defineProperty(navigator, 'userAgentData', {
    get: () => ({
      brands: [
        { brand: 'Chromium', version: '$chromeVer' },
        { brand: 'Google Chrome', version: '$chromeVer' },
        { brand: 'Not?A_Brand', version: '99' }
      ],
      mobile: ${fp.osType == 'Android' ? 'true' : 'false'},
      platform: '${fp.osType}',
      getHighEntropyValues: async () => ({
        architecture: '${fp.osType == 'Android' || fp.osType == 'macOS' ? 'arm' : 'x86'}',
        bitness: '64',
        mobile: ${fp.osType == 'Android' ? 'true' : 'false'},
        platform: '${fp.osType}',
        uaFullVersion: '$chromeVer.0.0.0'
      })
    }),
    configurable: true
  });
  } catch (_) {}

  // 3. WebRTC IP Leak Protection (GoLogin-style Disabled/Masked)
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

  // 4. Geolocation & Timezone Spoofing
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
      res.timeZone = '${fp.timezone}';
      return res;
    };
  } catch (e) {}

  // 5. ClientRects Sub-pixel Fingerprint Noise
  try {
    const dRect = (SEED % 7 + 1) * 0.00001;
    const origGetRect = Element.prototype.getBoundingClientRect;
    Element.prototype.getBoundingClientRect = function() {
      const r = origGetRect.apply(this, arguments);
      return new DOMRect(r.x + dRect, r.y + dRect, r.width, r.height);
    };
  } catch (e) {}

  // 6. MediaDevices & Battery Spoofing
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

  // 7. Clean window.chrome & Permissions
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

  // 8. Canvas Fingerprint Protection (${fp.canvasMode})
  if ('${fp.canvasMode}' === 'Block') {
    HTMLCanvasElement.prototype.toDataURL = function() { return 'data:,'; };
  } else if ('${fp.canvasMode}' === 'Noise') {
    const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
    HTMLCanvasElement.prototype.toDataURL = function() {
      try {
        const ctx = this.getContext('2d');
        if (ctx && this.width > 0 && this.height > 0) {
          const img = ctx.getImageData(0, 0, 1, 1);
          img.data[0] = (img.data[0] + (SEED % 5) + 1) & 255;
          ctx.putImageData(img, 0, 0);
        }
      } catch (e) {}
      return origToDataURL.apply(this, arguments);
    };
  }

  // 9. WebGL Vendor & Renderer Spoofing
  const spoofWebGL = (proto) => {
    if (!proto || !proto.getParameter) return;
    const origGetParam = proto.getParameter;
    proto.getParameter = function(param) {
      if (param === 37445) return '${fp.webglVendor}';
      if (param === 37446) return '${fp.webglRenderer}';
      return origGetParam.apply(this, arguments);
    };
  };
  if (window.WebGLRenderingContext) spoofWebGL(WebGLRenderingContext.prototype);
  if (window.WebGL2RenderingContext) spoofWebGL(WebGL2RenderingContext.prototype);

  // 10. AudioContext Fingerprint Noise (${fp.audioMode})
  if ('${fp.audioMode}' === 'Noise' && window.AudioBuffer && AudioBuffer.prototype.getChannelData) {
    const origGetChannelData = AudioBuffer.prototype.getChannelData;
    AudioBuffer.prototype.getChannelData = function() {
      const data = origGetChannelData.apply(this, arguments);
      if (data && data.length > 0) {
        data[0] = data[0] + noise(1);
      }
      return data;
    };
  }
})();
''';
  }
}
