// =============================================================================
// Plik: TeethRowGenerator.swift
// Opis: Proceduralny generator dwóch łuków zębów (16 górnych + 16 dolnych).
// =============================================================================

import Foundation
import simd

/// Mesh łuku zębów.
public struct TeethRowMesh: Sendable {
    public let upperVerts: [SIMD3<Float>]
    public let upperUVs: [SIMD2<Float>]
    public let upperNormals: [SIMD3<Float>]
    public let upperTris: [SIMD3<UInt16>]

    public let lowerVerts: [SIMD3<Float>]
    public let lowerUVs: [SIMD2<Float>]
    public let lowerNormals: [SIMD3<Float>]
    public let lowerTris: [SIMD3<UInt16>]

    public init(
        upperVerts: [SIMD3<Float>], upperUVs: [SIMD2<Float>], upperNormals: [SIMD3<Float>], upperTris: [SIMD3<UInt16>],
        lowerVerts: [SIMD3<Float>], lowerUVs: [SIMD2<Float>], lowerNormals: [SIMD3<Float>], lowerTris: [SIMD3<UInt16>]
    ) {
        self.upperVerts = upperVerts
        self.upperUVs = upperUVs
        self.upperNormals = upperNormals
        self.upperTris = upperTris
        self.lowerVerts = lowerVerts
        self.lowerUVs = lowerUVs
        self.lowerNormals = lowerNormals
        self.lowerTris = lowerTris
    }
}

/// Generator łuków zębów — każdy ząb to 8-wierzchołkowy prostopadłościan.
public struct TeethRowGenerator: Sendable {
    /// Liczba zębów w łuku.
    public let teethPerArc: Int
    /// Szerokość łuku u podstawy (odległość między "kłami" – w przybliżeniu szerokość ust).
    public let arcWidth: Float
    /// Głębokość łuku w osi Z (jak bardzo wygięte są siekacze do przodu).
    public let arcDepth: Float
    /// Wymiary pojedynczego zęba: (szerokość, wysokość, głębokość).
    public let toothSize: SIMD3<Float>

    public init(
        teethPerArc: Int = 16,
        arcWidth: Float = 0.054,
        arcDepth: Float = 0.025,
        toothSize: SIMD3<Float> = SIMD3<Float>(0.006, 0.009, 0.006)
    ) {
        self.teethPerArc = teethPerArc
        self.arcWidth = arcWidth
        self.arcDepth = arcDepth
        self.toothSize = toothSize
    }

    /// Generuje obie łuki.
    public func generate() -> TeethRowMesh {
        let (uv, uuv, un, ut) = buildArc(isUpper: true)
        let (lv, luv, ln, lt) = buildArc(isUpper: false)
        return TeethRowMesh(
            upperVerts: uv, upperUVs: uuv, upperNormals: un, upperTris: ut,
            lowerVerts: lv, lowerUVs: luv, lowerNormals: ln, lowerTris: lt
        )
    }

    // Zwraca (verts, uvs, normals, tris) dla pojedynczego łuku.
    private func buildArc(isUpper: Bool) -> ([SIMD3<Float>], [SIMD2<Float>], [SIMD3<Float>], [SIMD3<UInt16>]) {
        var verts: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var normals: [SIMD3<Float>] = []
        var tris: [SIMD3<UInt16>] = []

        verts.reserveCapacity(teethPerArc * 8)
        uvs.reserveCapacity(teethPerArc * 8)
        normals.reserveCapacity(teethPerArc * 8)
        tris.reserveCapacity(teethPerArc * 12)

        // Parabola y = a x² (w ukł. lokalnym) — ale my używamy w osi Z: z = a x².
        // Rozpiętość x: [-arcWidth/2, arcWidth/2]. Głębokość w z: od 0 (siekacze) do -arcDepth (trzonowce).
        let halfWidth = arcWidth * 0.5
        let aCoef = arcDepth / (halfWidth * halfWidth)
        let yOffset: Float = isUpper ? 0 : -toothSize.y * 1.1  // Górny i dolny — rozstęp bazowy.

        for i in 0..<teethPerArc {
            let t = Float(i) / Float(teethPerArc - 1)
            let x = -halfWidth + t * arcWidth
            let zParabola = -aCoef * x * x  // Wklęsła w kierunku -z (do tyłu jamy ustnej).
            // Lokalne centrum zęba.
            let center = SIMD3<Float>(x, yOffset, zParabola)
            // Tangent — pochodna parabolae.
            let tangent = simd_normalize(SIMD3<Float>(1, 0, -2.0 * aCoef * x))
            // Normalna styczna do łuku (wychodząca na zewnątrz ust).
            let normal = SIMD3<Float>(tangent.z, 0, -tangent.x)
            // Trzeci wektor (pionowy).
            let up = SIMD3<Float>(0, 1, 0)

            let baseIndex = UInt16(verts.count)
            let hx = toothSize.x * 0.5
            let hy = toothSize.y * 0.5 * (isUpper ? 1 : -1)
            let hz = toothSize.z * 0.5

            // 8 wierzchołków prostopadłościanu zorientowanego wg bazy (tangent, up, normal).
            let corners: [SIMD3<Float>] = [
                center + ( tangent * -hx + up * -hy + normal * -hz),
                center + ( tangent *  hx + up * -hy + normal * -hz),
                center + ( tangent *  hx + up *  hy + normal * -hz),
                center + ( tangent * -hx + up *  hy + normal * -hz),
                center + ( tangent * -hx + up * -hy + normal *  hz),
                center + ( tangent *  hx + up * -hy + normal *  hz),
                center + ( tangent *  hx + up *  hy + normal *  hz),
                center + ( tangent * -hx + up *  hy + normal *  hz)
            ]
            verts.append(contentsOf: corners)
            // Normalne — dla prostoty, normalna zęba na zewnątrz.
            for _ in 0..<8 {
                normals.append(normal)
            }
            // UV jednolite (cały ząb biały) — rozrzuć punkty w 0..1 żeby uniknąć collapse.
            let uvBase: [SIMD2<Float>] = [
                SIMD2<Float>(0.0, 0.0), SIMD2<Float>(1.0, 0.0),
                SIMD2<Float>(1.0, 1.0), SIMD2<Float>(0.0, 1.0),
                SIMD2<Float>(0.0, 0.0), SIMD2<Float>(1.0, 0.0),
                SIMD2<Float>(1.0, 1.0), SIMD2<Float>(0.0, 1.0)
            ]
            uvs.append(contentsOf: uvBase)

            // 12 trójkątów prostopadłościanu (2 per face × 6 ścian).
            let faces: [(Int, Int, Int, Int)] = [
                (0, 1, 2, 3), // front (normal -hz)
                (5, 4, 7, 6), // back
                (4, 0, 3, 7), // left
                (1, 5, 6, 2), // right
                (3, 2, 6, 7), // top
                (4, 5, 1, 0)  // bottom
            ]
            for face in faces {
                let a = baseIndex + UInt16(face.0)
                let b = baseIndex + UInt16(face.1)
                let c = baseIndex + UInt16(face.2)
                let d = baseIndex + UInt16(face.3)
                tris.append(SIMD3<UInt16>(a, b, c))
                tris.append(SIMD3<UInt16>(a, c, d))
            }
        }
        return (verts, uvs, normals, tris)
    }
}
