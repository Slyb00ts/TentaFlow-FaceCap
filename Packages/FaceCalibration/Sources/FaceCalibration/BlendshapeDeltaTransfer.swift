// =============================================================================
// Plik: BlendshapeDeltaTransfer.swift
// Opis: Przenosi delta z ARKit canonical mesh (1220 verts) do mesh skanu po bridge'u.
// =============================================================================

import Foundation
import simd

/// Transfer delta ARKit -> scan mesh.
public struct BlendshapeDeltaTransfer: Sendable {
    public init() {}

    /// Przenosi 52 delta z canonical 1220v na N verts scan.
    /// Strategia: dla każdego ARKit verta a_i akumulujemy delta do `mapped[a_i]` scan verta.
    /// Dla scan vertów które mają >1 ARKit verta, uśredniamy. Vert pozbawiony mapowania ma delta 0.
    public func transfer(
        arkitDeltas: [BlendshapeDelta],
        bridge: ARKitFaceBridge,
        scanVertexCount: Int
    ) -> [BlendshapeDelta] {
        guard !arkitDeltas.isEmpty, scanVertexCount > 0 else { return [] }
        let auCount = arkitDeltas.count
        let mapping = bridge.arkitToScan
        let rotation = simd_float3x3(
            SIMD3<Float>(bridge.transform.columns.0.x, bridge.transform.columns.0.y, bridge.transform.columns.0.z),
            SIMD3<Float>(bridge.transform.columns.1.x, bridge.transform.columns.1.y, bridge.transform.columns.1.z),
            SIMD3<Float>(bridge.transform.columns.2.x, bridge.transform.columns.2.y, bridge.transform.columns.2.z)
        )

        var result: [BlendshapeDelta] = []
        result.reserveCapacity(auCount)

        for auDelta in arkitDeltas {
            var scanDeltas = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: scanVertexCount)
            var counts = [Int](repeating: 0, count: scanVertexCount)

            let arkitVerts = auDelta.verts
            let limit = min(arkitVerts.count, mapping.count)

            for i in 0..<limit {
                let scanIdx = mapping[i]
                guard scanIdx >= 0 && scanIdx < scanVertexCount else { continue }
                // Przekształć delta przez rotację bridge'a (translation nie dotyczy wektorów).
                let rotated = rotation * arkitVerts[i]
                scanDeltas[scanIdx] += rotated
                counts[scanIdx] += 1
            }
            // Uśrednienie.
            for v in 0..<scanVertexCount where counts[v] > 1 {
                scanDeltas[v] /= Float(counts[v])
            }

            result.append(BlendshapeDelta(
                auID: auDelta.auID,
                verts: scanDeltas,
                observedWeights: auDelta.observedWeights
            ))
        }
        return result
    }
}
