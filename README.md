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

## Interface

![Interface](desktop/assets/icon/ui-preview.png)

Dark, yellow-gradient house style on both platforms. The right-hand panel is a
live **publishing checklist**: every field the storefront asks for, grouped,
with the reason behind each recommendation and a copy button on each value.
The same list writes `metadata.txt`, so the screen and the file can never drift
apart.

## Models

Two rolling aliases, so the app follows Google's current flash models without a
code change:

| model | use it for |
|---|---|
| `gemini-flash-latest` | default - best prose quality per rupee |
| `gemini-flash-lite-latest` | cheapest and fastest, good for drafts and long books |

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
cover.png      1600 x 2560, AI-generated artwork with the title typeset on top
<Title>.epub   validated EPUB 3
metadata.txt   title, blurb, BISAC, keywords, price, age rating, DRM advice
<Title>-publishing-kit.zip   all of the above in one archive
```

## Editor pass

When a book is finished, press **Editor pass**. The whole manuscript goes back
to the model as a continuity and line editor, which returns a score out of 100,
an honest verdict, and a list of real problems: contradictions in names, dates,
places or clues; repeated images and beats; filler; pacing. Every issue tied to
a chapter gets a **Rewrite chapter N** button. The report is saved as
`quality-report.md` and travels in the ZIP.

## Rewrite a single chapter

Open **Chapters** on any finished book and press **Rewrite** next to the one you
do not like. Say what should change; the chapter is rewritten against the book
bible and everything the reader knew up to that point, then the EPUB, the
metadata sheet and the ZIP are rebuilt around it. The rest of the book is
untouched.

## Cover studio

Covers are real images: the app asks Gemini's image model for the artwork
(no text on it), then typesets the title, tagline and author locally so the
words are always spelled correctly and stay crisp at print size. Press
**Cover studio** for four AI-generated options - the current one plus three
honest alternatives. Pick one, or build your own with the colour, layout
(`center`, `left`, `bottom`) and font (`serif`, `sans`) pickers, and
**Shuffle art** to draw a fresh piece of artwork. The chosen cover is written
straight into the EPUB, the `cover.png` and the ZIP.

## Front & back matter

Open **Front & back matter** before generating and the book is built with the
pages a paid title is expected to have:

* a proper copyright page (rights notice, fiction disclaimer, imprint, edition
  year, cover credit);
* an **About the author** page - yours, or the one the planner wrote;
* an **Also by** list of your other titles;
* a short, non-pushy **review request** naming Google Play Books;
* an optional **Stay in touch** page.

## Batch: many books in one run

The topic box takes **one topic per line**. Three lines means three complete
books, written back to back with the same settings, author and cover theme.

* The button becomes **Generate 3 books** and the progress bar covers the whole
  queue ("Writing book 2 of 3...").
* A book that fails does not kill the batch - the error is logged and the next
  topic starts.
* **Cancel** stops after the current book; whatever finished is kept.
* When more than one book is done you also get
  `batch-YYYY-MM-DD-N-books.zip` with every book in its own folder, plus the
  usual per-book ZIP.

## Three providers

Pick the back end in **Provider**. Each one keeps its own key pile and its own
model list, so you can switch without retyping anything.

| provider | models |
| --- | --- |
| Google Gemini | `gemini-flash-latest`, `gemini-flash-lite-latest` |
| NVIDIA (build.nvidia.com) | `z-ai/glm-5.2`, `nvidia/nemotron-3-super-120b-a12b`, `nvidia/nemotron-3-ultra-550b-a55b`, `nvidia/nemotron-3.5-lightning-30b-a3b` |
| Gemini Web (cookie session) | the web app's current flash model (no set-up model) |

NVIDIA is called through its OpenAI-compatible endpoint
(`integrate.api.nvidia.com/v1/chat/completions`) with your `nvapi-...` keys.
Nemotron's thinking mode is switched through `chat_template_kwargs`, and a
`<think>` block in the reply is stripped before the text reaches the book.
Rough guide: **glm-5.2** for most books, **nemotron-3-ultra** for a plot that
has to hold together, **nemotron-3.5-lightning** for cheap fast drafts.

The cookie-session provider talks to gemini.google.com itself with the
session you exported from your own browser - handy when the API quota is
exhausted. Paste the session JSON (a Playwright storageState or a
cookie-editor export from gemini.google.com) into the session box and hit
**Test session**. Cover artwork is painted through the session too: the app
asks the web app for the artwork, downloads the picture it draws, and
typesets the title on top. API keys are still preferred when present, and
the drawn cover remains the last resort.

## Bulk API keys

Tap the key icon and paste **as many keys as you have** into the Gemini box,
the NVIDIA box, or both - one per line (commas and spaces work too). The app:

* rotates to the next key on every request, so no single key eats the whole
  free-tier rate limit;
* parks a key for 60 seconds when it returns `429`, and for an hour when it is
  rejected outright, then carries on with the others;
* never prints a key in the log - only `key 3/8 rate limited, switching key`.

One key still works exactly as before. Keys are stored on the device only.

## Length: words or pages

**Chapters**, **Total words** and **Pages** sit next to each other and the last
two are linked: 1 page is counted as about 250 words, the same rule storefronts
use for an ebook page count. Type `80` pages and the word target becomes
`20000`; type the words and the page estimate follows. Set whichever number you
actually care about.

## Preview your book before you upload

Every finished book gets a **Preview book** button. It opens a paged reader
with the real generated cover on page one and the chapters typeset the way
an ebook reader presents them - white paper, serif text, justified
paragraphs, a page number at the foot - a close cousin of the Google Play
Books layout. Swipe or press Prev/Next, then hit **Open EPUB** to send the
real file to your favourite ereader (Play Books, Calibre, anything that
opens EPUB) for the final check.

## Downloading the result

When the book is finished the app packs every artefact into
`<Title>-publishing-kit.zip`.
* **Desktop** - press **Download ZIP** and pick where to save it.
* **Android** - press **Download ZIP (everything)**, choose a folder in the
  system file picker, or use **Share ZIP** to send it to Drive, Telegram, email
  or anywhere else.

## How the writing stays coherent

The planner first produces a **book bible**: for fiction the setting, cast,
motives, the real culprit, every clue and where it is planted, and the ending;
for non-fiction the framework and the through-line argument. Every chapter is
then written against that bible plus a **running summary** that is rewritten
after each chapter. That is what stops chapter 14 contradicting chapter 3.

## Cover themes

The theme picks the **art direction** the image model paints with:

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
