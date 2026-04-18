# ARCHITECTURE — tentaflow-facecap

Przegląd architektury aplikacji iOS i jej integracji z urządzeniem Tab5
(projekt rack-eye).

---

## 1. Przepływ danych (end-to-end)

```
                iPhone (SwiftUI + ARKit + Metal + AVFoundation)
                --------------------------------------------------------------
                                                                            
 [Onboarding] ─► [HeadScanBrief] ─► [HeadScanCapture]                     
                                    │                                        
                                    ▼                                        
                             HeadScanCoordinator                             
                             ├─ ObjectCaptureSessionWrapper (LiDAR)          
                             └─ FallbackPhotoCapture (manual 8 zdjęć)        
                                    │                                        
                                    ▼                                        
                             USDZMeshExtractor ─► MeshDecimator ─► ScanQualityAnalyzer
                                    │                                        
                                    ▼                                        
                             HeadScanResult (vertices, normals, uvs, tri, tex)
                                    │                                        
                                    ▼                                        
 [CalibrationBrief] ─► [NeutralFace] ─► [CalibrationStep × 52]                
                                    │                                        
                                    ▼                                        
                             FaceTrackingSession (ARKit ARFaceAnchor 60 Hz)   
                             ├─ ARKitFaceBridger (mesh delta extraction)     
                             ├─ BlendshapeReader (52 AU)                      
                             ├─ NeutralFaceCapture (baseline)                 
                             ├─ CalibrationStepController (per-AU capture)   
                             ├─ BlendshapeDeltaExtractor                      
                             ├─ DecorrelationSolver (NNLS 52×52)              
                             ├─ BlendshapeDeltaTransfer (→ scan mesh topology)
                             └─ CalibrationValidator                          
                                    │                                        
                                    ▼                                        
                             FaceCalibrationResult (52 blendshape deltas)   
                                    │                                        
                                    ▼                                        
                             AssetInjection (auto, z landmarków ARKit neutral)
                             ├─ EyeSphereGenerator + EyePositioner           
                             ├─ IrisColorSampler (tęczówka z kamery)         
                             ├─ TeethRowGenerator + TeethPositioner          
                             ├─ TongueGenerator + TonguePositioner           
                             └─ MouthCavityGenerator + MouthCavityPositioner 
                                    │                                        
                                    ▼                                        
                             AssetInjectionResult (eyes, teeth, tongue, mouth)
                                    │                                        
                                    ▼                                        
 [PerformanceCapture] ─► do 5 klipów × 60 s                                  
                             ├─ PerformanceRecorder (timeline 52 AU 30 Hz)   
                             ├─ AudioRecorder (AVAudioEngine 44.1 kHz)       
                             ├─ AudioResampler (→ 16 kHz mono)               
                             └─ PerformanceQuantizer (f32 → u8)              
                                    │                                        
                                    ▼                                        
                             [Preview] — FacePreviewRenderer (Metal)         
                             ├─ PreviewMeshBuilder                            
                             ├─ RigSkinner (live blend)                      
                             ├─ LiveFaceDriver (ARKit → preview)             
                             ├─ EmotionBlender + EmotionPreset               
                             ├─ VisemeOverlay (lipsync debug)                
                             └─ IdleAnimator (breath, microsaccades)         
                                    │                                        
                                    ▼                                        
                             [Export] ─► FaceAssetData                       
                                    │                                        
                                    ▼                                        
                             FaceFileWriter                                   
                             ├─ SectionBuilder × 11 sekcji                   
                             ├─ TextureConverter (CIImage → RGB565 512×512)  
                             ├─ SparseDeltaEncoder (dense/sparse)            
                             ├─ PerformanceQuantizer (weights + PCM16)       
                             ├─ ByteWriter (append + patch + pad)            
                             └─ CRC32 (IEEE, pole wyzerowane)                
                                    │                                        
                                    ▼                                        
                             Documents/Faces/<profile>.face                   
                                    │                                        
                                    ▼                                        
 [Transfer] ── AirDrop / Files.app / Wi-Fi Bonjour _rackeye._tcp.             
                                                                            
═══════════════════════════════════════════════════════════════════════════════
                                                                            
                rack-eye (ESP32-P4 Tab5, Rust no_std-ish)                    
                --------------------------------------------------------------
                                                                            
 assets/faces/user.face  (include_bytes! w build time, albo microSD mmap)    
                                    │                                        
                                    ▼                                        
                             face_v3_loader::FaceV3Ref::from_bytes           
                             ├─ magic / version / total_size / CRC32         
                             ├─ directory walk (32 B-aligned check)          
                             └─ section slicing (zero-copy)                  
                                    │                                        
                                    ▼                                        
                             head7_user::load_user_face ─► Head7Data         
                             ├─ vertices + edges (VertexGrouped)             
                             ├─ mesh_variants[4] (sparse/normal/dense/ultra) 
                             ├─ uv_coords + triangles                        
                             ├─ texture RGB565                                
                             ├─ blendshape deltas (52, sparse/dense)         
                             ├─ masks L/R                                    
                             ├─ eye_spheres / teeth_row / tongue / mouth_cav 
                             └─ performance_clips                            
                                    │                                        
                                    ▼                                        
                             FaceRenderer ─► rasterizer ─► LCD 720×1280      
                                                                            
```

---

## 2. Moduły Swift

Aplikacja jest podzielona na 8 lokalnych pakietów SPM + target aplikacji.

| Pakiet | Rola |
|---|---|
| **Shared** | Baza dla wszystkich pozostałych — logger, error type, capabilities, math helpers, reusable UI (LoadingOverlay) |
| **HeadScan** | Skan głowy 3D — RealityKit Object Capture (LiDAR) lub manual photo capture jako fallback. Ekstrakcja USDZ → mesh → decimacja |
| **FaceCalibration** | Kalibracja 52 AU przez ARKit Face Tracking. Obejmuje guided UX (52 kroki), NNLS dekorelację i transfer delt na topologię skanu |
| **AssetInjection** | Automatyczne wstrzyknięcie 4 rigid assets (oczy/zęby/język/jama ustna) z pozycjami wyprowadzonymi z ARKit landmarks |
| **PerformanceCapture** | Nagrywanie do 5 klipów × 60 s — 52 AU weights 30 Hz + audio 16 kHz PCM16. Biblioteka klipów z quantyzacją |
| **Preview** | Podgląd Metal — mesh + rig + texture + blendshapes. Live driver z ARKit, emotion presets, viseme overlay, idle animator |
| **Export** | Zapis pliku `.face v3` — cały writer z SectionBuilder, CRC32, CIImage → RGB565, sparse delta encoder, walidator |
| **Transfer** | Wysyłka pliku — AirDrop, Files.app, Wi-Fi Bonjour (`_rackeye._tcp.`). Progres transferu jako Combine publisher |

### Target aplikacji

Katalog `tentaflow-facecap/`:
- `App/TentaflowFacecapApp.swift` — `@main`, konfiguracja sceny
- `App/AppRouter.swift` — navigation state machine (12 ekranów, enum `AppScreen`)
- `App/AppEnvironment.swift` — DI kontener (`@EnvironmentObject`)
- `Views/*.swift` — 9 ekranów SwiftUI (onboarding → head scan → calibration → performance → preview → export → transfer)
- `Resources/ARKitBlendshapeGuide.json` — 52 wpisy z promptami PL dla kroków kalibracji
- `Resources/Localizable.strings` — UI strings PL

---

## 3. Zależności runtime

Aplikacja używa **wyłącznie** frameworków Apple — brak zewnętrznych dependencies.

| Framework | Wykorzystanie |
|---|---|
| **SwiftUI** | Całe UI, routing, environment |
| **Combine** | Progress publishers (transfer, recording), reactive bindings |
| **ARKit** | `ARFaceTrackingConfiguration`, `ARFaceAnchor.blendShapes`, face landmarks |
| **RealityKit** | `ObjectCaptureSession`, `PhotogrammetrySession`, USDZ export |
| **Metal / MetalKit** | `FacePreviewRenderer`, `PreviewShaders.metal` (vertex + fragment) |
| **AVFoundation** | `AVAudioEngine` (mic input), `AVAudioConverter` (resampling 44.1 → 16 kHz) |
| **Accelerate** | `vImage`, `vDSP` — NNLS solver, FFT w viseme, konwersja f32↔f16 |
| **CoreImage** | Pre-processing tekstury przed konwersją do RGB565 |
| **simd** | Wektory/macierze do kalibracji i renderingu |
| **Network** | `NWConnection` dla Wi-Fi Bonjour uploadu, `NWBrowser` dla discovery |

**Minimum deployment target:** iOS 17.0 (ARFaceAnchor API, ObjectCaptureSession).

---

## 4. Strona rack-eye (Rust)

### 4.1. Parser — `face_v3_loader.rs`

Zero-copy, działa w środowisku embedded (`no_std` friendly). Podstawowe kontrakty:

- Wejście: `&[u8]` (z `include_bytes!` albo mmap z microSD).
- Wyjście: `FaceV3Ref<'a>` — wszystkie metody zwracają `&'a [T]` bez kopii.
- Gwarancje walidacji: magic + wersja + CRC32 + directory offsetów 32B-aligned.
- Błędy jako enum `FaceV3Error` (7 wariantów).

Struktura:
```
FaceV3Ref::from_bytes(&buf)
  ├─ header() → FileHeader
  ├─ section_count() / section_entry(idx)
  ├─ mesh_positions() / mesh_normals() / mesh_uvs()
  ├─ mesh_triangles() → (tris, Option<uv_tris>)
  ├─ vertex_groups()
  ├─ texture() → TextureView (width, height, pixels RGB565 LE)
  ├─ blendshape_count() / blendshape_entry(idx) / iter_blendshapes()
  ├─ sparse_delta_slice(bs) / dense_delta_slice(bs)
  ├─ masks() → Option<(left, right)>
  ├─ performance_clips() → Option<PerformanceClipsView>
  ├─ eye_spheres() → Option<EyeSpheresView>
  ├─ teeth_row() → Option<TeethRowView>
  ├─ tongue() → Option<TongueView>
  └─ mouth_cavity() → Option<MouthCavityView>
```

### 4.2. Adapter — `head7_user.rs`

Konwertuje `FaceV3Ref` na struktury wewnętrzne rendera rack-eye:

```
FaceV3Ref  ─► head7_user::load_user_face  ─► Head7Data {
   vertices:      Vec<VertexGrouped>
   edges:         Vec<Edge>
   edge_kinds:    Vec<EdgeKind>
   mesh_variants: [Vec<u32>; 4]        // sparse/normal/dense/ultra
   triangles:     Vec<[u16; 3]>
   uv_coords:     Vec<[f32; 2]>
   texture:       Option<TextureRGB565>
   blendshapes:   Vec<BlendshapeDelta>
   masks:         (MaskL, MaskR)
   eye_spheres:   Option<EyeSpheresData>
   teeth_row:     Option<TeethRowData>
   tongue:        Option<TongueData>
   mouth_cavity:  Option<MouthCavityData>
   clips:         Vec<PerformanceClipData>
}
```

Pozostałe pliki łączenia:
- `board/face/types.rs` — `enum HeadKind { Human, Jarvis, Head3, Head4, Head5, Head7 }`,
  `HeadKind::build()` deleguje do `head7_user::Head7User.build()`.
- `board/face/renderer.rs` — `FaceRenderer` bierze `Head7Data` i renderuje na LCD.

### 4.3. Placeholder mode

Jeśli `assets/faces/user.face` jest pusty lub uszkodzony:
- `FaceV3Ref::from_bytes` zwraca `FaceV3Error::TooShort` / `BadMagic`,
- `head7_user::load_user_face` spada na **ośmiościan** (8 wierzchołków, 12 krawędzi),
- Logger emituje WARN, aplikacja nadal działa.

Placeholder umożliwia development rack-eye bez konieczności generowania prawdziwego
pliku `.face`.

---

## 5. Kolejność renderowania multi-mesh na Tab5

Każdy frame na Tab5 renderuje nawet 5 różnych geometrii. Poprawna kolejność
**MA ZNACZENIE** dla widoczności (z-buffer i zasłanianie):

```
1. mouth_cavity       (0x0044) — najgłębiej, wnętrze ust
2. teeth_row          (0x0042) — zęby przed jamą ustną
3. tongue             (0x0043) — język między zębami
4. eye_sockets        (część face_skin, generowane lokalnie) — oczodoły
5. eye_spheres        (0x0041) — sfery w oczodołach
6. face_skin          (0x0001..0x0005 + 0x0010) — skóra twarzy na końcu
```

**Dlaczego tak:**
- mouth_cavity ma być niewidoczne z zewnątrz — renderuje się **przed** face_skin,
- tongue może wystawać przez zęby (animacja *tongueOut*) — musi być renderowany
  po zębach, żeby zasłaniać je z odpowiedniej strony,
- eye_sockets to geometria face_skin wokół oczu, z góry zasłania część sfery
  (powieki), ale sfera wystaje do przodu — renderuje się sferę **przed** skórą.

Rasterizer rack-eye używa painter's algorithm z sortowaniem per-triangle (nie
Z-buffer), więc kolejność meshów jest wymagana przez samą architekturę rendera.

---

## 6. Wydajność (estymaty)

| Metryka | Wartość | Źródło |
|---|---|---|
| Rozmiar `.face v3` | 2–3 MB | ~2000 vertów + 512² RGB565 + 52 AU + 30 s performance |
| iPhone — Object Capture | 30–45 s | LiDAR + 3 okrążenia |
| iPhone — Calibration 52 AU | 4–6 min | 52 kroki × 5–7 s |
| iPhone — Export | 2–5 s | CIImage→RGB565 + zip sekcji |
| Transfer Wi-Fi Bonjour | 1–3 s | 2 MB @ 802.11n lokalny |
| Rack-eye — parse .face | 10 ms | zero-copy, tylko nagłówek kopiowany |
| Rack-eye — render frame | 5–10 fps | 2000 verts + textura + rasterizer |

---

## 7. Future work (w rack-eye, zgodne z ADR)

Elementy przygotowane po stronie iOS, które **jeszcze nie są** zaimplementowane
w runtime rack-eye:

- **`Mimicry52`** — runtime blendshape applier (analogicznie do `Mimicry` dla Head5).
  Parser ma już delty, brakuje mikserki na poziomie rendera.
- **`EmotionBlender`** — wybór presetu (joy/anger/surprise/…) + interpolacja do 52 AU.
  Preset table jest po stronie iOS w `Preview/EmotionPreset.swift`, ale runtime
  na Tab5 musi mieć własną kopię.
- **`VisemeStreamer`** — pipeline audio (mikrofon Tab5) → FFT → fonemy → viseme
  weights → 52 AU. W tej chwili klipy performance to *pre-nagrane* audio + wagi.
- **`IdleAnimator`** — losowe micro-saccades + oddech (breath cycle). Po stronie iOS
  istnieje implementacja referencyjna w `Preview/IdleAnimator.swift`.

Patrz [`/home/critix/repos/rust/rack-eye/docs/head7_integration.md`](../../../rust/rack-eye/docs/head7_integration.md).
