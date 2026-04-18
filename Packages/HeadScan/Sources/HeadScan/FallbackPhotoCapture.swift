// =============================================================================
// Plik: FallbackPhotoCapture.swift
// Opis: Fallback bez LiDAR — AVCaptureSession + AVCapturePhotoOutput, 30 zdjęć guided.
// =============================================================================

import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Postęp fallbackowego captury.
public struct FallbackCaptureProgress: Sendable {
    public let captured: Int
    public let total: Int
    public let prompt: String
    public let angleDegrees: Float
}

/// Prosty rejestrator zdjęć z guided UX — obracaj głowę co ~12°.
@available(iOS 17.0, *)
public final class FallbackPhotoCapture: NSObject, @unchecked Sendable {
    public let targetPhotoCount: Int
    public let photoIntervalDegrees: Float

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.tentaflow.fallback-photo", qos: .userInitiated)

    private var saveDirectory: URL
    private var counter: Int = 0
    private var progressHandler: (@Sendable (FallbackCaptureProgress) -> Void)?
    private var completion: (@Sendable (Result<URL, Error>) -> Void)?
    private var isConfigured: Bool = false

    public init(targetPhotoCount: Int = 30, saveDirectory: URL) {
        self.targetPhotoCount = targetPhotoCount
        self.photoIntervalDegrees = 360.0 / Float(targetPhotoCount)
        self.saveDirectory = saveDirectory
        super.init()
    }

    /// Konfiguruje i startuje sesję.
    public func start(
        progress: @escaping @Sendable (FallbackCaptureProgress) -> Void,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.progressHandler = progress
        self.completion = completion

        queue.async { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: self.saveDirectory, withIntermediateDirectories: true)
                try self.configureSessionIfNeeded()
                self.session.startRunning()
                self.counter = 0
                self.emitProgress()
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Wykonaj kolejne zdjęcie — wywołaj po stabilizacji pozy użytkownika.
    public func captureNext() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            if self.counter >= self.targetPhotoCount {
                return
            }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            settings.isHighResolutionPhotoEnabled = true
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Anuluje sesję.
    public func cancel() {
        queue.async { [weak self] in
            self?.session.stopRunning()
            self?.completion?(.failure(HeadScanError.cancelled))
            self?.completion = nil
        }
    }

    // MARK: - Konfiguracja AVCapture

    private func configureSessionIfNeeded() throws {
        if isConfigured { return }
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            throw HeadScanError.captureFailed("Brak kamery tylnej.")
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            throw HeadScanError.captureFailed("Nie można otworzyć kamery: \(error.localizedDescription)")
        }

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw HeadScanError.captureFailed("Sesja nie akceptuje wejścia kamery.")
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            throw HeadScanError.captureFailed("Sesja nie akceptuje wyjścia zdjęć.")
        }
        session.addOutput(photoOutput)
        photoOutput.isHighResolutionCaptureEnabled = true

        session.commitConfiguration()
        isConfigured = true
    }

    private func emitProgress() {
        let angle = Float(counter) * photoIntervalDegrees
        let prompt: String
        if counter == 0 {
            prompt = "Ustaw twarz na wprost i naciśnij przycisk, żeby wykonać pierwsze zdjęcie."
        } else if counter >= targetPhotoCount {
            prompt = "Gotowe — przetwarzanie klatek."
        } else {
            prompt = "Obróć głowę o \(Int(photoIntervalDegrees.rounded()))° w prawo."
        }
        progressHandler?(FallbackCaptureProgress(
            captured: counter,
            total: targetPhotoCount,
            prompt: prompt,
            angleDegrees: angle
        ))
    }

    fileprivate func onPhotoSaved(to url: URL) {
        counter += 1
        emitProgress()
        if counter >= targetPhotoCount {
            session.stopRunning()
            completion?(.success(saveDirectory))
            completion = nil
        }
    }
}

@available(iOS 17.0, *)
extension FallbackPhotoCapture: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput,
                            didFinishProcessingPhoto photo: AVCapturePhoto,
                            error: Error?) {
        if let error {
            completion?(.failure(HeadScanError.captureFailed(error.localizedDescription)))
            completion = nil
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            completion?(.failure(HeadScanError.captureFailed("Brak danych zdjęcia.")))
            completion = nil
            return
        }
        let filename = String(format: "frame_%03d.heic", counter)
        let url = saveDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            onPhotoSaved(to: url)
        } catch {
            completion?(.failure(HeadScanError.captureFailed("Zapis nieudany: \(error.localizedDescription)")))
            completion = nil
        }
    }
}
