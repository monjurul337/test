# Moxixo Antidetect Browser

Multi-profile browser manager built with **Electron + Node.js** by **Moxixo** (Founder & CEO: Monjurul Islam).

Run many accounts side by side — every profile is a fully separate browser identity on your own device.

## What it does

- **Isolated profiles** — each profile has its own persistent session partition: separate cookies, cache, localStorage and login state. Nothing leaks between profiles.
- **Per-profile proxy** — HTTP / HTTPS / SOCKS5, with username + password auth. One profile = one exit IP.
- **VPN config per profile (v1.2)** — import or paste a **WireGuard `.conf`** or **OpenVPN `.ovpn`** file in the profile editor (Connection → VPN). WireGuard runs *per profile* in userspace via the bundled **wireproxy** engine (config is turned into a local SOCKS5 tunnel — no admin rights, other apps unaffected, each profile can use a different VPN). OpenVPN uses your installed OpenVPN client and is *system-wide* while that profile runs (one at a time; Windows needs Administrator). Config type and server endpoint are auto-detected; invalid configs are rejected with a clear reason before launch. VPN keys stay in the local profile store on your device only.
- **Consistent fingerprint per profile** — user-agent preset (Windows Chrome/Edge, macOS Chrome, Linux Chrome), screen resolution, language, timezone (applied via Chrome DevTools Protocol `Emulation.setTimezoneOverride`), plus a stable hardware profile (CPU cores / memory) derived from the profile ID so it never drifts between launches. `navigator.webdriver` is hidden.
- **Proxy / IP checker** — one click loads an IP echo service *inside* the profile's own session and shows the real exit IP, city, country and ISP.
- **Dashboard** — create, edit, clone, delete, group, search and filter profiles; live running status; import/export of profile settings as JSON.
- **Private by design** — all cookies and profile data stay in the app's local data folder on your device. No server, no telemetry.

## Run locally (development)

```bash
npm install
npm start
```

## Build installers locally

```bash
npm install
npm run dist:win    # Windows NSIS installer + portable .exe
npm run dist:mac    # macOS .dmg
npm run dist:linux  # Linux AppImage + .deb
```

Output goes to `dist/`.

## Build with GitHub Actions (no local setup)

See **[BUILD-GITHUB.md](BUILD-GITHUB.md)** — push this repo to GitHub, open the
**Actions** tab, run **“Build Moxixo Antidetect Browser”**, then download the
installers from the run's **Artifacts**. Pushing a tag like `v1.0.1` also
publishes a GitHub Release with all three platforms attached.

## Honest limitations (v1.0)

Electron's Chromium is a real browser kernel, so profile isolation, proxies,
timezone, language and user-agent are genuinely applied. What this version does
**not** do is low-level canvas/WebGL/audio noise spoofing — commercial tools
like Multilogin patch the browser kernel for that. For multi-account work, the
biggest factors are session isolation, one clean proxy per profile, and a
*consistent* identity (proxy country = timezone = language), which this app
handles. Keep those three aligned for every profile.

## Project structure

```
main.js               Electron main process — sessions, proxy, launch, IPC
preload.js            Safe bridge for the dashboard
src/index.html        Dashboard UI
src/styles.css        MostLogin-style light theme (sidebar + profile table)
src/renderer.js       Dashboard logic
src/fingerprint.js    UA presets, resolutions, fingerprint injection script
.github/workflows/    GitHub Actions build (Windows / macOS / Linux)
```

## License

MIT © 2026 Moxixo — Monjurul Islam
