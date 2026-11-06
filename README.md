# Maliha — AI Desktop & Remote Assistant (Flutter + Kotlin)

তোমার নিজের Windows PC-কে বাইরে থেকে ফোন দিয়ে কন্ট্রোল করার অ্যাপ।
PC অফ থাকলেও কমান্ড cloud-এ জমা থাকে — বাড়ির Bridge ডিভাইস PC-কে
Wake-on-LAN দিয়ে অন করে দেয়, অন হলেই জমা কাজগুলো নিজে নিজে হয়ে যায়।

## কীভাবে কাজ করে (৩টা রোল, একটাই অ্যাপ)

```
  তুমি (Controller অ্যাপ, ফোনে)
        │  কমান্ড
        ▼
  Firebase Realtime Database  ── command queue + heartbeat + wake flag
        │                              │
        ▼                              ▼
  PC Agent (Windows অ্যাপ)      Bridge (পুরোনো Android ফোন, বাড়িতে)
  কমান্ড পেলেই কাজ করে,          wake flag দেখলেই magic packet
  screenshot / status পাঠায়    পাঠিয়ে PC অন করে দেয় (Kotlin)
```

| রোল | কোথায় চলে | কী করে |
|---|---|---|
| **Controller** | তোমার ফোন (Android) | কমান্ড লিখে/বলে পাঠানো, PC online কিনা দেখা, screenshot ও result দেখা |
| **PC Agent** | Windows PC | প্রতি ৪ সেকেন্ডে কমান্ড check করে, app/URL খোলে, screenshot নেয়, lock/shutdown করে, প্রতি ১০ সেকেন্ডে heartbeat পাঠায় |
| **Bridge** | বাড়ির পুরোনো ফোন (Android) | Kotlin foreground service প্রতি ৫ সেকেন্ডে wake flag check করে, Wake-on-LAN magic packet (১০২ byte) পাঠায় |

Voice & AI: Controller-এ mic বোতাম — Android-এর নিজের speech recognition
(Kotlin `SpeechRecognizer`), বাংলা `bn-BD` আর English `en-US` দুটো বোতামই আছে।
তাছাড়া এতে **Google Gemini AI** সাপোর্ট যুক্ত করা হয়েছে — Setup স্ক্রিনে Gemini API Key দিলে
যেকোনো সাধারণ বাংলা বা ইংরেজি বাক্য এআই নিজে বুঝে পিসিতে কমান্ড চালিয়ে দেবে! API key না দিলেও
বিল্ট-ইন বাংলা/ইংরেজি রুল-বেসড পার্সার স্বাভাবিকভাবে কাজ করবে।

## সেটআপ (একবারই)

### ১) Firebase Realtime Database বানাও (ফ্রি)
1. console.firebase.google.com → Add project (যেকোনো নাম) → Create
2. বাম মেনু: Build → Realtime Database → Create Database → **Start in test mode**
3. উপরে ডাটাবেসের URL-টা দেখবে, এমন: `https://তোমার-প্রজেক্ট-default-rtdb.firebaseio.com` — এটাই লাগবে
4. (পরে চাইলে) Rules ট্যাবে test mode-এর ৩০ দিন শেষ হওয়ার আগেই নিজের
   pairing-code পথটা ছাড়া বাকি সব বন্ধ করে দেওয়া যাবে; pairing code-টাই
   তোমার গোপন চাবি, তাই সেটা কাউকে দিও না।

### ২) তিনটা ডিভাইসেই একই সেটিং বসাও
প্রতিটা ডিভাইসে অ্যাপ খুলে Setup স্ক্রিনে বসাও:
- **Database URL** — উপরের URL-টা (সব ডিভাইসে হুবহু একই)
- **Pairing code** — একটা ডিভাইসে Generate চেপে বানাও, বাকি দুটোতে **হুবহু একই** code বসাও
- **PC MAC address** — PC-র **wired Ethernet** adapter-এর MAC (PC-তে `ipconfig /all`)
- **Broadcast IP** — সাধারণত `192.168.1.255` (রাউটারের subnet 192.168.0.x হলে `192.168.0.255`)
- তারপর প্রতিটা ডিভাইসে নিজের **Role** বেছে Save করো

### ৩) PC-তে Wake-on-LAN চালু করো (একবারই, মন দিয়ে)
**BIOS/UEFI:** Wake on LAN / Power On By PCI-E / Resume By PCI-E = **Enabled**,
আর **ErP / EuP = Disabled** (ErP অন থাকলে NIC-তে standby power যায় না, WoL অসম্ভব)।
**Windows:**
- LAN **কেবল** দিয়ে PC রাউটারে লাগানো থাকতে হবে — Wi-Fi দিয়ে WoL বেশিরভাগ PC-তে হয় না
- Device Manager → Ethernet adapter → Power Management: *Allow this device to wake the computer* + *Only allow a magic packet* = ✅
- Advanced: Wake on Magic Packet = Enabled, Energy Efficient Ethernet = Disabled
- Control Panel → Power Options → **Fast Startup = OFF** (এটা অন থাকলে full shutdown থেকে wake হয় না)
**PC Agent অ্যাপে:** Start agent চাপো, তারপর **Enable autostart** চাপো —
তাহলে PC অন হলেই agent নিজে থেকে চালু হবে (এটাই সবচেয়ে জরুরি ধাপ)।

### ৪) Bridge ফোন
পুরোনো ফোনটা চার্জারে লাগিয়ে বাড়ির Wi-Fi-তে রাখো → অ্যাপে Role = Bridge →
**Start bridge**। Android Settings-এ এই অ্যাপের **battery optimisation OFF** করে দিও,
নাহলে ফোন service-টা মেরে ফেলতে পারে। "Test: wake the PC now" দিয়ে একবার পরীক্ষা করে নিও।

## GitHub দিয়ে Build (APK + Windows installer)

> ⚠️ **পুরো প্রোজেক্টটা** repo-তে তুলবে — লুকানো `.github` ফোল্ডার আর
> `installer/` ফোল্ডারসহ। আংশিক তুললে আগেরবারের মতো build fail / ভুল ফাইল হবে।

1. GitHub-এ নতুন repo বানিয়ে এই পুরো ফোল্ডারটা push করো
2. Actions ট্যাব → **Build PC Assistant (APK + Windows)** → Run workflow
3. শেষ হলে Artifacts-এ পাবে: `pc-assistant-apk` (app-release.apk) আর
   `pc-assistant-windows-setup` (PCAssistant-Setup-1.0.0.exe — পূর্ণ installer)
- Android job: JDK 17 + Flutter 3.24.5 (ubuntu)
- Windows job: **windows-2022** runner (Flutter 3.24.5-এর জন্য বাধ্যতামূলক —
  windows-latest-এ Visual Studio 2026 থাকে, যেটা দিয়ে এই Flutter build হয় না)

এই মেশিনে Java/Flutter SDK নেই, তাই local build হয় না — GitHub Actions-ই
build-এর পথ (আগের প্রোজেক্টের বেলাতেও এমনই ছিল)।

## কমান্ডের তালিকা

| যা লিখবে/বলবে | যা হবে |
|---|---|
| `open youtube` / `ইউটিউব চালাও` / `play <গান> on youtube` | YouTube খুলবে / search result খুলবে |
| `open notepad` / `নোটপ্যাড খোলো`, chrome, calculator, vs code, explorer, paint | অ্যাপ খুলবে |
| `search google for <...>` / `গুগলে সার্চ করো <...>` | Google search |
| `screenshot` / `স্ক্রিনশট নাও` | PC-র screenshot Controller-এ ছবি হয়ে আসবে |
| `pc status` / `পিসির অবস্থা` | CPU / RAM / Disk রিপোর্ট |
| `lock my pc` / `পিসি লক করো` | PC lock |
| `shutdown` / `শাটডাউন` | ৬০ সেকেন্ড পরে shutdown (এর মধ্যে `cancel shutdown` পাঠালে বাতিল) |
| `বলো <...>` / `say <...>` | PC নিজের স্পিকারে কথা বলবে |

## নিরাপত্তা
- Pairing code = তোমার গোপন চাবি। Code + Database URL যার হাতে যাবে, সে তোমার
  PC-তে কমান্ড পাঠাতে পারবে — তাই code কাউকে দিও না, screenshot-এও দেখাইও না।
- Shutdown/Restart সবসময় ৬০ সেকেন্ড delay দিয়ে হয়, ভুল কমান্ড বাতিল করা যায়।
- অ্যাপটা শুধু **তোমার নিজের** PC/ফোনে ব্যবহারের জন্য।

## সমস্যা হলে

| লক্ষণ | কারণ → সমাধান |
|---|---|
| Controller-এ PC সবসময় OFFLINE | PC Agent চালু নেই / autostart হয়নি / Database URL বা pairing code মেলে না |
| Wake পাঠালেও PC অন হয় না | ErP অন, Fast Startup অন, Wi-Fi MAC ব্যবহার, LAN কেবল নেই → ধাপ ৩ আবার দেখো |
| Bridge কিছুক্ষণ পর বন্ধ হয়ে যায় | Battery optimisation অন → OFF করো, ফোন চার্জারে রাখো |
| কমান্ড গেছে কিন্তু কাজ হয়নি | Agent-এর log দেখো; app চেনা না গেলে পুরো path দিয়ে আবার পাঠাও |
| GitHub-এ Windows build fail | পুরো প্রোজেক্ট (`.github` + `installer/` ফোল্ডারসহ) উঠেছে কিনা check করো |

## তোমার বাকি কাজ (শুধু এগুলোই)
1. Firebase Realtime Database বানিয়ে URL নেওয়া (৫ মিনিট)
2. GitHub repo-তে পুরো প্রোজেক্ট তুলে Actions Run করা, APK + Setup.exe নামানো
3. PC-তে BIOS + Windows WoL সেটিং (ধাপ ৩) আর Agent-এ Enable autostart
4. Bridge ফোনে battery optimisation OFF করে Start bridge
