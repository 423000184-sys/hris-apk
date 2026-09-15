════════════════════════════════════════════════════════════════
R.A.C.O.M.A. HRIS BIOMETRICS — COMPLETE WORKFLOW GUIDE (v2)
Project:  C:\Users\april\Documents\hris_biometrics
Repo:     github.com/423000184-sys/hris-apk
Landing:  https://week-9-activity-53484.web.app
Hosting:  C:\hris-apk-hosting
════════════════════════════════════════════════════════════════


┌──────────────────────────────────────────────────────────────┐
│  SECTION 1 — MGA FOLDER AT URLS NA DAPAT MONG MALAMAN        │
└──────────────────────────────────────────────────────────────┘

📁 Project Folder:
C:\Users\april\Documents\hris_biometrics

📁 APK Output:
C:\Users\april\Documents\hris_biometrics\build\app\outputs\flutter-apk\app-release.apk

📁 Landing Page Folder:
C:\hris-apk-hosting

📁 Landing Page HTML:
C:\hris-apk-hosting\index.html

🔗 GitHub Repo:
https://github.com/423000184-sys/hris-apk

🔗 Releases Page:
https://github.com/423000184-sys/hris-apk/releases

🔗 Landing Page:
https://week-9-activity-53484.web.app

🔗 Firebase Console:
https://console.firebase.google.com

🔗 QR Code Generator:
https://www.qr-code-generator.com

🔧 GitHub CLI Path:
C:\Program Files\GitHub CLI\gh.exe


┌──────────────────────────────────────────────────────────────┐
│  SECTION 2 — ONE-TIME SETUP (KADA BUKAS NG POWERSHELL)       │
└──────────────────────────────────────────────────────────────┘

Buksan ang PowerShell. I-type:

    $gh = "C:\Program Files\GitHub CLI\gh.exe"

I-verify na gumagana:

    & $gh --version

✅ Dapat lumabas: gh version 2.100.0 (o kahit anong version)

─────────────────────────────────────────────
KUNG NA-EXPIRE ANG LOGIN:
─────────────────────────────────────────────

    & $gh auth login

Piliin:
• GitHub.com
• HTTPS
• Y (authenticate git with credentials)
• Login with a web browser

I-copy ang code na lalabas → pindutin Enter
→ paste sa browser → Authorize


┌──────────────────────────────────────────────────────────────┐
│  SECTION 3 — ARAW-ARAW NA WORKFLOW (EDIT + PUSH)             │
└──────────────────────────────────────────────────────────────┘

GAMITIN ITO KAPAG MAY BINAGO SA CODE (pero walang bagong APK release):

─────────────────────────────────────────────
STEP 1 — I-EDIT ANG CODE
─────────────────────────────────────────────
• Buksan ang VS Code
• I-edit ang .dart files
• I-save (Ctrl+S)

─────────────────────────────────────────────
STEP 2 — I-TEST LOCALLY (OPTIONAL)
─────────────────────────────────────────────
cd C:\Users\april\Documents\hris_biometrics
flutter run -d chrome --dart-define=page=admin

    (Para sa employee page, palitan ng --dart-define=page=employee)

    Pindutin "q" sa terminal para mag-quit.

─────────────────────────────────────────────
STEP 3 — I-PUSH SA GITHUB (3 COMMANDS LANG)
─────────────────────────────────────────────
cd C:\Users\april\Documents\hris_biometrics
git add .
git commit -m "Update: describe mo ang binago"
git push

✅ Dapat lumabas: "main -> main" o "up to date"


┌──────────────────────────────────────────────────────────────┐
│  SECTION 4 — APK RELEASE WORKFLOW (KAPAG MAY BAGONG VERSION) │
└──────────────────────────────────────────────────────────────┘

GAMITIN ITO KAPAG READY NA MAG-RELEASE NG BAGONG APK:

─────────────────────────────────────────────
STEP 1 — I-BUILD ANG APK
─────────────────────────────────────────────
cd C:\Users\april\Documents\hris_biometrics
flutter build apk --release

    ⏱️  3-10 minutes
    ✅  Dapat lumabas:
        "✓ Built build\app\outputs\flutter-apk\app-release.apk"

─────────────────────────────────────────────
STEP 2 — I-DELETE ANG LUMANG RELEASE
─────────────────────────────────────────────
Buksan sa browser:
https://github.com/423000184-sys/hris-apk/releases

    • Hanapin ang lumang release (e.g. v1.0.2)
    • Pindutin ang 🗑️ (trash icon)
    • Kumpirmahin ang delete

    ⚠️  KAILANGAN i-delete muna bago gumawa ng bago.
        Hindi puwedeng mag-upload ng same tag twice.

─────────────────────────────────────────────
STEP 3 — GUMAWA NG BAGONG RELEASE
─────────────────────────────────────────────
$gh = "C:\Program Files\GitHub CLI\gh.exe"

    & $gh release create v1.0.3 `
      "C:\Users\april\Documents\hris_biometrics\build\app\outputs\flutter-apk\app-release.apk" `
      --repo 423000184-sys/hris-apk `
      --title "HRIS Biometrics v1.0.3" `
      --notes "Latest update"

    ⚠️  PALITAN ANG v1.0.3 NG BAGONG VERSION NUMBER!
    ⏱️  1-3 minutes (119 MB upload)
    ✅  Dapat lumabas: https://github.com/.../releases/tag/v1.0.3

─────────────────────────────────────────────
STEP 4 — I-UPDATE ANG LANDING PAGE
─────────────────────────────────────────────
Buksan: C:\hris-apk-hosting\index.html (Notepad)

    Hanapin:  releases/download/v1.0.2/app-release.apk
    Palitan:  releases/download/v1.0.3/app-release.apk

    I-save (Ctrl+S)

─────────────────────────────────────────────
STEP 5 — I-DEPLOY ANG LANDING PAGE
─────────────────────────────────────────────
cd C:\hris-apk-hosting
firebase deploy --only hosting

    ⏱️  30 seconds
    ✅  Dapat lumabas: Hosting URL: https://week-9-activity-53484.web.app

─────────────────────────────────────────────
STEP 6 — I-PUSH ANG SOURCE CODE
─────────────────────────────────────────────
cd C:\Users\april\Documents\hris_biometrics
git add .
git commit -m "Release v1.0.3"
git push

✅  TAPOS NA! Share ang bagong APK link sa users.


┌──────────────────────────────────────────────────────────────┐
│  SECTION 5 — ⚠️ BABALA SA SECRETS (BASAHIN ITO!)              │
└──────────────────────────────────────────────────────────────┘

ANG MGA SUMUSUNOD NA FILES AY HINDI DAPAT I-COMMIT:

    ❌ serviceAccount.json  (Google Cloud credentials)
    ❌ .env files
    ❌ *.keystore, *.jks    (Android signing keys)
    ❌ *.p12, *.mobileprovision  (iOS signing)
    ❌ google-services.json  (kung may sensitive data)

─────────────────────────────────────────────
KUNG MAKAKITA MO ANG ERROR NA:
"Push cannot contain secrets"
─────────────────────────────────────────────

I-type ITO sa PowerShell:

    cd C:\Users\april\Documents\hris_biometrics
    git rm --cached serviceAccount.json
    Add-Content .gitignore "`nserviceAccount.json"
    Add-Content .gitignore "*.json.key"
    Add-Content .gitignore "**/serviceAccount*.json"
    git commit --amend --no-edit
    git push

✅  Tapos na — pasado na sa GitHub.

─────────────────────────────────────────────
I-VERIFY NA NASA .gitignore:
─────────────────────────────────────────────

    Get-Content .gitignore | Select-String "serviceAccount"

Dapat lumabas:
serviceAccount.json
*.json.key
**/serviceAccount*.json


┌──────────────────────────────────────────────────────────────┐
│  SECTION 6 — QUICK COMMANDS REFERENCE (COPY-PASTE READY)     │
└──────────────────────────────────────────────────────────────┘

[RUN ADMIN LOCALLY]
cd C:\Users\april\Documents\hris_biometrics
flutter run -d chrome --dart-define=page=admin

[RUN EMPLOYEE LOCALLY]
cd C:\Users\april\Documents\hris_biometrics
flutter run -d chrome --dart-define=page=employee

[BUILD APK]
cd C:\Users\april\Documents\hris_biometrics
flutter build apk --release

[CLEAN BUILD (kapag may error)]
cd C:\Users\april\Documents\hris_biometrics
flutter clean
flutter pub get

[PUSH SOURCE CODE]
cd C:\Users\april\Documents\hris_biometrics
git add .
git commit -m "Update"
git push

[CREATE GITHUB RELEASE]
$gh = "C:\Program Files\GitHub CLI\gh.exe"
& $gh release create v1.0.X `
      "C:\Users\april\Documents\hris_biometrics\build\app\outputs\flutter-apk\app-release.apk" `
--repo 423000184-sys/hris-apk `
      --title "HRIS Biometrics v1.0.X" `
--notes "Release notes"

[DEPLOY LANDING PAGE]
cd C:\hris-apk-hosting
firebase deploy --only hosting

[DELETE OLD RELEASE]
Buksan: https://github.com/423000184-sys/hris-apk/releases
Pindutin 🗑️ sa lumang version


┌──────────────────────────────────────────────────────────────┐
│  SECTION 7 — TROUBLESHOOTING                                 │
└──────────────────────────────────────────────────────────────┘

❌ "gh: command not found"
→ $gh = "C:\Program Files\GitHub CLI\gh.exe"
→ & $gh --version

❌ "Authentication failed"
→ & $gh auth login

❌ "Repository is empty"
→ Kailangan may README.md. Push muna.

❌ "Push cannot contain secrets"
→ Tingnan ang SECTION 5 (i-remove ang secret file)

❌ "Rejected — non-fast-forward"
→ git pull origin main --rebase
→ git push

❌ Firebase "HTTP 400 — Executable files forbidden"
→ Bawal mag-host ng APK sa Firebase Spark plan.
→ I-host sa GitHub Releases na lang.

❌ Cache issues (web browser)
→ Chrome Incognito o clear site data.

❌ APK "Parse error"
→ Rebuild. Baka corrupt ang file.

❌ "App not installed"
→ I-uninstall muna ang lumang version sa phone.

❌ Camera hindi gumagana sa web
→ HTTPS kailangan. Gamitin ang APK para sa real test.

❌ "Version code" error sa Play Store
→ Taasan ang version sa pubspec.yaml (e.g. 1.0.2+3 → 1.0.3+4)


┌──────────────────────────────────────────────────────────────┐
│  SECTION 8 — TESTING CHECKLIST (BAGO MAG-RELEASE)            │
└──────────────────────────────────────────────────────────────┘

[ ] App nag-launch? → Walang crash sa startup
[ ] Login gumagana? → Admin at Employee
[ ] Notification bell? → Nagpapakita ng count
[ ] Notification page? → Walang error, may list
[ ] Dark mode toggle? → Sumasabay ang buong app
[ ] Send Update (admin)? → Kita ang text sa dropdowns
[ ] APK nag-install sa phone? → Allow unknown sources → Install
[ ] Landing page nag-load? → https://week-9-activity-53484.web.app
[ ] Download button gumagana? → Pindutin, mag-download
[ ] QR code nag-scan? → Gamitin ang phone camera


┌──────────────────────────────────────────────────────────────┐
│  SECTION 9 — SHORTCUT .BAT FILES (OPTIONAL)                  │
└──────────────────────────────────────────────────────────────┘

Gumawa ng .bat files sa Desktop via PowerShell:

─────────────────────────────────────────────
[1-build-apk.bat]
─────────────────────────────────────────────
@'
@echo off
cd /d C:\Users\april\Documents\hris_biometrics
flutter build apk --release
pause
'@ | Out-File -FilePath "$env:USERPROFILE\Desktop\1-build-apk.bat" -Encoding ascii

─────────────────────────────────────────────
[2-deploy-landing.bat]
─────────────────────────────────────────────
@'
@echo off
cd /d C:\hris-apk-hosting
firebase deploy --only hosting
pause
'@ | Out-File -FilePath "$env:USERPROFILE\Desktop\2-deploy-landing.bat" -Encoding ascii

─────────────────────────────────────────────
[3-push-source.bat]
─────────────────────────────────────────────
@'
@echo off
cd /d C:\Users\april\Documents\hris_biometrics
git add .
git commit -m "Auto-update"
git push
pause
'@ | Out-File -FilePath "$env:USERPROFILE\Desktop\3-push-source.bat" -Encoding ascii

Pagkatapos: Double-click lang ang .bat files kapag may update.


┌──────────────────────────────────────────────────────────────┐
│  SECTION 10 — QR CODE (PARA SA MGA USERS)                    │
└──────────────────────────────────────────────────────────────┘

1. Pumunta sa: https://www.qr-code-generator.com
2. Type: URL
3. I-paste: https://week-9-activity-53484.web.app
4. Generate QR Code
5. Download PNG (500x500 minimum)
6. I-print o i-display

FLOW:
[QR Code] → landing page → Download App → GitHub APK → Install


┌──────────────────────────────────────────────────────────────┐
│  SECTION 11 — WORKFLOW SUMMARY (TYPICAL DAY)                 │
└──────────────────────────────────────────────────────────────┘

PARA SA MALIIT NA UPDATE (walang bagong APK):
1. Edit code sa VS Code
2. flutter run -d chrome (test)
3. git add . && git commit -m "..." && git push
✅ Tapos na!

PARA SA BAGONG APK RELEASE:
1. Edit code sa VS Code
2. flutter run -d chrome (test)
3. flutter build apk --release
4. Delete lumang release sa GitHub
5. gh release create v1.0.X
6. Update index.html (bagong version)
7. firebase deploy --only hosting
8. git add . && git commit && git push
✅ Tapos na! Share QR code / landing page URL.


┌──────────────────────────────────────────────────────────────┐
│  SECTION 12 — IOS BUILDS (PARA SA FUTURE)                    │
└──────────────────────────────────────────────────────────────┘

⚠️  WALANG MAC? Hindi problema. Gamiting ang Codemagic:

1. Sign up sa: https://codemagic.io
2. Connect sa GitHub repo mo
3. Auto-build ng iOS app sa cloud (free tier: 500 min/month)
4. Download ang .ipa file

⚠️  Para ma-install sa iPhone, kailangan ng:
• Apple Developer Account ($99/year)
• TestFlight (para sa beta testing)
• App Store (para sa production)

WALANG FREE na paraan para mag-install ng native iOS app.
Ang $99/year ay fixed cost ng lahat ng iOS developers.

BEST OPTION NGAYON:
• Android-only (free, native)
• Flutter Web sa iPhone (free, hindi native)
• Codemagic + Apple Dev ($99/year, native)


┌──────────────────────────────────────────────────────────────┐
│  SECTION 13 — MGA PAALALA SA PAG-COMMIT                     │
└──────────────────────────────────────────────────────────────┘

BAGO MAG-COMMIT, I-VERIFY MUNA:

    git status --short

Tingnan kung may kahina-hinalang files tulad ng:
❌ serviceAccount.json
❌ .env
❌ *.key, *.keystore
❌ Kahit anong may "secret" o "credential" sa filename

Kung may nakita:
1. I-add sa .gitignore: echo "filename" >> .gitignore
2. I-remove sa staging: git rm --cached filename
3. Saka i-commit

MAGANDANG COMMIT MESSAGE:
✅ "Fix: notification bell color sa dark mode"
✅ "Add: employee notification watcher"
✅ "Update: dropdown text visibility"
❌ "asdf"
❌ "update"
❌ "fix"


════════════════════════════════════════════════════════════════
END OF GUIDE
════════════════════════════════════════════════════════════════

Good luck! 🚀

Kung may tanong o issue:
• github.com/423000184-sys/hris-apk
• console.firebase.google.com
• codemagic.io (para sa iOS future)