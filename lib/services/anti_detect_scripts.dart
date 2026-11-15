import '../models/studio_models.dart';

class AntiDetectScripts {
  static String buildUserScript(FingerprintProfile fp) {
    return '''
(function() {
  'use strict';
  const SEED = ${fp.seed};
  const noise = (i) => (((Math.sin(SEED * 9301 + i * 49297) * 233280) % 1) - 0.5) * 0.0001;

  // 1. Mask webdriver & hardware properties
  Object.defineProperty(navigator, 'webdriver', { get: () => false });
  Object.defineProperty(navigator, 'platform', { get: () => 'Win32' });
  Object.defineProperty(navigator, 'maxTouchPoints', { get: () => 0 });
  Object.defineProperty(navigator, 'hardwareConcurrency', { get: () => ${fp.hardwareConcurrency} });
  Object.defineProperty(navigator, 'deviceMemory', { get: () => ${fp.deviceMemory} });
  Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });

  // 2. Clean window.chrome presence
  if (!window.chrome) {
    window.chrome = { runtime: {}, app: {}, csi: function(){}, loadTimes: function(){} };
  }

  // 3. Deterministic Canvas Fingerprint Noise
  const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
  HTMLCanvasElement.prototype.toDataURL = function() {
    try {
      const ctx = this.getContext('2d');
      if (ctx && this.width > 0 && this.height > 0) {
        const img = ctx.getImageData(0, 0, 1, 1);
        img.data[0] = (img.data[0] + (SEED % 3)) & 255;
        ctx.putImageData(img, 0, 0);
      }
    } catch (e) {}
    return origToDataURL.apply(this, arguments);
  };

  // 4. WebGL Vendor & Renderer Spoofing
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

  // 5. AudioContext Fingerprint Noise
  if (window.AudioBuffer && AudioBuffer.prototype.getChannelData) {
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
