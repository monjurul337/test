# IVAC Visa Bot — Complete System

> Automates Indian Visa appointment slot booking on [appointment.ivacbd.com](https://appointment.ivacbd.com)

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         System Overview                          │
│                                                                  │
│  ┌──────────────────┐        ┌─────────────────┐               │
│  │  Android App     │◄──────►│  Backend Server  │◄─────────────►│
│  │  (OTP Source)    │  WS/   │  (Node.js)       │  WebSocket   │
│  │                  │  REST  │  port 3000        │              │
│  └──────────────────┘        └────────┬────────┘               │
│                                        │ WebSocket               │
│                               ┌────────▼────────┐               │
│                               │ Chrome Extension │               │
│                               │  (MV3)           │               │
│                               │  Content Scripts │               │
│                               │  + Popup UI      │               │
│                               └────────┬────────┘               │
│                                        │ Content Scripts         │
│                               ┌────────▼────────┐               │
│                               │ appointment.     │               │
│                               │ ivacbd.com       │               │
│                               └─────────────────┘               │
└─────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
visa/
├── backend/                    # Node.js Backend Server
│   ├── src/
│   │   └── server.js           # Express + WebSocket server
│   ├── package.json
│   └── .env
│
├── chrome-extension/           # Chrome Extension (Manifest V3)
│   ├── manifest.json
│   ├── icons/
│   │   └── icon128.jpg         # Extension icon
│   ├── background/
│   │   ├── service-worker.js   # Background SW (WS + OTP routing)
│   │   └── constants.js        # Shared constants
│   ├── content/
│   │   ├── utils.js            # DOM utilities
│   │   ├── form-filler.js      # Form auto-fill + PDF upload
│   │   ├── navigator.js        # Page navigation
│   │   ├── slot-monitor.js     # Calendar scanning + booking
│   │   ├── otp-handler.js      # OTP auto-fill
│   │   └── main.js             # Automation orchestrator
│   └── popup/
│       ├── popup.html          # 4-tab dashboard UI
│       ├── popup.css           # Dark glassmorphism styles
│       └── popup.js            # Popup logic
│
└── android-app/                # Android App (Kotlin)
    └── app/src/main/
        ├── AndroidManifest.xml
        ├── java/com/visabot/app/
        │   ├── MainActivity.kt         # Main UI
        │   ├── MainViewModel.kt        # ViewModel
        │   ├── SmsReceiver.kt          # SMS BroadcastReceiver
        │   ├── OtpForwardingService.kt # Foreground Service + WebSocket
        │   └── BootReceiver.kt         # Auto-start on boot
        └── res/
            ├── layout/activity_main.xml
            └── values/{colors,strings,themes}.xml
```

---

## 🚀 Quick Start

### Step 1 — Backend Server

**Requirements:** [Node.js 18+](https://nodejs.org)

```bash
cd backend
npm install
npm start
```

The server runs at `http://localhost:3000`.

> **For remote access** (so Android phone can reach it): use your PC's local IP (e.g. `http://192.168.1.100:3000`) or deploy to a VPS and use your public URL. Update `SERVER_URL` in `.env`.

### Step 2 — Chrome Extension (In-Page Corner Control)

> 💡 **No Popup Dependency**: Rather than a small popup window that closes when clicking outside, a sleek floating launcher button appears right in the **bottom-right corner of the IVAC portal interface** (`appointment.ivacbd.com`).

1. Open Chrome → `chrome://extensions/`
2. Enable **Developer Mode** (top right)
3. Click **Load unpacked** → select the `chrome-extension/` folder
4. Navigate to `https://appointment.ivacbd.com/`
5. You will see the floating **🤖 IVAC Bot** button in the bottom-right corner!
   - Click it or press **`Alt + V`** to slide open the full control center right on the page!
   - Configure Mission, IVAC center, and applicant details.
   - Click **▶ START AUTOMATION**.

### Step 3 — Android App Release APK (GitHub Actions Build - JDK 17 + Kotlin)

The Android companion app is built using **Kotlin** and **Java 17 (JDK 17)**. You can build the ready-to-install **Release APK** automatically using **GitHub Actions**:

1. Push this project to your GitHub repository:
   ```bash
   git init
   git add .
   git commit -m "IVAC Visa Bot complete system"
   git branch -M main
   git remote add origin https://github.com/<your-username>/<your-repo-name>.git
   git push -u origin main
   ```
2. In your GitHub repo, go to the **Actions** tab.
3. The **"Build Android Release APK"** workflow runs automatically on push (or via manual trigger).
4. Download the compiled **`IVAC-VisaBot-Release-APK`** artifact directly from the run summary!
5. Install `IVAC-VisaBot-release.apk` on your Android phone, grant SMS permissions, and enter the pairing code shown on your IVAC portal screen. Tap **Start Service**.

*(Optional Local Build with JDK 17)*:
```bash
cd android-app
./gradlew assembleRelease
# Output APK: app/build/outputs/apk/release/app-release.apk
```

---

## 🔗 Pairing Flow

```
Extension Popup                  Backend                    Android App
    │                               │                            │
    │  POST /api/sessions           │                            │
    ├──────────────────────────────►│                            │
    │  ← { sessionId, pairingCode } │                            │
    │                               │                            │
    │  WS: extension_connect        │                            │
    ├──────────────────────────────►│                            │
    │                               │                            │
    │                               │◄───────────────────────────┤
    │                               │  WS: android_connect       │
    │                               │      { pairingCode: "XXXXXX" }
    │                               │                            │
    │                               │  ── PAIRED ──              │
    │                               │                            │
    │          Incoming SMS OTP received on Android phone         │
    │                               │◄───────────────────────────┤
    │                               │  WS: { type: "otp",        │
    │                               │        otp: "123456" }     │
    │◄──────────────────────────────┤                            │
    │  WS: { type: "otp", ... }     │                            │
    │                               │                            │
    │  [Content Script auto-fills OTP on IVAC portal]            │
```

---

## ⚙️ Configuration

### Chrome Extension Popup — Dashboard Tab

| Setting | Description |
|---------|-------------|
| **Mission** | Indian High Commission/Consulate (e.g., Kolkata) |
| **IVAC Center** | City where your IVAC office is located |
| **Visa Type** | Tourist, Business, Medical, etc. |
| **Check Interval** | How often (seconds) to scan for slots (default: 20s) |
| **Preferred Dates** | Comma-separated dates (e.g. `2024-12-15, 2024-12-20`) |
| **Auto-confirm** | Automatically confirm the booking after slot selection |

### Chrome Extension Popup — Profiles Tab

Add applicant profiles with:
- Personal information (name, passport, DOB, phone, email)
- PDF documents (passport copy, photos) — drag & drop upload

### Backend `.env`

```env
PORT=3000
LOG_LEVEL=info
NODE_ENV=production
```

---

## 🤖 Automation Logic

The automation flow follows these page states:

```
HOME → MISSION_SELECT → FORM_FILL → PDF_UPLOAD → DATE_SELECT → OTP_INPUT → CONFIRM → SUCCESS
```

**Slot Monitoring** (runs every ~20 seconds via Chrome alarm):
1. Parses available calendar cells on the date selection page
2. **Priority 1**: Checks if any available date matches your preferred dates
3. **Priority 2**: Takes the first available slot if no preference matches
4. Selects date → selects time → waits for OTP → fills OTP → confirms booking

---

## 📱 Android OTP Detection

The `SmsReceiver` detects visa-related OTPs using:

**Trusted senders:** `IVACBD`, `IVAC`, `VFSIND`, `INDVISA`, `BLS`

**Body keywords:** `OTP`, `one-time password`, `verification code`, `your code is`, `do not share`, `visa`, `vfs`

**OTP extraction:** Regex `\b(\d{4,8})\b` — prefers 6-digit codes, excludes years (1900-2100)

---

## 🔐 Security Notes

- The pairing code is a **6-digit number** valid for the session lifetime (2 hours idle timeout)
- OTPs are **never stored permanently** — they live in memory until consumed
- The backend uses **rate limiting** (60 req/min) and **Helmet** security headers
- Enable HTTPS/WSS for production deployment (use nginx reverse proxy + Let's Encrypt)

---

## 🚢 Production Deployment

For deploying the backend to a server:

```bash
# Install PM2 for process management
npm install -g pm2
cd backend
npm install
pm2 start src/server.js --name visa-bot-backend
pm2 save
pm2 startup

# Use nginx for HTTPS (example)
# server {
#   listen 443 ssl;
#   location / { proxy_pass http://localhost:3000; }
#   location /ws { proxy_pass http://localhost:3000; proxy_http_version 1.1;
#                  proxy_set_header Upgrade $http_upgrade;
#                  proxy_set_header Connection "upgrade"; }
# }
```

---

## 📋 REST API Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/sessions` | Create new session (returns sessionId + pairingCode) |
| `GET` | `/api/sessions/:id` | Get session status |
| `DELETE` | `/api/sessions/:id` | Delete session |
| `POST` | `/api/otp` | Submit OTP (Android HTTP fallback) |
| `GET` | `/api/otp/:sessionId` | Poll pending OTPs |
| `GET` | `/health` | Health check |
| `WS` | `/ws` | WebSocket endpoint |

### WebSocket Messages

| Type | Sender | Fields | Description |
|------|--------|--------|-------------|
| `extension_connect` | Extension | `sessionId` | Extension authenticates |
| `android_connect` | Android | `pairingCode` | Android pairs |
| `otp` | Android | `otp, rawMessage, sender` | Send OTP |
| `ping` | Any | — | Keepalive |

---

## ⚠️ Disclaimer

This tool is intended for personal use to assist with legitimate visa appointment bookings. Use responsibly and in accordance with the IVAC portal's terms of service.
