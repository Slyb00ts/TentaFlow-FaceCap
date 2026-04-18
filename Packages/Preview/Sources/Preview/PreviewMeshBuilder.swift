// =============================================================================
// Plik: PreviewMeshBuilder.swift
// Opis: Budowanie Metal buforów per-mesh z danych kalibracji + wstrzykniętych assetów.
// =============================================================================

import Foundation
import Metal
import simd

/// Typ mesha decydujący o kolejności rysowania i wyborze shadera.
public enum PreviewMeshKind: Int, Sendable {
    case mouthCavity = 0
    case teeth = 1
    case tongue = 2
    case eyeSockets = 3
    case eyeSpheres = 4
    case faceSkin = 5
}

/// Pojedynczy wiersz wierzchołka używany przez shader (12+12+8 = 32 B).
public struct PreviewVertex: Sendable {
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var uv: SIMD2<Float>

    public init(position: SIMD3<Float>, normal: SIMD3<Float>, uv: SIMD2<Float>) {
        self.position = position
        self.normal = normal
        self.uv = uv
    }
}

/// Dane źródłowe pojedynczego mesha – wejście do buildera.
public struct PreviewMeshSource: Sendable {
    public var kind: PreviewMeshKind
    /// Baza (przed skinningiem) – pozycje, normalne, uv.
    public var vertices: [PreviewVertex]
    /// Indeksy triangli (UInt32 żeby obsłużyć duże meshe twarzy).
    public var indices: [UInt32]
    /// Delty blendshape'ów (52 × vertexCount × SIMD3<Float>) lub `nil` gdy mesh statyczny.
    public var blendshapeDeltas: [SIMD3<Float>]?
    /// Liczba blendshape'ów (typowo 52 lub 0 dla statycznych meshy).
    public var blendshapeCount: Int
    /// Opcjonalna tekstura albedo.
    public var albedo: MTLTexture?
    /// Kolor iris dla eye_sphere (używany tylko gdy kind == .eyeSpheres).
    public var irisColor: SIMD3<Float>

    public init(kind: PreviewMeshKind,
                vertices: [PreviewVertex],
                indices: [UInt32],
                blendshapeDeltas: [SIMD3<Float>]? = nil,
                blendshapeCount: Int = 0,
                albedo: MTLTexture? = nil,
                irisColor: SIMD3<Float> = SIMD3<Float>(0.35, 0.55, 0.75)) {
        self.kind = kind
        self.vertices = vertices
        self.indices = indices
        self.blendshapeDeltas = blendshapeDeltas
        self.blendshapeCount = blendshapeCount
        self.albedo = albedo
        self.irisColor = irisColor
    }
}

/// Metalowa reprezentacja pojedynczego mesha – bufory gotowe do rysowania.
public final class PreviewMesh {
    public let kind: PreviewMeshKind
    public let vertexBuffer: MTLBuffer
    public let indexBuffer: MTLBuffer
    public let indexCount: Int
    public var albedo: MTLTexture?
    public var irisColor: SIMD3<Float>

    /// Bazowe pozycje wierzchołków (CPU, potrzebne do `RigSkinner`).
    public let baseVerts: [SIMD3<Float>]
    /// Delty blendshape'ów – row-major `[b * vertexCount + i]`.
    public let deltas: [SIMD3<Float>]
    public let blendshapeCount: Int
    /// Cache znormalizowany, żeby nie budować go na każdą klatkę.
    public let uvs: [SIMD2<Float>]
    public let normals: [SIMD3<Float>]
    public let vertexCount: Int

    /// Opcjonalny skinner – `nil` gdy mesh statyczny (np. teeth, eye_sockets).
    public let skinner: RigSkinner?

    init(kind: PreviewMeshKind,
         vertexBuffer: MTLBuffer,
         indexBuffer: MTLBuffer,
         indexCount: Int,
         albedo: MTLTexture?,
         irisColor: SIMD3<Float>,
         baseVerts: [SIMD3<Float>],
         deltas: [SIMD3<Float>],
         blendshapeCount: Int,
         uvs: [SIMD2<Float>],
         normals: [SIMD3<Float>],
         skinner: RigSkinner?) {
        self.kind = kind
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        self.indexCount = indexCount
        self.albedo = albedo
        self.irisColor = irisColor
        self.baseVerts = baseVerts
        self.deltas = deltas
        self.blendshapeCount = blendshapeCount
        self.uvs = uvs
        self.normals = normals
        self.vertexCount = baseVerts.count
        self.skinner = skinner
    }
}

/// Bundle meshy renderowanych w ustalonej kolejności (mouth_cavity → ... → face_skin).
public final class PreviewMeshBundle {

    /// Meshe posortowane wg `PreviewMeshKind.rawValue`.
    public let meshes: [PreviewMesh]

    init(meshes: [PreviewMesh]) {
        // Gwarantujemy deterministyczną kolejność rysowania.
        self.meshes = meshes.sorted { $0.kind.rawValue < $1.kind.rawValue }
    }
}

/// Builder zamieniający surowe dane meshy w `PreviewMeshBundle` z `MTLBuffer`ami.
public final class PreviewMeshBuilder {

    private let device: MTLDevice

    public init(device: MTLDevice) {
        self.device = device
    }

    /// Buduje `PreviewMeshBundle` z listy źródeł.
    ///
    /// - Throws: `PreviewError.invalidMeshBundle` gdy vertexCount == 0 lub brak indeksów.
    public func build(from sources: [PreviewMeshSource]) throws -> PreviewMeshBundle {
        if sources.isEmpty {
            throw PreviewError.invalidMeshBundle("brak źródeł")
        }
        var meshes: [PreviewMesh] = []
        meshes.reserveCapacity(sources.count)
        for src in sources {
            if src.vertices.isEmpty || src.indices.isEmpty {
                throw PreviewError.invalidMeshBundle("mesh \(src.kind) pusty")
            }
            let mesh = try buildOne(src: src)
            meshes.append(mesh)
        }
        return PreviewMeshBundle(meshes: meshes)
    }

    /// Aktualizuje zawartość `vertexBuffer` mesha nowymi pozycjami (po skinningu).
    ///
    /// Zachowuje normalne i UV (te nie zmieniają się w linear-blend). Wykonujemy
    /// jeden ciągły zapis w pamięci – bez alokacji – dzięki `contents()` na buforze.
    public func updateVertices(_ mesh: PreviewMesh,
                                posed: UnsafePointer<SIMD3<Float>>) {
        let count = mesh.vertexCount
        let ptr = mesh.vertexBuffer.contents()
        let vertPtr = ptr.assumingMemoryBound(to: PreviewVertex.self)
        for i in 0..<count {
            vertPtr[i] = PreviewVertex(position: posed[i],
                                        normal: mesh.normals[i],
                                        uv: mesh.uvs[i])
        }
        #if os(macOS)
        mesh.vertexBuffer.didModifyRange(0..<(count * MemoryLayout<PreviewVertex>.stride))
        #endif
    }

    // MARK: - Prywatne

    private func buildOne(src: PreviewMeshSource) throws -> PreviewMesh {
        let vertByteLen = src.vertices.count * MemoryLayout<PreviewVertex>.stride
        guard let vb = device.makeBuffer(bytes: src.vertices,
                                          length: vertByteLen,
                                          options: .storageModeShared) else {
            throw PreviewError.invalidMeshBundle("vertex buffer alloc")
        }
        let idxByteLen = src.indices.count * MemoryLayout<UInt32>.stride
        guard let ib = device.makeBuffer(bytes: src.indices,
                                          length: idxByteLen,
                                          options: .storageModeShared) else {
            throw PreviewError.invalidMeshBundle("index buffer alloc")
        }

        let baseVerts = src.vertices.map { $0.position }
        let normals = src.vertices.map { $0.normal }
        let uvs = src.vertices.map { $0.uv }
        let deltas = src.blendshapeDeltas ?? []
        let bcount = src.blendshapeCount
        let skinner: RigSkinner?
        if bcount > 0 && !deltas.isEmpty {
            skinner = RigSkinner(vertexCount: baseVerts.count, blendshapeCount: bcount)
        } else {
            skinner = nil
        }

        return PreviewMesh(kind: src.kind,
                            vertexBuffer: vb,
                            indexBuffer: ib,
                            indexCount: src.indices.count,
                            albedo: src.albedo,
                            irisColor: src.irisColor,
                            baseVerts: baseVerts,
                            deltas: deltas,
                            blendshapeCount: bcount,
                            uvs: uvs,
                            normals: normals,
                            skinner: skinner)
    }
}
