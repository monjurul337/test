# Threat model & leak checklist

## What Softizence defends against

| Threat | Mitigation | Where |
|---|---|---|
| Real IP exposed by WebRTC | `RTCPeerConnection` removed; Chromium launched with `--force-webrtc-ip-handling-policy=disable_non_proxied_udp` | `StealthScripts`, `CefBrowserEngine` |
| Traffic leaking when the tunnel drops | Kill switch gates navigation at the `NetworkMode` level; `VpnService.setBlocking(true)` | `TunnelManager`, `SoftizenceVpnService` |
| Partial-tunnel config | Import refuses configs without `AllowedIPs = 0.0.0.0/0` | `TunnelManager.import` |
| Dead tunnel reported as healthy | Handshake age > 180 s → `Reconnecting` | `DesktopTunnelController.refreshStatistics` |
| Vendor-reported "you are protected" | Public IP resolved from neutral third parties *after* connect | `KtorPublicIpResolver` |
| Timezone / exit-country mismatch | Spoofed timezone derived from the peer's country label | `BrowserViewModel.applyTimezoneFor` |
| Naive stealth scripts being detected | Native `toString()` preserved on every patched function | `StealthScripts` |
| Canvas scrambling detected as scrambling | Deterministic sub-perceptual noise, stable per profile | `FingerprintProfile`, `StealthScripts` |
| Stolen config folder yields WireGuard keys | Sealed at rest; keys in Android Keystore / AES-GCM keyfile | `FileWireGuardConfigStore`, vaults |
| Private key lingering on disk during connect | 0600 temp file, overwritten and deleted after use | `DesktopTunnelController` |
| QUIC bypassing a userspace tunnel | `--disable-quic` | `CefBrowserEngine` |

## What it does **not** defend against

- **Traffic analysis / timing correlation.** WireGuard is not a mixnet. A global observer can still
  correlate.
- **Account-level deanonymisation.** Logging into a real account defeats fingerprint masking entirely.
- **Malicious extensions.** A loaded MV3 extension runs with the permissions its manifest requests.
  Only load extensions you trust.
- **A compromised host OS.** Keystore and DPAPI assume the device itself is not owned.
- **Proton's own logs.** This app verifies *routing*, not the provider's policy.

## Pre-release leak test

1. Import a Proton config, connect, confirm the badge IP matches the exit.
2. Visit `browserleaks.com/webrtc` — no local or public candidates.
3. Visit `creepjs` — persona must be internally consistent and **stable across restarts**.
4. Kill the tunnel mid-download. Navigation must be refused, not silently resumed.
5. Revoke the VPN permission on Android (Settings → VPN). The badge must go red, not green.
6. Delete all configs. The app must browse direct and *say* "Direct".
