// =============================================================================
// Plik: TonguePositioner.swift
// Opis: Pozycjonowanie języka — rest za zębami, extended na AU tongueOut.
// =============================================================================

import Foundation
import simd

/// Placement języka z wariantem animacji tongueOut.
public struct TonguePlacement: Sendable {
    public let transform: simd_float4x4
    public let restPosition: SIMD3<Float>
    public let extendedPosition: SIMD3<Float>
    public let extensionAxis: SIMD3<Float>

    public init(transform: simd_float4x4, restPosition: SIMD3<Float>, extendedPosition: SIMD3<Float>, extensionAxis: SIMD3<Float>) {
        self.transform = transform
        self.restPosition = restPosition
        self.extendedPosition = extendedPosition
        self.extensionAxis = extensionAxis
    }
}

/// Pozycjoner języka.
public struct TonguePositioner: Sendable {
    public let maxExtensionMeters: Float

    public init(maxExtensionMeters: Float = 0.03) {
        self.maxExtensionMeters = maxExtensionMeters
    }

    public func placement(
        lowerLipInner: SIMD3<Float>,
        upperLipInner: SIMD3<Float>,
        mouthCornerLeft: SIMD3<Float>,
        mouthCornerRight: SIMD3<Float>
    ) -> TonguePlacement {
        let mouthCenter = (upperLipInner + lowerLipInner) * 0.5
        // Rest: w głębi jamy ustnej, ~1cm za centrum ust.
        let restPos = mouthCenter + SIMD3<Float>(0, -0.002, -0.015)
        // Kierunek przedni (patrzymy na -Z w typowej przestrzeni ARKit).
        let mouthVector = mouthCornerRight - mouthCornerLeft
        // Wektor normalny do osi ust (prostopadły do mouthVector i pionowej).
        let up = SIMD3<Float>(0, 1, 0)
        var axis = simd_cross(up, mouthVector)
        if simd_length(axis) < 1e-5 {
            axis = SIMD3<Float>(0, 0, 1)
        }
        let extensionAxis = simd_normalize(axis)
        let extendedPos = restPos + extensionAxis * maxExtensionMeters

        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(restPos, 1)

        return TonguePlacement(
            transform: transform,
            restPosition: restPos,
            extendedPosition: extendedPos,
            extensionAxis: extensionAxis
        )
    }

    /// Transform dla animowanego tongueOut 0..1.
    public func animatedTransform(placement: TonguePlacement, tongueOut: Float) -> simd_float4x4 {
        let clamped = max(0, min(1, tongueOut))
        let pos = simd_mix(placement.restPosition, placement.extendedPosition, SIMD3<Float>(repeating: clamped))
        var t = matrix_identity_float4x4
        t.columns.3 = SIMD4<Float>(pos, 1)
        return t
    }
}
