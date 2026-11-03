'use strict';
// Shared fingerprint helpers: UA presets + the script injected into every
// profile page so each profile presents one consistent device identity.

const CHROME_VERSION = '128.0.0.0';

const UA_PRESETS = [
  {
    id: 'win-chrome',
    label: 'Windows 10/11 — Chrome',
    os: 'Windows',
    platform: 'Win32',
    userAgent:
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/' +
      CHROME_VERSION +
      ' Safari/537.36'
  },
  {
    id: 'win-edge',
    label: 'Windows 10/11 — Edge',
    os: 'Windows',
    platform: 'Win32',
    userAgent:
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/' +
      CHROME_VERSION +
      ' Safari/537.36 Edg/128.0.0.0'
  },
  {
    id: 'mac-chrome',
    label: 'macOS — Chrome',
    os: 'macOS',
    platform: 'MacIntel',
    userAgent:
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/' +
      CHROME_VERSION +
      ' Safari/537.36'
  },
  {
    id: 'linux-chrome',
    label: 'Linux — Chrome',
    os: 'Linux',
    platform: 'Linux x86_64',
    userAgent:
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/' +
      CHROME_VERSION +
      ' Safari/537.36'
  }
];

const RESOLUTIONS = [
  { id: '1920x1080', label: '1920 × 1080 (Full HD)', width: 1920, height: 1080 },
  { id: '1366x768', label: '1366 × 768 (Laptop)', width: 1366, height: 768 },
  { id: '1536x864', label: '1536 × 864', width: 1536, height: 864 },
  { id: '1440x900', label: '1440 × 900', width: 1440, height: 900 },
  { id: '2560x1440', label: '2560 × 1440 (QHD)', width: 2560, height: 1440 },
  { id: '1280x720', label: '1280 × 720 (HD)', width: 1280, height: 720 }
];

const LANGUAGES = [
  { id: 'en-US', label: 'English (US)', value: 'en-US' },
  { id: 'en-GB', label: 'English (UK)', value: 'en-GB' },
  { id: 'bn-BD', label: 'Bangla (Bangladesh)', value: 'bn-BD' },
  { id: 'hi-IN', label: 'Hindi (India)', value: 'hi-IN' },
  { id: 'es-ES', label: 'Spanish (Spain)', value: 'es-ES' },
  { id: 'pt-BR', label: 'Portuguese (Brazil)', value: 'pt-BR' },
  { id: 'id-ID', label: 'Indonesian', value: 'id-ID' },
  { id: 'vi-VN', label: 'Vietnamese', value: 'vi-VN' },
  { id: 'ru-RU', label: 'Russian', value: 'ru-RU' },
  { id: 'zh-CN', label: 'Chinese (China)', value: 'zh-CN' }
];

const TIMEZONES = [
  'Asia/Dhaka', 'Asia/Kolkata', 'Asia/Dubai', 'Asia/Singapore',
  'Europe/London', 'Europe/Berlin', 'Europe/Moscow',
  'America/New_York', 'America/Chicago', 'America/Los_Angeles',
  'America/Sao_Paulo', 'Australia/Sydney', 'Pacific/Auckland', 'UTC'
];

// Small deterministic hash so a profile's hardware values never drift
// between launches (consistency matters more than randomness).
function seedFromString(str) {
  let h = 2166136261;
  for (let i = 0; i < String(str).length; i++) {
    h ^= String(str).charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return Math.abs(h >>> 0);
}

function hardwareForSeed(seed) {
  const cores = [4, 6, 8, 8, 12, 16][seed % 6];
  const memory = [4, 8, 8, 16][seed % 4];
  return { cores, memory };
}

// Script executed in the profile window on every page load (dom-ready).
// Overrides the navigator/screen values a site can read, consistently
// per-profile, and hides the automation flag.
function buildInjection(profile) {
  const preset = UA_PRESETS.find((p) => p.id === profile.uaPreset) || UA_PRESETS[0];
  const res =
    RESOLUTIONS.find((r) => r.id === profile.resolution) || RESOLUTIONS[0];
  const seed = seedFromString(profile.id || profile.name || 'moxixo');
  const hw = hardwareForSeed(seed);
  const lang = profile.language || 'en-US';
  const cfg = {
    platform: preset.platform,
    language: lang,
    languages: [lang, lang.split('-')[0], 'en'],
    cores: hw.cores,
    memory: hw.memory,
    width: res.width,
    height: res.height,
    colorDepth: 24
  };
  return `
;(() => {
  const cfg = ${JSON.stringify(cfg)};
  const def = (obj, prop, value) => {
    try { Object.defineProperty(obj, prop, { get: () => value, configurable: true }); } catch (e) {}
  };
  def(Navigator.prototype, 'platform', cfg.platform);
  def(Navigator.prototype, 'language', cfg.language);
  def(Navigator.prototype, 'languages', Object.freeze(cfg.languages.slice()));
  def(Navigator.prototype, 'hardwareConcurrency', cfg.cores);
  def(Navigator.prototype, 'deviceMemory', cfg.memory);
  def(Navigator.prototype, 'webdriver', false);
  def(Screen.prototype, 'width', cfg.width);
  def(Screen.prototype, 'height', cfg.height);
  def(Screen.prototype, 'availWidth', cfg.width);
  def(Screen.prototype, 'availHeight', Math.max(0, cfg.height - 40));
  def(Screen.prototype, 'colorDepth', cfg.colorDepth);
  def(Screen.prototype, 'pixelDepth', cfg.colorDepth);
  try { delete navigator.__proto__.webdriver; } catch (e) {}
})();`;
}

module.exports = { UA_PRESETS, RESOLUTIONS, LANGUAGES, TIMEZONES, buildInjection, seedFromString };
