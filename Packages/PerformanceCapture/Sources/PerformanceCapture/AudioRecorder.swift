// =============================================================================
// Plik: AudioRecorder.swift
// Opis: Wrapper AVAudioRecorder: PCM s16le 16 kHz mono do pliku tymczasowego.
// =============================================================================

import Foundation
import AVFoundation
import os

/// Rejestrator audio wypluwający surowe PCM s16le 16 kHz mono.
///
/// Używany równolegle z `PerformanceRecorder` — timeline AU i PCM powstają
/// w tej samej sesji i mają wspólny `startedAt`, dzięki czemu można je
/// synchronicznie odtwarzać (`PerformancePlayer`).
public final class AudioRecorder {

    /// Stan rejestratora.
    public enum State: Equatable {
        case idle
        case recording(url: URL)
    }

    /// Aktualny stan.
    public private(set) var state: State = .idle

    /// URL pliku wynikowego (WAV PCM s16le, 16 kHz, mono) — dostępny po `stopRecording`.
    public private(set) var outputURL: URL?

    private let log = Logger(subsystem: "pl.tentaflow.facecap", category: "audio-recorder")
    private var recorder: AVAudioRecorder?

    public init() {}

    /// Uruchamia nagrywanie do pliku w `NSTemporaryDirectory()`.
    ///
    /// - Throws: `PerformanceCaptureError.audioSessionFailed` przy błędach sesji.
    public func startRecording() async throws -> URL {
        if case .recording = state {
            throw PerformanceCaptureError.audioSessionFailed("Już nagrywam")
        }
        try configureSession()

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let fileURL = tempDir.appendingPathComponent("perf-\(UUID().uuidString).wav")

        // WAV PCM s16le 16 kHz mono — format najlżejszy dla ESP32 (brak resamplingu
        // po stronie Tab5, bo tam mamy już 16 kHz w pipeline audio).
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let rec = try AVAudioRecorder(url: fileURL, settings: settings)
            rec.isMeteringEnabled = false
            if !rec.prepareToRecord() {
                throw PerformanceCaptureError.audioSessionFailed("prepareToRecord zwróciło false")
            }
            if !rec.record() {
                throw PerformanceCaptureError.audioSessionFailed("record() zwróciło false")
            }
            self.recorder = rec
            self.outputURL = fileURL
            self.state = .recording(url: fileURL)
            log.info("Rozpoczęto nagrywanie audio → \(fileURL.lastPathComponent, privacy: .public)")
            return fileURL
        } catch let err as PerformanceCaptureError {
            throw err
        } catch {
            throw PerformanceCaptureError.audioSessionFailed("\(error)")
        }
    }

    /// Zatrzymuje nagrywanie i zwraca URL gotowego pliku WAV.
    @discardableResult
    public func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        let url = outputURL
        state = .idle
        log.info("Zatrzymano nagrywanie audio")
        return url
    }

    /// Zatrzymuje nagrywanie i usuwa plik wynikowy.
    public func discard() {
        recorder?.stop()
        recorder = nil
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        outputURL = nil
        state = .idle
        log.info("Odrzucono nagranie audio")
    }

    // MARK: - Prywatne

    /// Konfiguruje `AVAudioSession` — kategoria `.playAndRecord`, sampleRate 16 kHz.
    ///
    /// Rzuca `audioSessionFailed` jeśli iOS odrzuci konfigurację. W takim wypadku
    /// wyżej `AudioResampler` może dokonać konwersji z fallbackowego 48 kHz.
    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .measurement,
                                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try session.setPreferredSampleRate(16_000.0)
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true, options: [])
        } catch {
            log.error("AVAudioSession.setCategory/setActive błąd: \(error.localizedDescription, privacy: .public)")
            throw PerformanceCaptureError.audioSessionFailed("\(error)")
        }
    }
}
