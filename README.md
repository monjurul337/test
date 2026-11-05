# Signtech Digital — Android App + Windows App (Flutter)

তোমার Signtech Digital software-টার **Android APK** আর **Windows app**।
**পুরো software-টাই app-এর ভিতরে bundle করা** (assets/www/index.html) —
তাই **blog/Blogger লাগবে না**, app একাই চলে (Flutter + Kotlin shell,
ভিতরের file-টা device-এর localhost দিয়ে চলে যাতে login save থাকে)।

- ডাটা একই Firebase — app, Windows, আর চাইলে blog-এর web version — সব জায়গায় **একই হিসাব**
- Software-এর নতুন version বের হলে শুধু `assets/www/index.html` replace করে app আবার build করতে হয় (নিচে ধাপ ১ দেখো)
- WhatsApp / Messenger শেয়ার বাটন আসল app-এ খোলে, ডাউনলোড (Backup/CSV) browser-এ যায়
- Android-এ pull-to-refresh, back button, offline হলে Retry স্ক্রিন; Windows-এ উপরে Back/Forward/Reload/Home বার

---

## ১) Software bundle (blog লাগবে না)

App-এর ভিতরের software ফাইলটা হলো: **`assets/www/index.html`**
(এটাই তোমার Signtech Digital-এর সর্বশেষ single-file version)।

- নতুন feature/fix app-এ নিতে চাইলে: নতুন `index.html` দিয়ে এই ফাইলটা
  **replace** করো, তারপর GitHub-এ push করে আবার build করো — ব্যাস।
- Blog-এর web version (metamonjurul1.blogspot.com) চাইলে আলাদা করে
  চালু রাখতে পারো — ডাটা একই Firebase, দুটোতেই একই হিসাব দেখাবে।
  App চালাতে blog-এর **কোনো দরকার নেই**।

## ২) GitHub দিয়ে build (JDK 17)

1. এই পুরো ফোল্ডারটা একটা GitHub repo-তে push করো
2. GitHub repo → **Actions** ট্যাব → **"Build Signtech Digital (APK + Windows)"** → **Run workflow**
3. Build শেষ হলে workflow-এর নিচে **Artifacts** থেকে ডাউনলোড:
   - `signtech-digital-apk` → ভিতরে `app-release.apk` (মোবাইলে সরাসরি install হবে)
   - `signtech-digital-windows` → ভিতরে zip, unzip করে `SigntechDigital.exe` চালালেই হবে

- Android job-এ **JDK 17** (Temurin) ব্যবহার করা হয়েছে — Gradle/Kotlin build JDK 17 দিয়েই হয়।
- Flutter version পিন করা: **3.24.5** (stable)।

## ৩) Signing নোট

Release APK আপাতত **debug key দিয়ে sign** করা — ফোনে সরাসরি install করে দোকানে
ব্যবহারের জন্য যথেষ্ট। কিন্তু:

- এই debug-sign করা APK-এর **উপরে** পরে অন্য key দিয়ে sign করা update install হবে না (আগে uninstall লাগবে)
- Play Store-এ দিতে চাইলে নিজের **keystore** লাগবে — বললেই আমি keystore বানিয়ে
  GitHub Secrets দিয়ে proper signing সেট করে দেব (Zedge Earn-এর মতো)

## ৪) Windows নোট

- Windows app চালাতে **Microsoft Edge WebView2 Runtime** লাগে — Windows 11 আর
  হালনাগাদ Windows 10-এ আগে থেকেই থাকে। না থাকলে Microsoft-এর সাইট থেকে
  ফ্রি install করা যায়।
- Invoice print: Windows-এ app-এর ভিতর থেকেই Print বাটন কাজ করবে (WebView2-র নিজের print)।

## ৫) লোকাল build (চাইলে)

```
flutter pub get
flutter build apk --release        # Android
flutter build windows --release    # Windows PC লাগবে
```

## প্রজেক্ট তথ্য

- App name: **Signtech Digital**
- Android package: `com.signtech.digital`
- Android সাইড: Kotlin (`MainActivity.kt`) + Flutter 3.24.5
- WebView: `flutter_inappwebview` 6, বাইরের লিংকের জন্য `url_launcher`
