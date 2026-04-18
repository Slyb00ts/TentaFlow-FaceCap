// =============================================================================
// Plik: ExportView.swift
// Opis: Finalizacja pliku .face — nazwa profilu, opcja LiDAR, rozmiar, eksport.
// =============================================================================

import SwiftUI
import simd
import Shared
import Export
import AssetInjection
import PerformanceCapture

struct ExportView: View {

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var environment: AppEnvironment

    @State private var profileName: String = "twarz_01"
    @State private var useLiDAR: Bool = false
    @State private var estimatedSize: String = "—"
    @State private var isExporting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(NSLocalizedString("export.title", comment: ""))
                .font(.largeTitle.bold())

            Form {
                Section(NSLocalizedString("export.section.profile", comment: "")) {
                    TextField(NSLocalizedString("export.profile.name", comment: ""), text: $profileName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Toggle(NSLocalizedString("export.use.lidar", comment: ""), isOn: $useLiDAR)
                        .disabled(!DeviceCapabilities.hasLiDAR)
                }
                Section(NSLocalizedString("export.section.summary", comment: "")) {
                    LabeledContent(NSLocalizedString("export.sum.vertices", comment: ""),
                                   value: "\(environment.session.scannedMeshVertices.count)")
                    LabeledContent(NSLocalizedString("export.sum.triangles", comment: ""),
                                   value: "\(environment.session.scannedMeshTriangles.count)")
                    LabeledContent(NSLocalizedString("export.sum.au", comment: ""),
                                   value: "\(environment.session.acceptedAU.count) / 52")
                    LabeledContent(NSLocalizedString("export.sum.clips", comment: ""),
                                   value: "\(environment.session.performanceClips.count)")
                    LabeledContent(NSLocalizedString("export.sum.expressions", comment: ""),
                                   value: "\(environment.expressionLibrary.snapshots.count) / \(ExpressionPreset.allCases.count)")
                    LabeledContent(NSLocalizedString("export.sum.size", comment: ""),
                                   value: estimatedSize)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Button(NSLocalizedString("export.cta", comment: "")) {
                Task { await performExport() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .disabled(isExporting || profileName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .onAppear {
            profileName = environment.session.profileName
            estimatedSize = estimateSize()
        }
        .overlay {
            if isExporting {
                LoadingOverlay(title: NSLocalizedString("export.loading", comment: ""))
            }
        }
    }

    // MARK: — Logika

    private func estimateSize() -> String {
        let v = environment.session.scannedMeshVertices.count
        let t = environment.session.scannedMeshTriangles.count
        let bs = environment.session.calibratedDeltas.values.reduce(0) { acc, deltas in
            acc + deltas.count * 10
        }
        let clips = environment.session.performanceClips.reduce(0) { acc, clip in
            acc + Int(clip.frameCount) * 52 + (clip.audioPCM?.count ?? 0) * 2
        }
        let base = 48 + 32 * 12 + v * 12 + v * 12 + v * 8 + t * 6 + v + 512 * 512 * 2
        let total = base + bs + clips
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }

    private func performExport() async {
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        environment.session.profileName = profileName
        environment.session.lidarUsed = useLiDAR && DeviceCapabilities.hasLiDAR

        let asset = buildAsset()

        do {
            let url = try environment.writer.write(asset)
            try environment.validator.validate(fileURL: url, expected: asset)
            await MainActor.run {
                environment.session.lastExportedFileURL = url
                router.advance()
            }
        } catch {
            AppLog.export.error("Export failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func buildAsset() -> FaceAssetData {
        let session = environment.session
        let guide = BlendshapeGuideLoader.loadAll()

        // Maski L/R liczone po znaku X wierzchołków skanu — używane tam, gdzie AU
        // dotyczy jednej strony twarzy (lewo vs prawo).
        let vertexCount = session.scannedMeshVertices.count
        let (maskLeft, maskRight) = buildLeftRightMasks(vertices: session.scannedMeshVertices)

        var entries: [BlendshapeEntry] = []
        for entry in guide {
            let deltas = session.calibratedDeltas[entry.auIndex]
                ?? [Vec3](repeating: .zero, count: vertexCount)

            // Dla kierunkowych AU (Left/Right) podpinamy maski strony, dla reszty — nil.
            let sideMasks = sideMasksForBlendshape(
                arkitKey: entry.arkitKey,
                maskLeft: maskLeft,
                maskRight: maskRight
            )

            entries.append(BlendshapeEntry(
                arkitIndex: UInt8(entry.auIndex),
                name: entry.namePL,
                deltas: deltas,
                maskLeft: sideMasks.left,
                maskRight: sideMasks.right,
                sparse: true
            ))
        }

        // Grupy wierzchołków per strefa mimiczna — dzielone wg pozycji.
        let vertexGroups = computeVertexGroups(vertices: session.scannedMeshVertices)

        // Rigid pieces: oczy / zęby / język / jama ustna.
        // Scan mesh nie ma zapamiętanych landmarków ARKit, więc zakładamy bounding box
        // jako proxy — daje to wystarczająco dobre placementy dla wersji eksportu.
        let rigid = buildRigidPieces(
            vertices: session.scannedMeshVertices,
            texture: session.scannedTexture
        )

        // Snapshoty wyrazów twarzy (faza F9) — konwertujemy na skwantyzowane wpisy 80 B.
        let snapshotEntries: [ExpressionSnapshotEntry] = environment.expressionLibrary
            .exportAsArray()
            .map { snap in
                ExpressionSnapshotEntry(
                    name: snap.name,
                    weights: snap.weights,
                    qualityScore: snap.qualityScore
                )
            }

        return FaceAssetData(
            profileName: session.profileName,
            vertices: session.scannedMeshVertices,
            normals: session.scannedMeshNormals,
            uvs: session.scannedMeshUVs,
            triangles: session.scannedMeshTriangles,
            triangleUVIndices: nil,
            vertexGroups: vertexGroups,
            textureImage: session.scannedTexture,
            blendshapes: entries,
            performanceClips: session.performanceClips,
            expressionSnapshots: snapshotEntries.isEmpty ? nil : snapshotEntries,
            eyes: rigid.eyes,
            teeth: rigid.teeth,
            tongue: rigid.tongue,
            mouthCavity: rigid.mouthCavity,
            lidarUsed: session.lidarUsed,
            createdAt: Date()
        )
    }

    // MARK: — Rigid pieces

    /// Paczka assetów rigid obliczona z bounding box skanu.
    private struct RigidPieces {
        let eyes: EyeSpheres?
        let teeth: TeethRow?
        let tongue: Tongue?
        let mouthCavity: MouthCavity?
    }

    /// Buduje komplet rigid pieces na podstawie bounding box skanu.
    /// Gdy skan jest pusty, zwraca pojedyncze generatory w pozycji (0,0,0) —
    /// ekran preview i tak pokaże je względem twarzy docelowej na urządzeniu.
    private func buildRigidPieces(vertices: [Vec3], texture: CGImage?) -> RigidPieces {
        let landmarks = estimateLandmarks(vertices: vertices)

        let eyeGen = EyeSphereGenerator()
        let eyeMesh = eyeGen.generate()

        // Transform sfer oka do współrzędnych świata twarzy.
        let leftVerts = transform(mesh: eyeMesh.verts, translation: landmarks.leftEyeCenter)
        let rightVerts = transform(mesh: eyeMesh.verts, translation: landmarks.rightEyeCenter)

        // Kolor tęczówki — z tekstury skanu (jeśli jest), inaczej fallback gray.
        let irisColors: IrisColors
        if let tex = texture {
            let sampler = IrisColorSampler()
            // Heurystyczne UV środka tęczówki — dwa punkty symetryczne wokół środka obrazu.
            let leftUV = SIMD2<Float>(0.35, 0.45)
            let rightUV = SIMD2<Float>(0.65, 0.45)
            irisColors = sampler.sampleBothEyes(texture: tex, leftCenterUV: leftUV, rightCenterUV: rightUV)
        } else {
            let fallback = Rgb565(value: 0x8410)
            irisColors = IrisColors(left: fallback, right: fallback)
        }

        let eyes = EyeSpheres(
            leftVertices: leftVerts,
            rightVertices: rightVerts,
            leftUVs: eyeMesh.uvs,
            rightUVs: eyeMesh.uvs,
            leftCenter: landmarks.leftEyeCenter,
            rightCenter: landmarks.rightEyeCenter,
            radius: eyeGen.radius,
            irisColorLeft: irisColors.left.value,
            irisColorRight: irisColors.right.value
        )

        // Zęby: transform wierzchołków górnych/dolnych do pozycji ust.
        let teethGen = TeethRowGenerator()
        let teethMesh = teethGen.generate()
        let upperPos = landmarks.mouthCenter + SIMD3<Float>(0, 0.005, -0.002)
        let lowerPos = landmarks.mouthCenter + SIMD3<Float>(0, -0.005, -0.002)
        let upperVerts = transform(mesh: teethMesh.upperVerts, translation: upperPos)
        let lowerVerts = transform(mesh: teethMesh.lowerVerts, translation: lowerPos)
        // Trójkąty dolnej szczęki indeksują wspólną przestrzeń `upper ∥ lower`, więc
        // przesuwamy je o rozmiar górnej szczęki.
        let upperOffset = UInt16(teethMesh.upperVerts.count)
        let combinedTris: [SIMD3<UInt16>] =
            teethMesh.upperTris +
            teethMesh.lowerTris.map { SIMD3<UInt16>($0.x &+ upperOffset, $0.y &+ upperOffset, $0.z &+ upperOffset) }
        let teeth = TeethRow(
            upperVertices: upperVerts,
            lowerVertices: lowerVerts,
            triangles: combinedTris
        )

        // Język — ellipsoid przesunięty do wnętrza ust.
        let tongueGen = TongueGenerator()
        let tongueMesh = tongueGen.generate()
        let tonguePos = landmarks.mouthCenter + SIMD3<Float>(0, -0.002, -0.015)
        let tongue = Tongue(
            vertices: transform(mesh: tongueMesh.verts, translation: tonguePos),
            triangles: tongueMesh.tris
        )

        // Jama ustna — box w głębi za zębami.
        let cavityGen = MouthCavityGenerator()
        let cavityMesh = cavityGen.generate()
        let cavityPos = landmarks.mouthCenter + SIMD3<Float>(0, 0, -0.025)
        let mouthCavity = MouthCavity(
            vertices: transform(mesh: cavityMesh.verts, translation: cavityPos),
            triangles: cavityMesh.tris,
            colorRGB565: cavityMesh.colorRgb565
        )

        return RigidPieces(eyes: eyes, teeth: teeth, tongue: tongue, mouthCavity: mouthCavity)
    }

    /// Przesunięcie wierzchołków meshy generatora do docelowej pozycji w przestrzeni twarzy.
    private func transform(mesh: [SIMD3<Float>], translation: SIMD3<Float>) -> [Vec3] {
        mesh.map { $0 + translation }
    }

    /// Heurystyczne landmarki twarzy z bounding box skanu.
    /// Konwencja: +Y = góra, +Z = do kamery (prawoskrętny, ARKit-compatible).
    private struct HeuristicLandmarks {
        let leftEyeCenter: SIMD3<Float>
        let rightEyeCenter: SIMD3<Float>
        let mouthCenter: SIMD3<Float>
    }

    /// Estymuje landmarki na podstawie bounding box wierzchołków skanu.
    private func estimateLandmarks(vertices: [Vec3]) -> HeuristicLandmarks {
        guard !vertices.isEmpty else {
            // Fallback: twarz referencyjna ARKit (~16 cm wysokości, centrowana w y≈0).
            return HeuristicLandmarks(
                leftEyeCenter: SIMD3<Float>(-0.03, 0.025, 0.04),
                rightEyeCenter: SIMD3<Float>(0.03, 0.025, 0.04),
                mouthCenter: SIMD3<Float>(0, -0.04, 0.05)
            )
        }
        var minV = vertices[0]
        var maxV = vertices[0]
        for v in vertices {
            minV = SIMD3<Float>(min(minV.x, v.x), min(minV.y, v.y), min(minV.z, v.z))
            maxV = SIMD3<Float>(max(maxV.x, v.x), max(maxV.y, v.y), max(maxV.z, v.z))
        }
        let width = max(1e-5, maxV.x - minV.x)
        let height = max(1e-5, maxV.y - minV.y)
        let centerX = (minV.x + maxV.x) * 0.5

        let eyeY = minV.y + height * 0.65
        let eyeZ = maxV.z - width * 0.1
        let eyeOffsetX = width * 0.2

        let mouthY = minV.y + height * 0.3
        let mouthZ = maxV.z - width * 0.05

        return HeuristicLandmarks(
            leftEyeCenter: SIMD3<Float>(centerX - eyeOffsetX, eyeY, eyeZ),
            rightEyeCenter: SIMD3<Float>(centerX + eyeOffsetX, eyeY, eyeZ),
            mouthCenter: SIMD3<Float>(centerX, mouthY, mouthZ)
        )
    }

    // MARK: — Maski L/R

    /// Liczy pary (maskLeft, maskRight) per-vertex z rampy po osi X.
    private func buildLeftRightMasks(vertices: [Vec3]) -> (left: [UInt8], right: [UInt8]) {
        let count = vertices.count
        guard count > 0 else { return ([], []) }
        var minX: Float = .infinity
        var maxX: Float = -.infinity
        for v in vertices {
            if v.x < minX { minX = v.x }
            if v.x > maxX { maxX = v.x }
        }
        let center = (minX + maxX) * 0.5
        let halfRange = max(1e-5, (maxX - minX) * 0.5)
        var left = [UInt8](repeating: 0, count: count)
        var right = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            let normalized = (vertices[i].x - center) / halfRange
            let leftF = max(0.0, min(1.0, 0.5 - 0.5 * normalized))
            let rightF = max(0.0, min(1.0, 0.5 + 0.5 * normalized))
            left[i] = UInt8((leftF * 255.0).rounded())
            right[i] = UInt8((rightF * 255.0).rounded())
        }
        return (left, right)
    }

    /// Dla AU z sufiksem `Left`/`Right` zwraca właściwą maskę strony. Dla pozostałych
    /// AU zwraca `nil` na obu polach (reader nie zapisze sekcji masks per entry).
    private func sideMasksForBlendshape(
        arkitKey: String,
        maskLeft: [UInt8],
        maskRight: [UInt8]
    ) -> (left: [UInt8]?, right: [UInt8]?) {
        if arkitKey.hasSuffix("Left") {
            return (maskLeft, nil)
        }
        if arkitKey.hasSuffix("Right") {
            return (nil, maskRight)
        }
        return (nil, nil)
    }

    // MARK: — Grupy wierzchołków

    /// Przypisuje wierzchołki do grup mimicznych na podstawie pozycji. Wartości
    /// id grup zgodne z FORMAT_SPEC §11.
    private func computeVertexGroups(vertices: [Vec3]) -> [UInt8] {
        let count = vertices.count
        guard count > 0 else { return [] }
        var minV = vertices[0]
        var maxV = vertices[0]
        for v in vertices {
            minV = SIMD3<Float>(min(minV.x, v.x), min(minV.y, v.y), min(minV.z, v.z))
            maxV = SIMD3<Float>(max(maxV.x, v.x), max(maxV.y, v.y), max(maxV.z, v.z))
        }
        let height = max(1e-5, maxV.y - minV.y)
        let width = max(1e-5, maxV.x - minV.x)
        let centerX = (minV.x + maxV.x) * 0.5

        // Progi wysokości (od góry): czoło, oczy, nos, usta, żuchwa.
        let foreheadThresh = minV.y + height * 0.78
        let eyeThresh      = minV.y + height * 0.58
        let noseThresh     = minV.y + height * 0.42
        let mouthThresh    = minV.y + height * 0.22
        let eyeXOffset     = width * 0.12

        var groups = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            let v = vertices[i]
            let dx = v.x - centerX
            if v.y >= foreheadThresh {
                groups[i] = 5 // forehead
            } else if v.y >= eyeThresh {
                if dx < -eyeXOffset {
                    groups[i] = 1 // left eye area
                } else if dx > eyeXOffset {
                    groups[i] = 2 // right eye area
                } else {
                    groups[i] = 5 // forehead / between-brows
                }
            } else if v.y >= noseThresh {
                groups[i] = 6 // nose
            } else if v.y >= mouthThresh {
                groups[i] = 3 // mouth area
            } else if v.y >= minV.y + height * 0.08 {
                groups[i] = 4 // jaw
            } else {
                groups[i] = 7 // chin
            }
        }
        return groups
    }
}
