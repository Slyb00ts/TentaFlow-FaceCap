// =============================================================================
// Plik: ARKitFaceBridger.swift
// Opis: Bridging ARKit canonical (1220 verts) do mesh skanu — Kabsch ICP + kd-tree 3D.
// =============================================================================

import Foundation
import Accelerate
import simd

/// Wynik bridga — transformacja + mapowanie wierzchołków ARKit -> scan.
public struct ARKitFaceBridge: Sendable {
    /// Macierz transformacji (rotation+translation+scale) 4×4.
    public let transform: simd_float4x4
    /// Mapa: dla każdego wierzchołka ARKit (indeks 0..1219), najbliższy indeks w scan mesh.
    public let arkitToScan: [Int]
    /// Dystans nn dla każdego wierzchołka.
    public let nearestDistances: [Float]
    /// RMS błędu rejestracji ICP.
    public let alignmentRMS: Float

    public init(transform: simd_float4x4, arkitToScan: [Int], nearestDistances: [Float], alignmentRMS: Float) {
        self.transform = transform
        self.arkitToScan = arkitToScan
        self.nearestDistances = nearestDistances
        self.alignmentRMS = alignmentRMS
    }
}

/// Dopasowuje ARKit canonical verts do scan mesh przez ICP, buduje kd-tree i mapping.
public struct ARKitFaceBridger: Sendable {
    public let icpIterations: Int
    public let convergenceThreshold: Float

    public init(icpIterations: Int = 20, convergenceThreshold: Float = 1e-5) {
        self.icpIterations = icpIterations
        self.convergenceThreshold = convergenceThreshold
    }

    /// Dopasowuje ARKit verts (source) do scan verts (target).
    public func buildBridge(
        arkitVerts: [SIMD3<Float>],
        scanVerts: [SIMD3<Float>]
    ) throws -> ARKitFaceBridge {
        guard !arkitVerts.isEmpty, !scanVerts.isEmpty else {
            throw FaceCalibrationError.bridgeAlignmentFailed(reason: "Puste chmury punktów.")
        }

        // Budujemy kd-tree na chmurze scan.
        let scanTree = KDTree3D(points: scanVerts)

        // ICP: iteracja — znajdź pary nn, Kabsch rotation+translation, zastosuj do source.
        var currentSource = arkitVerts
        var cumulativeTransform = matrix_identity_float4x4
        var lastRMS: Float = .infinity

        for _ in 0..<icpIterations {
            // Paruj każdy source vertex z najbliższym target.
            var targetPairs = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: currentSource.count)
            var sqSum: Float = 0
            for i in 0..<currentSource.count {
                let (nnIdx, distSq) = scanTree.nearest(to: currentSource[i])
                targetPairs[i] = scanVerts[nnIdx]
                sqSum += distSq
            }
            let rms = sqrt(sqSum / Float(currentSource.count))

            // Kabsch — oblicz optymalną rotation+translation.
            let (rotation, translation) = try Self.kabsch(source: currentSource, target: targetPairs)

            // Zastosuj.
            for i in 0..<currentSource.count {
                let rotated = rotation * currentSource[i]
                currentSource[i] = rotated + translation
            }

            // Aktualizuj cumulative transform.
            var delta = matrix_identity_float4x4
            delta.columns.0 = SIMD4<Float>(rotation.columns.0, 0)
            delta.columns.1 = SIMD4<Float>(rotation.columns.1, 0)
            delta.columns.2 = SIMD4<Float>(rotation.columns.2, 0)
            delta.columns.3 = SIMD4<Float>(translation, 1)
            cumulativeTransform = delta * cumulativeTransform

            if abs(lastRMS - rms) < convergenceThreshold {
                lastRMS = rms
                break
            }
            lastRMS = rms
        }

        // Po ICP — finalny mapping.
        var mapping = [Int](repeating: 0, count: currentSource.count)
        var distances = [Float](repeating: 0, count: currentSource.count)
        for i in 0..<currentSource.count {
            let (nnIdx, distSq) = scanTree.nearest(to: currentSource[i])
            mapping[i] = nnIdx
            distances[i] = sqrt(distSq)
        }

        return ARKitFaceBridge(
            transform: cumulativeTransform,
            arkitToScan: mapping,
            nearestDistances: distances,
            alignmentRMS: lastRMS
        )
    }

    // MARK: - Kabsch algorithm

    /// Oblicza optymalną rotation+translation między source i target (równoliczne).
    /// Rotation: 3×3. Translation: 3D.
    public static func kabsch(
        source: [SIMD3<Float>],
        target: [SIMD3<Float>]
    ) throws -> (rotation: simd_float3x3, translation: SIMD3<Float>) {
        let n = min(source.count, target.count)
        guard n >= 3 else {
            throw FaceCalibrationError.bridgeAlignmentFailed(reason: "Za mało punktów do Kabsch (\(n)).")
        }

        // Centroidy.
        var srcCentroid = SIMD3<Float>(0, 0, 0)
        var dstCentroid = SIMD3<Float>(0, 0, 0)
        for i in 0..<n {
            srcCentroid += source[i]
            dstCentroid += target[i]
        }
        srcCentroid /= Float(n)
        dstCentroid /= Float(n)

        // H = Σ (src_i - src_c)(dst_i - dst_c)^T — macierz 3×3.
        var H = [Double](repeating: 0, count: 9)
        for i in 0..<n {
            let s = source[i] - srcCentroid
            let t = target[i] - dstCentroid
            // H += s ⊗ t (outer product) — kolumna-major.
            for col in 0..<3 {
                let tv: Double
                switch col {
                case 0: tv = Double(t.x)
                case 1: tv = Double(t.y)
                default: tv = Double(t.z)
                }
                H[0 + col * 3] += Double(s.x) * tv
                H[1 + col * 3] += Double(s.y) * tv
                H[2 + col * 3] += Double(s.z) * tv
            }
        }

        // SVD: H = U · Σ · V^T. LAPACK dgesvd_.
        var jobu: CChar = CChar(UnicodeScalar("A").value)
        var jobvt: CChar = CChar(UnicodeScalar("A").value)
        var m = __CLPK_integer(3)
        var nn = __CLPK_integer(3)
        var lda = m
        var ldu = m
        var ldvt = nn
        var S = [Double](repeating: 0, count: 3)
        var U = [Double](repeating: 0, count: 9)
        var VT = [Double](repeating: 0, count: 9)

        // Zapytanie o optymalny LWORK.
        var workQuery: Double = 0
        var lwork: __CLPK_integer = -1
        var info: __CLPK_integer = 0
        H.withUnsafeMutableBufferPointer { hPtr in
            S.withUnsafeMutableBufferPointer { sPtr in
                U.withUnsafeMutableBufferPointer { uPtr in
                    VT.withUnsafeMutableBufferPointer { vtPtr in
                        dgesvd_(
                            &jobu, &jobvt, &m, &nn,
                            hPtr.baseAddress, &lda,
                            sPtr.baseAddress,
                            uPtr.baseAddress, &ldu,
                            vtPtr.baseAddress, &ldvt,
                            &workQuery, &lwork, &info
                        )
                    }
                }
            }
        }
        lwork = __CLPK_integer(workQuery)
        if lwork < 1 { lwork = 64 }
        var work = [Double](repeating: 0, count: Int(lwork))

        H.withUnsafeMutableBufferPointer { hPtr in
            S.withUnsafeMutableBufferPointer { sPtr in
                U.withUnsafeMutableBufferPointer { uPtr in
                    VT.withUnsafeMutableBufferPointer { vtPtr in
                        work.withUnsafeMutableBufferPointer { wPtr in
                            dgesvd_(
                                &jobu, &jobvt, &m, &nn,
                                hPtr.baseAddress, &lda,
                                sPtr.baseAddress,
                                uPtr.baseAddress, &ldu,
                                vtPtr.baseAddress, &ldvt,
                                wPtr.baseAddress, &lwork, &info
                            )
                        }
                    }
                }
            }
        }

        if info != 0 {
            throw FaceCalibrationError.bridgeAlignmentFailed(reason: "dgesvd_ info=\(info).")
        }

        // R = V · diag(1, 1, det(V U^T)) · U^T. U i V kolumna-major.
        // Wyciągamy kolumny U (3×3).
        let u00 = Float(U[0]), u10 = Float(U[1]), u20 = Float(U[2])
        let u01 = Float(U[3]), u11 = Float(U[4]), u21 = Float(U[5])
        let u02 = Float(U[6]), u12 = Float(U[7]), u22 = Float(U[8])

        // VT: wiersze V^T to kolumny V transposed.
        // VT[i + j*3] = V^T[i][j] = V[j][i]. Budujemy V.
        let v00 = Float(VT[0]), v01 = Float(VT[1]), v02 = Float(VT[2])
        let v10 = Float(VT[3]), v11 = Float(VT[4]), v12 = Float(VT[5])
        let v20 = Float(VT[6]), v21 = Float(VT[7]), v22 = Float(VT[8])
        // Uwaga: LAPACK VT to macierz V^T w kolumna-major, więc V[i][j] = VT[j + i*3].
        // Przepiszemy jako simd:
        let U_mat = simd_float3x3(
            SIMD3<Float>(u00, u10, u20),
            SIMD3<Float>(u01, u11, u21),
            SIMD3<Float>(u02, u12, u22)
        )
        // V = (V^T)^T. VT w kolumna-major: kolumna i = [VT[0+i*3], VT[1+i*3], VT[2+i*3]] to wiersz i macierzy V^T, czyli kolumna i macierzy V.
        let V_mat = simd_float3x3(
            SIMD3<Float>(v00, v01, v02),
            SIMD3<Float>(v10, v11, v12),
            SIMD3<Float>(v20, v21, v22)
        )

        let UT = U_mat.transpose
        var R = V_mat * UT

        // Correct reflection: jeśli det(R) < 0, odwróć znak ostatniej kolumny V i przelicz.
        let det = R.determinant
        if det < 0 {
            var VFixed = V_mat
            VFixed.columns.2 = -VFixed.columns.2
            R = VFixed * UT
        }

        let t = dstCentroid - R * srcCentroid
        return (R, t)
    }
}

// MARK: - kd-tree 3D

/// Prosty rekurencyjny kd-tree dla punktów 3D — nearest neighbor O(log n).
public struct KDTree3D: Sendable {
    fileprivate struct Node: Sendable {
        let pointIndex: Int
        let axis: Int
        let left: Int?
        let right: Int?
    }

    private let nodes: [Node]
    private let points: [SIMD3<Float>]
    private let rootIndex: Int

    public init(points: [SIMD3<Float>]) {
        self.points = points
        var nodeStorage: [Node] = []
        nodeStorage.reserveCapacity(points.count)
        var indices = Array(points.indices)
        let root = Self.build(indices: &indices, depth: 0, points: points, nodes: &nodeStorage)
        self.nodes = nodeStorage
        self.rootIndex = root ?? 0
    }

    private static func build(
        indices: inout [Int],
        depth: Int,
        points: [SIMD3<Float>],
        nodes: inout [Node]
    ) -> Int? {
        if indices.isEmpty { return nil }
        let axis = depth % 3
        indices.sort { lhs, rhs in
            return component(points[lhs], axis: axis) < component(points[rhs], axis: axis)
        }
        let medianIdx = indices.count / 2
        let pivot = indices[medianIdx]
        var leftSlice = Array(indices[0..<medianIdx])
        var rightSlice = Array(indices[(medianIdx + 1)..<indices.count])
        let leftNode = build(indices: &leftSlice, depth: depth + 1, points: points, nodes: &nodes)
        let rightNode = build(indices: &rightSlice, depth: depth + 1, points: points, nodes: &nodes)
        let node = Node(pointIndex: pivot, axis: axis, left: leftNode, right: rightNode)
        nodes.append(node)
        return nodes.count - 1
    }

    /// Znajduje najbliższego sąsiada. Zwraca (indeks, dystans²).
    public func nearest(to target: SIMD3<Float>) -> (index: Int, distanceSquared: Float) {
        guard !nodes.isEmpty else { return (0, .infinity) }
        var bestIndex = nodes[rootIndex].pointIndex
        var bestDistSq: Float = .infinity
        search(nodeIndex: rootIndex, target: target, bestIndex: &bestIndex, bestDistSq: &bestDistSq)
        return (bestIndex, bestDistSq)
    }

    private func search(
        nodeIndex: Int,
        target: SIMD3<Float>,
        bestIndex: inout Int,
        bestDistSq: inout Float
    ) {
        let node = nodes[nodeIndex]
        let point = points[node.pointIndex]
        let diff = point - target
        let distSq = simd_dot(diff, diff)
        if distSq < bestDistSq {
            bestDistSq = distSq
            bestIndex = node.pointIndex
        }
        let axis = node.axis
        let delta = Self.component(target, axis: axis) - Self.component(point, axis: axis)
        let (near, far) = delta < 0 ? (node.left, node.right) : (node.right, node.left)
        if let n = near {
            search(nodeIndex: n, target: target, bestIndex: &bestIndex, bestDistSq: &bestDistSq)
        }
        // Sprawdź drugą stronę tylko gdy ball intersects plane.
        if delta * delta < bestDistSq, let f = far {
            search(nodeIndex: f, target: target, bestIndex: &bestIndex, bestDistSq: &bestDistSq)
        }
    }

    private static func component(_ p: SIMD3<Float>, axis: Int) -> Float {
        switch axis {
        case 0: return p.x
        case 1: return p.y
        default: return p.z
        }
    }
}
