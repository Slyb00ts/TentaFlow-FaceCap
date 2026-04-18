// =============================================================================
// Plik: FaceAssetData.swift
// Opis: Struktury danych wejściowych do writera .face v3 — wszystkie artefakty.
// =============================================================================

import Foundation
import simd
import CoreGraphics

/// Wektor 3D float32.
public typealias Vec3 = SIMD3<Float>

/// Wektor 2D float32 (dla UV).
public typealias Vec2 = SIMD2<Float>

/// Pojedynczy wpis jednostki akcji (AU) ARKit.
public struct BlendshapeEntry: Equatable {

    /// Indeks AU ARKit (0..51).
    public let arkitIndex: UInt8

    /// Czytelna nazwa (max 24 bajty ASCII w pliku).
    public let name: String

    /// Delty na wierzchołkach (Δx, Δy, Δz) — wektor długości `vertexCount` lub
    /// wersja sparse (indeks + delta).
    public let deltas: [Vec3]

    /// Maska lewa (opcjonalna). Wartości 0…255.
    public let maskLeft: [UInt8]?

    /// Maska prawa (opcjonalna).
    public let maskRight: [UInt8]?

    /// Czy trzymać deltę jako sparse.
    public let sparse: Bool

    public init(arkitIndex: UInt8,
                name: String,
                deltas: [Vec3],
                maskLeft: [UInt8]? = nil,
                maskRight: [UInt8]? = nil,
                sparse: Bool = true) {
        self.arkitIndex = arkitIndex
        self.name = name
        self.deltas = deltas
        self.maskLeft = maskLeft
        self.maskRight = maskRight
        self.sparse = sparse
    }
}

/// Pojedynczy klip performance capture.
public struct PerformanceClip: Equatable {

    /// Nazwa klipu (max 24 bajty ASCII).
    public let name: String

    /// Klatki na sekundę (zwykle 60).
    public let fps: UInt8

    /// Macierz [frame][52] wag blendshape (0…1).
    public let weights: [[Float]]

    /// Surowe audio PCM float32 mono (opcjonalne). Sample rate musi być 16 000.
    public let audioPCM: [Float]?

    public init(name: String, fps: UInt8, weights: [[Float]], audioPCM: [Float]? = nil) {
        self.name = name
        self.fps = fps
        self.weights = weights
        self.audioPCM = audioPCM
    }

    public var frameCount: UInt32 { UInt32(weights.count) }
}

/// Opis pojedynczej sfery oka.
public struct EyeSpheres: Equatable {

    public let leftVertices: [Vec3]
    public let rightVertices: [Vec3]
    public let leftUVs: [Vec2]
    public let rightUVs: [Vec2]
    public let leftCenter: Vec3
    public let rightCenter: Vec3
    public let radius: Float
    public let irisColorLeft: UInt16       // RGB565
    public let irisColorRight: UInt16      // RGB565

    public init(leftVertices: [Vec3], rightVertices: [Vec3],
                leftUVs: [Vec2], rightUVs: [Vec2],
                leftCenter: Vec3, rightCenter: Vec3,
                radius: Float,
                irisColorLeft: UInt16, irisColorRight: UInt16) {
        self.leftVertices = leftVertices
        self.rightVertices = rightVertices
        self.leftUVs = leftUVs
        self.rightUVs = rightUVs
        self.leftCenter = leftCenter
        self.rightCenter = rightCenter
        self.radius = radius
        self.irisColorLeft = irisColorLeft
        self.irisColorRight = irisColorRight
    }
}

/// Opis rzędu zębów (górny + dolny + trójkąty).
public struct TeethRow: Equatable {
    public let upperVertices: [Vec3]
    public let lowerVertices: [Vec3]
    public let triangles: [SIMD3<UInt16>]

    public init(upperVertices: [Vec3], lowerVertices: [Vec3], triangles: [SIMD3<UInt16>]) {
        self.upperVertices = upperVertices
        self.lowerVertices = lowerVertices
        self.triangles = triangles
    }
}

/// Opis języka.
public struct Tongue: Equatable {
    public let vertices: [Vec3]
    public let triangles: [SIMD3<UInt16>]

    public init(vertices: [Vec3], triangles: [SIMD3<UInt16>]) {
        self.vertices = vertices
        self.triangles = triangles
    }
}

/// Opis jamy ustnej (ciemnoróżowa powierzchnia wewnątrz).
public struct MouthCavity: Equatable {
    public let vertices: [Vec3]
    public let triangles: [SIMD3<UInt16>]
    public let colorRGB565: UInt16

    public init(vertices: [Vec3], triangles: [SIMD3<UInt16>], colorRGB565: UInt16) {
        self.vertices = vertices
        self.triangles = triangles
        self.colorRGB565 = colorRGB565
    }
}

/// Wszystkie dane potrzebne do eksportu profilu twarzy.
public struct FaceAssetData {

    /// Nazwa profilu (używana w nazwie pliku wynikowego).
    public let profileName: String

    // Siatka głowy.
    public let vertices: [Vec3]
    public let normals: [Vec3]
    public let uvs: [Vec2]
    public let triangles: [SIMD3<UInt16>]
    public let triangleUVIndices: [SIMD3<UInt16>]?
    public let vertexGroups: [UInt8]

    // Tekstura.
    public let textureImage: CGImage?

    // Kalibracja.
    public let blendshapes: [BlendshapeEntry]

    // Performance clips.
    public let performanceClips: [PerformanceClip]

    // Rigid pieces.
    public let eyes: EyeSpheres?
    public let teeth: TeethRow?
    public let tongue: Tongue?
    public let mouthCavity: MouthCavity?

    // Znaczniki dodatkowe.
    public let lidarUsed: Bool
    public let createdAt: Date

    public init(profileName: String,
                vertices: [Vec3],
                normals: [Vec3],
                uvs: [Vec2],
                triangles: [SIMD3<UInt16>],
                triangleUVIndices: [SIMD3<UInt16>]? = nil,
                vertexGroups: [UInt8],
                textureImage: CGImage?,
                blendshapes: [BlendshapeEntry],
                performanceClips: [PerformanceClip] = [],
                eyes: EyeSpheres? = nil,
                teeth: TeethRow? = nil,
                tongue: Tongue? = nil,
                mouthCavity: MouthCavity? = nil,
                lidarUsed: Bool = false,
                createdAt: Date = Date()) {
        self.profileName = profileName
        self.vertices = vertices
        self.normals = normals
        self.uvs = uvs
        self.triangles = triangles
        self.triangleUVIndices = triangleUVIndices
        self.vertexGroups = vertexGroups
        self.textureImage = textureImage
        self.blendshapes = blendshapes
        self.performanceClips = performanceClips
        self.eyes = eyes
        self.teeth = teeth
        self.tongue = tongue
        self.mouthCavity = mouthCavity
        self.lidarUsed = lidarUsed
        self.createdAt = createdAt
    }
}
