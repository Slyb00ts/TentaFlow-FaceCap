// =============================================================================
// Plik: FaceCalibrationResult.swift
// Opis: Wynik pełnej kalibracji twarzy — neutral, delta, bridge, maski L/R.
// =============================================================================

import Foundation
import simd

/// Wynik kompletnej kalibracji twarzy użytkownika.
public struct FaceCalibrationResult: Sendable {
    /// Neutralna twarz (baseline).
    public let neutralFace: NeutralFace
    /// 52 dekorelowane delta w przestrzeni ARKit (1220 verts).
    public let decorrelatedDeltas: [BlendshapeDelta]
    /// Bridge ARKit → scan mesh.
    public let arkitBridge: ARKitFaceBridge
    /// 52 delta przeniesione na mesh skanu.
    public let transferredDeltas: [BlendshapeDelta]
    /// Maska lewa (0..255) — waga AU na wierzchołek L.
    public let leftMask: [UInt8]
    /// Maska prawa (0..255) — waga AU na wierzchołek R.
    public let rightMask: [UInt8]
    /// Pominięte AU (user skipped).
    public let skippedAUs: [ArkitAU]

    public init(
        neutralFace: NeutralFace,
        decorrelatedDeltas: [BlendshapeDelta],
        arkitBridge: ARKitFaceBridge,
        transferredDeltas: [BlendshapeDelta],
        leftMask: [UInt8],
        rightMask: [UInt8],
        skippedAUs: [ArkitAU]
    ) {
        self.neutralFace = neutralFace
        self.decorrelatedDeltas = decorrelatedDeltas
        self.arkitBridge = arkitBridge
        self.transferredDeltas = transferredDeltas
        self.leftMask = leftMask
        self.rightMask = rightMask
        self.skippedAUs = skippedAUs
    }

    /// Generuje maski L/R dla mesh na podstawie znaku x wierzchołków skanu.
    public static func buildLeftRightMasks(scanVerts: [SIMD3<Float>]) -> (left: [UInt8], right: [UInt8]) {
        let count = scanVerts.count
        var left = [UInt8](repeating: 0, count: count)
        var right = [UInt8](repeating: 0, count: count)
        // Szukamy zakresu x dla normalizacji smooth mask.
        var minX: Float = .infinity
        var maxX: Float = -.infinity
        for v in scanVerts {
            if v.x < minX { minX = v.x }
            if v.x > maxX { maxX = v.x }
        }
        let range = max(1e-5, maxX - minX)
        let center = (minX + maxX) * 0.5
        let halfRange = range * 0.5
        for i in 0..<count {
            let x = scanVerts[i].x
            let normalized = (x - center) / halfRange  // -1..1
            // Gładka rampa: w środku obie maski ~128, po bokach 255 / 0.
            let leftF = max(0.0, min(1.0, 0.5 - 0.5 * normalized))
            let rightF = max(0.0, min(1.0, 0.5 + 0.5 * normalized))
            left[i] = UInt8((leftF * 255.0).rounded())
            right[i] = UInt8((rightF * 255.0).rounded())
        }
        return (left, right)
    }
}
