# HANDOFF — tentaflow-facecap

Dokument przekazania projektu kolejnemu programiście lub agentowi AI, który będzie
dokańczał aplikację na Macu. Projekt został zbudowany przez 4 równoległe agenty AI
na środowisku Linux (bez Xcode), więc **części nie dało się zweryfikować** i wymagają
sprawdzenia w Xcode na fizycznym urządzeniu.

Przeczytaj ten dokument **w całości** przed pierwszym uruchomieniem.

---

## 1. Co zostało zrobione

Projekt podzielono na 4 porcje pracy dla równoległych agentów. Każdy agent
odpowiadał za dedykowany pakiet SPM lub zestaw ekranów.

### Agent #1 — core app + Shared/Export/Transfer (~4900 linii)

| Moduł | Ścieżka | Kluczowe klasy |
|---|---|---|
| Xcode project | `tentaflow-facecap.xcodeproj/project.pbxproj` | objectVersion 77, sceneManifest single-scene |
| App entry | `tentaflow-facecap/App/TentaflowFacecapApp.swift` | `@main struct TentaflowFacecapApp` |
| Routing | `tentaflow-facecap/App/AppRouter.swift` | `AppRouter`, enum `AppScreen` (12 kroków) |
| DI | `tentaflow-facecap/App/AppEnvironment.swift` | `AppEnvironment` — singleton kontener serwisów |
| Views | `tentaflow-facecap/Views/*.swift` | `OnboardingView`, `HeadScanBriefView`, `HeadScanCaptureView`, `CalibrationBriefView`, `NeutralFaceView`, `CalibrationStepView`, `PerformanceCaptureView`, `ExportView`, `TransferProgressView` |
| **Shared** | `Packages/Shared/` | `AppLog`, `DeviceCapabilities`, `FacecapError`, `LoadingOverlay`, math (`SIMDExtensions`, `LinearAlgebra`, `QuadraticSolver`) |
| **Export** | `Packages/Export/` | `FaceFileWriter`, `SectionBuilder`, `ByteWriter`, `CRC32`, `TextureConverter`, `SparseDeltaEncoder`, `PerformanceQuantizer`, `FaceFileValidator`, `FaceAssetData`, `FaceFileFormat` |
| **Transfer** | `Packages/Transfer/` | `AirDropExporter`, `FilesAppExporter`, `WiFiUploader` (Bonjour `_tentaflow._tcp.`), `ShareSheetController`, `TransferProgress` |
| Info.plist | `tentaflow-facecap/Info.plist` | 4 usage descriptions PL + UTI `pl.tentaflow.face` |
| Entitlements | `tentaflow-facecap/tentaflow-facecap.entitlements` | Local network client |
| Resources | `tentaflow-facecap/Resources/` | `Localizable.strings` (PL), `ARKitBlendshapeGuide.json`, `Assets.xcassets` (AppIcon/AccentColor) |

### Agent #2 — HeadScan + FaceCalibration + AssetInjection (~4300 linii)

| Pakiet | Ścieżka | Kluczowe klasy |
|---|---|---|
| **HeadScan** | `Packages/HeadScan/` | `HeadScanCoordinator`, `ObjectCaptureSessionWrapper` (RealityKit Object Capture), `PhotogrammetrySessionRunner`, `FallbackPhotoCapture` (manual bez LiDAR), `USDZMeshExtractor`, `MeshDecimator`, `ScanQualityAnalyzer`, `CaptureGuidance`, `HeadScanResult` |
| **FaceCalibration** | `Packages/FaceCalibration/` | `FaceTrackingSession` (ARKit), `ARKitFaceBridger`, `BlendshapeReader`, `NeutralFaceCapture`, `CalibrationStepController`, `ArkitAU` (52 AU), `BlendshapeDeltaExtractor`, `BlendshapeDeltaTransfer`, `DecorrelationSolver` (NNLS), `CalibrationValidator`, `FaceCalibrationResult` |
| **AssetInjection** | `Packages/AssetInjection/` | `EyeSphereGenerator`/`EyePositioner`/`IrisColorSampler`, `TeethRowGenerator`/`TeethPositioner`, `TongueGenerator`/`TonguePositioner`, `MouthCavityGenerator`/`MouthCavityPositioner`, `AssetInjectionResult` |

### Agent #3 — PerformanceCapture + Preview (~2560 linii)

| Pakiet | Ścieżka | Kluczowe klasy |
|---|---|---|
| **PerformanceCapture** | `Packages/PerformanceCapture/` | `PerformanceRecorder` (timeline 52 AU), `PerformancePlayer`, `AudioRecorder` (AVFoundation), `AudioResampler` (→ 16 kHz PCM16), `PerformanceQuantizer` (u8 0..255), `PerformanceClip`, `ClipLibrary`, `PerformanceCaptureError` |
| **Preview** | `Packages/Preview/` | `FacePreviewView`, `FacePreviewRenderer` (Metal), `PreviewShaders.metal`, `PreviewMeshBuilder`, `RigSkinner`, `LiveFaceDriver`, `EmotionBlender`, `EmotionPreset`, `VisemeOverlay`, `IdleAnimator`, `PreviewError` |

### Agent #4 — Rust loader (tentaflow-buddy, ~1200 linii)

| Moduł | Ścieżka |
|---|---|
| Parser zero-copy | `rack-eye/src/board/face/face_v3_loader.rs` |
| Typy binarne | `rack-eye/src/board/face/face_v3_types.rs` |
| Adapter head7 | `rack-eye/src/board/face/head7_user.rs` |
| Placeholder | `rack-eye/assets/faces/user.face` (pusty) |

---

## 2. Co wymaga uwagi NA MACU

Tego nie dało się przetestować z Linuxa. Lista rzeczy, które **muszą zostać
zweryfikowane** przy pierwszym otwarciu na macOS:

### 2.1. Pierwsze otwarcie w Xcode — auto-upgrade pbxproj

Xcode 15.4 może zaproponować konwersję `project.pbxproj` na nowszy format
(objectVersion 77 jest OK, ale schema xcworkspace może być zaktualizowane).
**Zaakceptuj** propozycję, po czym zrób commit.

### 2.2. Apple Developer Team

W *Signing & Capabilities* target `tentaflow-facecap` nie ma przypisanego Team.
Wybierz swoje konto Apple ID. Free Apple ID wystarczy do sideload na 7 dni;
dla dłuższego testowania potrzeba Paid Developer Program.

### 2.3. Brakujące pakiety SPM (**KRYTYCZNE**)

`project.pbxproj` obecnie referuje tylko trzy lokalne pakiety SPM:
- `Packages/Shared`
- `Packages/Export`
- `Packages/Transfer`

**Brakujące pakiety** (istnieją na dysku, ale nie są podpięte do targetu):
- `Packages/HeadScan`
- `Packages/FaceCalibration`
- `Packages/AssetInjection`
- `Packages/PerformanceCapture`
- `Packages/Preview`

**Kroki ręcznego podłączenia w Xcode UI:**

1. W Xcode: *File → Add Package Dependencies…*
2. W oknie dialogowym kliknij *Add Local…* (dolny lewy róg).
3. Wybierz katalog `Packages/HeadScan` i dodaj do targetu `tentaflow-facecap`.
4. Powtórz krok 2–3 dla każdego z: `FaceCalibration`, `AssetInjection`,
   `PerformanceCapture`, `Preview`.
5. W *Target → General → Frameworks, Libraries, and Embedded Content*
   upewnij się, że wszystkie 5 pakietów są na liście *(Do Not Embed — static library)*.
6. Zrób commit zmian w `project.pbxproj`.

Po tej operacji `packageReferences` w pbxproj powinien zawierać 8 wpisów
`XCLocalSwiftPackageReference`.

### 2.4. Widoki mogą potrzebować dodatkowych importów

Pliki w `tentaflow-facecap/Views/` używają typów z pakietów, które dopiero
podłączysz (pkt 2.3). Jeśli kompilator zgłosi *cannot find type X in scope*,
dodaj na górze odpowiedniego widoku brakujący `import`:

```swift
import HeadScan            // HeadScanCaptureView, HeadScanBriefView
import FaceCalibration     // NeutralFaceView, CalibrationStepView, CalibrationBriefView
import AssetInjection      // (używane wewnątrz pipeline'u po kalibracji)
import PerformanceCapture  // PerformanceCaptureView
import Preview             // Podgląd na końcu flow
```

`Shared` i `Export` są już zaimportowane w większości plików.

### 2.5. ARKit tylko na prawdziwym iPhonie

`ARFaceTrackingConfiguration.isSupported` zwraca `false` na symulatorze.
Test face calibration **musi** odbyć się na fizycznym iPhone X+ z iOS 17+.

### 2.6. Object Capture — LiDAR wymagany dla najlepszej jakości

`RealityKit Object Capture` pełną jakość daje tylko na iPhone 12 Pro+.
Na starszych urządzeniach `HeadScanCoordinator` automatycznie przełączy się
na `FallbackPhotoCapture` (manualne zdjęcia z pozycji 8 punktów + photogrammetria
cloud).

### 2.7. Metal preview

`FacePreviewRenderer` używa `MTLDevice.createSystemDefault()`. Symulator iOS
ma ograniczone wsparcie Metal — test tylko na urządzeniu.

### 2.8. Permissions

Info.plist ma **polskie** teksty w usage descriptions:
- `NSCameraUsageDescription` — skan głowy i mimika
- `NSMicrophoneUsageDescription` — audio do klipów performance
- `NSPhotoLibraryAddUsageDescription` — zapis tekstur do biblioteki
- `NSLocalNetworkUsageDescription` — Bonjour/Wi-Fi transfer
- `NSBonjourServices = [_tentaflow._tcp.]`

Jeśli zmieniasz `CFBundleDevelopmentRegion` z `pl` na `en`, odpowiednio zaktualizuj
`Resources/Localizable.strings`.

---

## 3. Znane niezgodności i bugi do naprawy

### 3.1. (**KRYTYCZNE**) Rozmiar wpisu `BLENDSHAPE_TABLE` — 36 B vs 32 B

**Problem:** Swift writer i Rust reader **nie zgadzają się** co do rozmiaru
wpisu w tabeli blendshape.

| Strona | Plik | Rozmiar wpisu | Zawartość |
|---|---|---|---|
| Swift (writer) | `SectionBuilder.swift:118-127` | **32 B** (au_id, flags, name_len, pad, name[24], delta_offset u32) — `delta_count` **NIE JEST** zapisywany |
| Rust (reader) | `face_v3_types.rs:100` `BLENDSHAPE_ENTRY_SIZE = 32` | **32 B** — `delta_count` wyprowadza z różnicy offsetów sąsiednich wpisów (`face_v3_loader.rs:459-474`) |

**Stan faktyczny:** oba pisze/czyta 32 B. Jeśli planowana była wersja 36 B z polem
`delta_count: u32`, nie została wdrożona. Wariant 32 B **działa**, ale jest kruchy:
- wymaga, żeby writer utrzymywał rosnące offsety,
- wyprowadzenie count dla ostatniego wpisu wymaga znajomości długości blobu delt.

**Rekomendacja:** **przejść na 36 B** (dodać jawne pole `delta_count: u32` na końcu
wpisu). Dzięki temu:
- reader nie musi skanować tabeli,
- sparse delty można przestawiać bez dbania o kolejność,
- entry wyrównane do 4 B bez paddingu.

**Kroki migracji:**
1. W `FaceFileFormat.swift:23` zmień `sectionDirEntrySize` (to dotyczy katalogu
   sekcji — **zostaw 32**) — tu chodzi tylko o wpis blendshape'u.
2. W `SectionBuilder.swift:101-128` dodaj `tableW.writeU32(encoded.count)` **przed**
   `tableW.padPad32()`.
3. W `face_v3_types.rs:100` zmień `BLENDSHAPE_ENTRY_SIZE = 36`.
4. W `face_v3_loader.rs:429-483` usuń skanowanie sąsiednich offsetów i czytaj
   `delta_count` bezpośrednio z offsetu 32.
5. Zbuduj plik testowy, sprawdź CRC, zweryfikuj na Tab5.

Patrz [`FORMAT_SPEC.md`](FORMAT_SPEC.md) — ten dokument **wygrywa** przy konflikcie
i opisuje **36 B** jako wersję kanoniczną.

### 3.2. pbxproj — brak podpiętych 5 pakietów

Opisane w pkt **2.3** wyżej. Bez tego aplikacja nie zbudować się nie zbuduje.

### 3.3. `assets/faces/user.face` — pusty placeholder

Plik `/home/critix/repos/rust/rack-eye/assets/faces/user.face` **istnieje** (wymagane
przez `include_bytes!` w `head7_user.rs:19`), ale jest pusty (0 bajtów). Parser
`FaceV3Ref::from_bytes` wykryje `FaceV3Error::TooShort` i `head7_user::load_user_face`
spadnie na **placeholder mode** — ośmiościan (zobacz
`rack-eye/docs/head7_integration.md`).

**Żeby użyć prawdziwej twarzy:** wygeneruj `.face` z aplikacji iOS i skopiuj pod
tę ścieżkę **przed** `cargo build` (patrz pkt 4 poniżej).

### 3.4. Widoki Views — brak importów

Opisane w pkt **2.4**. Error widoczny dopiero po podpięciu pakietów SPM.

---

## 4. Instrukcja testu end-to-end

Zakłada, że punkty 2.1–2.4 zostały już wykonane (projekt się buduje).

**Pipeline:** iPhone → apka → plik `.face` → scp/AirDrop → tentaflow-buddy →
`cargo build` → flash → Tab5.

### Krok 1. Skan głowy
1. Otwórz `tentaflow-facecap.xcodeproj` w Xcode 15.4+.
2. Podłącz iPhone X+ / iOS 17+, wybierz w pasku schematu.
3. Build & Run (⌘R).
4. **Onboarding** — zaakceptuj uprawnienia kamera/mikrofon/sieć lokalna.
5. **Head Scan** — jeśli LiDAR: powoli obejdź głowę 2 razy (30–45 s).
   Bez LiDAR: zrób 8 zdjęć wg wskazówek na ekranie.

### Krok 2. Kalibracja 52 AU
6. **Neutral Face** — zrelaksuj twarz, naciśnij *Capture Neutral* (3 s countdown).
7. **52 Calibration Steps** — po kolei wykonuj prompty (uśmiech, marsz brwi,
   otwarcie ust, wysuwanie języka, itd.). Każdy krok 2–3 s.
8. Po kalibracji: dekorelacja NNLS biegnie w tle, efektem jest 52 delty.

### Krok 3. Asset injection (auto)
9. Po kalibracji system automatycznie pozycjonuje sfery oczu, wiersz zębów, język
   i jamę ustną używając landmarków ARKit z kroku neutralnego.

### Krok 4. Performance capture
10. **Record** — nagraj do 5 klipów (każdy max 60 s, audio 16 kHz).
    Sugestia: jeden klip = dłuższa wypowiedź, inne = krótkie emocje.

### Krok 5. Preview
11. **Preview** — Metal renderer pokazuje twarz z live ARKit driverem i opcjonalnym
    playbackiem nagranych klipów.

### Krok 6. Export
12. **Export** — `FaceFileWriter.write(asset:)` zapisuje plik do
    `Documents/Faces/<profile>.face` i pokazuje sumę CRC32 oraz rozmiar.

### Krok 7. Transfer do Maca
13. Wybierz:
    - **AirDrop** → Mac (jeśli Mac jest na tym samym Wi-Fi), albo
    - **Files** → *On My iPhone → tentaflow-facecap → Faces*, potem scp.

### Krok 8. Wdrożenie na tentaflow-buddy (Tab5)
14. Na Macu:
    ```bash
    cp ~/Downloads/<profile>.face \
       ~/repos/rust/rack-eye/assets/faces/user.face
    cd ~/repos/rust/rack-eye
    cargo clean           # bo include_bytes! jest kompilowany na stałe
    cargo build --release
    # Jeśli to pierwszy build po cargo clean, uruchom:
    ./scripts/patch-esp-dl.sh
    cargo build --release
    ```
15. Flash na Tab5 (instrukcja w głównym `tentaflow-buddy` `CLAUDE.md`).
16. Zmień `HeadKind` w runtime na `Head7` (jeśli jeszcze nie default).

---

## 5. Architecture Decision Record (ADR)

### ADR-01: Custom binary format `.face v3` zamiast rkyv

**Decyzja:** zdefiniowaliśmy własny format binarny z 32-bajtowym wyrównaniem sekcji,
little-endian, bez zależności od biblioteki serializacyjnej.

**Dlaczego NIE rkyv:**
- rkyv wire format zależy od wersji Rust i feature flag (atomic, no_std, bytecheck),
- replikacja wire format w Swift wymagałaby portu kilku tysięcy linii kodu generycznego,
- zmiany w strukturze po stronie Rust (np. reorder pól) niewidocznie psują Swift,
- debugowanie binarne rkyv to hex dump bez logicznego layoutu.

**Zalety custom:**
- 1:1 mapa struct ↔ offset w pliku (patrz [`FORMAT_SPEC.md`](FORMAT_SPEC.md)),
- CRC32 IEEE jako prosta gwarancja integralności,
- zero-copy parsing po stronie Rust (`read_unaligned` na packed struct),
- sekcje opcjonalne (flagi) bez przepisywania całości.

### ADR-02: NIE Face Cap / FaceBuilder jako warstwa reprezentacji

**Decyzja:** reprezentujemy twarz jako mesh face_skin **plus** 4 niezależne rigid
assety (eye spheres, teeth row, tongue, mouth cavity).

**Dlaczego NIE Face Cap / FaceBuilder:**
- oba systemy zakładają monolityczną geometrię twarzy + textury,
- brak zębów jako osobnej geometrii → niemożliwe animacje żucia,
- brak oczu jako sfer → niemożliwe śledzenie spojrzenia z obrotem tęczówki,
- brak jamy ustnej → "czarna dziura" przy mowie (artefakt wizualny).

**Wymagania runtime Tab5:**
- mouth_cavity MUSI być renderowane **przed** teeth/tongue (zasłanianie głębi),
- eye_spheres mają własny UV + iris color RGB565 (nie z głównej textury).

### ADR-03: Asset injection wymagany (nie opcjonalny)

**Decyzja:** po photogrammetrii zawsze wstrzykujemy 4 rigid pieces z pozycjami
wyprowadzonymi z ARKit face landmarks (mode neutralny).

**Dlaczego:**
- Photogrammetria Object Capture nie łapie wnętrza jamy ustnej (LiDAR nie widzi
  przez wargi, fotogrametria wymaga tekstury),
- Sfery oczu generowane parametrycznie (promień + pozycja z landmarków) są
  znacznie lepsze niż wypełnienie oczodołu z teksturą,
- Zęby i język są generowane jako low-poly template + skalowanie do rozmiaru
  anatomicznego użytkownika.

### ADR-04: 52 AU ARKit zamiast FACS bezpośrednio

**Decyzja:** używamy 52 ARKit blendshapes jako bazy, nie Ekman FACS.

**Dlaczego:**
- ARKit oferuje **gotowe** estymaty 52 współczynników z 60 fps natywnie na iPhone
  (żaden custom ML model nie jest potrzebny),
- każde 52 AU jest liniową kombinacją 1–3 FACS AU (`ArkitAU.swift` ma mapowanie),
- runtime na Tab5 dostaje **52 u8** per-frame = 52 bajty × 30 fps = 1.56 KB/s
  — łatwo zmieścić w PSRAM,
- dekorelacja NNLS (`DecorrelationSolver.swift`) usuwa liniowe zależności między
  AU po stronie iOS — runtime już ich nie musi korygować.

**Kompromis:** niektóre subtelne emocje (np. *contempt* = AU14 jednostronny)
trudno wyrazić w 52 AU, bo ARKit nie ma dedykowanego `mouthDimple*` unilateralnego.
Akceptujemy ograniczoną paletę emocji.

---

## 6. Checklist przed uznaniem handoff za zakończony

- [ ] Pkt 2.1–2.4 wykonane, projekt się buduje bez erorrów na Xcode 15.4+
- [ ] Pkt 3.1 — decyzja: 32 B (keep) albo 36 B (migrate) + aktualizacja `FORMAT_SPEC.md`
- [ ] Pkt 4 — pełen pipeline iPhone → `.face` → tentaflow-buddy → flash → Tab5 przeszedł
- [ ] `FaceFileValidator.validate()` po stronie iOS zwraca OK
- [ ] `FaceV3Ref::from_bytes` po stronie Rust zwraca OK (`cargo test` w face/)
- [ ] CRC32 pliku policzone przez Swift == CRC32 pliku policzone przez Rust
- [ ] Na LCD Tab5 widoczna jest twarz użytkownika (nie ośmiościan-placeholder)
- [ ] Testy jednostkowe Rust `cargo test -p tentaflow-buddy face::` — zielone
- [ ] Jakość skanu — ScanQualityAnalyzer zgłasza `.good` albo `.acceptable`
