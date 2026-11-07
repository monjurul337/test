# Gemini HD Studio — Flutter (Android + Windows)

Full Flutter + Kotlin port of the **Gemini HD Studio v2.5.3 Chrome extension**
(Wallpaper Set Designer, AI Metadata & Panel Uploader). One codebase builds:

- **Android release APK** — `GeminiHDStudio-v1.0.0-release.apk`
- **Windows installer** — `GeminiHDStudio-Setup-1.0.0.exe` (Inno Setup) +
  portable `GeminiHDStudio-Windows-Portable.zip`

Build both from GitHub Actions — see **BUILD-GITHUB.md** (Bangla guide).

Package: `com.geminihd.studio` · Flutter **3.24.5** · Android side **Kotlin** · JDK **17**

---

## Gemini Login — how it works (the important part)

The extension worked because Chrome was already signed into Google and it
reused the browser's cookies. A standalone app has no browser cookie jar, so
this app keeps its **own cookie jar per account (u/0–u/5)** and does the same
thing the extension did:

1. **Gemini Login screen** (top-right account icon) opens
   `gemini.google.com` in an in-app WebView with a **desktop Chrome
   user-agent**. That UA matters: Google refuses sign-in to user-agents that
   look like an embedded app browser ("This browser or app may not be
   secure"). You sign in **on Google's own page** — the app never sees or
   stores your password.
2. Tap **Connect Gemini**. The app copies the session cookies
   (`__Secure-1PSID`, `SID`, …) out of the WebView, saves them on the device,
   then **verifies** the login exactly like the extension: it fetches
   `gemini.google.com/u/<n>/app`, extracts the **SNlM0e token**, build (`bl`),
   `f.sid` and your account email.
3. All generation then runs over pure Dart HTTP with that cookie jar:
   `StreamGenerate` RPC, resumable image upload to
   `push.clients6.google.com` + `ProcessFile` for image-to-image,
   HD fetch (`=s0`), with Origin/Referer headers mirroring the extension's
   `rules.json`.
4. **Multi-account**: Scan probes u/0–u/5, the header dropdown switches
   accounts, **Add Gmail** opens Google's AddSession page in the WebView,
   and on a quota/limit reply the generator **auto-switches** to the next
   account (extension behaviour).

**Fallback (if Google still blocks the WebView on your device):** sign in at
gemini.google.com in Chrome, then paste `__Secure-1PSID` +
`__Secure-1PSIDTS` — or a full Cookie header, or a cookies.txt export — into
the **"Login blocked? Paste cookie instead"** box on the login screen. It
lands in the same cookie jar and everything after that is identical.

Cookies live only in the app's on-device storage and are only ever sent to
`gemini.google.com` / Google upload hosts. Sign out from the login screen
clears the WebView and the saved jar.

---

## Features (ported from the extension)

- **Set modes**: Single 9:16 · 9:16 + Foldable · Dual (Lock + Home) ·
  24-Hour (4 JPG) · Battery Level (6 JPG) — all at 1620×2880 JPG, ≤8 MB,
  Zedge size rules enforced.
- **Prompt batch mode** (1 line = 1 set), optional **reference image**
  (anchor), per-stage custom prompt fields, story arcs
  (Light/Bloom/Rhythm, Energy/Growth/Awakening), variation strength,
  display target, colour boost, negative prompt, **AI Set Director**.
- **Cloudinary AI upscale** (`e_upscale`) with the extension's
  sign → upload → archive/poll flow, **falling back to local resize** on
  any failure. The Cloudinary **API key** from the original extension
  (`background.js` → `CLOUDINARY_API_KEY`) is **embedded in the app**,
  same as the extension, so upscale works out of the box. It can be
  overridden in *Panel Settings → Cloudinary AI Upscale* to use a
  different Cloudinary account. ⚠️ Because the key lives in the source
  (exactly like the extension), keep the GitHub repo **private**.
- **AI listing metadata** via the Gemini web session (title ≤30 chars,
  8–12 tags, 20 official Zedge categories, description ≤200 chars) with
  copy title/tags, inline editor and Rewrite-with-AI.
- **Showcase**: set cards, image lightbox, phone **set-preview simulator**,
  **regenerate a single stage**, per-set or all-set **Ready ZIP**
  (`set-01/<slot>.jpg` + root `metadata.json` + `prompts/`), standalone
  `metadata.json`.
- **Import local set**: pick 2/4/6 images → formatted to 1620×2880 JPG,
  optional AI metadata, straight into the Showcase.
- **Upload to Panel**: R2 Worker upload with SHA-256 + Firebase Realtime
  Database queue push, Spread auto-rotation or a chosen account, Test DB —
  same record shape as the extension (`distribute.dart` port).

### Where files go (no browser downloads in an app)
- Generated sets: `<app documents>/GeminiHDStudio/Gemini_HD/<set folder>/`
- Ready ZIP / metadata.json: `<app documents>/GeminiHDStudio/Exports/`
  (the app shows the full path after export; on Windows that's under your
  Documents folder, on Android it's the app's documents directory).

## Differences from the extension (honest list)
- Images are saved as real files instead of `chrome.downloads`.
- History keeps the latest 20 sets, same as the extension.
- No background service worker: generation runs while the app is open.
- The extension zip is kept in `original-extension/` for reference.

## Signing
The release APK is signed with the **debug key** (same as the user's other
GitHub-built apps) so the artifact installs directly. For Play Store /
update-over-install with your own key, add a keystore and a release
`signingConfig` in `android/app/build.gradle`.

## Verified vs not verified
- ✅ `flutter pub get` (locked) · `flutter analyze` — **no issues** ·
  `flutter test` — **6/6 passed** (app boot, cookie-paste parsing, Zedge
  size rules, StreamGenerate response parsing, metadata JSON extraction,
  quota detection).
- ⏳ The actual GitHub Actions APK/Windows builds and a live Gemini
  generation run are the first real end-to-end test — Google can change
  the Gemini web RPC or tighten WebView sign-in at any time; the cookie
  paste fallback covers the sign-in case.
