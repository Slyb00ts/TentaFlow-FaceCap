// =============================================================================
// Plik: ScanQualityAnalyzer.swift
// Opis: Analiza jakości skanu — coverage, ostrość Laplacian variance, wariancja pozy.
// =============================================================================

import Foundation
import CoreImage
import CoreVideo
import CoreMotion
import Accelerate
import simd

/// Pojedyncza obserwacja klatki i pozy.
public struct ScanFrameObservation: Sendable {
    /// Znormalizowana jasność/ostrość 0..n.
    public let sharpness: Float
    /// Orientacja urządzenia w momencie klatki (quaternion).
    public let orientation: simd_quatf
    public let timestamp: TimeInterval

    public init(sharpness: Float, orientation: simd_quatf, timestamp: TimeInterval) {
        self.sharpness = sharpness
        self.orientation = orientation
        self.timestamp = timestamp
    }
}

/// Analizator metryk skanu.
public final class ScanQualityAnalyzer {
    private var observations: [ScanFrameObservation] = []
    private let ciContext: CIContext

    public init() {
        self.ciContext = CIContext(options: [.cacheIntermediates: false])
    }

    /// Dodaje klatkę do analizy. Zwraca ostrość Laplacian variance.
    public func ingest(pixelBuffer: CVPixelBuffer, orientation: simd_quatf, timestamp: TimeInterval) -> Float {
        let sharpness = Self.laplacianVariance(pixelBuffer: pixelBuffer, context: ciContext)
        observations.append(ScanFrameObservation(
            sharpness: sharpness,
            orientation: orientation,
            timestamp: timestamp
        ))
        return sharpness
    }

    /// Resetuje zebrane obserwacje.
    public func reset() {
        observations.removeAll(keepingCapacity: true)
    }

    /// Generuje raport końcowy.
    public func finalize() -> ScanQualityReport {
        guard !observations.isEmpty else {
            return ScanQualityReport(coverage: 0, sharpnessScore: 0, poseVariance: 0, frameCount: 0)
        }

        // Średnia ostrość.
        let sumSharp = observations.reduce(Float(0)) { $0 + $1.sharpness }
        let avgSharp = sumSharp / Float(observations.count)

        // Wariancja orientacji: liczymy jako rozrzut kątów euler wokół Y.
        let yaws = observations.map { Self.yaw(from: $0.orientation) }
        let yawMean = yaws.reduce(Float(0), +) / Float(yaws.count)
        let yawVar = yaws.reduce(Float(0)) { $0 + ($1 - yawMean) * ($1 - yawMean) } / Float(yaws.count)

        // Coverage: normalizujemy po zakresie yaw — 360° pokrycia = 1.0.
        let yawRange: Float
        if let minY = yaws.min(), let maxY = yaws.max() {
            yawRange = maxY - minY
        } else {
            yawRange = 0
        }
        let coverage = min(1.0, yawRange / (2.0 * .pi))

        return ScanQualityReport(
            coverage: coverage,
            sharpnessScore: avgSharp,
            poseVariance: sqrt(yawVar),
            frameCount: observations.count
        )
    }

    // MARK: - Laplacian variance (ostrość obrazu)

    /// Liczy wariancję Laplacianu — klasyczny detektor rozmycia.
    /// Wyższa wartość = ostrzejsze zdjęcie.
    public static func laplacianVariance(pixelBuffer: CVPixelBuffer, context: CIContext) -> Float {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        // Przeskaluj do małej rozdzielczości — szybki proxy, ~200×200.
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let targetW: CGFloat = 200.0
        let scale = targetW / CGFloat(w)
        let resized = image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .applyingFilter("CIPhotoEffectMono")

        let extent = CGRect(x: 0, y: 0, width: Int(CGFloat(w) * scale), height: Int(CGFloat(h) * scale))
        let pixelsW = Int(extent.width)
        let pixelsH = Int(extent.height)
        guard pixelsW > 2 && pixelsH > 2 else { return 0 }

        var grayBytes = [UInt8](repeating: 0, count: pixelsW * pixelsH)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        context.render(resized,
                       toBitmap: &grayBytes,
                       rowBytes: pixelsW,
                       bounds: extent,
                       format: .R8,
                       colorSpace: colorSpace)

        // Laplacian 3×3.
        var floats = [Float](repeating: 0, count: pixelsW * pixelsH)
        vDSP_vfltu8(grayBytes, 1, &floats, 1, vDSP_Length(grayBytes.count))

        var laplacian = [Float](repeating: 0, count: pixelsW * pixelsH)
        for y in 1..<(pixelsH - 1) {
            for x in 1..<(pixelsW - 1) {
                let idx = y * pixelsW + x
                let center = floats[idx]
                let up = floats[idx - pixelsW]
                let down = floats[idx + pixelsW]
                let left = floats[idx - 1]
                let right = floats[idx + 1]
                laplacian[idx] = up + down + left + right - 4.0 * center
            }
        }

        var mean: Float = 0
        var variance: Float = 0
        vDSP_normalize(laplacian, 1, nil, 1, &mean, &variance, vDSP_Length(laplacian.count))
        // vDSP_normalize zwraca std dev w `variance` — podnieś do kwadratu.
        return variance * variance
    }

    /// Wyciąga kąt yaw (wokół Y) z quaternionu.
    private static func yaw(from quat: simd_quatf) -> Float {
        let w = quat.vector.w
        let x = quat.vector.x
        let y = quat.vector.y
        let z = quat.vector.z
        let siny_cosp = 2.0 * (w * y + z * x)
        let cosy_cosp = 1.0 - 2.0 * (x * x + y * y)
        return atan2(siny_cosp, cosy_cosp)
    }
}
