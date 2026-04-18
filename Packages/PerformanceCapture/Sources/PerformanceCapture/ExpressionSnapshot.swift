// =============================================================================
// Plik: ExpressionSnapshot.swift
// Opis: Pojedynczy snapshot wyrazu twarzy — 52 wagi AU zarejestrowane w peaku.
// Przykład: try ExpressionSnapshot(name: "happy", weights: ws, qualityScore: 0.8)
// =============================================================================

import Foundation
import Shared

/// Pojedynczy snapshot wyrazu twarzy — wagi 52 AU w jednym momencie (peak).
///
/// Wartości `weights` są przycinane do zakresu `[0, 1]` w inicjalizatorze —
/// dzięki temu serializacja i porównania są deterministyczne.
public struct ExpressionSnapshot: Sendable, Codable, Equatable {

    /// Identyfikator presetu / nazwa własna. Max 24 bajty ASCII (zgodnie z polem `name` w pliku `.face`).
    public let name: String

    /// Znacznik czasu — moment przechwytu peaku (UTC).
    public let capturedAt: Date

    /// Dokładnie 52 wartości w zakresie `[0, 1]`, ułożone w kolejności `ArkitAU.rawValue`.
    public let weights: [Float]

    /// Pewność kalibracji — im wyższa, tym lepiej user trafił w oczekiwane AU (zakres `[0, 1]`).
    public let qualityScore: Float

    public init(
        name: String,
        weights: [Float],
        qualityScore: Float,
        capturedAt: Date = Date()
    ) throws {
        guard weights.count == 52 else {
            throw FacecapError.invalidArgument("Snapshot musi mieć 52 wagi (otrzymano \(weights.count)).")
        }
        let nameBytes = name.utf8.count
        guard nameBytes <= 24 else {
            throw FacecapError.invalidArgument("Nazwa snapshotu > 24 B (otrzymano \(nameBytes)).")
        }
        guard !name.isEmpty else {
            throw FacecapError.invalidArgument("Nazwa snapshotu nie może być pusta.")
        }
        self.name = name
        self.capturedAt = capturedAt
        self.weights = weights.map { Self.clamp01($0) }
        self.qualityScore = Self.clamp01(qualityScore)
    }

    /// Pomocnicze — przycięcie do zakresu `[0, 1]` bez wymuszania `NaN`.
    private static func clamp01(_ value: Float) -> Float {
        if value.isNaN { return 0 }
        return min(max(value, 0), 1)
    }
}
