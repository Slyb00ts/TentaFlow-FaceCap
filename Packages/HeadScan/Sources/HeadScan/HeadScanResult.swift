// =============================================================================
// Plik: HeadScanResult.swift
// Opis: Wynik skanu głowy — geometria mesh, tekstura oraz raport jakości.
// =============================================================================

import Foundation
import CoreGraphics
import simd

/// Zdecymowany mesh głowy gotowy do dalszego przetwarzania.
public struct HeadScanResult: Sendable {
    /// URL do wygenerowanego pliku USDZ (cache lub tmp).
    public let usdzURL: URL
    /// Wierzchołki siatki — pozycje 3D w metrach.
    public let meshVerts: [SIMD3<Float>]
    /// Wektory normalne wierzchołków.
    public let meshNormals: [SIMD3<Float>]
    /// Współrzędne UV wierzchołków.
    public let meshUVs: [SIMD2<Float>]
    /// Indeksy trójkątów — UInt16 bo po decymacji < 65k wierzchołków.
    public let meshTriangles: [SIMD3<UInt16>]
    /// Tekstura diffuse mapy twarzy.
    public let textureCGImage: CGImage
    /// Raport jakości skanu.
    public let scanQuality: ScanQualityReport

    public init(
        usdzURL: URL,
        meshVerts: [SIMD3<Float>],
        meshNormals: [SIMD3<Float>],
        meshUVs: [SIMD2<Float>],
        meshTriangles: [SIMD3<UInt16>],
        textureCGImage: CGImage,
        scanQuality: ScanQualityReport
    ) {
        self.usdzURL = usdzURL
        self.meshVerts = meshVerts
        self.meshNormals = meshNormals
        self.meshUVs = meshUVs
        self.meshTriangles = meshTriangles
        self.textureCGImage = textureCGImage
        self.scanQuality = scanQuality
    }
}

/// Raport jakości skanu — metryki diagnostyczne.
public struct ScanQualityReport: Sendable, Equatable {
    /// Procent pokrycia głowy (0.0–1.0).
    public let coverage: Float
    /// Średnia ostrość Laplacian variance (wyższe = lepiej).
    public let sharpnessScore: Float
    /// Wariancja orientacji — czy użytkownik prawidłowo obrócił głowę.
    public let poseVariance: Float
    /// Liczba klatek wejściowych.
    public let frameCount: Int
    /// Ocena zbiorcza 0–100.
    public var overallScore: Int {
        let coverageComponent = coverage * 50.0
        let sharpnessComponent = min(1.0, sharpnessScore / 200.0) * 30.0
        let poseComponent = min(1.0, poseVariance / 2.0) * 20.0
        return Int((coverageComponent + sharpnessComponent + poseComponent).rounded())
    }

    public init(coverage: Float, sharpnessScore: Float, poseVariance: Float, frameCount: Int) {
        self.coverage = coverage
        self.sharpnessScore = sharpnessScore
        self.poseVariance = poseVariance
        self.frameCount = frameCount
    }
}

/// Błędy warstwy skanu głowy.
public enum HeadScanError: Error, LocalizedError {
    case captureFailed(String)
    case processingFailed(String)
    case meshLoadFailed(String)
    case noLidarAvailable
    case insufficientFrames(Int)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .captureFailed(let reason): return "Nie udało się przechwycić skanu: \(reason)"
        case .processingFailed(let reason): return "Błąd przetwarzania fotogrametrii: \(reason)"
        case .meshLoadFailed(let reason): return "Nie można załadować USDZ: \(reason)"
        case .noLidarAvailable: return "Urządzenie nie ma czujnika LiDAR."
        case .insufficientFrames(let count): return "Za mało klatek: \(count)."
        case .cancelled: return "Skan anulowany przez użytkownika."
        }
    }
}
