# New logo: bold triangle mark (v1.19.4+47)

## His brief (2026-11-27)

Professional bold icon, triangle-shape based, **not text**, minimal,
**no border, no background shape**. Replaces the flat-yellow "MH"
lettermark from v1.17.5.

## The mark

One flat brand-yellow (#FFD400) bold triangle with a negative-space
inner triangle cut out of the base - reads as a peak / upward mark.
Single colour, no text, no border, no background: the PNG alpha is
fully transparent everywhere outside the mark itself (verified:
corner alpha 0 on every asset). Rendered at 4x supersample with
softly rounded corners (generator: ~/workspace/logo-triangle/
make_icon.py in the build notes; preview checked on dark and light).

## Assets replaced (same paths, same sizes - CI pipeline untouched)

- `assets/icon/app_icon.png` (1024) - also the in-app logo shown on
  Home, Batch and Settings screens, so those update automatically.
- `assets/icon/app_icon.ico` - Windows exe + installer, 9 sizes
  (16-256).
- `assets/icon/android/mipmap-*/ic_launcher.png` (48-192) and
  `ic_launcher_foreground.png` - foreground mark drawn at 62% so it
  sits inside the adaptive-icon safe zone.
- Adaptive-icon background colour changed from dark navy (#0D0A24)
  to fully transparent (#00000000) - no background shape, per brief.
- The phone-mockup branding spot in `device_mockup.dart` that drew a
  bordered "MH" box now paints the same triangle mark (no border, no
  text) via a small CustomPainter.

## Verification

- All PNGs re-opened and checked: sizes unchanged, RGBA, transparent
  corners, mark present; ICO contains all 9 sizes; device_mockup.dart
  format/parse OK.
- Builds on v1.19.3 (player cards) + v1.19.2 (settings page) +
  v1.19.1 (Gemini Android fix). NOT compiled - CI is the real check.

## V2 of the mark (v1.19.5+48) - "too common"

He rejected the first mark (solid triangle / peak) as too common.
Replaced with a **segmented triangle ring**: three bold trapezoid
bars forming the triangle, clean gaps at the three corners, in three
flat tones of the yellow family (#FFD400 / #FFB000 / #E08A00 - flat
colours, no gradients). An impossible-triangle (tribar) draft was
tried and dropped - it read as crossed planks, not professional.
The segmented ring was preview-checked on dark + light and at 48 px
(mdpi launcher size) - it stays crisp and recognisable small.
Same asset paths/sizes as before; device-mockup painter updated to
the same segmented geometry (single muted tone there).
Generator: ~/workspace/logo-triangle/make_icon_v3.py (+ apply_v3.py).

## V3 of the mark (v1.19.6+49) - "MH, stylish, triangle, minimal"

He rejected the segmented ring too (common) and gave the real brief:
**MH itself, styled with triangles, minimal.** Final mark: a bold
geometric **M** (two triangular peaks, deep valley) + **H** whose
crossbar is a solid triangle (play-shaped) joining the stems -
single flat #FFD400, no border, no background. Reads clearly as MH
even at 48 px (checked). Generator: make_icon_v4.py + apply_v4.py.
Wide lockup, so the adaptive foreground uses a smaller fill (0.64)
to stay inside the safe zone. The device-mockup branding painter
keeps the small segmented-triangle geometry (subtle device-back
branding, not the app logo).

## Contrast fix (v1.19.7+50) - yellow on white

His launcher screenshot showed the transparent icon composited on a
WHITE tile by the launcher - yellow on white is unreadable ("white er
moddhe yellow very bad"). The mark itself he kept; the fix is
contrast: every full icon (app_icon.png, ICO, legacy launcher PNGs)
now carries its own flat near-black background (#121216), and the
adaptive-icon background colour is #121216 again with the
transparent MH foreground on top - so on any launcher the yellow
sits on dark and pops. Preview-checked as a dark tile on a white
page: crisp.

## V4 of the mark (v1.20.5+58) - round, audio + image

He dropped the MH monogram: wants a minimal creative ROUND icon
fusing AUDIO and IMAGE (the app's two jobs). Final mark: seven
vertical waveform bars (audio) whose tops trace a mountain
skyline - tall centre peak, smaller hill - with a sun dot over the
hill (the photo element), flat #FFD400 on a dark round disc
(#121216). An earlier filled mountain-wave silhouette draft read
as a blob and was discarded before shipping. Adaptive icons: dark
background colour + the yellow mark as foreground (mark sits at
60% width, inside the safe zone); full disc version for app_icon /
ICO / legacy launchers. Generator: make_icon_v6.py + apply_v6.py.
Preview-checked dark + light + 48 px (bars and sun stay legible).

## V5 of the mark (v1.24.2+64) - creative MJ for MJ STUDIO

Name changed MH STUDIO -> MJ STUDIO, so the logo changed too. New
mark: one continuous bold **MJ ligature** - M (two peaks, deep
valley) whose right stem drops past the baseline and hooks left
into a J - plus a small sun/lens dot over the right peak (echo of
the v4 sun; the photo element). Single flat #FFD400, no border, on
the same dark round disc #121216 (contrast fix from v1.19.7 kept:
yellow pops on any launcher, white included). Minimal, no text
besides the MJ mark itself. Generator:
~/workspace/mj-studio-logo/make_mj_icon.py (4x supersample) +
apply_mj_icon.py. Variant A (MJ only) was drawn and dropped in
favour of B (MJ + sun dot) - the dot makes it distinctive at a
glance. Preview-checked dark + light + 48 px (mark and dot stay
legible). Same asset paths/sizes as before: app_icon.png (1024),
app_icon.ico (9 sizes 16-256), mipmap launchers (48-192) +
foregrounds (mark at 60% width, transparent background). The
device-mockup painter keeps its small segmented-triangle geometry
(subtle device-back branding, not the app logo). NOT compiled - CI
is the real check.

## V6 of the mark (v1.24.3+65) - user-supplied MJ logo, used exactly

He sent his own logo (1000083230_0_3a5f.jpg, 683x520, white
background) and ordered: "Ei logo tai same hobe". So the V5
yellow MJ ligature I drew was REPLACED, not tweaked. The supplied
pixels are used as-is - red M (~#901020) + dark-grey J (~#404040)
with the diagonal slash, no redraw, no recolour, no reshaping.
- Full icon: logo cropped to its bounds (452x478) and centred on
  an opaque white 1024 square -> app_icon.png, app_icon.ico
  (9 sizes 16-256), legacy mipmap launchers (48-192).
- Adaptive foreground: same logo with white made transparent
  (feathered luminance alpha), mark at 60% width.
- Adaptive background colour changed #121216 -> #FFFFFF in
  ai_studio_colors.xml: the dark-grey J would vanish on the old
  dark background; the logo as supplied is dark-on-white.
- In-app logo (Home/Batch/Settings show app_icon.png) now shows
  the supplied logo on its white tile. Generator:
  ~/workspace/mj-studio-logo/apply_supplied_logo.py; cropped
  source saved as supplied_mj_logo_crop.png. Preview-checked
  full size + 48 px (readable). NOT compiled - CI is the real check.

## V7 of the mark (v1.24.7+69) - same supplied logo, cut/blur fixed

Live report 2026-11-27 ~23:12 (his home-screen screenshot): the icon
looked CUT at the edges, no contrast, blurry. Measured cause: the V6
crop had dark pixels ON its border (mark bbox 4..447 of 452, 4..477 of
478) and the mark filled 80% of the 1024 canvas, so the launcher's
squircle mask clipped the spike tips; the 452px JPEG crop upscaled
1.8x + a wide 45-level feathered alpha made the edges hazy.
Fix (same logo, no redraw, no recolour): white padding (~12%) added
around the mark, padded logo box now fits at 68% of the canvas (was
80%) and the mark itself at ~52% wide (dark bbox x 248..775, y
229..794 of 1024 - ~24% air on every side, no mask can reach it); near-white JPEG noise pushed to pure white; UnsharpMask
after every resize; legacy mipmaps rendered straight from the padded
crop (one resample, not via the 1024 master); adaptive foreground
alpha ramp narrowed (248->232) and mark at 56% width, verified inside
the 66/108 safe zone (fg192 alpha bbox x 53..137, y 51..141 of 192).
Preview-checked at 384/192/96/48 px with a squircle mask on a dark
wallpaper (preview_supplied_v7.png) - nothing cut, edges crisp.
Honest limit: the source photo itself truncates the bottom spike tip
(mark reaches y 519 of 520 in the JPG) - the tip's very end is not in
the photo, so it cannot be restored; only a clean original logo file
(PNG/AI) from him would fix that. Generator:
~/workspace/mj-studio-logo/apply_supplied_logo_v7.py.

## V8 of the mark (v1.24.8+70) - deep colour contrast, same supplied logo

His order on the voice call 2026-11-27 ~23:21 (after seeing V7): the
logo must NOT look blurry/washed - it must be beautiful with DEEP
colour contrast. V7 had deliberately left the colours untouched; V8
deepens them on his explicit order. Same logo, same shapes, same
geometry - only colour depth + sharpness.
Measured in the V7 crop: red M median (155, 28, 39), contrast vs
white 8.1:1 - deepened to (128, 9, 21), 10.7:1 (channels scaled
0.83/0.35/0.55, hue stays crimson, pink JPEG halo deepens with it,
shading kept because the scaling is multiplicative). Grey J median
(64, 64, 66), 10.3:1 - pushed toward near-black (37, 37, 38), 15.3:1
(luminance-aware darkening, so light edge halos barely move - no grey
fringe). White forced pure white. Sharpening raised: UnsharpMask
percent 90 -> 140 after every resize. Geometry unchanged from V7
(68% fit, dark bbox x 247..775, y 229..794 of 1024; adaptive fg
inside the safe zone x 53..137, y 51..141 of 192). Preview-checked
V7-vs-V8 side by side at 192 px + V8 at 384/96/48 px
(preview_supplied_v8.png) - V8 is visibly deeper and crisper.
Generator: ~/workspace/mj-studio-logo/apply_supplied_logo_v8.py.
The bottom spike tip is still truncated in his source photo itself
(see V7) - only a clean original logo file would restore it.
