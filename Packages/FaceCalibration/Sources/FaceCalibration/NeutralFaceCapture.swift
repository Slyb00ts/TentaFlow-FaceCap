// =============================================================================
// Plik: NeutralFaceCapture.swift
// Opis: Captures neutralnej twarzy — 3s hold, uśrednienie 60 klatek, walidacja AU.
// =============================================================================

import Foundation
import simd

/// Neutralna twarz — baseline do kalkulacji delta.
public struct NeutralFace: Sendable {
    /// Uśrednione pozycje 1220 wierzchołków ARKit.
    public let vertices: [SIMD3<Float>]
    /// Uśrednione wagi AU (powinny być bliskie 0).
    public let blendWeights: [Float]
    /// Liczba klatek użytych do uśrednienia.
    public let sampleCount: Int

    public init(vertices: [SIMD3<Float>], blendWeights: [Float], sampleCount: Int) {
        self.vertices = vertices
        self.blendWeights = blendWeights
        self.sampleCount = sampleCount
    }
}

/// Aktor captury neutralnej twarzy — zapewnia bezpieczeństwo przy async await.
public actor NeutralFaceCapture {
    /// Próg tolerancji AU dla neutralnej pozycji.
    public let neutralThreshold: Float
    /// Wymagana liczba klatek do uśrednienia.
    public let requiredSamples: Int
    /// Timeout oczekiwania w sekundach.
    public let timeoutSeconds: TimeInterval

    private let reader: BlendshapeReader

    public init(
        reader: BlendshapeReader,
        neutralThreshold: Float = 0.05,
        requiredSamples: Int = 60,
        timeoutSeconds: TimeInterval = 10.0
    ) {
        self.reader = reader
        self.neutralThreshold = neutralThreshold
        self.requiredSamples = requiredSamples
        self.timeoutSeconds = timeoutSeconds
    }

    /// Próbuje przechwycić neutralną twarz — czeka aż uzbiera się `requiredSamples` klatek.
    public func captureNeutral() async throws -> NeutralFace {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let window = reader.snapshot(lastN: requiredSamples)
            if window.count >= requiredSamples {
                return try averageAndValidate(window: window)
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        throw FaceCalibrationError.noNeutralFaceCaptured
    }

    /// Uśrednia klatki i waliduje czy żaden AU nie przekracza progu.
    private func averageAndValidate(window: [FaceFrame]) throws -> NeutralFace {
        guard let first = window.first else {
            throw FaceCalibrationError.noNeutralFaceCaptured
        }
        let vertexCount = first.vertices.count
        let auCount = ArkitAU.allCases.count

        var accumulatedVerts = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: vertexCount)
        var accumulatedWeights = [Float](repeating: 0, count: auCount)

        for frame in window {
            guard frame.vertices.count == vertexCount else { continue }
            for i in 0..<vertexCount {
                accumulatedVerts[i] += frame.vertices[i]
            }
            for i in 0..<auCount {
                accumulatedWeights[i] += frame.blendWeights[i]
            }
        }

        let invCount = 1.0 / Float(window.count)
        for i in 0..<vertexCount {
            accumulatedVerts[i] *= invCount
        }
        for i in 0..<auCount {
            accumulatedWeights[i] *= invCount
        }

        // Walidacja — wszystkie AU < threshold.
        for au in ArkitAU.allCases {
            let value = accumulatedWeights[au.rawValue]
            if value > neutralThreshold {
                throw FaceCalibrationError.userNotRelaxed(maxAU: au, value: value)
            }
        }

        return NeutralFace(
            vertices: accumulatedVerts,
            blendWeights: accumulatedWeights,
            sampleCount: window.count
        )
    }
}
