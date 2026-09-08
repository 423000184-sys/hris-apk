# 🔐 HRIS Biometrics — Smart Workforce Management

> A next-generation Human Resource Information System with multi-modal biometric authentication, enterprise-grade security, real-time analytics, and offline-first architecture.

---

## ✨ What Makes This Stand Out

Unlike generic HRIS apps, HRIS Biometrics combines:

| Innovation | What It Does |
|------------|-------------|
| 🧠 **Multi-Modal Auth** | Face ID + Fingerprint + PIN + QR Code — 4 methods in one |
| 🛡️ **Liveness Detection** | Anti-spoofing checks prevent photo/video attacks |
| 📍 **Smart Geo-Fencing** | Auto-validates location before allowing clock-in |
| 🔄 **Offline-First** | Full local SQLite DB — works without internet |
| 🔒 **Zero-Trust Security** | Every action is audited, device-signed, and encrypted |
| ⚡ **< 1s Auth Time** | Optimized biometric pipeline for instant verification |
| 🎨 **Sprout-Level UX** | Premium dark UI with fluid micro-animations |

---

## 📱 Screens

1. **Splash Screen** — Animated logo with loading indicator
2. **Landing Page** — Feature carousel with stats, CTA
3. **Login Screen** — Biometric ring + PIN pad + Employee ID
4. **Dashboard** — Greeting, today's status, weekly chart, quick actions
5. **Clock Screen** — 4 auth methods with success overlay animation
6. **Employees** — Searchable list with biometric enrollment status
7. **Reports** — Attendance trends, department breakdown, export options
8. **Profile** — Biometric management, security settings, audit log

---

## 🏗 Architecture

```
lib/
├── main.dart                    # App entry + Splash Screen
├── theme/
│   └── app_theme.dart          # Colors, fonts, component styles
├── models/
│   ├── employee.dart           # Employee data model
│   └── attendance.dart         # Attendance + enums
├── services/
│   ├── database_service.dart   # SQLite (sqflite) - local storage
│   ├── security_service.dart   # Biometrics, encryption, sessions
│   └── api_service.dart        # REST API client (Dio)
└── screens/
    ├── landing_screen.dart     # Landing/intro page
    ├── login_screen.dart       # Authentication screen
    ├── main_screen.dart        # Bottom nav shell
    ├── dashboard_screen.dart   # Home dashboard
    ├── clock_screen.dart       # Biometric clock-in/out
    ├── employees_screen.dart   # Employee management
    ├── reports_screen.dart     # Analytics & export
    └── profile_screen.dart     # Profile & settings
```

---

## 🔒 Security Architecture

### Biometric Layer
- Device biometrics via `local_auth` (Face ID / Fingerprint)
- Liveness score threshold: ≥ 75%
- Face angle validation: ±15° yaw/pitch, ±10° roll
- Anti-spoofing: rejects photos and pre-recorded videos

### PIN Security
- PBKDF2-equivalent: SHA-256 + unique per-user salt + server pepper
- Brute-force protection: 5 failed attempts → 15-min lockout
- Stored in `flutter_secure_storage` (Keychain / Keystore)

### Session Management
- JWT-style session tokens with 8-hour expiry
- Device fingerprinting: hashed hardware ID
- Trusted Device registry per employee

### Data Encryption
- Face embeddings: Base64 + AES-256 wrapper
- Database: SQLCipher-ready schema
- API calls: TLS 1.3 minimum, certificate pinning ready

### Audit Trail
Every action is logged:
```sql
audit_logs(id, user_id, action, details, device_id, timestamp, is_suspicious)
```

---

## 🗄 Database Schema

```sql
-- 6 tables total
employees          -- Profile + biometric hashes
attendance         -- Clock records with method + location
leave_requests     -- Leave management with approval flow
departments        -- Org structure
schedules          -- Per-employee work schedules
audit_logs         -- Complete security event trail
```

---

## 🌐 API Integration

The `ApiService` connects to your backend at `https://api.hrisbiometrics.company.com/v1`

**Endpoints:**
- `POST /auth/login` — Credential auth
- `POST /attendance/clock-in` — Server-side clock-in
- `POST /attendance/sync` — Batch sync offline records
- `GET /reports/dashboard` — Live stats
- `POST /biometrics/face/enroll` — Remote face enrollment

**Offline mode:** All operations save locally first. Auto-syncs when connectivity restored.

---

## 🚀 Getting Started

### Prerequisites
- Flutter 3.16+ / Dart 3.0+
- Android SDK 21+ / iOS 12+

### Installation

```bash
git clone https://github.com/your-org/hris-biometrics.git
cd hris_biometrics
flutter pub get
flutter run
```

### Android Setup
Add to `android/app/build.gradle`:
```groovy
android {
    compileSdkVersion 34
    defaultConfig {
        minSdkVersion 23    // Required for biometrics
        targetSdkVersion 34
    }
}
```

### iOS Setup
Add to `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>Required for face recognition attendance</string>
<key>NSFaceIDUsageDescription</key>
<string>Authenticate with Face ID for secure access</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Verify you are within office premises</string>
```

---

## 🔧 Configuration

### Backend URL
Edit `lib/services/api_service.dart`:
```dart
static const String _baseUrl = 'https://your-api.com/v1';
```

### Biometric Thresholds
Edit `lib/services/security_service.dart`:
```dart
bool checkLivenessScore(double score) => score >= 0.75; // 75% confidence
bool isValidFaceAngle(double yaw, double pitch, double roll) =>
    yaw.abs() < 15 && pitch.abs() < 15 && roll.abs() < 10;
```

### Office Location (Geo-Fencing)
```dart
const double OFFICE_LAT = 14.5995;
const double OFFICE_LNG = 120.9842;
const double ALLOWED_RADIUS_METERS = 150;
```

---

## 📊 Innovation Highlights

### 1. Smart Clock-In Intelligence
The system auto-detects:
- Is the user within geo-fence? ✅
- Is it a trusted device? ✅  
- Is the biometric genuine (liveness)? ✅
- Is the time within shift window? ✅

Only all ✅ = successful clock-in.

### 2. Attendance Risk Scoring
Each attendance record gets a confidence score based on:
- Auth method used (face = highest, PIN = lowest)
- Location verified or not
- Device trust status
- Time pattern analysis

### 3. QR Token System
Time-limited tokens (valid 1 minute) for when biometrics aren't available:
```
FORMAT: EMPLOYEE_ID:SHA256_HASH
VALIDITY: 60 seconds
USE CASE: Device biometric failed, HR officer scans token
```

---

## 🎨 Design System

| Token | Value |
|-------|-------|
| Primary | `#0A1628` Deep Navy |
| Accent | `#00E5C3` Teal-Emerald |
| Accent 2 | `#00B4FF` Sky Blue |
| Success | `#00E5A0` |
| Warning | `#FFB347` |
| Error | `#FF5252` |
| Font | SF Pro Display (system) |
| Radius | 12–24px contextual |

---

## 📜 License

MIT License — Free for commercial use

---

*Built with ❤️ — Inspired by Sprout's design excellence, secured like a bank vault.*
