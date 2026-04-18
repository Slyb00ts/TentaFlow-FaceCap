// =============================================================================
// Plik: PerformanceRecorder.swift
// Opis: Actor zbierający klatki AU (52 blendshapes @60Hz) do preallocated bufora.
// =============================================================================

import Foundation
import Combine
import simd
import os

/// Źródło klatek AU – protokół niezależny od konkretnej implementacji ARKit.
///
/// Pakiet `FaceCalibration` eksponuje publisher, którego `Output` jest
/// kompatybilny z tym protokołem przez extension — tutaj używamy wąskiego
/// interfejsu żeby `PerformanceRecorder` dało się testować jednostkowo bez ARKit.
public protocol AUFrameSource: AnyObject, Sendable {
    /// Publisher wystawia pary (timestamp_s, weights) dla każdej klatki sesji.
    var framePublisher: AnyPublisher<(Double, SIMD64<Float>), Never> { get }
}

/// Stan wewnętrzny rekordera — aktywny / zatrzymany.
public enum RecorderState: Equatable, Sendable {
    case idle
    case recording(startedAt: Date)
}

/// Actor zbierający klatki AU do preallocated ring bufora.
///
/// Pojemność: 60 fps * 60 s = 3600 klatek; alokacja jednorazowa w `init`.
/// Brak alokacji per-frame — narzut nagrywania to tylko zapis wektora do tablicy.
public actor PerformanceRecorder {

    /// Maksymalna pojemność bufora (klatki).
    public let capacity: Int

    /// Obecny stan rekordera.
    public private(set) var state: RecorderState = .idle

    /// Preallocated bufor wag AU — `count == capacity`, aktywnych `frameCount`.
    private var buffer: [SIMD64<Float>]

    /// Preallocated bufor znaczników czasu.
    private var timestamps: [Double]

    /// Liczba zapisanych klatek w bieżącym nagraniu.
    private var frameCount: Int = 0

    /// Źródło klatek (np. `FaceTrackingSession`).
    private weak var source: (AnyObject & AUFrameSource)?

    /// Subskrypcja do publishera (przechowywana tu, nie w Combine store).
    private var subscription: AnyCancellable?

    /// Logger diagnostyczny.
    private let log: Logger = Logger(subsystem: "pl.tentaflow.facecap",
                                     category: "performance-recorder")

    /// Inicjalizuje rekorder z podaną pojemnością w klatkach (default 3600 = 60 s @60fps).
    public init(capacity: Int = 3600) {
        self.capacity = capacity
        self.buffer = Array(repeating: .zero, count: capacity)
        self.timestamps = Array(repeating: 0.0, count: capacity)
    }

    /// Łączy rekorder ze źródłem klatek AU. Wywołaj przed `start()`.
    public func attach(source: AnyObject & AUFrameSource) {
        self.source = source
    }

    /// Rozpoczyna nagrywanie. Jeśli już trwa — no-op z ostrzeżeniem w logu.
    public func start() async {
        if case .recording = state {
            log.warning("start() wywołane podczas trwającego nagrania – ignoruję")
            return
        }
        frameCount = 0
        state = .recording(startedAt: Date())
        subscribe()
        log.info("Nagrywanie rozpoczęte, capacity=\(self.capacity, privacy: .public)")
    }

    /// Zatrzymuje nagrywanie i zwraca snapshot zebranych klatek jako `[RecordedFrame]`.
    public func stop() async -> [RecordedFrame] {
        subscription?.cancel()
        subscription = nil
        let count = frameCount
        var result: [RecordedFrame] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            result.append(RecordedFrame(timestamp: timestamps[i], weights: buffer[i]))
        }
        state = .idle
        log.info("Nagrywanie zakończone, klatek=\(count, privacy: .public)")
        return result
    }

    /// Przerywa nagrywanie bez zwracania danych (np. anulowanie).
    public func discard() async {
        subscription?.cancel()
        subscription = nil
        frameCount = 0
        state = .idle
        log.info("Nagranie odrzucone")
    }

    /// Zwraca bieżącą długość nagrania w sekundach (0 jeśli brak klatek).
    public func currentDuration() -> Double {
        guard frameCount > 0 else { return 0.0 }
        return timestamps[frameCount - 1] - timestamps[0]
    }

    /// Zwraca liczbę zapisanych klatek.
    public func framesRecorded() -> Int {
        frameCount
    }

    // MARK: - Prywatne

    /// Podpina subskrypcję do publishera źródła. Sink trafia na kolejkę actora.
    private func subscribe() {
        guard let source else {
            log.error("subscribe() – brak źródła klatek")
            return
        }
        subscription = source.framePublisher
            .sink { [weak self] (ts, weights) in
                guard let self else { return }
                Task { await self.ingest(timestamp: ts, weights: weights) }
            }
    }

    /// Zapisuje pojedynczą klatkę. W trybie `idle` ignoruje.
    private func ingest(timestamp: Double, weights: SIMD64<Float>) {
        guard case .recording = state else { return }
        if frameCount >= capacity {
            log.error("Buffer overflow – zatrzymuję nagrywanie")
            subscription?.cancel()
            subscription = nil
            state = .idle
            return
        }
        buffer[frameCount] = weights
        timestamps[frameCount] = timestamp
        frameCount += 1
    }
}
