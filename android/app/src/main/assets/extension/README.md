# Play Books Auto Uploader — Chrome Extension

**Version 9.1** — metadata-parser fixes + all-black panel theme:

- **Description is no longer truncated.** Inside DESCRIPTION / FULL DESCRIPTION /
  AUTHOR BIOGRAPHY blocks, only a real ALL-CAPS heading ends the block, so a
  normal sentence like `Price: it is not about money…` stays in the description.
- **More date formats.** `2026-11-15`, `November 15, 2026`, `Nov 15, 2026` and
  `15 November 2026` are all read. If a date really cannot be read, the panel and
  log now warn instead of silently using today + 4 days.
- **BISAC codes stripped with or without a dash.** `BUS070030 BUSINESS & ECONOMICS / …`
  works the same as `BUS070030 — BUSINESS & ECONOMICS / …`, so the genre picker
  gets a clean full path.
- **Real currency detection.** Any ISO code in the price line (BDT, INR, EUR, …) is
  used as-is and flagged in the panel, instead of being silently treated as USD.
  A price with no currency code is flagged too.
- **New warning area** in the panel summary (and ⚠ lines in the log at run start)
  listing everything the parser had to guess.
- **Design:** the panel, the floating button, the file cards and the log are now
  pure black (#000) with thin light borders and a violet accent on Run only.

---

**Version 9.0 (final)** — fixes from manually completing a real book
(GGKEY:D0QK26QCZJL) in the live console:

- **Wizard-less books handled.** Some books have no "Pricing" nav item
  and no release-date field. The Pricing stage now opens the pricing
  page directly by URL (`#book/<GGKEY>/jc=true/pricing`), clicks the
  page's **"Retry"** link if it first renders an error, and only then
  looks for the amount field.
- **Save clicks wait for enablement.** Angular keeps Save disabled
  until the form is valid; the extension now waits for an enabled Save
  button instead of clicking a disabled one and misreading the result.
- **Verify is honest about the Review page.** The price check falls
  back to the Pricing page when the Review page shows no price row,
  and genre checks compare case-insensitively (Review prints genre
  paths in Title Case, metadata carries BISAC upper case).
- **Deactivated-book publish flow.** Publish also recognises the
  "Sell on Google Play" activation button and Sell/Confirm dialogs,
  and a "Deactivated" status is read back as itself — never as
  "published" and never silently as "unknown".
- Console quirk worth knowing: the BISAC code for "Business &
  Economics / Industries / Computers & Information Technology" is
  **BUS070030** (not BUS070040); the extension matches genres by full
  path, so either code in a metadata file is harmless.

**Version 8.0** — live-recon fixes: the Subtitle field is revealed via
the "Add a subtitle" button before filling; the Genres stage drives
the real row-based picker (one searchable combobox per row,
suggestions matched exactly by full path); the create stage first
searches the catalog for the exact title and resumes an existing book
instead of duplicating it.

**Version 7.0** — full visual redesign of the in-page panel and floating
button: purple glassmorphism on a near-black background, gradient accents,
fully rounded pill buttons, glass file/summary/log cards. Design only —
all behaviour is unchanged from 6.0.

**Version 6.0** — reliability patch driven by a full audit of the stage
automation (see `AUDIT.md`) plus live verification of the create page:

- **Create flow fixed for the real page.** The "Add a book" form needs
  **two** selections, and both are now made and *verified by reading the
  control back*: first "Sell ebook on Google Play", then — in the second
  dropdown that appears — "Get a Google book ID (GGKEY)". Only then does
  "Save & Continue" enable. The book-ID step is required, never skipped.
- **Exact matching everywhere.** Option pickers (DRM, preview,
  copy/paste, currency, roles…) match option text *exactly* and read the
  chosen value back before continuing — "0%" can never silently become
  "10%" or "20%" again, and "No" never matches "None".
- **Saves are verified.** After each Save, the stage re-reads its
  critical values (title, page count, description, the three Settings
  values, price…) and fails loudly if they didn't stick.
- **No duplicates on retry.** If a stage is retried, Create resumes the
  book the previous attempt already created; Genres and Contributors
  skip entries that are already there.
- **Per-file upload confirmation.** The EPUB and the cover are each
  confirmed by their own new row on the Content tab (a leftover
  "Successfully uploaded" banner from the other file no longer counts),
  and upload/EpubCheck errors fail fast with the row text quoted.
- **Processing reads the current file only.** The processing poll reads
  the row of the *current* EPUB version — a previous version's failed
  row can neither halt the job nor mark it done.
- **Stronger Verify.** The Review check now also verifies the
  description, both dates, the page count (read from its field) and all
  three Settings values (DRM / preview / copy-paste).
- **Honest publish reporting.** The catalog status is read from the
  book's own page/row. If it can't be verified, the job reports
  "publish NOT verified" instead of claiming the book was published.
- **Lighter polling.** The DOM polling that made the page feel heavy
  was reduced (slower poll interval, cheaper text matching).

**Version 5.0** — **smart ZIP upload**. Instead of picking three files,
you can pick a single ZIP; the extension reads it in the page (no external
library), finds the EPUB, the cover image and the metadata .txt inside —
whatever their filenames or folders — shows you what it detected, and then
runs exactly as if you had picked the three files individually.

**Version 4.0** — new UI model. There is **no popup** any more, and clicking
Run **never opens or closes a tab**: everything happens in the Partner Center
tab you already have open. A floating **📚 Auto Upload** button sits at the
bottom-right of every Partner Center page; clicking it slides in a panel with
the file inputs, the metadata summary, the Run/Stop controls and the live log.
The panel header and the log show the installed version (e.g. "Play Books
Auto Uploader v6.0"), so a screenshot always proves which build is running.
(Earlier versions used a toolbar popup, and v3 opened a fresh tab at Run
start because old tabs could keep running stale code — the in-page design
makes both unnecessary: the panel and the automation live in the page
itself, so the code acting is always the code of the installed build. If you
reload the extension mid-run, reload the Partner Center tab too, then use
the panel's **Resume upload** button to continue the stored job in that tab.)

---

## 1. Load the extension (one time)

1. Open `chrome://extensions` in Chrome.
2. Turn on **Developer mode** (top-right toggle).
3. If any older copy of "Play Books Auto Uploader" is listed, **Remove**
   it first — keeping two copies causes version mix-ups.
4. Click **Load unpacked** and select the `playbooks-uploader-extension-v9.1` folder.
5. Open (or reload) a Partner Center tab and check that the floating
   **📚 Auto Upload** button appears at the bottom-right, and that the
   panel header reads **v9.1**. (Clicking the extension's toolbar icon
   also toggles the panel, but there is no popup.)

## 2. Prepare metadata.txt

Copy `metadata-template.txt`, rename it to `metadata.txt`, and fill in your
book's values. The parser accepts **two layouts**:

- **Template format** — `KEY: value` on one line, as in the template
  (headings listed below).
- **Heading format** — a heading alone on its own line (e.g. `TITLE`,
  `FULL DESCRIPTION (store blurb)`, `AUTHOR BIO (short)`) with the value on
  the following line(s), sections optionally separated by lines of `-` or
  `=`. In this format, pages are calculated from a `LENGTH` line
  (words ÷ 250), the price is the first `$` amount in the price section, and
  a leading BISAC code on a category line (e.g. `BUS012000 — BUSINESS & …`)
  is stripped automatically.

For the template format, keep the headings exactly as in the template — the parser looks
for:

- `TITLE:`, `SUBTITLE:`, `AUTHOR:`, `LANGUAGE:`
- `PAGE COUNT (Partner Center): <number>` (or a `PAGES:` line)
- The description block under `DESCRIPTION (exactly 200 words):`, ending at the
  `CATEGORIES` heading — pasted verbatim
- `CATEGORIES (BISAC):` followed by a numbered list of up to 3 genres, in order
- `SUGGESTED PRICE: ebook USD 12.99` (the ebook price is used; Worldwide)
- `AUTHOR BIOGRAPHY: <bio>` — pasted verbatim into the Contributors tab
- Optional: `RELEASE DATE:` / `PUBLICATION DATE:` (e.g. `October 27, 2026`),
  `MINIMUM AGE:` (default 18)

Fixed rules the extension always applies (the account owner's standing rules):

- Publisher = the author name
- Maximum age left blank, "For mature audiences?" = No
- Settings: **DRM = No**, **Preview = 20%**, **Copy/paste = 0%**
- **Release date rule:** the Partner Center rejects a release date that is not
  *more than 3 days from today*, so if the file's release date is missing or
  too soon, the extension uses **today + 4 days**. Publication date defaults to
  today.

## 3. Run an upload

1. Sign in to the Play Books Partner Center
   (<https://play.google.com/books/publish>) in the same Chrome profile, in
   any tab you like.
2. Click the floating **📚 Auto Upload** button at the bottom-right of the
   page (or the extension's toolbar icon) to open the panel.
3. In the panel, choose the three files: **EPUB**, **cover**, **metadata.txt**.
   A summary (title / author / price / pages / genres) appears — check it.
   **Or use the ZIP way (below) instead.**
4. Press **Run upload**. Everything happens in **this same tab** — no popup,
   no new tab. The panel narrates every step in its **Log** area, and you can
   close the panel and keep working; reopen it any time to watch progress
   (the log and status are kept in the extension's storage and update live).
5. **Stop** halts the job at any point (work already saved on Google's side
   stays saved; the draft book remains in your catalog). If the page is
   reloaded mid-run, the run continues automatically in that tab; if it
   doesn't, open the panel and press **Resume upload**.

### The ZIP way (v5.0)

1. Put the book's three ingredients in **one ZIP file**: the **.epub**, the
   **cover image** (.jpg/.jpeg/.png) and the **metadata .txt**. Filenames and
   folders inside the ZIP don't matter — name them anything, nest them in
   subfolders if you like.
2. In the panel, pick that ZIP under **"📦 OR drop everything in one ZIP"**.
3. The panel shows what it detected (EPUB / cover / metadata, with sizes)
   and the usual metadata summary. Detection rules: the **largest** EPUB;
   for the cover, an image whose name contains "cover" (otherwise the
   largest image); for metadata, a .txt whose name contains "metadata"
   (otherwise the largest .txt). If the EPUB or the metadata file is
   missing, the panel says so and nothing starts.
4. Press **Run upload** — from here on it is identical to the three-file
   flow. (You can also mix: ZIP plus an individually picked file — the
   individually picked file wins for that slot.)

## 4. What the extension does, stage by stage

| Stage | What happens |
|---|---|
| Create | Book Catalog → Add book → sell option "Sell ebook on Google Play" (verified by read-back) → book ID "Get a Google book ID (GGKEY)" in the second dropdown (also verified) → Save & Continue. The new GGKEY is captured and logged. |
| About | Title, subtitle, verbatim description, Language English, Publisher = author, Ebook, page count, publication + release dates, min age 18, max age blank, mature = No. Saved, then the critical values are re-read to confirm the save stuck. |
| Genres | The 3 BISAC genres from metadata.txt are added in order via the genre picker — only full-path suggestions are accepted, each pick is confirmed by its chip appearing, and genres already on the book are skipped. Saved. |
| Contributors | Author name, role **Author** (chosen inside the author's own row), verbatim biography. Saved and re-read. |
| Settings | DRM No / Preview 20% / Copy-paste 0% — each chosen with exact text matching and verified by reading the control back. Saved and re-verified. |
| Content | EPUB and cover are uploaded (files are rebuilt in the page from the stored copies and attached to the page's file inputs). Each file is confirmed by its own new row on the Content tab; upload errors surface immediately with the row text quoted. |
| Pricing | USD price from metadata.txt (currency read back as USD), Territories **Worldwide**. Saved and re-read. |
| Verify | Re-reads the book: all three Settings values, the description, both dates, the page count (from its field), plus identifier, title, genres, author, publisher and price on the Review page — PASS/FAIL per item in the log. Any critical failure stops the run before publishing. |
| Processing | The EPUB processing step is polled every ~2 minutes, read from the **current version's** row only, until it shows **step 6 of 6**. This works while Chrome is open, even if you close the panel. |
| Publish | Review/Publish → "Ready to publish" → "Publish to Google Play and Google Books", then reads the status from the book's own page/row (Live / Preorder / …) and notifies you. If the status can't be verified, you are told the publish is **not verified** rather than "published". Because the release date is a few days out, the book may show as **Preorder** until that date — that is expected. |

You get a Chrome notification when the book is published, when a stage fails,
or when a stop condition needs you.

## 5. Stop conditions (the extension halts and notifies you)

- **Sign-in / password / 2FA page** — the extension can never enter your
  password. Sign in yourself, then press Run again.
- **CAPTCHA** — solve it manually, then press Run again.
- **Tax / payment / identity prompt** — the extension *never* touches these.
  Complete them yourself in the Partner Center.
- **EPUB processing error** — the error text is quoted in the log/notification.
- Any stage that still fails after its automatic retries.

## 6. Notes & first live run

- **Watch the first live run.** Google changes the Partner Center layout from
  time to time; the extension finds controls by their visible text and labels
  (not fixed CSS selectors), which survives most redesigns — but if a step
  fails on the first real book, the log says exactly which control was not
  found, and the selectors/wording in `content.js` can be adjusted.
- A test run creates a **real draft book** in your catalog (there is no
  sandbox). If a run goes wrong, delete the draft from the catalog and re-run.
- Files are kept in the extension's local storage only for the duration of the
  job. Very large books (EPUB + cover over ~8 MB combined) may exceed Chrome's
  local-storage quota — if Run reports a storage error, that is why.
- The extension only runs on `play.google.com/books/publish/*` and interacts
  with the Partner Center only in the tab you are using (plus, if no Partner
  Center tab is open at all while a book is still processing, a background
  check may open one so the processing poll and auto-publish can finish).
