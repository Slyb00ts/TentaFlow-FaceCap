// =============================================================================
// Plik: PerformanceClip.swift
// Opis: Struktura klipu performance: metadane + timeline 52 AU + opcjonalne audio.
// =============================================================================

import Foundation
import simd

/// Pojedyncza klatka zarejestrowana z sesji ARKit — timestamp i 52 AU weights.
///
/// Używamy `SIMD64<Float>` jako szerokiego wektora (gorsze cache'owanie niż
/// `[Float]`, ale ARKit dostarcza dokładnie 52 wartości, a 64-elementowy SIMD
/// mieści to w dwóch rejestrach AVX — reszta (52..63) pozostaje zerowana).
public struct RecordedFrame: Hashable, Sendable {

    /// Monotoniczny znacznik czasu (sekundy od startu nagrania).
    public let timestamp: Double

    /// Wektor wag AU: indeksy 0..51 zawierają dane, 52..63 są zerowe.
    public let weights: SIMD64<Float>

    public init(timestamp: Double, weights: SIMD64<Float>) {
        self.timestamp = timestamp
        self.weights = weights
    }
}

/// Klip performance zapisany na dysku — metadane + pełny timeline AU + audio.
public struct PerformanceClip: Identifiable, Hashable, Sendable {

    /// Unikalny identyfikator klipu.
    public let id: UUID

    /// Nazwa nadana przez użytkownika (np. "Ziewanie", "Uśmiech").
    public var name: String

    /// Liczba klatek na sekundę (stała dla całego klipu, typowo 60).
    public let fps: UInt8

    /// Moment rozpoczęcia nagrania (lokalny czas urządzenia).
    public let startedAt: Date

    /// Długość klipu w sekundach — duration * fps ≈ weights.count.
    public let durationSec: Double

    /// Tablica wektorów AU — po jednym wpisie na klatkę.
    public let weights: [SIMD64<Float>]

    /// URL do pliku audio (PCM s16le 16 kHz mono) lub `nil` jeśli bez audio.
    public var audioURL: URL?

    public init(id: UUID = UUID(),
                name: String,
                fps: UInt8 = 60,
                startedAt: Date,
                durationSec: Double,
                weights: [SIMD64<Float>],
                audioURL: URL? = nil) {
        self.id = id
        self.name = name
        self.fps = fps
        self.startedAt = startedAt
        self.durationSec = durationSec
        self.weights = weights
        self.audioURL = audioURL
    }

    /// Zwraca skwantowany timeline jako surowe bajty row-major: `[u8; 52] * N`.
    ///
    /// Używane przy eksporcie do kontenera `.face v3`, w którym każdy AU zajmuje
    /// jeden bajt (0..255). Pętla po klatkach, kwantyzacja przez `PerformanceQuantizer`.
    public var weightsAsData: Data {
        let frameStride = 52
        var data = Data(count: weights.count * frameStride)
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            let dst = base.assumingMemoryBound(to: UInt8.self)
            for (i, vec) in weights.enumerated() {
                let offset = i * frameStride
                PerformanceQuantizer.quantize(vec, into: dst.advanced(by: offset))
            }
        }
        return data
    }

    /// Pomocnicza dekompozycja — zwraca klatkę dla danego czasu (nearest-neighbor).
    public func frame(at time: Double) -> SIMD64<Float> {
        guard !weights.isEmpty else { return .zero }
        let idx = Int((time * Double(fps)).rounded())
        let clamped = min(max(0, idx), weights.count - 1)
        return weights[clamped]
    }
}
