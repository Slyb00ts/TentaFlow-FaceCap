// =============================================================================
// Plik: BlendshapeDeltaExtractor.swift
// Opis: Wyciąga delta pozycji wierzchołków (peak - neutral) dla konkretnej AU.
// =============================================================================

import Foundation
import simd

/// Delta pozycji wierzchołków dla konkretnej AU.
public struct BlendshapeDelta: Sendable {
    /// AU, której dotyczy delta.
    public let auID: ArkitAU
    /// Wektory przesunięcia wierzchołków (peak - neutral).
    public let verts: [SIMD3<Float>]
    /// Wagi AU zaobserwowane przy peak (52 elementy) — do macierzy dekorelacji.
    public let observedWeights: [Float]

    public init(auID: ArkitAU, verts: [SIMD3<Float>], observedWeights: [Float]) {
        self.auID = auID
        self.verts = verts
        self.observedWeights = observedWeights
    }
}

/// Ekstraktor delta.
public struct BlendshapeDeltaExtractor: Sendable {
    public init() {}

    /// Wyciąga delta = peak.vertices - neutral.vertices.
    public func extract(neutral: NeutralFace, peak: FaceFrame, auID: ArkitAU) -> BlendshapeDelta {
        let vertexCount = min(neutral.vertices.count, peak.vertices.count)
        var deltaVerts = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: vertexCount)
        for i in 0..<vertexCount {
            deltaVerts[i] = peak.vertices[i] - neutral.vertices[i]
        }
        return BlendshapeDelta(
            auID: auID,
            verts: deltaVerts,
            observedWeights: peak.blendWeights
        )
    }
}
