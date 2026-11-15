# MH Motion Studio (Flutter Android)

Android mobile studio for **MH Motion** (`mh_motion_t4_fixed.ipynb`), featuring:
- **Colab T4 Studio Client**: Full REST + Cookie integration with `server.py` (Shader editor, GPU check, Snapshot, NVENC MP4 render & gallery download).
- **Anti-Detect Chromium Engine**: `flutter_inappwebview` with `AT_DOCUMENT_START` fingerprint masking (Clean Mobile Chrome UA, `webdriver=false`, deterministic Canvas/WebGL/Audio noise, persistent cookies).
- **Gemini Web Cookie-Session Metadata**: Generates Adobe Stock Title, Category, and 45-49 Keywords using your logged-in `gemini.google.com` session (no API key required).
- **Adobe Stock Auto-Upload & Submit**: Uploads rendered MP4s to `contributor.stock.adobe.com`, populates metadata, and submits to Review.
- **GitHub Actions CI/CD**: Automated JDK 17 Release APK build.

## Build Release APK via GitHub Actions
1. Push this repository to GitHub.
2. Go to **Actions** -> **Build Android Release APK (JDK 17)** -> **Run workflow** (or push to `main`).
3. Download `mh-motion-studio-release-apk` from the workflow artifacts.
