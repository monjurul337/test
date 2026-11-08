# GitHub দিয়ে Build — Gemini HD Studio

## যা যা পাবে
- **Android:** `GeminiHDStudio-v1.0.0-release.apk` (release APK)
- **Windows:** `GeminiHDStudio-Setup-1.0.0.exe` (full setup/installer) +
  `GeminiHDStudio-Windows-Portable.zip`

## ধাপে ধাপে

1. **নতুন GitHub repo বানাও — অবশ্যই Private রাখো** (app-এর source-এর
   ভিতরে Cloudinary API key আছে, extension-এর মতোই; public repo হলে
   যে কেউ key টা নিয়ে নিতে পারবে)।
2. **পুরো project টা upload করো — সবচেয়ে জরুরি কথা:**
   - শুধু `lib/` folder upload করলে হবে **না**।
   - লুকানো **`.github`** folder টা অবশ্যই সহ upload করতে হবে (Windows-এ
     File Explorer-এ "Hidden items" on করে দেখে নাও; GitHub Desktop /
     `git push` ব্যবহার করলে অটোমেটিক যাবে)।
   - **`installer/`** folder টাও লাগবে — না হলে Windows Setup .exe বানাবে না,
     workflow লাল error দিয়ে থামবে।
   - সহজ রাস্তা: এই project-এর ZIP টা extract করে সব ফাইল repo-তে push করো।
3. Repo-তে **Actions** tab → বামে **"Build Gemini HD Studio (APK + Windows)"**
   → **Run workflow** → সবুজ **Run workflow** বাটন।
4. ৫–১০ মিনিট পর run-টা খুললে নিচে **Artifacts**-এ দুটো download পাবে:
   - `gemini-hd-studio-android-apk`
   - `gemini-hd-studio-windows` (ভিতরে Setup .exe + Portable zip)
5. চাইলে **Release**-এও পাঠানো যাবে: `v1.0.0` নামে tag push করলেই
   workflow আবার চলবে আর APK + Setup দুটোই Release-এ attach হবে।

## Build configuration (যা আগে থেকে ঠিক করা আছে)
- Flutter **3.24.5** pinned, Android job-এ **JDK 17** (temurin)।
- Windows job **`windows-2022`** runner-এ চলে — `windows-latest` নিলে
  Visual Studio 2026-এর জন্য Flutter 3.24 build fail করে (Signtech-এ
  এই সমস্যা হয়েছিল)। Flutter version কোনোদিন আপগ্রেড করলে এই লাইনটা
  আবার যাচাই করো।
- Windows build-এর আগে workflow নিজে **NuGet** PATH-এ আছে কিনা দেখে,
  না থাকলে download করে নেয় (flutter_inappwebview-এর Windows অংশের জন্য লাগে)।
- APK আপাতত **debug key** দিয়ে signed — সরাসরি install হবে। Play Store-এ
  দিতে চাইলে নিজের keystore লাগবে (README দেখো)।

## প্রথমবার app চালিয়ে যা করবে (Gemini Login)
1. App খুলে ডানদিকের উপরে **account আইকন** → **Gemini Login** screen।
2. App-এর ভিতরের **Chromium browser**-এ নিজের **Google account দিয়ে sign in** করো
   (password শুধু Google-এর পেজেই যাবে, app দেখে না)।
3. Gemini-এর chat screen দেখা গেলে **Connect Gemini** চাপো —
   "Connected! ... তোমার ইমেইল" দেখলেই login হয়ে গেছে।
4. একাধিক Gmail থাকলে **Add Gmail** দিয়ে আরেকটা যোগ করে header-এর
   **Scan** চাপো — u/0–u/5 সব account দেখাবে, dropdown থেকে switch করা যাবে।
5. **যদি** Google "This browser or app may not be secure" দেখায়:
   Chrome-এ gemini.google.com-এ sign in করে F12 → Application → Cookies
   থেকে `__Secure-1PSID` আর `__Secure-1PSIDTS`-এর value কপি করে
   login screen-এর **"Login blocked? Paste cookie instead"** বাক্সে
   paste করে **Connect with pasted cookie** চাপো — একইভাবে কাজ করবে।
6. Generation-এর আগে **Panel Settings**-এ গিয়ে (cloud-upload আইকন):
   - R2 Worker URL + Firebase account(s) দাও (panel upload চাইলে)।
   - Cloudinary upscale-এর API key app-এর ভিতরেই দেওয়া আছে (extension-এর
     মতোই) — কিছু paste করতে হবে না, সরাসরি কাজ করবে।

## সমস্যা হলে
- **Workflow-তে installer error:** repo-তে `installer/` folder upload হয়নি।
  পুরো project আবার upload করো।
- **APK install হয় না (পুরনো version ছিল):** আগেরটা uninstall করে নতুনটা
  install করো (debug key বদলায় না, তবে অন্য source-এর একই package
  থাকলে conflict হয়)।
- **Login verify fail:** cookie expire হয়েছে — Gemini Login screen থেকে
  আবার Connect করো, অথবা paste পদ্ধতিতে নতুন cookie দাও।

## নতুন dashboard UI
App এখন modern dark dashboard: উপরে gradient header (title, account
switcher, stat chip), desktop-এ বামে navigation rail আর mobile-এ নিচে
bottom navigation — **Studio · Showcase** (কয়টা set আছে তার badge) ·
**Search · Prompt · Login** (কয়টা Gmail আছে তার badge)। Set Designer
এখন পরিষ্কার card-এর ভিতরে, Generate বাটন gradient (violet → cyan),
আর screen বদলালে smooth fade-slide animation হয়। আগের সব feature
ঠিক আগের মতোই কাজ করে — শুধু look টা বদলেছে।

## নতুন feature (Image to Prompt + Image Search)
- **Image to Prompt:** Set Designer-এ **Image to Prompt** বাটন — যেকোনো
  ছবি দিলে তোমার sign-in করা Gemini session ওই ছবি দেখে একটা বিস্তারিত
  generation prompt লিখে দেবে; চাইলে সরাসরি **Use in Set Designer**
  চাপলেই prompt field-এ বসে যাবে। Login করা না থাকলে ওই screen থেকেই
  Gemini Login খোলা যাবে।
- **Search images:** Set Designer-এ **Search images** বাটন — app-এর
  Chromium browser-এ **Google Images** / **Pinterest** search হবে।
  পছন্দের ছবিটা বড় করে খুলে **Pick image from this page** চাপলে
  সবচেয়ে বড় ছবিগুলোর list আসবে; একটা বাছলে download হয়ে তিনটা
  option পাবে — **Use as Reference image**, **Image to Prompt**,
  **Save a copy**। Pinterest-এ মাঝে মাঝে login চাইতে পারে — browser-এর
  ভিতরেই sign in করে নিলেই হবে।
