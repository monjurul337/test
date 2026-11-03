# GitHub দিয়ে Build করার গাইড — Moxixo Antidetect Browser

নিজের কম্পিউটারে কিছু install না করেই GitHub থেকে Windows / Mac / Linux-এর
installer বানানোর নিয়ম।

## ধাপ ১ — কোডটা GitHub-এ তোলো

1. github.com-এ লগইন করে **New repository** বানাও, নাম দাও যেমন: `moxixo-antidetect-browser`
2. এই ফোল্ডারের সব ফাইল repo-তে upload করো
   (GitHub ওয়েবসাইটে: **Add file → Upload files**, অথবা Git দিয়ে push করো)
3. খেয়াল রাখো `.github/workflows/build.yml` ফাইলটা যেন ঠিকঠাক ওঠে —
   এটাই অটো-build-এর প্রাণ।

Git ব্যবহার করলে:

```bash
git init
git add .
git commit -m "Moxixo Antidetect Browser v1.0.0"
git branch -M main
git remote add origin https://github.com/<তোমার-username>/moxixo-antidetect-browser.git
git push -u origin main
```

## ধাপ ২ — Build চালাও

1. Repo-র উপরে **Actions** ট্যাবে যাও
2. বামদিকে **“Build Moxixo Antidetect Browser”** সিলেক্ট করো
3. **Run workflow → Run workflow** চাপো
4. ৫–১০ মিনিট অপেক্ষা করো — Windows, macOS, Linux তিনটার build একসাথে হবে

## ধাপ ৩ — Installer ডাউনলোড করো

1. শেষ হওয়া run-টায় ক্লিক করো
2. নিচে **Artifacts** অংশে তিনটা ফাইল পাবে:
   - `moxixo-antidetect-windows-latest` → ভিতরে **.exe** (installer + portable)
   - `moxixo-antidetect-macos-latest` → ভিতরে **.dmg**
   - `moxixo-antidetect-ubuntu-latest` → ভিতরে **.AppImage** আর **.deb**
3. Windows ব্যবহারকারীর জন্য শুধু windows-এর টা ডাউনলোড করলেই হবে।

## ধাপ ৪ (ঐচ্ছিক) — Release বানাও

Version tag দিলে GitHub নিজে Release পেজে তিন প্ল্যাটফর্মের installer সাজিয়ে দেবে:

```bash
git tag v1.0.1
git push origin v1.0.1
```

## সাধারণ সমস্যা

- **Actions ট্যাব দেখা যাচ্ছে না / workflow নেই:** `.github` ফোল্ডারটা upload
  হয়নি বা ভুল জায়গায় আছে। Repo-র একদম গোড়ায় `.github/workflows/build.yml`
  থাকতে হবে।
- **Build লাল (fail) হলে:** run-এ ক্লিক করে লাল ধাপটা খোলো, শেষের error লাইনটা
  দেখো। সবচেয়ে common কারণ — `package.json` নষ্ট/বদলানো।
- **Windows SmartScreen সতর্কতা:** নিজের বানানো unsigned app-এ এটা স্বাভাবিক।
  “More info → Run anyway” চাপলেই চলবে। Code-signing certificate কিনলে এই
  সতর্কতা থাকে না।
- **macOS “unidentified developer”:** .dmg খুলে app-টা Applications-এ রেখে
  right-click → Open চাপো।
