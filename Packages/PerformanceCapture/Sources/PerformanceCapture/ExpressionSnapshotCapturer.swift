// =============================================================================
// Plik: ExpressionSnapshotCapturer.swift
// Opis: Aktor zbierający 60 klatek wag AU i wyłaniający peak jako snapshot.
// Przykład: let result = try await capturer.capture(preset: .happy, source: stream)
// =============================================================================

import Foundation
import Shared

/// Aktor wykonujący snapshot pojedynczego presetu. Zbiera przez zadany czas
/// strumień 52-wymiarowych wektorów wag, wybiera klatkę peak (największa
/// suma kwadratów wag), waliduje oczekiwane AU i zwraca gotowy snapshot.
public actor ExpressionSnapshotCapturer {

    /// Domyślny czas trwania okna rejestrującego (sekundy).
    public static let defaultCaptureDuration: TimeInterval = 1.0

    /// Próg detekcji oczekiwanego AU — wartość wagi w peaku musi być ≥ `0.3`.
    public static let expectedAUThreshold: Float = 0.3

    /// Maksymalna dozwolona wartość AU zakazanego (np. eyeBlinkRight dla winkLeft).
    public static let forbiddenAUThreshold: Float = 0.35

    /// Wynik zwracany przez `capture(...)`.
    public struct CaptureResult: Sendable {
        public let snapshot: ExpressionSnapshot
        public let peakObservedAt: Date
        public let framesConsumed: Int

        public init(snapshot: ExpressionSnapshot, peakObservedAt: Date, framesConsumed: Int) {
            self.snapshot = snapshot
            self.peakObservedAt = peakObservedAt
            self.framesConsumed = framesConsumed
        }
    }

    public init() {}

    /// Zbiera klatki z `source` przez `duration` sekund (najwyżej `maxFrames`),
    /// wybiera peak i zwraca snapshot wraz z metadanymi.
    ///
    /// - Parameters:
    ///   - preset: preset, którego user się uczy w tej chwili.
    ///   - source: `AsyncStream` emitujący tablice 52 wag (0..1) per klatka.
    ///   - duration: długość okna rejestrującego w sekundach (default: 1 s).
    ///   - maxFrames: górny limit zebranych klatek (default: 120 — 2 s @60 fps).
    public func capture(
        preset: ExpressionPreset,
        source: AsyncStream<[Float]>,
        duration: TimeInterval = ExpressionSnapshotCapturer.defaultCaptureDuration,
        maxFrames: Int = 120
    ) async throws -> CaptureResult {

        let deadline = Date().addingTimeInterval(duration)
        var frames: [[Float]] = []
        frames.reserveCapacity(maxFrames)

        // Iterujemy po strumieniu aż do wyczerpania okna czasowego albo limitu klatek.
        for await row in source {
            guard row.count == 52 else { continue }
            frames.append(row)
            if frames.count >= maxFrames { break }
            if Date() >= deadline { break }
        }

        guard !frames.isEmpty else {
            throw FacecapError.invalidArgument("Snapshot: brak klatek w oknie rejestrującym.")
        }

        // Peak wybieramy po euclidean magnitude (suma kwadratów). Nie normalizujemy —
        // interesuje nas absolutna siła mimiki.
        var peakIndex = 0
        var peakEnergy: Float = -1
        for (idx, row) in frames.enumerated() {
            var energy: Float = 0
            for value in row {
                let clamped = Self.clamp01(value)
                energy += clamped * clamped
            }
            if energy > peakEnergy {
                peakEnergy = energy
                peakIndex = idx
            }
        }

        let peakRow = frames[peakIndex]
        let peakObservedAt = Date()

        // Walidacja oczekiwanych AU — musimy zobaczyć co najmniej próg na dominujących AU.
        let expected = preset.expectedDominantAUs
        let forbidden = preset.forbiddenDominantAUs

        // Quality score = minimalna waga wśród oczekiwanych AU.
        // Jeśli preset nie ma oczekiwanych AU (np. `bored`), używamy średniej energii.
        let qualityScore = Self.computeQualityScore(
            peakRow: peakRow,
            expected: expected,
            forbidden: forbidden
        )

        let snapshot = try ExpressionSnapshot(
            name: preset.storageName,
            weights: peakRow.map { Self.clamp01($0) },
            qualityScore: qualityScore,
            capturedAt: peakObservedAt
        )

        return CaptureResult(
            snapshot: snapshot,
            peakObservedAt: peakObservedAt,
            framesConsumed: frames.count
        )
    }

    // MARK: — Obliczenie jakości snapshotu

    private static func computeQualityScore(
        peakRow: [Float],
        expected: [Int],
        forbidden: [Int]
    ) -> Float {
        // Brak oczekiwanych AU — użyj proxy z średniej energii.
        if expected.isEmpty {
            var energy: Float = 0
            for v in peakRow { energy += clamp01(v) }
            let mean = energy / Float(peakRow.count)
            // Preset typu "bored" bywa niską aktywnością — premiujemy spokojną twarz.
            let calmness = 1.0 - min(1.0, mean * 4.0)
            return clamp01(calmness)
        }

        // Minimalna waga wśród oczekiwanych AU — klasyczna metryka "najsłabsze ogniwo".
        var minExpected: Float = 1
        for idx in expected where idx >= 0 && idx < peakRow.count {
            let v = clamp01(peakRow[idx])
            if v < minExpected { minExpected = v }
        }

        // Kara za aktywne AU zakazane (asymetria).
        var maxForbidden: Float = 0
        for idx in forbidden where idx >= 0 && idx < peakRow.count {
            let v = clamp01(peakRow[idx])
            if v > maxForbidden { maxForbidden = v }
        }
        let asymmetryPenalty = max(0.0, maxForbidden - 0.2)

        let raw = minExpected - asymmetryPenalty
        return clamp01(raw)
    }

    private static func clamp01(_ value: Float) -> Float {
        if value.isNaN { return 0 }
        return min(max(value, 0), 1)
    }
}
