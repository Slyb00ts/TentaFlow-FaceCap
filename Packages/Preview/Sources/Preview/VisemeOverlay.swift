// =============================================================================
// Plik: VisemeOverlay.swift
// Opis: Mapowanie fonem → pozy usta (visemes) + kompozycja z emocją bazową.
// =============================================================================

import Foundation
import simd

/// Standardowy zestaw visemów Preston-Blair – każdy opisuje pozę ust dla fonemu.
public enum Viseme: String, CaseIterable, Sendable {
    case a
    case o
    case i
    case u
    case mbp      // m, b, p
    case fv       // f, v
    case sz       // s, z
    case tdln     // t, d, l, n
    case shch     // sh, ch
    case silence

    /// Wagi AU dla visemu (tylko usta/szczęka, reszta = 0).
    public var auWeights: SIMD64<Float> {
        var w = SIMD64<Float>(repeating: 0)
        switch self {
        case .a:
            w[AUIndex.jawOpen.rawValue] = 0.6
        case .o:
            w[AUIndex.jawOpen.rawValue] = 0.3
            w[AUIndex.mouthFunnel.rawValue] = 0.7
            w[AUIndex.mouthPucker.rawValue] = 0.4
        case .i:
            w[AUIndex.mouthStretchL.rawValue] = 0.5
            w[AUIndex.mouthStretchR.rawValue] = 0.5
            w[AUIndex.jawOpen.rawValue] = 0.1
        case .u:
            w[AUIndex.mouthPucker.rawValue] = 0.8
            w[AUIndex.mouthFunnel.rawValue] = 0.4
        case .mbp:
            w[AUIndex.mouthClose.rawValue] = 0.9
        case .fv:
            w[AUIndex.mouthUpperUpL.rawValue] = 0.3
            w[AUIndex.mouthUpperUpR.rawValue] = 0.3
            w[AUIndex.jawOpen.rawValue] = 0.2
        case .sz:
            w[AUIndex.mouthStretchL.rawValue] = 0.3
            w[AUIndex.mouthStretchR.rawValue] = 0.3
            w[AUIndex.jawOpen.rawValue] = 0.1
        case .tdln:
            w[AUIndex.jawOpen.rawValue] = 0.2
            w[AUIndex.tongueOut.rawValue] = 0.1
        case .shch:
            w[AUIndex.mouthFunnel.rawValue] = 0.3
            w[AUIndex.mouthPucker.rawValue] = 0.3
        case .silence:
            break
        }
        return w
    }

    /// Mapuje pojedynczy znak fonemu na viseme (case-insensitive).
    public static func from(phoneme char: Character) -> Viseme {
        switch Character(char.lowercased()) {
        case "a", "ą":
            return .a
        case "o", "ó":
            return .o
        case "e", "ę":
            return .i
        case "i", "y":
            return .i
        case "u":
            return .u
        case "m", "b", "p":
            return .mbp
        case "f", "w", "v":
            return .fv
        case "s", "z":
            return .sz
        case "t", "d", "l", "n":
            return .tdln
        default:
            return .silence
        }
    }
}

/// Maska AU, które odpowiadają za usta/szczękę – visemy mają prawo je nadpisywać.
private let mouthMask: SIMD64<Float> = {
    var m = SIMD64<Float>(repeating: 0)
    let mouthAUs: [AUIndex] = [
        .jawForward, .jawLeft, .jawOpen, .jawRight,
        .mouthClose, .mouthDimpleL, .mouthDimpleR, .mouthFrownL, .mouthFrownR,
        .mouthFunnel, .mouthLeft, .mouthLowerDownL, .mouthLowerDownR,
        .mouthPressL, .mouthPressR, .mouthPucker, .mouthRight,
        .mouthRollLower, .mouthRollUpper, .mouthShrugLower, .mouthShrugUpper,
        .mouthSmileL, .mouthSmileR, .mouthStretchL, .mouthStretchR,
        .mouthUpperUpL, .mouthUpperUpR, .tongueOut
    ]
    for au in mouthAUs { m[au.rawValue] = 1.0 }
    return m
}()

/// Kompozytor visemów – łączy emocję bazową z aktualnym viseme z crossfade'em.
public final class VisemeOverlay {

    /// Bieżący viseme (target).
    public private(set) var currentViseme: Viseme = .silence

    /// Viseme z którego aktualnie zjeżdżamy (dla crossfade na granicy fonemu).
    private var previousViseme: Viseme = .silence

    /// Postęp crossfade'u w [0,1]; 1 = w pełni currentViseme, 0 = previous.
    private var crossfadeT: Float = 1.0

    /// Prędkość crossfade'u w 1/s – typowo 15.0 (≈ 67 ms).
    public var crossfadeSpeed: Float = 15.0

    public init() {}

    /// Przełącza viseme rozpoczynając crossfade z poprzedniego.
    public func setViseme(_ v: Viseme) {
        if v != currentViseme {
            previousViseme = currentViseme
            currentViseme = v
            crossfadeT = 0.0
        }
    }

    /// Uaktualnia crossfade per klatkę.
    public func tick(dt: Float) {
        crossfadeT = min(1.0, crossfadeT + crossfadeSpeed * dt)
    }

    /// Zwraca skomponowany wektor AU = emocja ∪ viseme (max na masce ust).
    ///
    /// Poza maską ust wynik == `emotion`. Na masce ust bierzemy
    /// `max(emotion, viseme)` żeby mowa nie gasiła uśmiechu, tylko go dominowała.
    public func compose(emotion: SIMD64<Float>) -> SIMD64<Float> {
        let prev = previousViseme.auWeights
        let curr = currentViseme.auWeights
        // Mieszanie previous/current w okresie crossfade'u.
        let blended = prev + (curr - prev) * SIMD64<Float>(repeating: crossfadeT)
        // Maksimum z emocją tylko na AU ust.
        let maxed = simd_max(emotion, blended)
        let invMask = SIMD64<Float>(repeating: 1.0) - mouthMask
        return emotion * invMask + maxed * mouthMask
    }
}
