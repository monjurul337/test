# Signtech Digital — Android App + Windows App (Flutter)

তোমার Signtech Digital ওয়েব software-টারই **Android APK** আর **Windows app**।
App-এর ভিতরে তোমার live ওয়েব app-টাই চলে (Flutter + Kotlin WebView shell), তাই:

- ওয়েবে যা আপডেট করবে (নতুন feature, fix) — **সাথে সাথে app-এও** চলে আসবে, app আবার build করা লাগবে না
- ডাটা একই Firebase — ওয়েব, মোবাইল, Windows সব জায়গায় **একই হিসাব**
- WhatsApp / Messenger শেয়ার বাটন আসল app-এ খোলে, ডাউনলোড (Backup/CSV) browser-এ যায়
- Android-এ pull-to-refresh, back button, offline হলে Retry স্ক্রিন; Windows-এ উপরে Back/Forward/Reload/Home বার

---

## ১) প্রথম কাজ: তোমার সাইটের ঠিকানা বসাও

`lib/main.dart`-এর একদম উপরে:

```dart
const String kAppUrl = 'https://signtech-digital.blogspot.com/';
```

এখানে **তোমার আসল live ঠিকানাটা** বসাও (Blogger ঠিকানা হোক বা custom domain)।
এটাই একমাত্র জায়গা যেটা বদলাতে হবে।

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
