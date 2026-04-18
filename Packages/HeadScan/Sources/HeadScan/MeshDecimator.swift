// =============================================================================
// Plik: MeshDecimator.swift
// Opis: Decymacja mesh metodą quadric error metric (Garland–Heckbert) z priority queue.
// =============================================================================

import Foundation
import simd

/// Quadric 4×4 reprezentowany jako symmetric matrix (10 unikalnych współczynników).
/// Forma: ax²+by²+cz²+2dxy+2eyz+2fxz+2gx+2hy+2iz+j.
fileprivate struct Quadric {
    // Kolumna-major dla SIMD.
    var q: (Float, Float, Float, Float,
            Float, Float, Float, Float,
            Float, Float)
    // Indeksy: q00,q01,q02,q03,q11,q12,q13,q22,q23,q33

    static let zero = Quadric(q: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// Tworzy quadric z równania płaszczyzny n·x+d=0 (n znormalizowane).
    static func fromPlane(a: Float, b: Float, c: Float, d: Float) -> Quadric {
        return Quadric(q: (
            a * a, a * b, a * c, a * d,
            b * b, b * c, b * d,
            c * c, c * d,
            d * d
        ))
    }

    static func +(lhs: Quadric, rhs: Quadric) -> Quadric {
        return Quadric(q: (
            lhs.q.0 + rhs.q.0, lhs.q.1 + rhs.q.1, lhs.q.2 + rhs.q.2, lhs.q.3 + rhs.q.3,
            lhs.q.4 + rhs.q.4, lhs.q.5 + rhs.q.5, lhs.q.6 + rhs.q.6,
            lhs.q.7 + rhs.q.7, lhs.q.8 + rhs.q.8,
            lhs.q.9 + rhs.q.9
        ))
    }

    /// Oblicza błąd v^T Q v dla wierzchołka v = (x,y,z,1).
    func error(at p: SIMD3<Float>) -> Float {
        let x = p.x, y = p.y, z = p.z
        return q.0 * x * x + 2.0 * q.1 * x * y + 2.0 * q.2 * x * z + 2.0 * q.3 * x
             + q.4 * y * y + 2.0 * q.5 * y * z + 2.0 * q.6 * y
             + q.7 * z * z + 2.0 * q.8 * z
             + q.9
    }

    /// Próbuje wyliczyć optymalny wierzchołek minimalizujący błąd przez rozwiązanie 3×3.
    /// Zwraca nil gdy macierz jest osobliwa — wtedy użyj midpoint.
    func optimalPosition() -> SIMD3<Float>? {
        // A = [[q00,q01,q02],[q01,q11,q12],[q02,q12,q22]]
        // b = -[q03,q13,q23]
        let a00 = q.0, a01 = q.1, a02 = q.2
        let a11 = q.4, a12 = q.5
        let a22 = q.7
        let b0 = -q.3, b1 = -q.6, b2 = -q.8

        // Wyznacznik.
        let det = a00 * (a11 * a22 - a12 * a12)
                - a01 * (a01 * a22 - a12 * a02)
                + a02 * (a01 * a12 - a11 * a02)

        if abs(det) < 1e-9 { return nil }

        let invDet = 1.0 / det
        let i00 = (a11 * a22 - a12 * a12) * invDet
        let i01 = -(a01 * a22 - a12 * a02) * invDet
        let i02 = (a01 * a12 - a11 * a02) * invDet
        let i11 = (a00 * a22 - a02 * a02) * invDet
        let i12 = -(a00 * a12 - a01 * a02) * invDet
        let i22 = (a00 * a11 - a01 * a01) * invDet

        return SIMD3<Float>(
            i00 * b0 + i01 * b1 + i02 * b2,
            i01 * b0 + i11 * b1 + i12 * b2,
            i02 * b0 + i12 * b1 + i22 * b2
        )
    }
}

/// Min-heap dla edge collapse (mniejszy koszt -> wyżej).
fileprivate struct MinHeap<T> {
    private var storage: [T] = []
    private let less: (T, T) -> Bool

    init(less: @escaping (T, T) -> Bool) {
        self.less = less
    }

    var isEmpty: Bool { storage.isEmpty }
    var count: Int { storage.count }

    mutating func push(_ element: T) {
        storage.append(element)
        siftUp(from: storage.count - 1)
    }

    mutating func pop() -> T? {
        guard !storage.isEmpty else { return nil }
        storage.swapAt(0, storage.count - 1)
        let result = storage.removeLast()
        if !storage.isEmpty { siftDown(from: 0) }
        return result
    }

    private mutating func siftUp(from index: Int) {
        var i = index
        while i > 0 {
            let parent = (i - 1) / 2
            if less(storage[i], storage[parent]) {
                storage.swapAt(i, parent)
                i = parent
            } else {
                break
            }
        }
    }

    private mutating func siftDown(from index: Int) {
        var i = index
        let n = storage.count
        while true {
            let l = 2 * i + 1
            let r = 2 * i + 2
            var smallest = i
            if l < n && less(storage[l], storage[smallest]) { smallest = l }
            if r < n && less(storage[r], storage[smallest]) { smallest = r }
            if smallest == i { break }
            storage.swapAt(i, smallest)
            i = smallest
        }
    }
}

/// Wpis kolejki priorytetowej — koszt + unikalna wersja (stempel).
fileprivate struct EdgeRecord {
    let cost: Float
    let target: SIMD3<Float>
    let a: Int
    let b: Int
    let versionA: Int
    let versionB: Int
}

/// Dekymuje mesh do docelowej liczby wierzchołków.
public struct MeshDecimator {
    public let targetVertexCount: Int
    /// Indeksy wierzchołków, które muszą zostać zachowane (landmarki) — wagą kary.
    public let preservedIndices: Set<Int>
    /// Waga kary za próbę skolapsowania zachowanego wierzchołka (1e6 = de facto zablokowane).
    public let preservedPenalty: Float

    public init(targetVertexCount: Int, preservedIndices: Set<Int> = [], preservedPenalty: Float = 1e6) {
        self.targetVertexCount = max(4, targetVertexCount)
        self.preservedIndices = preservedIndices
        self.preservedPenalty = preservedPenalty
    }

    public struct DecimatedMesh: Sendable {
        public let verts: [SIMD3<Float>]
        public let normals: [SIMD3<Float>]
        public let uvs: [SIMD2<Float>]
        public let triangles: [SIMD3<UInt32>]
        /// Mapa indeksów: oryginalny -> nowy (-1 gdy został usunięty).
        public let vertexRemap: [Int]
    }

    public func decimate(
        verts: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        uvs: [SIMD2<Float>],
        triangles: [SIMD3<UInt32>]
    ) -> DecimatedMesh {
        var workingVerts = verts
        var workingNormals = normals
        var workingUVs = uvs

        // Deduplikacja wierzchołków oparta o pozycje (tolerancja 1e-5).
        let (dedupVerts, dedupNormals, dedupUVs, vertexMap) = Self.deduplicate(
            verts: workingVerts,
            normals: workingNormals,
            uvs: workingUVs
        )
        workingVerts = dedupVerts
        workingNormals = dedupNormals
        workingUVs = dedupUVs

        let n = workingVerts.count
        if n <= targetVertexCount {
            let remapTriangles = triangles.map {
                SIMD3<UInt32>(
                    UInt32(vertexMap[Int($0.x)]),
                    UInt32(vertexMap[Int($0.y)]),
                    UInt32(vertexMap[Int($0.z)])
                )
            }
            let cleaned = Self.removeDegenerate(triangles: remapTriangles)
            let remap = (0..<n).map { $0 }
            return DecimatedMesh(
                verts: workingVerts,
                normals: workingNormals,
                uvs: workingUVs,
                triangles: cleaned,
                vertexRemap: remap
            )
        }

        // Trójkąty po deduplikacji.
        var workingTris: [SIMD3<Int>] = triangles.map {
            SIMD3<Int>(
                vertexMap[Int($0.x)],
                vertexMap[Int($0.y)],
                vertexMap[Int($0.z)]
            )
        }
        workingTris = workingTris.filter { $0.x != $0.y && $0.y != $0.z && $0.x != $0.z }

        // Quadrics początkowe.
        var quadrics = [Quadric](repeating: .zero, count: n)
        for tri in workingTris {
            let p0 = workingVerts[tri.x]
            let p1 = workingVerts[tri.y]
            let p2 = workingVerts[tri.z]
            let edge1 = p1 - p0
            let edge2 = p2 - p0
            let normal = simd_cross(edge1, edge2)
            let len = simd_length(normal)
            if len < 1e-9 { continue }
            let n3 = normal / len
            let d = -simd_dot(n3, p0)
            let q = Quadric.fromPlane(a: n3.x, b: n3.y, c: n3.z, d: d)
            quadrics[tri.x] = quadrics[tri.x] + q
            quadrics[tri.y] = quadrics[tri.y] + q
            quadrics[tri.z] = quadrics[tri.z] + q
        }

        // Adjacency edges i incident triangles.
        var incident: [Set<Int>] = Array(repeating: [], count: n)
        for (idx, tri) in workingTris.enumerated() {
            incident[tri.x].insert(idx)
            incident[tri.y].insert(idx)
            incident[tri.z].insert(idx)
        }
        var neighbours: [Set<Int>] = Array(repeating: [], count: n)
        for tri in workingTris {
            neighbours[tri.x].insert(tri.y); neighbours[tri.x].insert(tri.z)
            neighbours[tri.y].insert(tri.x); neighbours[tri.y].insert(tri.z)
            neighbours[tri.z].insert(tri.x); neighbours[tri.z].insert(tri.y)
        }

        // Wersjonowanie wierzchołków — gdy wersja w heap < aktualna, rekord jest przestarzały.
        var versions = [Int](repeating: 0, count: n)
        var alive = [Bool](repeating: true, count: n)
        var triAlive = [Bool](repeating: true, count: workingTris.count)

        var heap = MinHeap<EdgeRecord>(less: { $0.cost < $1.cost })

        // Inicjalizacja krawędzi — enumeracja unikalnych par.
        var seen = Set<UInt64>()
        seen.reserveCapacity(workingTris.count * 3)
        for tri in workingTris {
            let edges: [(Int, Int)] = [(tri.x, tri.y), (tri.y, tri.z), (tri.x, tri.z)]
            for (a, b) in edges {
                let key = Self.edgeKey(a, b)
                if seen.contains(key) { continue }
                seen.insert(key)
                if let record = buildEdgeRecord(a: a, b: b, verts: workingVerts, quadrics: quadrics, versions: versions) {
                    heap.push(record)
                }
            }
        }

        var remainingVertices = n

        while remainingVertices > targetVertexCount {
            guard let edge = heap.pop() else { break }
            if !alive[edge.a] || !alive[edge.b] { continue }
            if versions[edge.a] != edge.versionA || versions[edge.b] != edge.versionB { continue }

            // Wykonaj collapse a -> target, przenieś b na a.
            let keep = edge.a
            let drop = edge.b
            let newPos = edge.target
            workingVerts[keep] = newPos
            // Średnia normali i UV.
            let nSum = workingNormals[keep] + workingNormals[drop]
            let nLen = simd_length(nSum)
            workingNormals[keep] = nLen > 1e-9 ? (nSum / nLen) : workingNormals[keep]
            workingUVs[keep] = (workingUVs[keep] + workingUVs[drop]) * 0.5

            quadrics[keep] = quadrics[keep] + quadrics[drop]
            alive[drop] = false
            remainingVertices -= 1
            versions[keep] += 1

            // Przenieś trójkąty incydentne z drop na keep, usuń zdegenerowane.
            let triIndices = incident[drop]
            for ti in triIndices {
                guard triAlive[ti] else { continue }
                var t = workingTris[ti]
                if t.x == drop { t.x = keep }
                if t.y == drop { t.y = keep }
                if t.z == drop { t.z = keep }
                if t.x == t.y || t.y == t.z || t.x == t.z {
                    triAlive[ti] = false
                    incident[t.x].remove(ti)
                    incident[t.y].remove(ti)
                    incident[t.z].remove(ti)
                } else {
                    workingTris[ti] = t
                    incident[keep].insert(ti)
                }
            }
            incident[drop].removeAll()

            // Merge sąsiadów.
            let dropNeighbours = neighbours[drop]
            for nb in dropNeighbours {
                neighbours[nb].remove(drop)
                if nb != keep && alive[nb] {
                    neighbours[nb].insert(keep)
                    neighbours[keep].insert(nb)
                }
            }
            neighbours[drop].removeAll()
            neighbours[keep].remove(drop)
            neighbours[keep].remove(keep)

            // Aktualizuj krawędzie sąsiadów `keep`.
            for nb in neighbours[keep] {
                guard alive[nb] else { continue }
                if let record = buildEdgeRecord(a: keep, b: nb, verts: workingVerts, quadrics: quadrics, versions: versions) {
                    heap.push(record)
                }
            }
        }

        // Kompaktyfikacja wierzchołków.
        var oldToNew = [Int](repeating: -1, count: n)
        var newVerts: [SIMD3<Float>] = []
        var newNormals: [SIMD3<Float>] = []
        var newUVs: [SIMD2<Float>] = []
        newVerts.reserveCapacity(remainingVertices)
        newNormals.reserveCapacity(remainingVertices)
        newUVs.reserveCapacity(remainingVertices)
        for i in 0..<n {
            if alive[i] {
                oldToNew[i] = newVerts.count
                newVerts.append(workingVerts[i])
                newNormals.append(workingNormals[i])
                newUVs.append(workingUVs[i])
            }
        }

        var newTris: [SIMD3<UInt32>] = []
        newTris.reserveCapacity(workingTris.count)
        for (idx, tri) in workingTris.enumerated() {
            guard triAlive[idx] else { continue }
            let a = oldToNew[tri.x]
            let b = oldToNew[tri.y]
            let c = oldToNew[tri.z]
            if a < 0 || b < 0 || c < 0 { continue }
            if a == b || b == c || a == c { continue }
            newTris.append(SIMD3<UInt32>(UInt32(a), UInt32(b), UInt32(c)))
        }

        // Mapowanie pierwotnych indeksów wejściowych do nowych.
        var finalRemap = [Int](repeating: -1, count: verts.count)
        for i in 0..<verts.count {
            let afterDedup = vertexMap[i]
            if afterDedup < n && alive[afterDedup] {
                finalRemap[i] = oldToNew[afterDedup]
            }
        }

        return DecimatedMesh(
            verts: newVerts,
            normals: newNormals,
            uvs: newUVs,
            triangles: newTris,
            vertexRemap: finalRemap
        )
    }

    // MARK: - Pomocnicze

    private func buildEdgeRecord(
        a: Int,
        b: Int,
        verts: [SIMD3<Float>],
        quadrics: [Quadric],
        versions: [Int]
    ) -> EdgeRecord? {
        if a == b { return nil }
        let combined = quadrics[a] + quadrics[b]
        var target: SIMD3<Float>
        if let opt = combined.optimalPosition() {
            target = opt
        } else {
            target = (verts[a] + verts[b]) * 0.5
        }
        var cost = combined.error(at: target)
        if cost.isNaN || cost.isInfinite { cost = 1e12 }
        if preservedIndices.contains(a) || preservedIndices.contains(b) {
            cost += preservedPenalty
            target = preservedIndices.contains(a) ? verts[a] : verts[b]
        }
        return EdgeRecord(
            cost: cost,
            target: target,
            a: a,
            b: b,
            versionA: versions[a],
            versionB: versions[b]
        )
    }

    private static func edgeKey(_ a: Int, _ b: Int) -> UInt64 {
        let lo = UInt64(min(a, b))
        let hi = UInt64(max(a, b))
        return (hi << 32) | lo
    }

    private static func deduplicate(
        verts: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        uvs: [SIMD2<Float>]
    ) -> ([SIMD3<Float>], [SIMD3<Float>], [SIMD2<Float>], [Int]) {
        let quantScale: Float = 1e5
        var dict: [SIMD3<Int32>: Int] = [:]
        dict.reserveCapacity(verts.count)
        var outVerts: [SIMD3<Float>] = []
        var outNormals: [SIMD3<Float>] = []
        var outUVs: [SIMD2<Float>] = []
        var remap = [Int](repeating: 0, count: verts.count)
        outVerts.reserveCapacity(verts.count)

        for i in 0..<verts.count {
            let v = verts[i]
            let key = SIMD3<Int32>(
                Int32((v.x * quantScale).rounded()),
                Int32((v.y * quantScale).rounded()),
                Int32((v.z * quantScale).rounded())
            )
            if let existing = dict[key] {
                remap[i] = existing
            } else {
                let newIndex = outVerts.count
                dict[key] = newIndex
                outVerts.append(v)
                outNormals.append(i < normals.count ? normals[i] : SIMD3<Float>(0, 1, 0))
                outUVs.append(i < uvs.count ? uvs[i] : SIMD2<Float>(0, 0))
                remap[i] = newIndex
            }
        }
        return (outVerts, outNormals, outUVs, remap)
    }

    private static func removeDegenerate(triangles: [SIMD3<UInt32>]) -> [SIMD3<UInt32>] {
        return triangles.filter { $0.x != $0.y && $0.y != $0.z && $0.x != $0.z }
    }
}
