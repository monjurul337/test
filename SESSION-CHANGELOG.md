# Gemini cookie-session integration

## Changes
- Replaced Gemini API-key authentication with user-supplied cookie JSON on desktop and Android.
- Desktop uses the supplied Dart web client, with tighter cookie scope, redirect handling and response parsing.
- Android uses a native Kotlin port of the same handshake and StreamGenerate flow.
- Added Test Gemini session in authentication settings (live handshake plus a tiny prompt).
- Cookie JSON is held in RAM only; it is not written to preferences or publishing kits.
- Removed obsolete Gemini REST generation paths. NVIDIA API-key support remains.
- Optional Gemini cover generation now uses the web session. Image availability depends on the account and web protocol.
- Gemini model choice is web-selected; API-only token, temperature and thinking controls cannot be guaranteed.

## Checks completed
- Dart source formatting, including parsing the desktop UI file.
- Dart static analysis of the provider/authentication/image-generation modules: no issues found.
  Flutter lint rules were unavailable because the Flutter SDK was not installed.
- Dart offline tests: input formats, auth-cookie requirement, hostname/path scope, expiry,
  header sanitation, provider factory, model migration, artwork choices, canonical stream parsing,
  rejection of metadata-only responses.
- Kotlin/JVM compilation of GeminiWeb, shared key pool, Llm, Nvidia and ImageGen with Java 17.
  ImageGen compilation used a test-only Android Base64 stand-in outside this repository.
- Kotlin offline tests for the same cookie and stream boundaries, provider/model routing and artwork choices.

## Not verified
- Full Flutter desktop build, Android Compose/APK build, or installer creation.
- Real-account Gemini handshake, text/JSON generation, image generation/download, or end-to-end book generation.
- Google may change this unofficial endpoint; locally passing tests do not prove live compatibility.

Build using the existing GitHub Actions workflow. In the installed app, open Session & API keys,
paste your own session locally, press Test Gemini session, and try a short book first.
Do not include cookie exports in logs or support messages.

## Offline test entry points
- Desktop: `dart desktop/test/session_smoke.dart` (Dart VM; no reflection or dart:mirrors required).
- Android core: `app/session-tests/SessionSmoke.kt` is a standalone JVM test, outside the app source set.

## Build fix: Flutter analyzer compatibility
- Removed `dart:mirrors` and all reflection calls from `desktop/test/session_smoke.dart`.
- Kept the stream-parser checks by calling `GeminiWebClient.parseStream` directly.
- Replaced test imports from `../lib/` with package imports.
- No analyzer exclusions, suppressed errors, or deleted tests.
- Rechecked the identical Dart provider modules and smoke test in an isolated Dart-only package: static analysis and all offline tests passed. Full Flutter/Windows and APK builds still require CI.

# Theme consistency (chapters, tone, cover)

## Changes
- The planner now emits three new fields, on both desktop and Android:
  - `themeStatement` - the governing sentence (reader, transformation/central question,
    controlling image). Everything else in the book is derived from it.
  - `coverConcept` - an art-direction brief taken from the controlling image, with the
    palette, lighting and typographic feel that carry the book's tone.
  - `chapters[].themeLink` - one sentence tying each chapter back to the theme statement.
    A chapter that cannot state one is merged or replaced at planning time.
- `styleGuide` is now explicitly the one fixed tone for the whole book and must suit the
  theme statement.
- The plan prompt gained a THEME CONSISTENCY block: no chapter may stray outside the theme
  statement, no two chapters may advance the same clause the same way, and the title,
  subtitle and tagline must promise exactly what the chapters deliver.
- The chapter prompt now carries the theme statement and that chapter's theme link, and
  forbids both off-theme material and tonal drift between chapters.
- The cover prompt now builds the artwork from the controlling image rather than genre
  stock imagery, rejects interchangeable covers, matches the palette to the writing's tone,
  and requires the title area to stay legible at thumbnail size.
- The editor pass gained `theme` and `tone` issue types, and flags a cover concept that no
  longer matches the finished manuscript.

## Compatibility
- All new prompt parameters default to empty and are omitted from the prompt when blank.
- `plan.json` files written before this change still load; the new fields read as empty.

## Checks completed
- Dart static analysis of `prompts.dart`, `plan.dart`, `writer.dart`: no issues.
- Kotlin/JVM compilation of `Prompts.kt` and `Plan.kt` with Java 17.
- Offline smoke test on both platforms: all four prompts carry the theme, tone and cover
  rules; blank fields leave no stray headings; new plan fields parse and round-trip;
  legacy plans without the fields still load.

## Theme panel in the UI
- Both apps now show the theme statement, the cover concept and each chapter's
  theme link in the finished-book panel, with an Edit theme dialog.
- Edits are written back to `plan.json` and kept in app state, so a later
  New artwork, chapter rewrite or editor pass is held to the corrected theme
  without replanning the book.
- Added `BookPlan.copyWith` (desktop) and `BookPlan.toJson` (Android) to support
  the round trip; `BookResult.copyWith` now accepts a replacement plan.
- Checks: Dart analysis reports no new errors and the edited files are
  dart-format clean; `Prompts.kt` and `Plan.kt` compile under Java 17;
  `MainActivity.kt` and `Studio.kt` parse with no syntax errors (full type
  checking needs the Android SDK, which is not installed here); offline tests
  confirm theme edits round-trip through `plan.json` without losing other fields.

# Covers: FLUX.1-schnell, one picture from the title

## Changes
- Cover art now always runs on `black-forest-labs/flux.1-schnell` through
  NVIDIA, whichever model writes the prose, and it is the default instead of Off.
  `BookWriter` takes a separate `imageKeys` (desktop) / `imageKeys` constructor
  argument (Android) so the NVIDIA key reaches the image call even when the text
  provider is the Gemini web session.
- Dropped the other image choices. The picker is now Off or FLUX.1-schnell:
  - `flux.1-dev` was removed because its licence is non-commercial, which does
    not suit covers on books that are sold.
  - `stable-diffusion-3.5-large` and the Gemini web image path were removed to
    keep one predictable cover engine.
- The cover prompt now sees the book title and nothing else. No bible, no genre,
  no theme statement, no style guide. One short art-director prompt, one picture.
- Removed `coverConcept` from the plan schema, both plan models, the Theme
  dialog, the result panel and the editor pass, because nothing reads it now
  that the cover is painted from the title.
- `themeStatement` and per-chapter `themeLink` are unchanged: chapters and tone
  are still held to the theme, and the editor pass still reports theme and tone
  drift.

## Checks completed
- Dart analysis of `imagegen.dart`, `prompts.dart`, `plan.dart`, `writer.dart`:
  no issues; edited files are dart-format clean.
- Kotlin/JVM compilation of `Prompts.kt` and `Plan.kt` with Java 17;
  `ImageGen.kt`, `BookWriter.kt`, `MainActivity.kt` and `Studio.kt` parse with
  no syntax errors.
- Offline tests on both platforms: the cover prompt contains the title and none
  of the book context; chapter and editor prompts still carry the theme and tone
  rules; the plan round-trips through `plan.json` without `coverConcept`.
