# Single-Account Version — ki change holo

Original `zedge-bot-v40.8` bundle e 4 ta Firebase account chilo
(zedge1-e30a0, zedge2-e8d78, zedge3-8a6ff, zedge4-36efb).
Ei version e **shudhu 1 ta account** rakha hoyeche — user er dewa config:

- projectId: `zedge2-e8d78`
- databaseURL: `https://zedge2-e8d78-default-rtdb.firebaseio.com`
- authDomain: `zedge2-e8d78.firebaseapp.com`
- storageBucket: `zedge2-e8d78.firebasestorage.app`
- messagingSenderId: `541024338424`
- appId: `1:541024338424:web:37ba73503fb1bf4983160d`
- measurementId: `G-P07Q38VYGT`
- (apiKey panel/app/desktop config e bosano ache — Firebase web config, secret na)

## Account slot name keno ZEDGE1?
Code er onek jaygay prothom account tai default/GitHub-settings er ghor
(ContentStudioApp, QueueRepository, VPN, theme, schedule fallback sob
"zedge1" key dhore). Tai sole account ta **zedge1 slot e** bosano hoyeche,
kintu oi slot er database ekhon **zedge2-e8d78** project tai. UI te account
dekhabe "Zedge 1 / ZEDGE1" — data jabe zedge2-e8d78 database e.

## Jekhane jekhane change
- `index.html` — configs e sudhu 1 entry; apps/dbs init 1 ta; header account
  dropdown e sudhu "Zedge 1"; DEFAULT_UPLOAD_WINDOWS, distOrder, VPN_ACCOUNTS,
  vpnStates, ACC_ORDER — sob e sudhu zedge1; GitHub workflow-file input sudhu Zedge 1.
- `app/.../core/Core.kt` — Accounts.all e 1 entry (zedge1 -> zedge2-e8d78 URL).
- `app/.../domain/RunSchedule.kt` — default windows sudhu zedge1 [10, 15, 20].
- `app/.../ui/MainViewModel.kt` + `DistributeScreen.kt` — distribute lekha single-account.
- `desktop/lib/config/profile_data.dart` — accounts e 1 entry (zedge1 key, zedge2-e8d78 values),
  defaultUploadWindows sudhu zedge1.
- `generator.yml` — FIREBASE_DB_MAP sudhu zedge_1 (secret ZEDGE1_DB_URL);
  target_account default zedge_1, options: zedge_1 / all_accounts (all = ei 1 tai);
  onno account er filename-style branch bad.
- `check_config.py` — ACCOUNTS = 1.
- `SECRETS.txt` — secret list single-account onujayi sajano.

## Delete kora file (onno account er bot)
- `zedge2.yml`, `zedge3.yml`, `zedge4.yml`
- `earning-zedge2.yml`, `earning-zedge3.yml`, `earning-zedge4.yml`
Rakhha hoyeche: `zedge1.yml`, `earning-zedge1.yml`, `generator.yml`, `build-all.yml`.

## GitHub Secrets (single account)
- `ZEDGE1_DB_URL` = `https://zedge2-e8d78-default-rtdb.firebaseio.com`  <-- kheyal: secret er naam ZEDGE1, value zedge2 project er URL
- `R2_WORKER_URL`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`
- Optional: `ZEDGE1_EMAIL`, `ZEDGE1_PASSWORD`, `GEMINI_SESSION`, `STABLE_AUDIO_TOKEN`

## Note
- V23–V27.12 change-note ar SETUP.md er kichu jaygay ekhono purono 4-account
  bornona thakte pare — ogula historical doc; asol config uporer list onujayi.
- R2 worker URL ager tai rakha ache (config er ongsho na, user chaile pore bodlano jabe).
- Build/run verify kora hoy ni — check_config.py PASS koreche (1 account, tin jaygay URL mileche).
