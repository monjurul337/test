# Sotizence Play Books Browser (with Proton VPN WireGuard)

Google Play Books Partner Center-এর জন্য ডেডিকেটেড সুরক্ষিত Windows ব্রাউজার, যার ভেতরে সরাসরি Proton VPN WireGuard (`.conf`) টানেল বিল্ট-ইন যুক্ত করা হয়েছে।

## নতুন ফিচারসমূহ

1. **Google Play Books Partner Center:**
   - ব্রাউজার ওপেন করলে সরাসরি `https://play.google.com/books/publish/u/0/` ওপেন হবে।
   - আগের Wafid সংক্রান্ত সব ট্যাব ও প্যানেল সরিয়ে সম্পূর্ণ ক্লিন ব্রাউজিং অভিজ্ঞতা রাখা হয়েছে।
   - Google Chrome Client Hints (`navigator.userAgentData`, `Sec-CH-UA`) প্রিসার্ভ করা হয়েছে যাতে Google একাউন্টে সহজে লগইন করা যায়।

2. **Proton VPN WireGuard (.conf) ইন্টিগ্রেশন:**
   - Proton VPN থেকে ডাউনলোড করা যেকোনো WireGuard `.conf` ফাইল সরাসরি ব্রাউজারে ইমপোর্ট বা পেস্ট করা যায়।
   - ব্যবহারকারীদের কম্পিউটারে কোনো আলাদা WireGuard বা TUN/TAP ড্রাইভার ইন্সটল করতে হবে না এবং কোনো Windows Administrator পারমিশনের প্রয়োজন নেই (এটি Userspace Wireproxy দিয়ে ব্রাউজারের ভেতর সরাসরি SOCKS5 টানেল তৈরি করে)।
   - ব্রাউজারের শীর্ষ বারে **VPN Pill** বোতাম রয়েছে যা দিয়ে রিয়েলটাইমে স্ট্যাটাস দেখা এবং চালু/বন্ধ করা যায়।
   - **Check IP (BrowserLeaks)** বোতাম দিয়ে টানেল চালু থাকা অবস্থায় আপনার পাবলিক আইপি এবং কান্ট্রি/লোকেশন টেস্ট করতে পারবেন।
   - **Auto-connect:** ব্রাউজার ওপেন করলেই স্বয়ংক্রিয়ভাবে ভিপিএন টানেল কানেক্ট করার অপশন।

3. **Chrome Extensions সাপোর্ট:**
   - ব্রাউজারের **Settings** &rarr; **Extensions** ট্যাবে গিয়ে যেকোনো আনপ্যাকড ক্রোম এক্সটেনশন (`manifest.json` সম্বলিত ফোল্ডার) সরাসরি লোড ও ইন্সটল করা যায়।
   - প্রতি প্রোফাইলে এক্সটেনশনগুলো সক্রিয় থাকে এবং প্রয়োজন অনুযায়ী Enable/Disable ও Uninstall করা যায়।

---

## Proton VPN WireGuard ফাইল কিভাবে যুক্ত করবেন?

1. Proton VPN এর ওয়েবসাইটে ([account.protonvpn.com/downloads](https://account.protonvpn.com/downloads)) লগইন করুন।
2. **WireGuard configuration** অপশনে যান।
3. আপনার পছন্দের কান্ট্রি/সার্ভার সিলেক্ট করে `.conf` ফাইল ডাউনলোড করুন।
4. ব্রাউজারের উপরের টুলবারে **VPN Off** পিল বা **Settings** &rarr; **Proton WireGuard** ট্যাবে যান।
5. **Select .conf File** বাটনে ক্লিক করে আপনার ডাউনলোড করা ফাইলটি সিলেক্ট করুন (বা বক্সে পেস্ট করে **Save Configuration** চাপুন)।
6. **Connect VPN** চাপলেই আপনার সম্পূর্ণ ব্রাউজার ট্রাফিক প্রোটন ভিপিএন ওয়্যারগার্ড দিয়ে পরিচালিত হবে।

---

## বিল্ড এবং রান করা

### ১. Windows Desktop App:
```powershell
npm install
npm start
```
Windows Installer (`.exe`) তৈরি করতে:
```powershell
npm run dist
```
`dist/` ফোল্ডারে `SotizencePlayBooksBrowser-Setup-1.0.0.exe` তৈরি হবে।

---

### ২. Android Mobile App (Kotlin / JDK 17):
Windows Desktop অ্যাপের প্রতিটি মূল ফিচার এখন Android Mobile অ্যাপেও হুবহু যুক্ত করা হয়েছে:
- **মাল্টি-ট্যাব সিস্টেম (Tabs Manager):** ব্রাউজারে যতখুশি ট্যাব ওপেন, ট্যাব কাউন্টার ব্যাজ (`[ 1 ]`), ট্যাব কার্ড গ্রিড প্রিভিউ, নতুন ট্যাব ওপেন ও যেকোনো ট্যাব ক্লোজ করার পূর্ণাঙ্গ সুবিধা।
- **Proton VPN & SOCKS5 Proxy কন্ট্রোল:** শীর্ষ বারে রিয়েলটাইম **VPN Pill** (VPN Off / VPN Active), সরাসরি ১ ক্লিকে ভিপিএন ও প্রক্সি টানেল কানেক্ট/ডিসকানেক্ট এবং **Check IP (BrowserLeaks)** টেস্ট বাটন।
- **Play Books Auto Uploader v9.26 ইন্টিগ্রেশন:** Partner Center-এ স্বয়ংক্রিয়ভাবে স্ক্রিপ্ট ইনজেকশন (`early-intercept.js`, `jszip.min.js`, `content.js`) এবং সেটিংস থেকে এক্সটেনশন Enable/Disable করার সুবিধা।
- **ব্রাউজিং হিস্ট্রি (History Manager):** ব্রাউজ করা সব পেজ স্বয়ংক্রিয়ভাবে টাইমস্ট্যাম্পসহ সেভ হওয়া, হিস্ট্রি সার্চ ও ক্লিয়ার করার সুবিধা।
- **বুকমার্কস ম্যানেজার (Bookmarks):** শীর্ষ বারে স্টার বোতাম এবং বটম শিট ডায়ালগে বুকমার্ক লিস্ট।
- **মাল্টি-প্রোফাইল (Profiles):** Default, Work ইত্যাদি স্বাধীন প্রোফাইল তৈরি ও সুইচ করার অপশন।
- **সার্চ ইঞ্জিন নির্বাচন:** Google, DuckDuckGo, Bing নির্বাচন করার সুবিধা।
- **ইউআরএল কপি (Copy URL):** শীর্ষ বারে এক ক্লিকে অ্যাড্রেস বারের লিঙ্ক ক্লিপবোর্ডে কপি করার বোতাম।
- **ক্যাশ ও ব্রাউজিং ডেটা ক্লিয়ার:** এক ক্লিকে কুকিজ, ক্যাশ ও লোকাল ডেটা রিসেট করার ব্যবস্থা।
- **ফাইল আপলোড সুবিধা:** মোবাইল থেকেই সরাসরি EPUB, কভার ও মেটাডাটা আপলোড।

লোকাল অ্যান্ড্রয়েড রিলিজ APK বিল্ড করতে:
```bash
cd android
./gradlew assembleRelease
```
APK আউটপুট পাথ: `android/app/build/outputs/apk/release/app-release.apk`

---

## GitHub Actions স্বয়ংক্রিয় ডুয়াল বিল্ড
`.github/workflows/build.yml` কনফিগার করা আছে যাতে `main` ব্রাঞ্চে পুশ করলে বা ট্যাগ (`v1.0.0`) রিলিজ দিলে:
1. **Windows Runner:** Electron দিয়ে উইন্ডোজ ইনস্টলার (`.exe`) বিল্ড ও আর্টফ্যাক্ট আপলোড করে।
2. **Android Runner (Ubuntu):** JDK 17 ও Gradle 8.7 দিয়ে কোটলিন রিলিজ APK (`SotizencePlayBooksBrowser-v1.0.0.apk`) সাইন করে বিল্ড ও আর্টফ্যাক্ট আপলোড করে।
3. **GitHub Release:** ট্যাগ পুশ করলে সরাসরি গিটহাব রিলিজ নোটে `.exe` ও `.apk` দুটিই ফাইল অ্যাটাচ হয়ে যায়।


