════════════════════════════════════════════════════════════════
R.A.C.O.M.A. HRIS BIOMETRICS — COMMANDS REFERENCE
Project:  C:\Users\april\Documents\hris_biometrics
Repo:     github.com/423000184-sys/hris-apk
Landing:  https://week-9-activity-53484.web.app
Hosting:  C:\hris-apk-hosting
════════════════════════════════════════════════════════════════


┌──────────────────────────────────────────────────────────────┐
│  SETUP (KADA BUKAS NG POWERSHELL)                            │
└──────────────────────────────────────────────────────────────┘

$gh = "C:\Program Files\GitHub CLI\gh.exe"
& $gh --version


┌──────────────────────────────────────────────────────────────┐
│  RUN LOCALLY                                                 │
└──────────────────────────────────────────────────────────────┘

# Admin
cd C:\Users\april\Documents\hris_biometrics
flutter run -d chrome --dart-define=page=admin

# Employee
cd C:\Users\april\Documents\hris_biometrics
flutter run -d chrome --dart-define=page=employee

# Android device (wired/wireless)
cd C:\Users\april\Documents\hris_biometrics
flutter devices
flutter run -d <DEVICE_ID>


┌──────────────────────────────────────────────────────────────┐
│  BUILD                                                   │
└──────────────────────────────────────────────────────────────┘

# Clean build
cd C:\Users\april\Documents\hris_biometrics
flutter clean
flutter pub get

# Build APK release
cd C:\Users\april\Documents\hris_biometrics
flutter build apk --release


┌──────────────────────────────────────────────────────────────┐
│  UPDATE SOURCE CODE (GitHub)                                 │
└──────────────────────────────────────────────────────────────┘

cd C:\Users\april\Documents\hris_biometrics
git add .
git commit -m "Update: describe changes"
git push


┌──────────────────────────────────────────────────────────────┐
│  CREATE GITHUB RELEASE                                       │
└──────────────────────────────────────────────────────────────┘

# 1. Delete old release manually via browser:
#    https://github.com/423000184-sys/hris-apk/releases

# 2. Create new release:
$gh = "C:\Program Files\GitHub CLI\gh.exe"

& $gh release create v1.0.X `
  "C:\Users\april\Documents\hris_biometrics\build\app\outputs\flutter-apk\app-release.apk" `
--repo 423000184-sys/hris-apk `
  --title "HRIS Biometrics v1.0.X" `
--notes "Release notes"


┌──────────────────────────────────────────────────────────────┐
│  UPDATE HOSTING (Landing Page)                               │
└──────────────────────────────────────────────────────────────┘

# 1. Edit index.html (palitan version number)
notepad C:\hris-apk-hosting\index.html

# 2. Verify version
cd C:\hris-apk-hosting
Get-Content index.html | Select-String "v1.0"

# 3. Deploy
cd C:\hris-apk-hosting
firebase deploy --only hosting

# 4. Verify
# Buksan: https://week-9-activity-53484.web.app (Incognito)


┌──────────────────────────────────────────────────────────────┐
│  FULL RELEASE WORKFLOW (APK + HOSTING)                       │
└──────────────────────────────────────────────────────────────┘

cd C:\Users\april\Documents\hris_biometrics
flutter build apk --release

cd C:\Users\april\Documents\hris_biometrics
git add .
git commit -m "Release v1.0.X"
git push

$gh = "C:\Program Files\GitHub CLI\gh.exe"
& $gh release create v1.0.X `
  "C:\Users\april\Documents\hris_biometrics\build\app\outputs\flutter-apk\app-release.apk" `
--repo 423000184-sys/hris-apk `
  --title "HRIS Biometrics v1.0.X" `
--notes "Latest update"

notepad C:\hris-apk-hosting\index.html

cd C:\hris-apk-hosting
firebase deploy --only hosting


┌──────────────────────────────────────────────────────────────┐
│  TROUBLESHOOTING                                             │
└──────────────────────────────────────────────────────────────┘

# Push fails - network issue
ipconfig /flushdns
ipconfig /release
ipconfig /renew
git push

# Push fails - authentication
& $gh auth login

# Push fails - non-fast-forward
git pull origin main --rebase
git push

# Push fails - secrets detected
cd C:\Users\april\Documents\hris_biometrics
git rm --cached serviceAccount.json
Add-Content .gitignore "`nserviceAccount.json"
git commit --amend --no-edit
git push

# Firebase not found
npm install -g firebase-tools
firebase --version

# Firebase auth error
firebase logout
firebase login

# Build fails
flutter clean
flutter pub get
flutter build apk --release


┌──────────────────────────────────────────────────────────────┐
│  VERSION NUMBERS                                             │
└──────────────────────────────────────────────────────────────┘

# Bago mag-release, i-update ang pubspec.yaml
# File: C:\Users\april\Documents\hris_biometrics\pubspec.yaml
# 
# Halimbawa:
#   version: 1.0.6+7  →  version: 1.0.7+8
#
# Sundin ang pattern:
#   pubspec.yaml:  version: 1.0.7+8
#   GitHub tag:    v1.0.7
#   index.html:    releases/download/v1.0.7/app-release.apk


┌──────────────────────────────────────────────────────────────┐
│  IMPORTANT PATHS                                             │
└──────────────────────────────────────────────────────────────┘

Project:        C:\Users\april\Documents\hris_biometrics
APK Output:     C:\Users\april\Documents\hris_biometrics\build\app\outputs\flutter-apk\app-release.apk
Hosting:        C:\hris-apk-hosting
Landing HTML:   C:\hris-apk-hosting\index.html
GitHub CLI:     C:\Program Files\GitHub CLI\gh.exe


┌──────────────────────────────────────────────────────────────┐
│  IMPORTANT URLS                                              │
└──────────────────────────────────────────────────────────────┘

GitHub Repo:    https://github.com/423000184-sys/hris-apk
Releases:       https://github.com/423000184-sys/hris-apk/releases
Landing Page:   https://week-9-activity-53484.web.app
Firebase:       https://console.firebase.google.com
QR Generator:   https://www.qr-code-generator.com


════════════════════════════════════════════════════════════════
END
════════════════════════════════════════════════════════════════