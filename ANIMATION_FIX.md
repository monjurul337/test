# Animation Studio — v1.24.4

> **REMOVED in v1.24.5 (2026-11-27):** the user set a hard rule — zero visible
> watermark on thumbnail/video, otherwise the Animation option goes entirely —
> and confirmed Veo 3 always bakes the visible Veo mark in on the Gemini-session
> route, so the whole section was deleted (`lib/animation/`,
> `lib/screens/animation_screen.dart`, Home card + toolbar button, animation
> tests). Everything below is the v1.24.4 historical record only.

New section in MJ STUDIO: portrait 9:16 charging animations from the
user's signed-in Gemini web session. **No API key anywhere in this
section** — the same session route as the Gemini image engine, not a
paid video API.

## What was added

- `lib/animation/animation_spec.dart` — fixed spec + prompt builder.
  Portrait 9:16 locked, final size exactly 1620x2880, 60fps target,
  durations 4/6/8s (default 8s), six styles (Cinematic, Neon Glow,
  Golden Luxury, Calm, Energetic, Dark Moody). Master prompt order:
  video-first lead + user prompt + style phrase + duration +
  'seamless loop' + spec suffix
  `1620x2880 vertical 9:16, 60fps, realistic, no text, no logo, no
  watermark` + a short originality clause on every prompt.
- `lib/animation/animation_models.dart` — `AnimationVideo` library
  record (JSON round-trip) and `AnimationAccountSlot`.
- `lib/animation/animation_accounts.dart` — **5 account slots**
  (Account 1–5). Each slot stores its own Gemini web session JSON in
  the OS secure storage (same place `GeminiWebStore` keeps the single
  session), plus a display email and a plan tag. Generation always
  uses the active slot's session only — no cross-slot fallback, so a
  slot can never silently spend another account's credits.
- `lib/animation/animation_driver.dart` — session driver. Checks the
  slot's session (`GeminiWebClient.test()`), then on desktop drives
  the Task prompt into the hidden signed-in Gemini tab
  (`ChromiumBrowser.evaluateOnGeminiTab`, new small CDP entry point)
  and polls the page for the finished video URL, then downloads the
  MP4. Every step is logged.
- `lib/animation/animation_postprocess.dart` — Cloudinary video
  upscale to exactly 1620x2880 (signed video upload + `w_1620,
  h_2880,c_fill` transformation), cover frame from the Cloudinary
  poster frame (ffmpeg frame grab as fallback), and a 60fps
  conversion attempt via ffmpeg `minterpolate`.
- `lib/animation/animation_publish.dart` — R2 + Firebase queue
  publish reusing `uploadFileToR2` / `pushToDatabase`. Record:
  `type video/mp4`, `isVideo true`, `contentType CHARGING_ANIMATION`,
  width 1620, height 2880, `thumbUrl`.
- `lib/animation/animation_service.dart` — accounts, batch queue
  (one line per prompt, sequential), library persistence
  (`animation_library.json`, atomic save), publish/delete, per-slot
  sign-in.
- `lib/screens/animation_screen.dart` — Accounts card (slot picker,
  email note, Pro/Free picker, Sign in / Save browser session / Test
  / Clear), Create card (prompts, style chips, duration chips,
  seamless loop), pinned Generate bar, Gallery (play, edit metadata,
  retry post-processing, upload to panel, delete), generation log.
- `lib/screens/home_screen.dart` — AppBar "Animation Studio" action
  + an Animation Studio entry card under Generate.
- `lib/browser/chromium_browser.dart` — new
  `evaluateOnGeminiTab()` (CDP `Runtime.evaluate` in the hidden
  Gemini tab) and the page `request()` now returns bytes for
  `video/*` responses too (MP4 download through the tab).

## Accounts: Pro / Free tags

**No slot is ever pre-labelled Pro — including any account named in
chat.** Every slot starts `Not set`. The tag is set only when the user
picks Pro / Free for that slot (the account itself is the source of
truth; the user updates his slots himself). The tag is never inferred
from the email. The email shown on a slot is a note the user types
himself — a session JSON carries cookies only, so the app cannot read
an email out of it.

Daily estimates shown per slot (labelled as estimates): Free ~5 Veo
Lite 8s clips/day from the daily 50 Flow credits; Pro the same daily
50 plus ~100 Lite clips/month from the 1,000 monthly Pro credits
(roughly 3 extra per day).

Per-slot sign-in: "Sign in this slot" opens the app browser and the
user signs in himself (no password is ever asked for or stored), then
the session is saved into that slot. "Save browser session" copies
whatever account is currently signed in to the app browser into the
slot. An expired session fails that slot only and the UI asks for a
re-sign-in of that slot.

One real limitation: the app browser profile is signed in to one
Google account at a time, so filling a second slot means signing in
as that account in the browser first. The saved per-slot sessions are
then used independently (cookie replay only — the driver builds its
client WITHOUT browser fallback, precisely so a dead session cannot
silently switch to another account).

## Honest limits (read before testing live)

1. **Session video flow is UNPROVEN live.** The driver types the
   Task prompt into Gemini's page DOM and polls for a video element.
   Google changes that page without notice; the first live run may
   stop at `no-composer`, `no-video-tool` or `timeout`. The driver
   log on the screen shows exactly where it stopped — report that
   step back, do not guess.
2. **Android cannot drive the Task in this build.** The built-in
   GeckoView tab has no JavaScript channel (GeckoBridge only does
   fetch/refresh/sign-in), so on Android the driver fails fast with
   `driver-unavailable-android` after the session check passes.
   Generation needs the Windows app in v1.24.4.
3. **8s max per clip.** Veo accepts 4, 6 or 8 seconds only; the UI
   offers exactly those three. The user's 10s standard is NOT
   reachable through Veo in one clip.
4. **1620x2880 and 60fps are post-processing, not native.**
   Veo generates 1080x1920 at 24fps. The size comes from the
   Cloudinary upscale (needs Cloudinary credentials, like the image
   upscale) and 60fps from ffmpeg `minterpolate`. The bundled
   Android ffmpeg is audio-only and Windows has none by default, so
   a missing ffmpeg is the normal case: the file stays 24fps and its
   card says "24fps — 60fps conversion pending". A 24fps file is
   NEVER labelled 60fps, in the UI or in the panel record.
5. **No cover, no upload.** A video record never goes out without a
   thumbnail. The cover comes from the Cloudinary poster frame (or
   an ffmpeg frame grab); when no cover can be made, publishing
   stops and says why.
6. **Model is not chosen by the app.** The signed-in Gemini page
   decides which video model serves the request (Veo 3.1 now,
   Gemini Omni as Google replaces Veo). There is no model picker in
   this route, by design.

## Tests

- `test/animation_spec_test.dart` — spec constants, duration clamp,
  six styles, master prompt order, plan-tag rules, estimates.
- `test/animation_accounts_test.dart` — five empty unlabeled slots,
  per-slot session isolation, active-slot persistence/clamping,
  per-slot plan tags, slot clearing.
- `test/animation_models_test.dart` — fps-label honesty, JSON
  round-trip, publish record shape (video/mp4, CHARGING_ANIMATION,
  1620x2880).

Full suite: run `flutter test` (see version history). The 5
pre-existing failures from the untouched v1.24.3 tree
(gemini_auth_recovery, gemini_fallback_regression, gemini_image_fast,
ringtone_screen_smoke, widget_test) are unchanged by this change.
