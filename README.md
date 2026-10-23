# Play Books Browser (with Proton VPN WireGuard)

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
   - **Check IP** বোতাম দিয়ে টানেল চালু থাকা অবস্থায় আপনার পাবলিক আইপি এবং কান্ট্রি/লোকেশন টেস্ট করতে পারবেন।
   - **Auto-connect:** ব্রাউজার ওপেন করলেই স্বয়ংক্রিয়ভাবে ভিপিএন টানেল কানেক্ট করার অপশন।

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

```powershell
npm install
npm start
```

## Windows Installer (.exe) তৈরি করতে:

```powershell
npm run dist
```
`dist/` ফোল্ডারে `PlayBooksBrowser-Setup-1.0.0.exe` তৈরি হবে।

