# Softizence Browser

A cross-platform browser for **Android** and **Desktop** (Windows / Linux / macOS), built with
Kotlin Multiplatform + Compose Multiplatform.

Three things make it different from a generic WebView wrapper:

1. **Obsidian & Brass UI** — a lacquered dark shell with a vertical tab rail, a security-aware
   omnibox and a tunnel badge that proves where your traffic exits.
2. **Anti-detect by construction** — one *coherent* device persona per browsing profile, not a
   pile of independently randomised values.
3. **Tunnel-exclusive networking** — drop in a Proton VPN `.conf` and the whole browser rides it,
   with a kill switch instead of a silent fallback.

---

## Project structure

```
SoftizenceBrowser/
├── settings.gradle.kts
├── build.gradle.kts
├── gradle.properties                 # version + BUILD_PROFILE
├── gradle/libs.versions.toml         # version catalog
├── .github/workflows/build-all.yml   # APK + MSI/DEB/DMG in one run
├── config/config.example.json        # the full configuration surface
└── composeApp/
    ├── build.gradle.kts
    └── src/
        ├── commonMain/kotlin/com/softizence/browser/
        │   ├── core/
        │   │   ├── config/     AppConfig.kt, ConfigStore.kt
        │   │   └── model/      Models.kt, FingerprintProfile.kt
        │   ├── browser/        BrowserEngine.kt           (expect)
        │   ├── privacy/        StealthScripts.kt, PrivacyPolicyEngine.kt
        │   ├── net/            WireGuardConfig.kt, TunnelController.kt,
        │   │                   TunnelManager.kt, FileWireGuardConfigStore.kt,
        │   │                   KtorPublicIpResolver.kt
        │   ├── extensions/     Mv3Manifest.kt, ExtensionHost.kt,
        │   │                   MatchPattern.kt, DnrRules.kt
        │   ├── session/        SessionVault.kt
        │   ├── di/             AppGraph.kt
        │   └── ui/             SoftizenceApp.kt, BrowserViewModel.kt,
        │                       SettingsPanel.kt, theme/, components/, screens/
        ├── androidMain/
        │   ├── AndroidManifest.xml
        │   └── kotlin/com/softizence/browser/
        │       ├── MainActivity.kt, SoftizenceApplication.kt, Platform.android.kt
        │       ├── browser/    WebViewBrowserEngine.kt
        │       ├── net/        AndroidTunnelController.kt, SoftizenceVpnService.kt
        │       ├── extensions/ AndroidExtensionHost.kt
        │       └── session/    AndroidSessionVault.kt
        └── desktopMain/kotlin/com/softizence/browser/
            ├── main.kt, Platform.desktop.kt
            ├── browser/        CefBrowserEngine.kt
            ├── net/            DesktopTunnelController.kt
            ├── extensions/     DesktopExtensionHost.kt
            └── session/        DesktopSessionVault.kt
```

## Architecture

```
            ┌──────────────── Compose UI (commonMain) ────────────────┐
            │  SoftizenceApp → TabRail · Omnibox · TunnelBadge · Panels │
            └───────────────────────────┬─────────────────────────────┘
                                        │
                              BrowserViewModel
             ┌──────────────┬───────────┴──────────┬──────────────────┐
             ▼              ▼                      ▼                  ▼
      BrowserEngine   TunnelManager         ExtensionHost        ConfigStore
       (expect)       (+ TunnelController)   (expect)            SessionVault
             │              │                      │
   ┌─────────┴───┐   ┌──────┴────────┐    ┌────────┴────────┐
   │ WebView     │   │ VpnService +  │    │ DNR + content-  │   Android
   │ (Android)   │   │ wireguard-go  │    │ script subset   │
   ├─────────────┤   ├───────────────┤    ├─────────────────┤
   │ JCEF/KCEF   │   │ wg-quick /    │    │ --load-extension│   Desktop
   │ (Chromium)  │   │ wireguard.exe │    │ (full MV3)      │
   └─────────────┘   └───────────────┘    └─────────────────┘
```

`BrowserViewModel` is the only place the four subsystems meet, and it enforces the product's
central invariant: **navigation is gated on `NetworkMode`**.

| Situation | `NetworkMode` | Behaviour |
|---|---|---|
| No `.conf` imported | `Direct` | Browses normally, badge says "Direct" |
| Configs present, none active | `Direct` | Browses normally |
| Tunnel up | `Tunnelled` | All traffic via WireGuard, public IP shown |
| Tunnel expected but down, kill switch on | `Blocked` | Navigation refused — no leak |

## 1. UI/UX

- **Obsidian & Brass** (`ui/theme/Theme.kt`): near-black lacquer surfaces, brass reserved for
  state that matters — tunnel status, active tab, focus ring, load progress.
- **Adaptive, not duplicated**: one shell. Wide windows get the vertical tab rail and docked side
  panels; narrow windows collapse to a bottom-anchored omnibox. The breakpoint is window width,
  not `Platform.isAndroid`.
- **Omnibox as a security control**: the leading glyph is brass-lock for HTTPS, muted globe for
  plain HTTP, magnifier for a search — so the address bar communicates risk before you press Go.
- **Tunnel badge**: shows the exit name *and* the independently-observed public IP. It never
  claims protection it cannot prove.
- **Home** (`softizence://home`): wordmark, live network truth, user shortcuts. No feed, no tiles,
  no telemetry.

## 2. Browser core, extensions & sessions

**Desktop — real Chromium.** `CefBrowserEngine` runs JCEF via KCEF. MV3 extensions are genuinely
hosted: `DesktopExtensionHost` validates each unpacked folder and passes
`--load-extension` / `--disable-extensions-except`, so Chromium itself runs the service workers,
`chrome.*` APIs, popups and declarativeNetRequest. Switches are read at start-up, so toggling an
extension flags `restartRequired` rather than pretending it applied.

**Android — the honest subset.** WebView has no extension runtime. `AndroidExtensionHost` compiles
each manifest down to what WebView *can* do — content-script injection and DNR URL blocking in
`shouldInterceptRequest` — and reports everything else in `ExtensionInfo.loadError`, surfaced in
the UI as "Partially loaded — unsupported on Android: …".

**Sessions.** Cookie jars and storage are partitioned per `BrowsingProfile`. CEF uses a persistent
cache path with `persistSessionCookies`, so logins survive restarts. Tabs and the active tunnel are
snapshotted to an encrypted `WorkspaceSnapshot` (Android Keystore / AES-256-GCM keyfile).

## 3. Anti-detect & fingerprint masking

`FingerprintProfile.forSeed()` picks **one coherent persona** and derives every surface from it.
Randomising each surface independently makes you *more* unique, not less — a Windows UA with a
Metal GPU string and an Asia/Dhaka timezone behind a Swiss exit IP is a signature.

`StealthScripts.documentStart()` is injected before any page script runs
(`WebViewCompat.addDocumentStartJavaScript` / CEF `onLoadStart`) and covers:

- `navigator` UA, platform, vendor, languages, cores, memory, **and `userAgentData`** kept in sync
- `screen` metrics and `devicePixelRatio`
- WebGL `UNMASKED_VENDOR/RENDERER`
- Canvas and AudioContext — deterministic *sub-perceptual* jitter, not zeroing (an all-zero canvas
  hash is itself a fingerprint)
- `Intl.DateTimeFormat` timezone, **auto-matched to the tunnel's exit country**
- WebRTC removed entirely (the classic real-IP leak behind a VPN)
- `navigator.webdriver`, `cdc_*` globals, `chrome.runtime`, `Permissions.query` consistency

Every patched function keeps a native-looking `toString()`, because
`Function.prototype.toString.call(fn).includes('[native code]')` is the most common detection probe.

Network-layer masking (`PrivacyPolicyEngine`) handles UA client hints, `DNT`/`Sec-GPC`, HTTPS
upgrade, tracking-parameter stripping (`utm_*`, `gclid`, `fbclid`…) and tracker-host blocking.

## 4. Advanced networking — Proton VPN WireGuard

**`WireGuardConfigParser`** reads `wg-quick` files exactly as Proton emits them, including the
`# CH-FR#1` peer comment it uses as the exit label (which becomes the country for timezone
matching). Malformed files produce actionable messages, never a silent half-tunnel. Import is
rejected outright if `AllowedIPs` is not `0.0.0.0/0` — a partial tunnel would leak.

**Android** (`AndroidTunnelController`): the original `.conf` text is handed to the official
`com.wireguard.config.Config.parse` and brought up through `GoBackend`. We never re-serialise it —
lossy round-trips are how split-tunnel leaks get introduced. `SoftizenceVpnService` uses
`setBlocking(true)` with a `0.0.0.0/0` route, so when the tunnel is down packets are dropped rather
than re-routed over Wi-Fi. `onRevoke` surfaces revocation as an error instead of falling back.

**Desktop** (`DesktopTunnelController`) executes the `.conf` directly, trying in order:

1. `wg-quick up <file>` — Linux/macOS
2. `wireguard.exe /installtunnelservice <file>` — Windows
3. `wireguard-go` + `wg setconf` + `ip route add default dev softizence0` — userspace fallback

The file is written 0600, used, then overwritten and deleted. Missing tools or missing elevation
become readable errors ("Administrator rights are required…") — never a false "connected".

**Proof of routing.** `KtorPublicIpResolver` queries neutral echo endpoints *after* the tunnel is
up, so the IP shown in the badge is independently observed, not vendor-reported. `refreshStatistics`
parses `wg show <iface> dump` for rx/tx and handshake age; a handshake older than 180 s flips the
state to `Reconnecting` instead of leaving a dead interface looking healthy.

**Fallback.** With zero configs imported the controller stays `Off` and browsing is direct and
clearly labelled. The fallback is a deliberate state, not an accident.

## 5. Configuration & extensibility

Everything tunable lives in one versioned document — `<configDir>/config.json`, mirrored in
`config/config.example.json`: appearance, search engines, privacy defaults, tunnel policy,
extension search paths, per-profile identities and feature flags.

- Atomic writes (temp + rename); a corrupt file is quarantined as `config.json.broken` rather than
  crashing the app.
- `schemaVersion` with a migration chain.
- Unknown keys are ignored on read, so a newer build's settings survive a downgrade.
- Config directories follow each OS convention (`%LOCALAPPDATA%`, `~/Library/Application Support`,
  `$XDG_DATA_HOME`).

## Building

```bash
# Android debug APK
./gradlew :composeApp:assembleDebug

# Desktop, run from source
./gradlew :composeApp:run

# Native installers
./gradlew :composeApp:packageReleaseMsi    # Windows
./gradlew :composeApp:packageReleaseDeb    # Linux
./gradlew :composeApp:packageReleaseDmg    # macOS
```

CI: **Actions → Build All Apps → Run workflow**. Tag `v*` to publish a Release with the APK and all
installers attached.

Requirements: JDK 17, Android SDK 35. Desktop tunnelling needs WireGuard installed
(`wg-quick` on Linux/macOS, the WireGuard service on Windows) and elevation to create the TUN device.

## Known gaps before shipping

- KCEF downloads the JCEF bundle on first launch; ship it pre-seeded for an offline installer.
- Desktop release packaging runs with ProGuard disabled. JCEF's reflective/native entry points
  are not resolvable by the shrinker, and the bundle size is dominated by Chromium anyway.
- Placeholder artwork: `composeApp/icons/app.{png,ico,icns}` and the Android adaptive launcher are
  real, valid, buildable assets, but they are a generated monogram — replace with final branding.
- Android's MV3 subset is intentionally partial. If full extension support on mobile is required,
  the path is GeckoView's WebExtensions API, not WebView.
