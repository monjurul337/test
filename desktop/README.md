# Book Generator
**Meta Hawladar Team**

![Book Generator](desktop/assets/icon/brand-logo-dark.png)

Give it a topic. It plans the book, writes every chapter, renders the cover,
builds a validated EPUB, and fills in every field the storefront upload form
asks for.

One repository, two apps, one build:

| folder | app | language | output |
|---|---|---|---|
| `desktop/` | Windows / Linux / macOS | Dart (Flutter) | installer, portable zip, tar.gz, .app |
| `app/` | Android | Kotlin (Jetpack Compose) | signed APK |

Both apps contain the same pipeline, written natively for each platform - no
server, no backend. The only network call is to the Gemini API with your own key.

## Build

1. Push this whole folder to one GitHub repository, keeping `desktop/` and
   `app/` side by side at the repo root.
2. GitHub -> **Actions** -> **Build All Apps** -> **Run workflow** -> choose
   targets (default `android+windows`) -> **Run workflow**.
3. When it finishes, open the run -> **Artifacts** -> download the APK and the
   Windows installer.

Tag a version to publish one GitHub Release with everything attached:

```
git tag v1.0.0 && git push --tags
```

### Android signing

Add these repository secrets before distributing
(*Settings -> Secrets and variables -> Actions*):

```
KEYSTORE_BASE64   base64 of your release.keystore
KEYSTORE_PASSWORD
KEY_ALIAS
KEY_PASSWORD
```

Without them CI generates a throwaway key, so the APK installs for testing but
every build is signed differently and users cannot update in place.

## Using the app

1. Open it and tap the key icon. Paste a Gemini API key - get one free at
   <https://aistudio.google.com/apikey>. It is stored only on your device.
2. Type a topic, pick Fiction or Non-fiction, set chapters and total words.
3. Press **Generate book**.

You get a folder containing:

```
plan.json      the book bible, blurb, keywords, chapter briefs
summary.txt    the running story-so-far used to keep chapters consistent
chapters/      one Markdown file per chapter
cover.png      1600 x 2560, ready for any store
<Title>.epub   validated EPUB 3
metadata.txt   title, blurb, BISAC, keywords, price, age rating, DRM advice
```

## How the writing stays coherent

The planner first produces a **book bible**: for fiction the setting, cast,
motives, the real culprit, every clue and where it is planted, and the ending;
for non-fiction the framework and the through-line argument. Every chapter is
then written against that bible plus a **running summary** that is rewritten
after each chapter. That is what stops chapter 14 contradicting chapter 3.

## Cover themes

`ember` warm night - mystery, thriller, drama
`frost` cold blue - noir, winter, literary
`forest` green-gold - cozy, rural, historical
`rose` pink-violet - romance, women's fiction
`slate` dark tech - business, non-fiction, self-help
`sand` warm neutral - memoir, essays, guides

Leave the theme on **auto** and the planner picks one to match the genre.

## Upload defaults the metadata sheet already recommends

- DRM: **No**
- Preview limit: **20%**
- Allow pre-orders: **No** - switch to Yes only for book 2 or later in a series
- Maximum age: leave blank
- ISBN: leave blank, the distributor assigns one free

## Repository layout

```
.github/workflows/build-all.yml   one workflow builds everything
desktop/
  lib/main.dart                   Flutter UI
  lib/src/gemini.dart             Gemini REST client (dart:io, no packages)
  lib/src/prompts.dart            every model-facing prompt
  lib/src/plan.dart               planner output model
  lib/src/writer.dart             plan -> chapters -> cover -> EPUB
  lib/src/cover.dart              cover renderer and the six themes
  lib/src/epub.dart               EPUB 3 builder
  lib/src/zipwriter.dart          ZIP writer (mimetype must be stored first)
  lib/src/markdown.dart           Markdown -> XHTML
  lib/src/metadata.dart           the upload sheet
  assets/icon/                    app icons for every platform
  installer/windows.iss           Inno Setup script
app/
  app/build.gradle.kts            versionName lives here
  app/src/main/java/com/metahawladar/bookgenerator/
    MainActivity.kt               Compose UI
    Gemini.kt  Prompts.kt  Plan.kt  BookWriter.kt
    CoverRenderer.kt  EpubBuilder.kt  Markdown.kt  MetadataSheet.kt
```
