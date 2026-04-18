// =============================================================================
// Plik: MouthCavityGenerator.swift
// Opis: Generator wnętrza jamy ustnej — ciemny prostopadłościan za zębami.
// =============================================================================

import Foundation
import simd

/// Mesh wnętrza jamy ustnej (box 8 verts × 12 tris).
public struct MouthCavityMesh: Sendable {
    public let verts: [SIMD3<Float>]
    public let uvs: [SIMD2<Float>]
    public let normals: [SIMD3<Float>]
    public let tris: [SIMD3<UInt16>]
    /// Kolor RGB565 wnętrza ust (domyślnie ciemnoróżowy 0x4a12).
    public let colorRgb565: UInt16

    public init(
        verts: [SIMD3<Float>],
        uvs: [SIMD2<Float>],
        normals: [SIMD3<Float>],
        tris: [SIMD3<UInt16>],
        colorRgb565: UInt16
    ) {
        self.verts = verts
        self.uvs = uvs
        self.normals = normals
        self.tris = tris
        self.colorRgb565 = colorRgb565
    }
}

/// Generator wnętrza jamy ustnej.
public struct MouthCavityGenerator: Sendable {
    public let sizeMeters: SIMD3<Float>
    public let colorRgb565: UInt16

    public init(
        sizeMeters: SIMD3<Float> = SIMD3<Float>(0.04, 0.02, 0.04),
        colorRgb565: UInt16 = 0x4a12
    ) {
        self.sizeMeters = sizeMeters
        self.colorRgb565 = colorRgb565
    }

    public func generate() -> MouthCavityMesh {
        let h = sizeMeters * 0.5
        // 8 wierzchołków boxa.
        let verts: [SIMD3<Float>] = [
            SIMD3<Float>(-h.x, -h.y, -h.z), SIMD3<Float>( h.x, -h.y, -h.z),
            SIMD3<Float>( h.x,  h.y, -h.z), SIMD3<Float>(-h.x,  h.y, -h.z),
            SIMD3<Float>(-h.x, -h.y,  h.z), SIMD3<Float>( h.x, -h.y,  h.z),
            SIMD3<Float>( h.x,  h.y,  h.z), SIMD3<Float>(-h.x,  h.y,  h.z)
        ]
        let normals: [SIMD3<Float>] = verts.map { simd_normalize($0) }
        let uvs: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(1, 1), SIMD2<Float>(0, 1),
            SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(1, 1), SIMD2<Float>(0, 1)
        ]
        // 12 trójkątów (każda ściana 2), normalne skierowane do WEWNĄTRZ (bo widok od strony jamy ustnej).
        let faces: [(Int, Int, Int, Int)] = [
            (1, 0, 3, 2),
            (4, 5, 6, 7),
            (0, 4, 7, 3),
            (5, 1, 2, 6),
            (7, 6, 2, 3),
            (0, 1, 5, 4)
        ]
        var tris: [SIMD3<UInt16>] = []
        tris.reserveCapacity(12)
        for face in faces {
            let a = UInt16(face.0)
            let b = UInt16(face.1)
            let c = UInt16(face.2)
            let d = UInt16(face.3)
            tris.append(SIMD3<UInt16>(a, b, c))
            tris.append(SIMD3<UInt16>(a, c, d))
        }
        return MouthCavityMesh(
            verts: verts,
            uvs: uvs,
            normals: normals,
            tris: tris,
            colorRgb565: colorRgb565
        )
    }
}
