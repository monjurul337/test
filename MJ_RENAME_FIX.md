# Rename: MH STUDIO -> MJ STUDIO + Firebase project change (v1.24.1+63)

## His order (2026-11-27)
- App name now **MJ STUDIO**.
- Package name also changed.
- Firebase Authentication moved to his new project **r-final-f0c62**.

## Firebase (new project)
- `lib/cloud_sync.dart`: `_apiKey` = new project's Web API key (public client
  key, from the firebaseConfig he pasted), `defaultDbUrl` =
  `https://r-final-f0c62-default-rtdb.firebaseio.com`.
- `CLOUD_SYNC_SETUP.md`: project name + DB URL updated to r-final-f0c62.
- Auth is still plain Firebase REST (no SDK, no google-services.json).
  Console steps for the new project (his to confirm): Email/Password
  enabled, Realtime Database created, per-user `/users/$uid` rules published.
- Old project `mh-studio-official` accounts/data do NOT carry over:
  create a fresh MJ STUDIO account in the app on the new project.

## Rename
- Display name: `MH STUDIO` -> `MJ STUDIO` (app title, Home header,
  Settings About, login screen, toasts, notifications, Android label,
  Windows exe metadata + window title, installer, CI workflow + release).
- Dart package: `ai_image_studio` -> `mj_studio` (pubspec + all
  `package:mj_studio/...` imports in lib/ and test/, app class
  `AiImageStudioApp` -> `MjStudioApp`).
- Android/Kotlin package: `com.aistudio.ai_image_studio` ->
  `com.mjstudio.mj_studio` (all Kotlin files, patch_android.py,
  CI `flutter create --org com.mjstudio --project-name mj_studio`,
  rotation test expectation).
- File-name form: `MHStudio` -> `MJStudio` (`MJStudio.exe`,
  `MJStudio-windows-x64-...`, `MJStudio-v...-release.apk`).
- Keystore throwaway alias: `aiimagestudio` -> `mjstudio`.
- Browser extension id: `ais-cookies@aistudio` -> `ais-cookies@mjstudio`.

## Deliberately NOT changed
- `NAME_FIX.md` / `LOGO_FIX.md`: historical rename/logo notes, kept as-is.
- Internal `ais_cookies` asset folder name and `__aisTouchUI` flag:
  internal identifiers only, renaming them risks the Android patch.
- Windows installer AppId GUID: unchanged, so the installer upgrades
  the old MH install in place on Windows. Android is a NEW package, so
  it installs as a separate app — uninstall the old MH STUDIO APK first
  to avoid two apps side by side.
- Version bumped 1.24.0+62 -> 1.24.1+63 so the new build is distinguishable.

## Verification
- grep: no `MH STUDIO` / `ai_image_studio` / `com.aistudio` /
  `mh-studio-official` left in code, CI or docs (except the two
  historical docs above).
- `flutter analyze` + `flutter test` run locally before delivery (see
  delivery message for the result). NOT live-tested on his phone/PC —
  first live check: launcher label + login screen must read MJ STUDIO,
  then Create account on the new Firebase project.
