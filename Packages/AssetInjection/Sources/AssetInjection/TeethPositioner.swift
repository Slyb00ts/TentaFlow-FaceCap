// =============================================================================
// Plik: TeethPositioner.swift
// Opis: Pozycjonowanie łuków zębów — górny do czaszki, dolny ruszany przez AU jawOpen.
// =============================================================================

import Foundation
import simd

/// Placement obu łuków zębów.
public struct TeethPlacement: Sendable {
    public let upperTransform: simd_float4x4
    public let lowerTransform: simd_float4x4
    public let scale: Float
    /// Maksymalny kąt otwarcia żuchwy w radianach (dla AU jawOpen = 1.0).
    public let jawOpenMaxAngle: Float
    /// Pivot żuchwy w przestrzeni twarzy.
    public let jawPivot: SIMD3<Float>

    public init(
        upperTransform: simd_float4x4,
        lowerTransform: simd_float4x4,
        scale: Float,
        jawOpenMaxAngle: Float,
        jawPivot: SIMD3<Float>
    ) {
        self.upperTransform = upperTransform
        self.lowerTransform = lowerTransform
        self.scale = scale
        self.jawOpenMaxAngle = jawOpenMaxAngle
        self.jawPivot = jawPivot
    }
}

/// Pozycjoner zębów.
public struct TeethPositioner: Sendable {
    public let maxJawOpenDegrees: Float

    public init(maxJawOpenDegrees: Float = 22.0) {
        self.maxJawOpenDegrees = maxJawOpenDegrees
    }

    /// Oblicza placement z pozycji wewnętrznych warg (upper/lower).
    public func placement(
        upperLipInner: SIMD3<Float>,
        lowerLipInner: SIMD3<Float>,
        mouthCornerLeft: SIMD3<Float>,
        mouthCornerRight: SIMD3<Float>
    ) -> TeethPlacement {
        // Centrum ust.
        let mouthCenter = (upperLipInner + lowerLipInner) * 0.5
        let mouthWidth = simd_distance(mouthCornerLeft, mouthCornerRight)
        let scale = max(0.8, min(1.2, mouthWidth / 0.05))  // Skaluj względem ~5cm szerokości.

        // Upper: +1mm powyżej wewnętrznej górnej wargi, z lekkim cofnięciem w Z.
        let upperOffset = SIMD3<Float>(0, -0.002, -0.002)
        let upperPos = upperLipInner + upperOffset
        var upperT = matrix_identity_float4x4
        upperT.columns.0 *= scale
        upperT.columns.1 *= scale
        upperT.columns.2 *= scale
        upperT.columns.3 = SIMD4<Float>(upperPos, 1)

        // Lower: +1mm pod wewnętrzną dolną wargą.
        let lowerOffset = SIMD3<Float>(0, 0.002, -0.002)
        let lowerPos = lowerLipInner + lowerOffset
        var lowerT = matrix_identity_float4x4
        lowerT.columns.0 *= scale
        lowerT.columns.1 *= scale
        lowerT.columns.2 *= scale
        lowerT.columns.3 = SIMD4<Float>(lowerPos, 1)

        // Pivot żuchwy: ~4 cm za centrum ust (typowy staw skroniowo-żuchwowy).
        let jawPivot = mouthCenter + SIMD3<Float>(0, 0.01, -0.04)
        let maxAngleRad = maxJawOpenDegrees * .pi / 180.0

        return TeethPlacement(
            upperTransform: upperT,
            lowerTransform: lowerT,
            scale: scale,
            jawOpenMaxAngle: maxAngleRad,
            jawPivot: jawPivot
        )
    }

    /// Zwraca transformację łuku dolnego z uwzględnieniem AU jawOpen (0..1).
    public func animatedLowerTransform(placement: TeethPlacement, jawOpen: Float) -> simd_float4x4 {
        let clamped = max(0, min(1, jawOpen))
        let angle = clamped * placement.jawOpenMaxAngle
        // Obrót wokół osi X w pivotze.
        let c = cos(-angle)
        let s = sin(-angle)
        var rot = matrix_identity_float4x4
        rot.columns.1 = SIMD4<Float>(0, c, s, 0)
        rot.columns.2 = SIMD4<Float>(0, -s, c, 0)

        // Pivot: T · R · T^-1 · originalLower
        var toPivot = matrix_identity_float4x4
        toPivot.columns.3 = SIMD4<Float>(-placement.jawPivot, 1)
        var fromPivot = matrix_identity_float4x4
        fromPivot.columns.3 = SIMD4<Float>(placement.jawPivot, 1)
        return fromPivot * rot * toPivot * placement.lowerTransform
    }
}
