# Signtech Digital — GitHub দিয়ে APK + Windows App Build করো

> ⚠️ **সবার আগে একটা জিনিস মিলিয়ে নাও (১ মিনিট):** `lib/main.dart`-এর
> উপরে `kAppUrl = 'https://signtech-digital.blogspot.com/'` লেখা আছে।
> এটা একটা অনুমান করা ঠিকানা — তোমার আসল Blogger blog-এর ঠিকানা
> অন্য কিছুও হতে পারে (বা custom domain হতে পারে)।
> **ভুল ঠিকানা থাকলে app খুলে ভুল/ফাঁকা সাইট দেখাবে।**
> Blogger খুলে **View blog** চেপে উপরের ঠিকানাটা copy করো, আর
> `lib/main.dart`-এ `kAppUrl`-এর জায়গায় সেটা বসিয়ে দাও।
> তারপর নিচের ধাপগুলো করো।

## যা যা লাগবে

- একটা GitHub account (free)
- এই folder-এর সব ফাইল

## ধাপ ১ — GitHub-এ repo বানাও

1. https://github.com/new খুলো
2. Repository name দাও: `signtech-digital-app`
3. **Public** বা **Private** — যেকোনো একটা (Private-ই ভালো, দোকানের app)
4. **Create repository** চাপো

## ধাপ ২ — Code push করো

GitHub-এর নতুন repo পেজে যে command গুলো দেখাবে, এই folder-এ
terminal খুলে সেগুলো চালাও (নিচেরটা উদাহরণ — তোমার repo-র
ঠিকানাটা ওখান থেকে নেবে):

```bash
git init
git add .
git commit -m "Signtech Digital app v1.0.0"
git branch -M main
git remote add origin https://github.com/TOMAR-USERNAME/signtech-digital-app.git
git push -u origin main
```

> `android/local.properties`-এ তোমার কম্পিউটারের Flutter-এর
> রাস্তা (path) লেখা আছে — ওটা `.gitignore`-এ আছে, তাই
> push হবে না, চিন্তা নেই।

## ধাপ ৩ — Build চালাও

1. Repo-র **Actions** ট্যাবে যাও
2. বামে **Build Signtech Digital (APK + Windows)** সিলেক্ট করো
3. **Run workflow** → **Run workflow** চাপো
4. ৫–১০ মিনিট অপেক্ষা করো (Android-এ JDK 17 + Flutter 3.24.5
   দিয়ে release APK বানাবে, Windows-এ Windows app বানাবে)

`v1.0.0` জাতীয় **tag** push করলেও build auto চালু হয়:
`git tag v1.0.0 && git push origin v1.0.0`

## ধাপ ৪ — Download করো

Build শেষ হলে ওই run-এর নিচে **Artifacts**-এ দুটো ফাইল পাবে:

| Artifact | কী পাবে | কী করবে |
|---|---|---|
| `signtech-digital-apk` | `app-release.apk` | ফোনে copy করে install করো (Install from unknown sources allow করতে হতে পারে) |
| `signtech-digital-windows` | `signtech-digital-windows.zip` | PC-তে unzip করে ভিতরের `signtech_digital.exe` চালাও |

## App-টা কীভাবে কাজ করে

- এটা তোমার **ওয়েব app-এরই** app-সংস্করণ: খুললেই তোমার Blogger
  সাইটটা চলে। ওয়েবে (Blogger template) যা আপডেট করবে, app-এও
  সাথে সাথে সেটাই দেখাবে — app আলাদা করে update করতে হয় না।
- Firebase login, cloud data, order/invoice/staff/cash-closing —
  সব ওয়েবের মতোই চলবে, একই data।
- Invoice-এর **WhatsApp / Messenger share** বোতাম চাপলে আসল
  WhatsApp/Messenger app-এ খুলবে।
- ফোনের **Back** বোতাম app-এর ভিতরে পেছনে যায়; আর পেছনে
  যাওয়ার কিছু না থাকলে app বন্ধ হয়।
- ইন্টারনেট না থাকলে "ইন্টারনেট সংযোগ নেই" দেখিয়ে **Retry**
  বোতাম দেবে।

## মনে রাখার মতো সীমাবদ্ধতা

- APK-টা **debug key দিয়ে sign** করা (Flutter template-এর
  default)। নিজের ফোনে/দোকানে চালানোর জন্য ঠিক আছে; Play Store-এ
  ছাড়তে হলে নিজের release keystore বানিয়ে signing বসাতে হবে।
- App চলতে **ইন্টারনেট লাগবেই** — data শুধু Firebase cloud-এ,
  ফোনে/PC-তে কোনো copy থাকে না (ওয়েব app-এর মতোই)।

## আবার build করতে চাইলে

`lib/main.dart` বা অন্য কিছু বদলে commit + push করলেই হবে —
তারপর Actions থেকে আবার **Run workflow** চাপো।
