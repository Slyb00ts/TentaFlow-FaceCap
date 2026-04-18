# BUILD — tentaflow-facecap

Szczegółowa instrukcja budowania aplikacji iOS.

---

## 1. Wymagania systemowe

| Pozycja | Minimum | Zalecane |
|---|---|---|
| macOS | Sonoma 14.0 | Sonoma 14.5+ |
| Xcode | 15.4 | 15.4+ |
| iOS SDK | 17.0 | 17.4+ |
| Swift toolchain | 5.10 | 5.10+ |
| Urządzenie testowe | iPhone X (TrueDepth) iOS 17.0 | iPhone 12 Pro+ iOS 17.4+ |
| Apple ID | free (7-day) | Paid Developer Program |
| Miejsce na dysku (build cache) | 2 GB | 5 GB |

Symulator iOS **NIE** wystarczy — `ARFaceTrackingConfiguration.isSupported` zwraca
`false`, Metal ma ograniczone wsparcie, Object Capture wymaga TrueDepth/LiDAR.

---

## 2. Budowa z Xcode (GUI)

```bash
cd /ścieżka/do/tentaflow-facecap
open tentaflow-facecap.xcodeproj
```

W Xcode:
1. Wybierz schemat `tentaflow-facecap` (górna belka, obok przycisków play/stop).
2. W *Signing & Capabilities* target `tentaflow-facecap`:
   - Zaznacz **Automatically manage signing**.
   - Wybierz swój **Team** (Apple ID).
3. Podłącz iPhone'a, pojawi się w liście urządzeń. Wybierz go.
4. Kliknij **Run** (⌘R) albo **Build** (⌘B).

Przy **pierwszym** buildzie Xcode:
- rozwiąże lokalne pakiety SPM (`XCLocalSwiftPackageReference` → `Packages/*`),
- wygeneruje `BuildDir/DerivedData/tentaflow-facecap-*`,
- skompiluje każdy pakiet osobno (zobacz zakładkę *Report Navigator* — ⌘9).

**UWAGA:** pierwszy build ujawni brakujące pakiety SPM (HeadScan, FaceCalibration,
AssetInjection, PerformanceCapture, Preview). Instrukcja podpięcia — patrz
[`HANDOFF.md`](HANDOFF.md#23-brakujące-pakiety-spm-krytyczne).

---

## 3. Budowa z CLI (`xcodebuild`)

### Build bez instalacji (verification)

```bash
xcodebuild -project tentaflow-facecap.xcodeproj \
           -scheme tentaflow-facecap \
           -destination "generic/platform=iOS" \
           -configuration Debug \
           build
```

### Build na konkretne urządzenie

```bash
# Znajdź UDID podłączonego iPhone'a:
xcrun xctrace list devices 2>&1 | grep iPhone

# Build + install:
xcodebuild -project tentaflow-facecap.xcodeproj \
           -scheme tentaflow-facecap \
           -destination "platform=iOS,id=<UDID>" \
           -configuration Release \
           build
```

### Build archive (IPA dla TestFlight / ad-hoc)

```bash
xcodebuild -project tentaflow-facecap.xcodeproj \
           -scheme tentaflow-facecap \
           -configuration Release \
           -archivePath build/tentaflow-facecap.xcarchive \
           archive

xcodebuild -exportArchive \
           -archivePath build/tentaflow-facecap.xcarchive \
           -exportOptionsPlist exportOptions.plist \
           -exportPath build/export
```

Przykładowy `exportOptions.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
```

---

## 4. Lokalne pakiety SPM

Projekt używa `XCLocalSwiftPackageReference` z relatywnymi ścieżkami. Wszystkie
pakiety leżą w katalogu `Packages/`:

```
Packages/
├── Shared/                     # framework bazowy
├── Export/                     # zapis .face v3
├── Transfer/                   # AirDrop/Files/Wi-Fi
├── HeadScan/                   # Object Capture
├── FaceCalibration/            # ARKit 52 AU
├── AssetInjection/             # eye/teeth/tongue/mouth
├── PerformanceCapture/         # nagrywanie klipów
└── Preview/                    # Metal preview
```

`Package.swift` każdego pakietu:
- platform: `.iOS(.v17)`
- swift-tools-version: `5.10`
- products: `.library(name: "<Nazwa>", type: .static, targets: [...])`
- dependencies: zwykle tylko `Shared` (relatywny path `../Shared`)

**Rozwiązywanie zależności** odbywa się automatycznie — Xcode obsługuje relatywne
ścieżki z `XCLocalSwiftPackageReference`.

**Czyszczenie cache'u SPM:**
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/tentaflow-facecap-*
rm -rf .swiftpm
```

---

## 5. Uprawnienia i entitlements

### Info.plist — Usage Descriptions

Wszystkie teksty są **po polsku** (CFBundleDevelopmentRegion = `pl`):

| Klucz | Użycie |
|---|---|
| `NSCameraUsageDescription` | Skan głowy 3D + ARKit 52 AU |
| `NSMicrophoneUsageDescription` | Audio w klipach performance |
| `NSPhotoLibraryAddUsageDescription` | Zapis teksur/klatek do biblioteki |
| `NSLocalNetworkUsageDescription` | Bonjour/Wi-Fi transfer do Tab5 |
| `NSBonjourServices` | `_rackeye._tcp.` |

### Entitlements

Plik `tentaflow-facecap.entitlements`:
- `com.apple.security.network.client` — klient Wi-Fi (dla Bonjour/`WiFiUploader`).

### UTI — własny typ pliku `.face`

```xml
<key>UTExportedTypeDeclarations</key>
<array>
  <dict>
    <key>UTTypeIdentifier</key>
    <string>com.rackeye.face</string>
    <key>UTTypeDescription</key>
    <string>TentaFlow Face Profile</string>
    <key>UTTypeTagSpecification</key>
    <dict>
      <key>public.filename-extension</key>
      <array><string>face</string></array>
      <key>public.mime-type</key>
      <array><string>application/x-rackeye-face</string></array>
    </dict>
  </dict>
</array>
```

Dzięki temu `.face` pokazuje się jako *TentaFlow Face Profile* w *Files* i Share Sheet.

### Wymagania urządzenia

`UIRequiredDeviceCapabilities`:
- `arm64`
- `front-facing-camera`
- `iphone-ipad-minimum-performance-a12` (blokuje iPhone'y poniżej X)
- `truedepth-camera` (blokuje iPhone 8 i starsze)

---

## 6. Signing

### Free Apple ID

- Pozwala instalować na **3** urządzeniach tego samego Apple ID.
- Certyfikat wygasa po **7 dniach** — po tym czasie aplikacja nie odpala się,
  trzeba ponownie Build & Run z Xcode.
- Wystarczy do testów developerskich pipeline'u iPhone → Tab5.

### Paid Developer Program (99 USD/rok)

- Certyfikaty developerskie ważne 1 rok.
- Możliwość dystrybucji przez TestFlight / Ad Hoc.
- Wymagane tylko jeśli chcesz dłuższe testowanie niż 7 dni albo dystrybucję.

### Automatic signing

`project.pbxproj` ma `CODE_SIGN_STYLE = Automatic`. Xcode sam tworzy profil
*iOS Team Provisioning Profile: com.rackeye.tentaflow-facecap* przy pierwszym
buildzie. Nie ingeruj ręcznie w profile.

---

## 7. Znane ostrzeżenia kompilatora

### 7.1. Strict concurrency

Niektóre pakiety mają `-strict-concurrency=targeted`. Możliwe ostrzeżenia:
```
warning: capture of 'self' with non-sendable type '...' in a `@Sendable` closure
```
Lokalizacja: `PerformanceRecorder.swift`, `FaceTrackingSession.swift`.

**Naprawa:** dodaj `@MainActor` do klasy albo opakuj `Task { @MainActor in ... }`.

### 7.2. Deprecated RealityKit API

`ObjectCaptureSession` miał kilka renamed API między iOS 17.0 a 17.2. W razie:
```
warning: 'ObjectCaptureSession.Configuration' is deprecated
```
Zaktualizuj `ObjectCaptureSessionWrapper.swift` do nowszego API (iOS 17.2+).

### 7.3. Metal shader warnings

`PreviewShaders.metal` może generować:
```
warning: implicit conversion loses precision
```
dla `float` → `half`. To celowe — Metal Performance Shaders na iPhone'ie 12+
używają half-precision do oszczędzania energii.

---

## 8. CI hint — GitHub Actions

Przykład workflow `.github/workflows/build.yml` (**nie jest jeszcze wdrożony**):

```yaml
name: Build iOS
on: [push, pull_request]

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode 15.4
        run: sudo xcode-select -s /Applications/Xcode_15.4.app
      - name: Resolve packages
        run: |
          xcodebuild -project tentaflow-facecap.xcodeproj \
                     -resolvePackageDependencies
      - name: Build
        run: |
          xcodebuild -project tentaflow-facecap.xcodeproj \
                     -scheme tentaflow-facecap \
                     -destination "generic/platform=iOS" \
                     -configuration Debug \
                     CODE_SIGNING_ALLOWED=NO \
                     build
```

`CODE_SIGNING_ALLOWED=NO` wyłącza signing w CI (nie ma certyfikatów).
Do pełnego release'u dodaj Fastlane `match` i secret'y.

---

## 9. Troubleshooting

| Symptom | Przyczyna | Rozwiązanie |
|---|---|---|
| `cannot find type 'HeadScanCoordinator' in scope` | Brak podpięcia SPM `HeadScan` | Dodaj Local Package (patrz [HANDOFF §2.3](HANDOFF.md#23-brakujące-pakiety-spm-krytyczne)) |
| `Missing package product 'Shared'` | Cache SPM | `rm -rf .swiftpm && rm -rf ~/Library/Developer/Xcode/DerivedData/*` + reset packages w Xcode |
| `ARFaceTrackingConfiguration is not supported` | Symulator / iPhone bez TrueDepth | Zmień target na fizyczny iPhone X+ |
| `Provisioning profile does not match bundle identifier` | Stary cache signing | W Signing & Capabilities: od-zaznacz i zaznacz ponownie *Automatically manage signing* |
| Build działa, ale `.face` ma CRC mismatch na Tab5 | Niezgodność layout 32/36 B blendshape | Patrz [HANDOFF §3.1](HANDOFF.md#31-krytyczne-rozmiar-wpisu-blendshape_table--36-b-vs-32-b) |
| `Library 'stdc++' not found` | Mylisz z projektem rack-eye — to Rust build, nie Xcode | Sprawdź katalog roboczy |
