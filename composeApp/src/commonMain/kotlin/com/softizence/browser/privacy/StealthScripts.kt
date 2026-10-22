package com.softizence.browser.privacy

import com.softizence.browser.core.model.FingerprintProfile

/**
 * Document-start JavaScript that masks the engine's real identity.
 *
 * Design rules (what separates this from the usual copy-pasted "stealth.js"):
 *  - Every patched function keeps its native `toString()`, because
 *    `Function.prototype.toString.call(fn).includes('[native code]')` is the single
 *    most common detection probe.
 *  - Values are *consistent* with the persona and the exit country, never random.
 *  - Canvas/audio get deterministic sub-perceptual noise, not a blank/zeroed readback -
 *    an all-zero canvas hash is itself a fingerprint.
 *  - Nothing is deleted that a real Chrome has; we only change values.
 */
object StealthScripts {

    fun documentStart(fp: FingerprintProfile): String = buildString {
        append(PRELUDE)
        append(navigatorPatch(fp))
        append(screenPatch(fp))
        append(webglPatch(fp))
        append(canvasPatch(fp))
        append(audioPatch(fp))
        append(timezonePatch(fp))
        if (fp.blockWebRtc) append(WEBRTC_BLOCK)
        append(AUTOMATION_SCRUB)
        append(EPILOGUE)
    }

    private val PRELUDE = """
        (function () {
          'use strict';
          if (window.__sfz__) return;
          Object.defineProperty(window, '__sfz__', { value: true, enumerable: false });

          const nativeToString = Function.prototype.toString;
          const patched = new WeakMap();

          // Keep every override indistinguishable from a native binding.
          function mask(fn, original) {
            patched.set(fn, original);
            return fn;
          }
          Function.prototype.toString = mask(function toString() {
            const original = patched.get(this);
            return nativeToString.call(original || this);
          }, nativeToString);

          function define(target, prop, value) {
            try {
              Object.defineProperty(target, prop, {
                get: mask(function () { return value; }, Object.getOwnPropertyDescriptor(target, prop)?.get),
                configurable: true,
                enumerable: true,
              });
            } catch (_) { /* frozen in some sandboxes - ignore */ }
          }
    """.trimIndent() + "\n"

    private fun navigatorPatch(fp: FingerprintProfile) = """
          define(navigator, 'userAgent', ${fp.userAgent.q()});
          define(navigator, 'appVersion', ${fp.userAgent.removePrefix("Mozilla/").q()});
          define(navigator, 'platform', ${fp.platform.q()});
          define(navigator, 'vendor', ${fp.vendor.q()});
          define(navigator, 'language', ${fp.languages.first().q()});
          define(navigator, 'languages', Object.freeze(${fp.languages.joinToString(prefix = "[", postfix = "]") { it.q() }}));
          define(navigator, 'hardwareConcurrency', ${fp.hardwareConcurrency});
          define(navigator, 'deviceMemory', ${fp.deviceMemoryGb});
          define(navigator, 'maxTouchPoints', ${fp.maxTouchPoints});
          define(navigator, 'pdfViewerEnabled', true);

          // userAgentData must agree with the UA string, or the mismatch is the fingerprint.
          if (navigator.userAgentData) {
            define(navigator, 'userAgentData', {
              brands: [
                { brand: 'Chromium', version: '131' },
                { brand: 'Not_A Brand', version: '24' },
                { brand: 'Google Chrome', version: '131' }
              ],
              mobile: ${fp.maxTouchPoints > 0},
              platform: ${fp.platformLabel().q()},
              getHighEntropyValues: function (hints) {
                return Promise.resolve({
                  architecture: 'x86', bitness: '64', model: '',
                  platform: ${fp.platformLabel().q()}, platformVersion: '15.0.0',
                  uaFullVersion: '131.0.0.0', fullVersionList: [{ brand: 'Google Chrome', version: '131.0.0.0' }]
                });
              },
              toJSON: function () { return {}; }
            });
          }

    """.trimIndent() + "\n"

    private fun screenPatch(fp: FingerprintProfile) = """
          define(screen, 'width', ${fp.screenWidth});
          define(screen, 'height', ${fp.screenHeight});
          define(screen, 'availWidth', ${fp.screenWidth});
          define(screen, 'availHeight', ${fp.screenHeight - 40});
          define(screen, 'colorDepth', ${fp.colorDepth});
          define(screen, 'pixelDepth', ${fp.colorDepth});
          define(window, 'devicePixelRatio', ${fp.devicePixelRatio});

    """.trimIndent() + "\n"

    private fun webglPatch(fp: FingerprintProfile) = """
          const GL_VENDOR = 0x9245, GL_RENDERER = 0x9246;
          for (const Ctx of [self.WebGLRenderingContext, self.WebGL2RenderingContext]) {
            if (!Ctx) continue;
            const original = Ctx.prototype.getParameter;
            Ctx.prototype.getParameter = mask(function getParameter(p) {
              if (p === GL_VENDOR) return ${fp.webglVendor.q()};
              if (p === GL_RENDERER) return ${fp.webglRenderer.q()};
              return original.apply(this, arguments);
            }, original);
          }

    """.trimIndent() + "\n"

    private fun canvasPatch(fp: FingerprintProfile) = """
          const NOISE = ${fp.canvasNoise};
          const SEED = ${fp.seed};
          function jitter(data) {
            let s = SEED >>> 0;
            for (let i = 0; i < data.length; i += 4) {
              s = (s * 1664525 + 1013904223) >>> 0;
              const d = ((s % 3) - 1) * Math.max(1, Math.round(NOISE * 1000));
              data[i]     = Math.min(255, Math.max(0, data[i]     + d));
              data[i + 1] = Math.min(255, Math.max(0, data[i + 1] + d));
              data[i + 2] = Math.min(255, Math.max(0, data[i + 2] + d));
            }
            return data;
          }
          const getImageData = CanvasRenderingContext2D.prototype.getImageData;
          CanvasRenderingContext2D.prototype.getImageData = mask(function (x, y, w, h) {
            const out = getImageData.apply(this, arguments);
            jitter(out.data);
            return out;
          }, getImageData);

          const toDataURL = HTMLCanvasElement.prototype.toDataURL;
          HTMLCanvasElement.prototype.toDataURL = mask(function () {
            const ctx = this.getContext('2d');
            if (ctx && this.width > 0 && this.height > 0) {
              try {
                const img = getImageData.call(ctx, 0, 0, this.width, this.height);
                jitter(img.data);
                ctx.putImageData(img, 0, 0);
              } catch (_) {}
            }
            return toDataURL.apply(this, arguments);
          }, toDataURL);

    """.trimIndent() + "\n"

    private fun audioPatch(fp: FingerprintProfile) = """
          const A_NOISE = ${fp.audioNoise};
          if (self.AnalyserNode) {
            const getFloatFrequencyData = AnalyserNode.prototype.getFloatFrequencyData;
            AnalyserNode.prototype.getFloatFrequencyData = mask(function (array) {
              getFloatFrequencyData.apply(this, arguments);
              for (let i = 0; i < array.length; i++) array[i] += A_NOISE * ((i % 7) - 3);
            }, getFloatFrequencyData);
          }

    """.trimIndent() + "\n"

    private fun timezonePatch(fp: FingerprintProfile) = """
          const TZ = ${fp.timezone.q()};
          const DTF = Intl.DateTimeFormat;
          const resolvedOptions = DTF.prototype.resolvedOptions;
          DTF.prototype.resolvedOptions = mask(function () {
            const opts = resolvedOptions.apply(this, arguments);
            opts.timeZone = TZ;
            opts.locale = ${fp.languages.first().q()};
            return opts;
          }, resolvedOptions);

    """.trimIndent() + "\n"

    /** WebRTC is the classic VPN-defeating leak: it reports the real LAN/WAN candidates. */
    private val WEBRTC_BLOCK = """
          for (const key of ['RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCDataChannel']) {
            if (key in window) {
              try { Object.defineProperty(window, key, { value: undefined, configurable: true }); } catch (_) {}
            }
          }
          if (navigator.mediaDevices) {
            const enumerate = navigator.mediaDevices.enumerateDevices;
            navigator.mediaDevices.enumerateDevices = mask(function () {
              return Promise.resolve([]);
            }, enumerate);
          }

    """.trimIndent() + "\n"

    private val AUTOMATION_SCRUB = """
          try { Object.defineProperty(navigator, 'webdriver', { get: () => undefined, configurable: true }); } catch (_) {}
          delete window.cdc_adoQpoasnfa76pfcZLmcfl_Array;
          delete window.cdc_adoQpoasnfa76pfcZLmcfl_Promise;
          delete window.cdc_adoQpoasnfa76pfcZLmcfl_Symbol;
          if (!window.chrome) window.chrome = {};
          if (!window.chrome.runtime) window.chrome.runtime = {};
          window.chrome.csi = window.chrome.csi || function () { return {}; };
          window.chrome.loadTimes = window.chrome.loadTimes || function () { return {}; };

          // Permissions.query must not disagree with Notification.permission.
          const query = navigator.permissions && navigator.permissions.query;
          if (query) {
            navigator.permissions.query = mask(function (p) {
              if (p && p.name === 'notifications') {
                return Promise.resolve({ state: Notification.permission, onchange: null });
              }
              return query.apply(navigator.permissions, arguments);
            }, query);
          }

    """.trimIndent() + "\n"

    private val EPILOGUE = "})();\n"

    private fun String.q(): String =
        "\"" + replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\""

    private fun FingerprintProfile.platformLabel(): String = when {
        platform.startsWith("Win") -> "Windows"
        platform.startsWith("Mac") -> "macOS"
        platform.contains("armv8") -> "Android"
        else -> "Linux"
    }
}
