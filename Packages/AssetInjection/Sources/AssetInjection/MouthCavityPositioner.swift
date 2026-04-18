// =============================================================================
// Plik: MouthCavityPositioner.swift
// Opis: Pozycjonowanie wnętrza jamy ustnej w tyle, za łukiem zębów.
// =============================================================================

import Foundation
import simd

/// Placement wnętrza jamy ustnej.
public struct MouthCavityPlacement: Sendable {
    public let transform: simd_float4x4
    public let depth: Float

    public init(transform: simd_float4x4, depth: Float) {
        self.transform = transform
        self.depth = depth
    }
}

/// Pozycjoner wnętrza jamy ustnej.
public struct MouthCavityPositioner: Sendable {
    public let depthBehindTeeth: Float

    public init(depthBehindTeeth: Float = 0.025) {
        self.depthBehindTeeth = depthBehindTeeth
    }

    /// Umieszcza box w głębi ust.
    public func placement(
        upperLipInner: SIMD3<Float>,
        lowerLipInner: SIMD3<Float>,
        mouthCornerLeft: SIMD3<Float>,
        mouthCornerRight: SIMD3<Float>
    ) -> MouthCavityPlacement {
        let mouthCenter = (upperLipInner + lowerLipInner) * 0.5
        let mouthWidth = simd_distance(mouthCornerLeft, mouthCornerRight)
        // Kierunek "do wewnątrz" — przeciwny do normalnej twarzy (założenie: -Z).
        let offset = SIMD3<Float>(0, 0, -depthBehindTeeth)
        let center = mouthCenter + offset
        var transform = matrix_identity_float4x4
        // Skalujemy proporcjonalnie do szerokości ust.
        let scale = max(0.9, min(1.15, mouthWidth / 0.05))
        transform.columns.0 *= scale
        transform.columns.1 *= scale
        transform.columns.2 *= scale
        transform.columns.3 = SIMD4<Float>(center, 1)
        return MouthCavityPlacement(transform: transform, depth: depthBehindTeeth)
    }
}
