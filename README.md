# tentaflow-facecap

Native iOS app (Swift 5.10, SwiftUI, iOS 17+) for scanning the user's head,
calibrating 52 ARKit blendshapes, injecting rigid assets (eye spheres, teeth,
tongue, mouth cavity), recording performance clips, capturing 20 authentic
facial expression snapshots, and exporting a face profile in the binary
`.face v3` format to the **ESP32-P4 M5Stack Tab5** device of the **rack-eye**
project.

**Repository:** `git@github.com:Slyb00ts/TentaFlow-FaceCap.git`

---

## Who is this for

Tab5 device owners who want to display their own face on the LCD instead of
a default avatar. The whole process takes about 15–20 minutes and produces
a single `.face` file (2–3 MB) which is then loaded by the Rust runtime on
Tab5 as `HeadKind::Head7` (Head_7 User).

---

## Requirements

| Item | Minimum | Recommended |
|---|---|---|
| iOS | 17.0 | 17.4+ |
| iPhone | X, XR, XS (TrueDepth required) | 12 Pro+ (LiDAR for Object Capture) |
| Xcode | 15.4 | 15.4+ |
| macOS | Sonoma 14.0 | Sonoma 14.5+ |
| Apple Developer ID | free (7-day sideload) | paid (unlimited) |
| Disk space | 500 MB (clips + textures) | 2 GB |

The app **will not run in the simulator** — ARKit `ARFaceTrackingConfiguration`
and Metal preview require a physical device.

---

## Pipeline overview

```
Onboarding → Head Scan → Face Calibration (52 AU) → Performance Capture
    → Expression Snapshots (20 presets) → Preview → Export → Transfer
```

1. **Head Scan** — Object Capture (iOS 17+) or manual photogrammetry captures
   your full head geometry. Decimated on-device to ~2000 vertices via
   Garland-Heckbert quadric edge collapse.

2. **Face Calibration** — guided 52 ARKit Action Units (AU), each calibrated
   individually. NNLS decorrelation via Accelerate LAPACK decouples
   correlated AUs (e.g. `eyeBlinkLeft` accidentally mixed with `eyeLookDownLeft`).
   Kabsch/ICP + KD-tree bridges canonical ARKit 1220-vertex mesh deltas to your
   scan mesh.

3. **Performance Capture** — optional timeline recordings (60 fps × up to 60 s)
   with synchronized PCM audio (16 kHz mono) for emotional arcs and talking
   animations.

4. **Expression Snapshots** — 20 authentic facial expressions captured as
   52-AU weight vectors at peak moment. User's natural muscle mixing replaces
   heuristic FACS composition on-device. Includes asymmetric expressions
   (single brow raise, wink, half-smile) that standard FACS cannot represent.

5. **Asset Injection** — procedural rigid pieces auto-positioned from ARKit
   landmarks: eye spheres (with iris color sampled from scan texture), teeth
   rows (upper + jaw-animated lower), tongue, dark mouth cavity. Solves the
   photogrammetry limitation of capturing only outer surfaces.

6. **Export** — serializes everything to `.face v3` custom binary format
   (little-endian, 32-byte cache-line aligned, CRC32-IEEE checksummed).

7. **Transfer** — AirDrop / Files app / Bonjour-discovered WiFi upload
   (`_rackeye._tcp.local`) to the Tab5 device.

---

## Quick start (4 steps)

1. Clone the repository and open in Xcode:
   ```bash
   git clone git@github.com:Slyb00ts/TentaFlow-FaceCap.git
   cd TentaFlow-FaceCap
   open tentaflow-facecap.xcodeproj
   ```

2. In Xcode select your **Team** under *Signing & Capabilities*
   (target `tentaflow-facecap`). A free Apple ID is sufficient.

3. **Add the missing local SPM packages** (details in
   [`docs/HANDOFF.md`](docs/HANDOFF.md)):
   *File → Add Package Dependencies → Add Local…* and select each of:
   `Packages/HeadScan`, `Packages/FaceCalibration`, `Packages/AssetInjection`,
   `Packages/PerformanceCapture`, `Packages/Preview`.

4. Connect your iPhone via USB, select it in the scheme selector and
   click **Run** (⌘R).

---

## Architecture

8 local Swift Package Manager modules + main app target:

| Module | Responsibility |
|---|---|
| `Shared` | Logger, device capabilities, math (SIMD helpers, Lawson-Hansen NNLS via LAPACK) |
| `Export` | `.face v3` writer, 13 section builders, CRC32, sparse f16 delta encoder |
| `Transfer` | AirDrop, Files app, Bonjour-discovered WiFi multipart uploader |
| `HeadScan` | Object Capture wrapper, Garland-Heckbert quadric mesh decimation |
| `FaceCalibration` | ARKit 52 AU, NNLS solver (`dgesv_`), Kabsch SVD (`dgesvd_`), KD-tree |
| `PerformanceCapture` | Timeline recorder (52 AU × 60 fps) + audio + expression snapshots |
| `AssetInjection` | Procedural eye spheres / teeth rows / tongue / mouth cavity |
| `Preview` | Metal renderer with FACS emotion blender and Preston-Blair viseme overlay |

~13 000 lines of Swift. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for
the complete data-flow diagram.

---

## Further documentation

| Document | Contents |
|---|---|
| [`docs/HANDOFF.md`](docs/HANDOFF.md) | Handoff for the next developer / AI — project state, known bugs, E2E test checklist, architecture decision records |
| [`docs/BUILD.md`](docs/BUILD.md) | Build details (Xcode, CLI, signing, entitlements, warnings) |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Data flow, Swift modules, runtime dependencies, Rust side |
| [`docs/FORMAT_SPEC.md`](docs/FORMAT_SPEC.md) | **Canonical** binary `.face v3` specification — byte-by-byte layout |

On the rack-eye side: [`rack-eye/docs/head7_integration.md`](../../rust/rack-eye/docs/head7_integration.md).

---

## Device compatibility matrix

| iPhone model | TrueDepth | LiDAR | Head scan path | Calibration |
|---|---|---|---|---|
| iPhone X / XR / XS / 11 | ✅ | ❌ | Fallback (manual 30-photo capture) | Full 60 fps |
| iPhone 12 / 13 / 14 / 15 | ✅ | ❌ | Fallback (manual 30-photo capture) | Full 60 fps |
| iPhone 12 Pro / 13 Pro / 14 Pro / 15 Pro | ✅ | ✅ | Object Capture (real-time guided) | Full 60 fps |

LiDAR is strongly recommended — Object Capture produces markedly cleaner
geometry with live coverage feedback compared to the manual photo capture
fallback.

---

## License

Licensed under the [Apache License, Version 2.0](LICENSE).

Copyright © 2026 TentaFlow / Slyb00ts.

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.
