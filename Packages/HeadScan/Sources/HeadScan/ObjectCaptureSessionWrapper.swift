// =============================================================================
// Plik: ObjectCaptureSessionWrapper.swift
// Opis: Wrapper nad RealityKit.ObjectCaptureSession udostępniający AsyncStream stanu.
// =============================================================================

import Foundation
import RealityKit

/// Zdarzenie przechwytywania przekazywane do warstwy UI.
@available(iOS 17.0, *)
public enum CaptureEvent: Sendable {
    case stateChanged(ObjectCaptureSession.CaptureState)
    case feedback(Set<ObjectCaptureSession.Feedback>)
    case frameCaptured(count: Int)
    case error(String)
    case finished(imagesDirectory: URL)
}

/// Owija RealityKit.ObjectCaptureSession i udostępnia spójny interfejs asynchroniczny.
@available(iOS 17.0, *)
@MainActor
public final class ObjectCaptureSessionWrapper {
    private let session: ObjectCaptureSession
    private let imagesDirectory: URL
    private let checkpointDirectory: URL
    private var pumpTask: Task<Void, Never>?
    private var frameCount: Int = 0

    public private(set) var isRunning: Bool = false

    /// Strumień zdarzeń sesji.
    public let events: AsyncStream<CaptureEvent>
    private let eventsContinuation: AsyncStream<CaptureEvent>.Continuation

    public init(imagesDirectory: URL, checkpointDirectory: URL) {
        self.imagesDirectory = imagesDirectory
        self.checkpointDirectory = checkpointDirectory
        self.session = ObjectCaptureSession()

        let (stream, continuation) = AsyncStream<CaptureEvent>.makeStream()
        self.events = stream
        self.eventsContinuation = continuation
    }

    deinit {
        pumpTask?.cancel()
        eventsContinuation.finish()
    }

    /// Uruchamia sesję. Rzuca błąd gdy urządzenie nie wspiera ObjectCapture.
    public func start() throws {
        guard ObjectCaptureSession.isSupported else {
            throw HeadScanError.captureFailed("ObjectCaptureSession nie jest wspierana na tym urządzeniu.")
        }
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: checkpointDirectory, withIntermediateDirectories: true)

        var configuration = ObjectCaptureSession.Configuration()
        configuration.checkpointDirectory = checkpointDirectory
        configuration.isOverCaptureEnabled = false

        session.start(imagesDirectory: imagesDirectory, configuration: configuration)
        isRunning = true
        startPumping()
    }

    /// Ręczne pobranie kolejnej klatki referencyjnej.
    public func captureImage() {
        guard session.canRequestCapture else { return }
        session.requestImageCapture()
    }

    /// Finalizuje przechwytywanie — po tym można uruchomić PhotogrammetrySession.
    public func finish() {
        session.finish()
    }

    /// Pauza sesji.
    public func pause() {
        session.pause()
    }

    /// Wznawia sesję po pauzie.
    public func resume() {
        session.resume()
    }

    /// Anuluje sesję.
    public func cancel() {
        session.cancel()
        isRunning = false
        pumpTask?.cancel()
        eventsContinuation.finish()
    }

    // MARK: - Wewnętrzne

    private func startPumping() {
        pumpTask = Task { [weak self] in
            guard let self else { return }
            await self.pumpStateAndFeedback()
        }
    }

    private func pumpStateAndFeedback() async {
        async let stateLoop: Void = pumpStateUpdates()
        async let feedbackLoop: Void = pumpFeedbackUpdates()
        _ = await (stateLoop, feedbackLoop)
    }

    private func pumpStateUpdates() async {
        for await state in session.stateUpdates {
            eventsContinuation.yield(.stateChanged(state))
            switch state {
            case .completed:
                eventsContinuation.yield(.finished(imagesDirectory: imagesDirectory))
                eventsContinuation.finish()
                isRunning = false
                return
            case .failed(let error):
                eventsContinuation.yield(.error(String(describing: error)))
                eventsContinuation.finish()
                isRunning = false
                return
            default:
                break
            }
        }
    }

    private func pumpFeedbackUpdates() async {
        for await feedback in session.feedbackUpdates {
            eventsContinuation.yield(.feedback(feedback))
        }
    }
}
