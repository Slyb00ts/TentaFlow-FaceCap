# tentaflow-facecap

Natywna aplikacja iOS (Swift 5.10, SwiftUI, iOS 17+) do skanowania głowy użytkownika,
kalibracji 52 blendshapes ARKit, wstrzyknięcia rigid assets (oczy/zęby/język/jama ustna),
nagrywania klipów performance i eksportu profilu twarzy w binarnym formacie `.face v3`
do urządzenia **ESP32-P4 M5Stack Tab5** projektu **rack-eye**.

**Repozytorium:** `git@github.com:Slyb00ts/TentaFlow-FaceCap.git`

---

## Dla kogo

Użytkownik-właściciel urządzenia Tab5, który chce wyświetlać na LCD własną twarz
zamiast domyślnego avatara. Cały proces zajmuje ok. 15 minut i generuje jeden plik
`.face` (2–3 MB), który jest następnie ładowany przez runtime Rust na Tab5 jako
`HeadKind::Head7` (Head_7 User).

---

## Wymagania

| Pozycja | Minimum | Zalecane |
|---|---|---|
| iOS | 17.0 | 17.4+ |
| iPhone | X, XR, XS (TrueDepth wymagany) | 12 Pro+ (LiDAR dla Object Capture) |
| Xcode | 15.4 | 15.4+ |
| macOS | Sonoma 14.0 | Sonoma 14.5+ |
| Apple Developer ID | free (7-day sideload) | Paid (unlimited) |
| Miejsce na dysku | 500 MB (klipy + tekstury) | 2 GB |

Aplikacja **nie uruchomi się na symulatorze** — ARKit `ARFaceTrackingConfiguration`
oraz Metal preview wymagają fizycznego urządzenia.

---

## Szybki start (4 kroki)

1. Sklonuj repozytorium i otwórz w Xcode:
   ```bash
   git clone git@github.com:Slyb00ts/TentaFlow-FaceCap.git
   cd TentaFlow-FaceCap
   open tentaflow-facecap.xcodeproj
   ```

2. W Xcode wybierz **Team** w zakładce *Signing & Capabilities*
   (target `tentaflow-facecap`). Free Apple ID jest wystarczające.

3. **Dodaj brakujące lokalne pakiety SPM** (szczegóły w [`docs/HANDOFF.md`](docs/HANDOFF.md)):
   *File → Add Package Dependencies → Add Local…* i wskaż po kolei katalogi:
   `Packages/HeadScan`, `Packages/FaceCalibration`, `Packages/AssetInjection`,
   `Packages/PerformanceCapture`, `Packages/Preview`.

4. Podłącz iPhone'a przez USB, wybierz go w pasku schematu i kliknij **Run** (⌘R).

---

## Dalsza dokumentacja

| Dokument | Zawartość |
|---|---|
| [`docs/HANDOFF.md`](docs/HANDOFF.md) | Handoff dla następnego programisty / AI — stan projektu, znane bugi, checklist testu E2E, ADR |
| [`docs/BUILD.md`](docs/BUILD.md) | Szczegóły buildu (Xcode, CLI, signing, entitlements, ostrzeżenia) |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Przepływ danych, moduły Swift, zależności runtime, po stronie Rust |
| [`docs/FORMAT_SPEC.md`](docs/FORMAT_SPEC.md) | **Kanoniczna** specyfikacja formatu binarnego `.face v3` — layout bajt po bajcie |

Po stronie rack-eye: [`rack-eye/docs/head7_integration.md`](../../rust/rack-eye/docs/head7_integration.md).

---

## Licencja

Projekt wewnętrzny TentaFlow. Zobacz `LICENSE` (TBD).
