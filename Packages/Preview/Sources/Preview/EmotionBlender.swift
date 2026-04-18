// =============================================================================
// Plik: EmotionBlender.swift
// Opis: Interpolacja liniowa wag AU między bieżącym stanem a docelowym presetem.
// =============================================================================

import Foundation
import Combine
import simd

/// Mieszalnik emocji – smooth-luj current → target AU weights z zadaną prędkością.
///
/// Używany w podglądzie live: gdy użytkownik przełącza preset, animujemy dojście
/// do nowych wartości przez kilka klatek zamiast skokowej zmiany.
public final class EmotionBlender: ObservableObject {

    /// Aktualny stan wag (udostępniany przez `@Published`).
    @Published public private(set) var current: SIMD64<Float> = .zero

    /// Docelowy stan – wypadkowa presetu + intensywności.
    public private(set) var target: SIMD64<Float> = .zero

    /// Prędkość mieszania [1/s]. `3.0` oznacza ~1/3 s dojścia do targetu.
    public var blendSpeed: Float = 3.0

    public init(initial: SIMD64<Float> = .zero) {
        self.current = initial
        self.target = initial
    }

    /// Ustawia nowy cel blendu z presetu i intensywności w [0,1].
    public func setEmotion(_ preset: EmotionPreset, intensity: Float = 1.0) {
        let i = max(0.0, min(1.0, intensity))
        target = preset.auWeights * SIMD64<Float>(repeating: i)
    }

    /// Ustawia cel jako surowy wektor AU (np. z live ARKit lub klipu).
    public func setTarget(_ weights: SIMD64<Float>) {
        target = weights
    }

    /// Krok mieszania. Wywoływać z CADisplayLink (dt w sekundach).
    public func tick(dt: Float) {
        let k = min(max(blendSpeed * dt, 0.0), 1.0)
        let diff = target - current
        current = current + diff * SIMD64<Float>(repeating: k)
    }

    /// Natychmiastowy skok do targetu (bez animacji) – np. przy seek w klipie.
    public func snap() {
        current = target
    }

    /// Reset do zer (neutralna twarz).
    public func reset() {
        target = .zero
        current = .zero
    }
}
