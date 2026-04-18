// =============================================================================
// Plik: CalibrationValidator.swift
// Opis: Walidator nagrania AU — peak, cross-correlation Pearson r względem innych AU.
// =============================================================================

import Foundation
import Accelerate

/// Wynik walidacji pojedynczej AU.
public enum ValidationResult: Sendable, Equatable {
    case ok(peak: Float)
    case peakTooLow(peak: Float, threshold: Float)
    case correlated(with: [ArkitAU])
    case insufficientData
}

/// Walidator kalibracji — threshold 0.85 dla blink, 0.6 domyślny, Pearson < 0.5.
public struct CalibrationValidator: Sendable {
    public let correlationThreshold: Float
    public let minSamples: Int

    public init(correlationThreshold: Float = 0.5, minSamples: Int = 30) {
        self.correlationThreshold = correlationThreshold
        self.minSamples = minSamples
    }

    /// Waliduje nagranie dla wskazanej AU.
    public func validate(recording: [FaceFrame], targetAU: ArkitAU) -> ValidationResult {
        guard recording.count >= minSamples else { return .insufficientData }

        // Wartości target AU w czasie.
        var targetSeries = [Float](repeating: 0, count: recording.count)
        for (i, frame) in recording.enumerated() {
            targetSeries[i] = frame.blendWeights[targetAU.rawValue]
        }

        // Peak.
        var peak: Float = 0
        vDSP_maxv(targetSeries, 1, &peak, vDSP_Length(targetSeries.count))
        if peak < targetAU.detectionThreshold {
            return .peakTooLow(peak: peak, threshold: targetAU.detectionThreshold)
        }

        // Pearson correlation między target a każdym innym AU.
        var correlated: [ArkitAU] = []
        for candidate in ArkitAU.allCases where candidate != targetAU {
            // Pomijamy AU z innej grupy — mała szansa, ale też mniej istotne.
            if candidate.correlationGroup != targetAU.correlationGroup {
                continue
            }
            var candidateSeries = [Float](repeating: 0, count: recording.count)
            for (i, frame) in recording.enumerated() {
                candidateSeries[i] = frame.blendWeights[candidate.rawValue]
            }
            let r = Self.pearson(targetSeries, candidateSeries)
            // Wysoka korelacja przy jednoczesnym niezerowym peak candidate = cross-talk.
            var candidatePeak: Float = 0
            vDSP_maxv(candidateSeries, 1, &candidatePeak, vDSP_Length(candidateSeries.count))
            if abs(r) >= correlationThreshold && candidatePeak > 0.3 {
                correlated.append(candidate)
            }
        }

        if !correlated.isEmpty {
            return .correlated(with: correlated)
        }
        return .ok(peak: peak)
    }

    /// Pearson r pomiędzy dwoma szeregami tej samej długości.
    public static func pearson(_ x: [Float], _ y: [Float]) -> Float {
        let n = min(x.count, y.count)
        guard n > 1 else { return 0 }
        var meanX: Float = 0
        var meanY: Float = 0
        vDSP_meanv(x, 1, &meanX, vDSP_Length(n))
        vDSP_meanv(y, 1, &meanY, vDSP_Length(n))

        var dx = [Float](repeating: 0, count: n)
        var dy = [Float](repeating: 0, count: n)
        var negMeanX = -meanX
        var negMeanY = -meanY
        vDSP_vsadd(x, 1, &negMeanX, &dx, 1, vDSP_Length(n))
        vDSP_vsadd(y, 1, &negMeanY, &dy, 1, vDSP_Length(n))

        var cov: Float = 0
        vDSP_dotpr(dx, 1, dy, 1, &cov, vDSP_Length(n))

        var dxSq: Float = 0
        var dySq: Float = 0
        vDSP_svesq(dx, 1, &dxSq, vDSP_Length(n))
        vDSP_svesq(dy, 1, &dySq, vDSP_Length(n))

        let denom = sqrt(dxSq * dySq)
        if denom < 1e-9 { return 0 }
        return cov / denom
    }
}
