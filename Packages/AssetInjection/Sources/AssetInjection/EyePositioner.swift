// =============================================================================
// Plik: EyePositioner.swift
// Opis: Pozycjonowanie sfer oczu na podstawie landmarków ARKit z neutralnej twarzy.
// =============================================================================

import Foundation
import ARKit
import simd

/// Placement dla pary sfer oczu.
public struct EyeSpherePlacement: Sendable {
    public let leftCenter: SIMD3<Float>
    public let rightCenter: SIMD3<Float>
    public let radius: Float
    public let eyeSocketDepth: Float
    public let leftTransform: simd_float4x4
    public let rightTransform: simd_float4x4

    public init(
        leftCenter: SIMD3<Float>,
        rightCenter: SIMD3<Float>,
        radius: Float,
        eyeSocketDepth: Float,
        leftTransform: simd_float4x4,
        rightTransform: simd_float4x4
    ) {
        self.leftCenter = leftCenter
        self.rightCenter = rightCenter
        self.radius = radius
        self.eyeSocketDepth = eyeSocketDepth
        self.leftTransform = leftTransform
        self.rightTransform = rightTransform
    }
}

/// Pozycjoner oczu — korzysta z wierzchołków ARKit wokół obszaru oka.
public struct EyePositioner: Sendable {
    /// Indeksy wierzchołków ARKit obejmujące lewe oko (upper/lower/corners).
    /// W ARKit 1220-vert canonical indeksy są stabilne między urządzeniami, ale nie dokumentowane.
    /// Stosujemy regiony: jeśli znamy simd_float4x4 leftEyeTransform z ARFaceAnchor — używamy tego.
    public let socketDepthRatio: Float

    public init(socketDepthRatio: Float = 0.5) {
        self.socketDepthRatio = socketDepthRatio
    }

    /// Wyprowadza placement ze stałych anchor transform (z ARFaceAnchor.leftEyeTransform/rightEyeTransform).
    public func placement(
        leftEyeTransform: simd_float4x4,
        rightEyeTransform: simd_float4x4,
        faceTransform: simd_float4x4
    ) -> EyeSpherePlacement {
        // Pozycje w przestrzeni twarzy.
        let leftPos = SIMD3<Float>(leftEyeTransform.columns.3.x,
                                   leftEyeTransform.columns.3.y,
                                   leftEyeTransform.columns.3.z)
        let rightPos = SIMD3<Float>(rightEyeTransform.columns.3.x,
                                    rightEyeTransform.columns.3.y,
                                    rightEyeTransform.columns.3.z)
        // Średni dystans między oczami = bazowy promień szacunkowy (~1.2 cm).
        let ipd = simd_distance(leftPos, rightPos)
        let radius = max(0.008, min(0.015, ipd * 0.18))
        let depth = radius * socketDepthRatio

        return EyeSpherePlacement(
            leftCenter: leftPos,
            rightCenter: rightPos,
            radius: radius,
            eyeSocketDepth: depth,
            leftTransform: leftEyeTransform,
            rightTransform: rightEyeTransform
        )
    }

    /// Fallback placement — obliczony z regionów wierzchołków neutralnej twarzy ARKit.
    /// Używa heurystyki: pozycja z ARFaceAnchor.leftEyeTransform nieznana, więc bierzemy
    /// średnią spośród wskazanych indeksów.
    public func placementFromRegions(
        neutralVertices: [SIMD3<Float>],
        leftEyeRegionIndices: [Int],
        rightEyeRegionIndices: [Int]
    ) -> EyeSpherePlacement? {
        guard !leftEyeRegionIndices.isEmpty, !rightEyeRegionIndices.isEmpty else { return nil }
        var leftCenter = SIMD3<Float>(0, 0, 0)
        for idx in leftEyeRegionIndices where idx >= 0 && idx < neutralVertices.count {
            leftCenter += neutralVertices[idx]
        }
        leftCenter /= Float(leftEyeRegionIndices.count)

        var rightCenter = SIMD3<Float>(0, 0, 0)
        for idx in rightEyeRegionIndices where idx >= 0 && idx < neutralVertices.count {
            rightCenter += neutralVertices[idx]
        }
        rightCenter /= Float(rightEyeRegionIndices.count)

        let ipd = simd_distance(leftCenter, rightCenter)
        let radius = max(0.008, min(0.015, ipd * 0.18))
        let depth = radius * socketDepthRatio

        var leftT = matrix_identity_float4x4
        leftT.columns.3 = SIMD4<Float>(leftCenter, 1)
        var rightT = matrix_identity_float4x4
        rightT.columns.3 = SIMD4<Float>(rightCenter, 1)

        return EyeSpherePlacement(
            leftCenter: leftCenter,
            rightCenter: rightCenter,
            radius: radius,
            eyeSocketDepth: depth,
            leftTransform: leftT,
            rightTransform: rightT
        )
    }
}
