// =============================================================================
// Plik: PhotogrammetrySessionRunner.swift
// Opis: Orkiestrator RealityKit.PhotogrammetrySession — batch processing klatek do USDZ.
// =============================================================================

import Foundation
import RealityKit

/// Postęp przetwarzania fotogrametrii.
public struct PhotogrammetryProgress: Sendable {
    public let fractionComplete: Double
    public let processingStage: String

    public init(fractionComplete: Double, processingStage: String) {
        self.fractionComplete = fractionComplete
        self.processingStage = processingStage
    }
}

/// Uruchamia PhotogrammetrySession w trybie asynchronicznym.
@available(iOS 17.0, *)
public struct PhotogrammetrySessionRunner {
    public enum Detail: Sendable {
        case preview
        case reduced
        case medium
        case full

        fileprivate var requestDetail: PhotogrammetrySession.Request.Detail {
            switch self {
            case .preview: return .preview
            case .reduced: return .reduced
            case .medium: return .medium
            case .full: return .full
            }
        }
    }

    public let inputDirectory: URL
    public let outputURL: URL
    public let detail: Detail

    public init(inputDirectory: URL, outputURL: URL, detail: Detail = .reduced) {
        self.inputDirectory = inputDirectory
        self.outputURL = outputURL
        self.detail = detail
    }

    /// Wykonuje pełen pipeline fotogrametrii. Raportuje postęp przez `progressHandler`.
    public func run(progressHandler: @Sendable @escaping (PhotogrammetryProgress) -> Void) async throws -> URL {
        guard PhotogrammetrySession.isSupported else {
            throw HeadScanError.processingFailed("PhotogrammetrySession nie jest wspierana na tym urządzeniu.")
        }

        var configuration = PhotogrammetrySession.Configuration()
        configuration.featureSensitivity = .high
        configuration.sampleOrdering = .sequential
        configuration.isObjectMaskingEnabled = true

        let session: PhotogrammetrySession
        do {
            session = try PhotogrammetrySession(
                input: inputDirectory,
                configuration: configuration
            )
        } catch {
            throw HeadScanError.processingFailed("Konstrukcja sesji zawiodła: \(error.localizedDescription)")
        }

        let request = PhotogrammetrySession.Request.modelFile(
            url: outputURL,
            detail: detail.requestDetail
        )

        do {
            try session.process(requests: [request])
        } catch {
            throw HeadScanError.processingFailed("Wysłanie żądania zawiodło: \(error.localizedDescription)")
        }

        for try await output in session.outputs {
            switch output {
            case .processingComplete:
                return outputURL
            case .requestComplete(_, let result):
                if case .modelFile(let url) = result {
                    return url
                }
            case .requestProgress(_, let fraction):
                progressHandler(PhotogrammetryProgress(
                    fractionComplete: fraction,
                    processingStage: "Przetwarzanie"
                ))
            case .requestProgressInfo(_, let info):
                let stageName = Self.stageDescription(info.processingStage)
                progressHandler(PhotogrammetryProgress(
                    fractionComplete: 0.0,
                    processingStage: stageName
                ))
            case .requestError(_, let error):
                throw HeadScanError.processingFailed("Błąd requestu: \(error.localizedDescription)")
            case .processingCancelled:
                throw HeadScanError.cancelled
            case .inputComplete:
                continue
            case .invalidSample(_, let reason):
                // Niekrytyczne — kontynuujemy.
                progressHandler(PhotogrammetryProgress(
                    fractionComplete: 0.0,
                    processingStage: "Pominięto klatkę: \(reason)"
                ))
            case .skippedSample:
                continue
            case .automaticDownsampling:
                progressHandler(PhotogrammetryProgress(
                    fractionComplete: 0.0,
                    processingStage: "Automatyczne zmniejszanie rozdzielczości"
                ))
            case .stitchingIncomplete:
                continue
            @unknown default:
                continue
            }
        }

        throw HeadScanError.processingFailed("Sesja zakończona bez modelu.")
    }

    private static func stageDescription(_ stage: PhotogrammetrySession.Output.ProcessingStage?) -> String {
        guard let stage else { return "Nieznany etap" }
        switch stage {
        case .preProcessing: return "Pre-processing"
        case .imageAlignment: return "Wyrównywanie zdjęć"
        case .pointCloudGeneration: return "Chmura punktów"
        case .meshGeneration: return "Generowanie siatki"
        case .textureMapping: return "Mapowanie tekstur"
        case .optimization: return "Optymalizacja"
        @unknown default: return "Etap przetwarzania"
        }
    }
}
