// =============================================================================
// Plik: FaceTrackingSession.swift
// Opis: Sesja ARKit Face Tracking — publikuje ARFaceAnchor przez Combine.
// =============================================================================

import Foundation
import Combine
import ARKit

/// Zdarzenie face trackingu przekazywane downstream.
public struct FaceFrame: Sendable {
    /// Znormalizowane pozycje 1220 wierzchołków ARKit (1220 × SIMD3<Float>).
    public let vertices: [SIMD3<Float>]
    /// 52 wagi blendshape'ów (indeks = ArkitAU.rawValue).
    public let blendWeights: [Float]
    /// Transformacja twarzy w świecie.
    public let transform: simd_float4x4
    /// Znacznik czasu klatki.
    public let timestamp: TimeInterval

    public init(vertices: [SIMD3<Float>], blendWeights: [Float], transform: simd_float4x4, timestamp: TimeInterval) {
        self.vertices = vertices
        self.blendWeights = blendWeights
        self.transform = transform
        self.timestamp = timestamp
    }
}

/// Sesja ARKit Face Tracking.
@MainActor
public final class FaceTrackingSession: NSObject, ObservableObject {
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var lastFrame: FaceFrame?

    private let session = ARSession()
    private let subject = PassthroughSubject<FaceFrame, Never>()

    /// Publikowany strumień klatek.
    public var framePublisher: AnyPublisher<FaceFrame, Never> {
        subject.eraseToAnyPublisher()
    }

    public override init() {
        super.init()
        session.delegate = self
    }

    /// Sprawdza wsparcie urządzenia.
    public static var isSupported: Bool {
        return ARFaceTrackingConfiguration.isSupported
    }

    /// Startuje sesję.
    public func start() throws {
        guard ARFaceTrackingConfiguration.isSupported else {
            throw FaceCalibrationError.faceTrackingUnsupported
        }
        let configuration = ARFaceTrackingConfiguration()
        configuration.isWorldTrackingEnabled = false
        configuration.providesAudioData = false
        configuration.maximumNumberOfTrackedFaces = 1
        configuration.isLightEstimationEnabled = false
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    /// Zatrzymuje sesję.
    public func stop() {
        session.pause()
        isRunning = false
    }
}

extension FaceTrackingSession: ARSessionDelegate {
    public nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        // Zero alokacji — unikamy filter/map; pętla po tablicy.
        for anchor in anchors {
            guard let faceAnchor = anchor as? ARFaceAnchor else { continue }
            handle(faceAnchor: faceAnchor, timestamp: faceAnchor.timestamp)
        }
    }

    private nonisolated func handle(faceAnchor: ARFaceAnchor, timestamp: TimeInterval) {
        let geometry = faceAnchor.geometry
        // Bufor vertices — alokacja jest tu konieczna (struct FaceFrame jest Sendable).
        let verts = Array(UnsafeBufferPointer(start: geometry.vertices, count: geometry.vertices.count))
        // Wagi AU.
        var weights = [Float](repeating: 0, count: ArkitAU.allCases.count)
        let blendShapes = faceAnchor.blendShapes
        for au in ArkitAU.allCases {
            if let value = blendShapes[au.arkitKey] as? NSNumber {
                weights[au.rawValue] = value.floatValue
            }
        }
        let frame = FaceFrame(
            vertices: verts,
            blendWeights: weights,
            transform: faceAnchor.transform,
            timestamp: timestamp
        )
        // PassthroughSubject.send jest thread-safe — publikujemy natychmiast na wątku delegata.
        subject.send(frame)
        // Aktualizacja @Published wymaga MainActor; tylko tu jest alokacja per klatka.
        let publishedFrame = frame
        Task { @MainActor [weak self] in
            self?.lastFrame = publishedFrame
        }
    }
}

/// Błędy warstwy kalibracji.
public enum FaceCalibrationError: Error, LocalizedError {
    case faceTrackingUnsupported
    case noNeutralFaceCaptured
    case userNotRelaxed(maxAU: ArkitAU, value: Float)
    case validationFailed(au: ArkitAU, reason: String)
    case solverFailed(reason: String)
    case bridgeAlignmentFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .faceTrackingUnsupported:
            return "To urządzenie nie obsługuje ARKit Face Tracking."
        case .noNeutralFaceCaptured:
            return "Brak przechwytu neutralnej twarzy."
        case .userNotRelaxed(let au, let value):
            return "Twarz nie jest neutralna — \(au.nameForUI) = \(value)."
        case .validationFailed(let au, let reason):
            return "Walidacja \(au.nameForUI) nie powiodła się: \(reason)"
        case .solverFailed(let reason):
            return "Solver NNLS zawiódł: \(reason)"
        case .bridgeAlignmentFailed(let reason):
            return "Alignment ICP zawiódł: \(reason)"
        }
    }
}
