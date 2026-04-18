// =============================================================================
// Plik: IdleAnimator.swift
// Opis: Idle animations – mrugnięcia, oddech, sakady, mikroekspresje (Poisson + sin).
// =============================================================================

import Foundation
import simd

/// Procedurowy generator „życia" avatara w trybie idle.
///
/// Wypluwa dodatkowy wektor AU do zmieszania z emocją/visemem. Wewnętrznie:
///  - **blink**: Poisson (średnio 4 s), cascade 3 klatki close + 3 klatki open,
///  - **breathing**: `sin(t * 2π / 5 s) * 0.05` na `jawOpen`,
///  - **saccades**: losowy target eyeLook* co 1.5–4 s, hold 0.8 s, potem 0,
///  - **micro-expressions**: co 8–15 s losowy AU flash o amplitudzie 0.05 przez 200 ms.
public final class IdleAnimator {

    // Blink state machine
    private enum BlinkPhase {
        case idle
        case closing(framesLeft: Int)
        case holding
        case opening(framesLeft: Int)
    }
    private var blinkPhase: BlinkPhase = .idle
    private var nextBlinkAt: Double = 0.0
    private var blinkStrength: Float = 0.0

    // Saccade state
    private var saccadeTarget: (Float, Float) = (0, 0)  // (dx, dy) in -1..1
    private var nextSaccadeAt: Double = 0.0
    private var saccadeReleaseAt: Double = 0.0

    // Micro-expression state
    private var microAUIndex: Int = -1
    private var microEndAt: Double = 0.0
    private var nextMicroAt: Double = 0.0

    // Clock
    private var elapsed: Double = 0.0

    /// Generator losowy – deterministyczny dla testów (seedable).
    private var rng: SystemRandomNumberGenerator

    public init() {
        self.rng = SystemRandomNumberGenerator()
        self.nextBlinkAt = 2.0 + Double.random(in: 0...2.0, using: &rng)
        self.nextSaccadeAt = 1.5 + Double.random(in: 0...2.5, using: &rng)
        self.nextMicroAt = 8.0 + Double.random(in: 0...7.0, using: &rng)
    }

    /// Krok generatora. Zwraca wektor AU dodawany do emocji/visemy.
    public func tick(dt: Float) -> SIMD64<Float> {
        elapsed += Double(dt)
        var out = SIMD64<Float>(repeating: 0)
        applyBlink(&out, dt: dt)
        applyBreathing(&out)
        applySaccades(&out)
        applyMicroExpression(&out)
        return out
    }

    // MARK: - Blink

    private func applyBlink(_ out: inout SIMD64<Float>, dt: Float) {
        switch blinkPhase {
        case .idle:
            if elapsed >= nextBlinkAt {
                blinkPhase = .closing(framesLeft: 3)
                blinkStrength = 0.0
            }
        case .closing(let left):
            blinkStrength += 1.0 / 3.0
            out[AUIndex.eyeBlinkL.rawValue] = min(1.0, blinkStrength)
            out[AUIndex.eyeBlinkR.rawValue] = min(1.0, blinkStrength)
            if left <= 1 {
                blinkPhase = .holding
            } else {
                blinkPhase = .closing(framesLeft: left - 1)
            }
        case .holding:
            out[AUIndex.eyeBlinkL.rawValue] = 1.0
            out[AUIndex.eyeBlinkR.rawValue] = 1.0
            blinkPhase = .opening(framesLeft: 3)
        case .opening(let left):
            blinkStrength -= 1.0 / 3.0
            let v = max(0.0, blinkStrength)
            out[AUIndex.eyeBlinkL.rawValue] = v
            out[AUIndex.eyeBlinkR.rawValue] = v
            if left <= 1 {
                blinkPhase = .idle
                // Poisson: interval = -ln(U) / rate; rate = 1 / 4s.
                let u = Float.random(in: 0.001...1.0, using: &rng)
                let interval = Double(-log(u) * 4.0)
                nextBlinkAt = elapsed + max(0.8, min(12.0, interval))
            } else {
                blinkPhase = .opening(framesLeft: left - 1)
            }
        }
        _ = dt
    }

    // MARK: - Breathing

    private func applyBreathing(_ out: inout SIMD64<Float>) {
        let phase = sin(elapsed * 2.0 * .pi / 5.0)
        let v = Float(phase) * 0.05
        // Dodajemy, nie nadpisujemy – mieszanie z istniejącymi wartościami.
        out[AUIndex.jawOpen.rawValue] += max(0.0, v)
    }

    // MARK: - Saccades

    private func applySaccades(_ out: inout SIMD64<Float>) {
        if elapsed >= nextSaccadeAt {
            let dx = Float.random(in: -0.6...0.6, using: &rng)
            let dy = Float.random(in: -0.4...0.4, using: &rng)
            saccadeTarget = (dx, dy)
            saccadeReleaseAt = elapsed + 0.8
            nextSaccadeAt = elapsed + Double.random(in: 1.5...4.0, using: &rng)
        }
        if elapsed < saccadeReleaseAt {
            let (dx, dy) = saccadeTarget
            if dx > 0 {
                out[AUIndex.eyeLookOutL.rawValue] = dx
                out[AUIndex.eyeLookInR.rawValue] = dx
            } else if dx < 0 {
                out[AUIndex.eyeLookInL.rawValue] = -dx
                out[AUIndex.eyeLookOutR.rawValue] = -dx
            }
            if dy > 0 {
                out[AUIndex.eyeLookUpL.rawValue] = dy
                out[AUIndex.eyeLookUpR.rawValue] = dy
            } else if dy < 0 {
                out[AUIndex.eyeLookDownL.rawValue] = -dy
                out[AUIndex.eyeLookDownR.rawValue] = -dy
            }
        }
    }

    // MARK: - Micro-expressions

    private func applyMicroExpression(_ out: inout SIMD64<Float>) {
        if microAUIndex == -1, elapsed >= nextMicroAt {
            microAUIndex = Int.random(in: 0..<52, using: &rng)
            microEndAt = elapsed + 0.2
            nextMicroAt = elapsed + Double.random(in: 8.0...15.0, using: &rng)
        }
        if microAUIndex != -1 {
            if elapsed < microEndAt {
                out[microAUIndex] += 0.05
            } else {
                microAUIndex = -1
            }
        }
    }
}
