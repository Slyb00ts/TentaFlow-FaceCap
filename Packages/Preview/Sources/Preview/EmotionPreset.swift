// =============================================================================
// Plik: EmotionPreset.swift
// Opis: Predefiniowane presety emocji (FACS) – mapują się na 52-elementowy wektor AU.
// =============================================================================

import Foundation
import simd

/// Indeksy 52 ARKit blendshape AU zgodne z kolejnością `ARFaceAnchor.BlendShapeLocation`.
///
/// Enum case’y mają wartości surowe odpowiadające pozycji w wektorze — dzięki temu
/// `weights[AUIndex.mouthSmileL.rawValue] = 0.8` jest czytelne i niezawodne.
public enum AUIndex: Int, CaseIterable, Sendable {
    case browDownL = 0
    case browDownR = 1
    case browInnerUp = 2
    case browOuterUpL = 3
    case browOuterUpR = 4
    case cheekPuff = 5
    case cheekSquintL = 6
    case cheekSquintR = 7
    case eyeBlinkL = 8
    case eyeBlinkR = 9
    case eyeLookDownL = 10
    case eyeLookDownR = 11
    case eyeLookInL = 12
    case eyeLookInR = 13
    case eyeLookOutL = 14
    case eyeLookOutR = 15
    case eyeLookUpL = 16
    case eyeLookUpR = 17
    case eyeSquintL = 18
    case eyeSquintR = 19
    case eyeWideL = 20
    case eyeWideR = 21
    case jawForward = 22
    case jawLeft = 23
    case jawOpen = 24
    case jawRight = 25
    case mouthClose = 26
    case mouthDimpleL = 27
    case mouthDimpleR = 28
    case mouthFrownL = 29
    case mouthFrownR = 30
    case mouthFunnel = 31
    case mouthLeft = 32
    case mouthLowerDownL = 33
    case mouthLowerDownR = 34
    case mouthPressL = 35
    case mouthPressR = 36
    case mouthPucker = 37
    case mouthRight = 38
    case mouthRollLower = 39
    case mouthRollUpper = 40
    case mouthShrugLower = 41
    case mouthShrugUpper = 42
    case mouthSmileL = 43
    case mouthSmileR = 44
    case mouthStretchL = 45
    case mouthStretchR = 46
    case mouthUpperUpL = 47
    case mouthUpperUpR = 48
    case noseSneerL = 49
    case noseSneerR = 50
    case tongueOut = 51
}

/// Presety emocji wyrażone jako wagi AU (SIMD64 z 52 aktywnymi lane).
public enum EmotionPreset: String, CaseIterable, Identifiable, Sendable {
    case happy
    case sad
    case angry
    case surprised
    case disgusted
    case fearful
    case thinking
    case sleepy
    case neutral

    public var id: String { rawValue }

    /// Lokalizowana etykieta w polskim UI.
    public var displayName: String {
        switch self {
        case .happy: return "Radość"
        case .sad: return "Smutek"
        case .angry: return "Złość"
        case .surprised: return "Zaskoczenie"
        case .disgusted: return "Obrzydzenie"
        case .fearful: return "Strach"
        case .thinking: return "Zamyślenie"
        case .sleepy: return "Senność"
        case .neutral: return "Neutralny"
        }
    }

    /// Zwraca wektor wag AU odpowiadający presetowi.
    ///
    /// Wartości oparte na standardowych kombinacjach FACS — nie placeholder.
    public var auWeights: SIMD64<Float> {
        var w = SIMD64<Float>(repeating: 0)
        switch self {
        case .happy:
            w[AUIndex.mouthSmileL.rawValue] = 0.8
            w[AUIndex.mouthSmileR.rawValue] = 0.8
            w[AUIndex.cheekSquintL.rawValue] = 0.4
            w[AUIndex.cheekSquintR.rawValue] = 0.4
            w[AUIndex.eyeSquintL.rawValue] = 0.2
            w[AUIndex.eyeSquintR.rawValue] = 0.2
        case .sad:
            w[AUIndex.mouthFrownL.rawValue] = 0.6
            w[AUIndex.mouthFrownR.rawValue] = 0.6
            w[AUIndex.browInnerUp.rawValue] = 0.5
            w[AUIndex.eyeLookDownL.rawValue] = 0.3
            w[AUIndex.eyeLookDownR.rawValue] = 0.3
        case .angry:
            w[AUIndex.browDownL.rawValue] = 0.8
            w[AUIndex.browDownR.rawValue] = 0.8
            w[AUIndex.mouthPressL.rawValue] = 0.5
            w[AUIndex.mouthPressR.rawValue] = 0.5
            w[AUIndex.noseSneerL.rawValue] = 0.3
            w[AUIndex.noseSneerR.rawValue] = 0.3
        case .surprised:
            w[AUIndex.browInnerUp.rawValue] = 0.9
            w[AUIndex.browOuterUpL.rawValue] = 0.7
            w[AUIndex.browOuterUpR.rawValue] = 0.7
            w[AUIndex.eyeWideL.rawValue] = 0.8
            w[AUIndex.eyeWideR.rawValue] = 0.8
            w[AUIndex.jawOpen.rawValue] = 0.4
        case .disgusted:
            w[AUIndex.noseSneerL.rawValue] = 0.8
            w[AUIndex.noseSneerR.rawValue] = 0.8
            w[AUIndex.mouthUpperUpL.rawValue] = 0.6
            w[AUIndex.mouthUpperUpR.rawValue] = 0.6
            w[AUIndex.browDownL.rawValue] = 0.4
            w[AUIndex.browDownR.rawValue] = 0.4
        case .fearful:
            w[AUIndex.browInnerUp.rawValue] = 0.7
            w[AUIndex.browOuterUpL.rawValue] = 0.3
            w[AUIndex.browOuterUpR.rawValue] = 0.3
            w[AUIndex.eyeWideL.rawValue] = 0.9
            w[AUIndex.eyeWideR.rawValue] = 0.9
            w[AUIndex.mouthStretchL.rawValue] = 0.4
            w[AUIndex.mouthStretchR.rawValue] = 0.4
        case .thinking:
            w[AUIndex.browDownL.rawValue] = 0.3
            w[AUIndex.browDownR.rawValue] = 0.3
            w[AUIndex.eyeLookUpL.rawValue] = 0.4
            w[AUIndex.eyeLookUpR.rawValue] = 0.4
            w[AUIndex.mouthLeft.rawValue] = 0.2
        case .sleepy:
            w[AUIndex.eyeBlinkL.rawValue] = 0.6
            w[AUIndex.eyeBlinkR.rawValue] = 0.6
            w[AUIndex.browDownL.rawValue] = 0.2
            w[AUIndex.browDownR.rawValue] = 0.2
            w[AUIndex.mouthClose.rawValue] = 0.3
        case .neutral:
            break
        }
        return w
    }
}
