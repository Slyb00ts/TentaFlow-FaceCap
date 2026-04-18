// =============================================================================
// Plik: ExpressionPreset.swift
// Opis: 20 predefiniowanych wyrazów twarzy w 4 kategoriach (emocje, stany,
//       asymetryczne, sceniczne) wraz z instrukcjami i mapą oczekiwanych AU.
// Przykład: ExpressionPreset.winkLeft.expectedDominantAUs // [0]
// =============================================================================

import Foundation
import FaceCalibration

/// Kategorie tematyczne presetów — używane w UI do grupowania w `DisclosureGroup`.
public enum ExpressionCategory: String, CaseIterable, Sendable, Codable {
    case basic       // Emocje podstawowe (6)
    case state       // Stany (4)
    case asymmetric  // Asymetryczne (6) — specjalna prośba usera
    case scenic      // Sceniczne / wokaliczne (4)

    public var titleForUI: String {
        switch self {
        case .basic:      return "Emocje podstawowe"
        case .state:      return "Stany"
        case .asymmetric: return "Asymetryczne"
        case .scenic:     return "Sceniczne"
        }
    }
}

/// 20 predefiniowanych wyrazów twarzy. Każdy preset ma własne instrukcje,
/// oczekiwane dominujące AU oraz poziom trudności.
public enum ExpressionPreset: String, CaseIterable, Sendable, Codable {

    // === Podstawowe emocje (6) ===
    case happy
    case sad
    case angry
    case surprised
    case disgusted
    case fearful

    // === Stany (4) ===
    case thinking
    case sleepy
    case confused
    case bored

    // === Asymetryczne (6) — specjalnie na prośbę usera ===
    case winkLeft
    case winkRight
    case browUpLeft
    case browUpRight
    case halfSmileLeft
    case halfSmileRight

    // === Sceniczne / wokaliczne (4) ===
    case laugh
    case kiss
    case gasp
    case smirk

    /// Nazwa zapisywana w pliku `.face` — max 24 bajty ASCII, snake_case.
    public var storageName: String {
        switch self {
        case .happy:           return "happy"
        case .sad:             return "sad"
        case .angry:           return "angry"
        case .surprised:       return "surprised"
        case .disgusted:       return "disgusted"
        case .fearful:         return "fearful"
        case .thinking:        return "thinking"
        case .sleepy:          return "sleepy"
        case .confused:        return "confused"
        case .bored:           return "bored"
        case .winkLeft:        return "wink_left"
        case .winkRight:       return "wink_right"
        case .browUpLeft:      return "brow_up_left"
        case .browUpRight:     return "brow_up_right"
        case .halfSmileLeft:   return "half_smile_left"
        case .halfSmileRight:  return "half_smile_right"
        case .laugh:           return "laugh"
        case .kiss:            return "kiss"
        case .gasp:            return "gasp"
        case .smirk:           return "smirk"
        }
    }

    /// Polski tytuł prezentowany w UI.
    public var titleForUI: String {
        switch self {
        case .happy:           return "Wesoły"
        case .sad:             return "Smutny"
        case .angry:           return "Zły"
        case .surprised:       return "Zaskoczony"
        case .disgusted:       return "Obrzydzenie"
        case .fearful:         return "Strach"
        case .thinking:        return "Zamyślenie"
        case .sleepy:          return "Senność"
        case .confused:        return "Dezorientacja"
        case .bored:           return "Znudzenie"
        case .winkLeft:        return "Puszczenie lewego oka"
        case .winkRight:       return "Puszczenie prawego oka"
        case .browUpLeft:      return "Unieś lewą brew"
        case .browUpRight:     return "Unieś prawą brew"
        case .halfSmileLeft:   return "Uśmieszek z lewej"
        case .halfSmileRight:  return "Uśmieszek z prawej"
        case .laugh:           return "Szeroki śmiech"
        case .kiss:            return "Całus / usta w dzióbek"
        case .gasp:            return "Zdziwienie (szeroko otwarte usta)"
        case .smirk:           return "Sarkastyczny uśmieszek"
        }
    }

    /// Pełna instrukcja dla usera — pojawia się jako duży prompt w ekranie capture.
    public var instructionForUser: String {
        switch self {
        case .happy:           return "Uśmiechnij się naturalnie, jakbyś zobaczył kogoś bliskiego"
        case .sad:             return "Zrób smutną minę — opadnięte kąciki ust, brwi w górę w środku"
        case .angry:           return "Zmarszcz brwi, zaciśnij usta, napnij szczękę"
        case .surprised:       return "Otwórz szeroko oczy, unieś brwi, rozchyl usta"
        case .disgusted:       return "Zmarszcz nos, podnieś górną wargę jakbyś zobaczył coś obrzydliwego"
        case .fearful:         return "Szeroko otwarte oczy, rozciągnięte usta, uniesione brwi"
        case .thinking:        return "Zamyśl się — lekko zmarszczone brwi, wzrok w górę lub w bok"
        case .sleepy:          return "Wpółzamknięte oczy, rozluźnione usta, głowa lekko opadnięta"
        case .confused:        return "Zrób minę zmieszaną — jedna brew w górę, druga w dół, usta skrzywione"
        case .bored:           return "Rozluźniona twarz, oczy patrzące w dół, wyraz obojętny"
        case .winkLeft:        return "Mrugnij TYLKO LEWYM okiem (prawe zostaw otwarte)"
        case .winkRight:       return "Mrugnij TYLKO PRAWYM okiem (lewe zostaw otwarte)"
        case .browUpLeft:      return "Unieś TYLKO LEWĄ brew, prawą zostaw bez ruchu"
        case .browUpRight:     return "Unieś TYLKO PRAWĄ brew, lewą zostaw bez ruchu"
        case .halfSmileLeft:   return "Uśmiechnij się tylko LEWYM kącikiem ust"
        case .halfSmileRight:  return "Uśmiechnij się tylko PRAWYM kącikiem ust"
        case .laugh:           return "Śmiej się szeroko — otwarte usta, zmarszczone oczy, widoczne zęby"
        case .kiss:            return "Zrób minę do całusa — usta zaciśnięte w mały dzióbek"
        case .gasp:            return "Zaskoczenie — otwórz szeroko buzię jakbyś mówił 'ach!'"
        case .smirk:           return "Sarkastyczny uśmieszek — jeden kącik w górę, oczy lekko mrużone"
        }
    }

    /// Kategoria tematyczna presetu.
    public var category: ExpressionCategory {
        switch self {
        case .happy, .sad, .angry, .surprised, .disgusted, .fearful:
            return .basic
        case .thinking, .sleepy, .confused, .bored:
            return .state
        case .winkLeft, .winkRight, .browUpLeft, .browUpRight, .halfSmileLeft, .halfSmileRight:
            return .asymmetric
        case .laugh, .kiss, .gasp, .smirk:
            return .scenic
        }
    }

    /// Czy preset jest wymagany do ukończenia fazy (reszta jest opcjonalna).
    public var isRequired: Bool {
        switch self {
        case .happy, .sad, .angry, .surprised, .thinking, .laugh:
            return true
        default:
            return false
        }
    }

    /// Oczekiwane dominujące AU dla walidacji jakości snapshotu — indeksy `0..51`
    /// zgodne z `ArkitAU.rawValue`.
    public var expectedDominantAUs: [Int] {
        switch self {
        case .happy:
            return [
                ArkitAU.cheekSquintLeft.rawValue,
                ArkitAU.cheekSquintRight.rawValue,
                ArkitAU.mouthSmileLeft.rawValue,
                ArkitAU.mouthSmileRight.rawValue
            ]
        case .sad:
            return [
                ArkitAU.mouthFrownLeft.rawValue,
                ArkitAU.mouthFrownRight.rawValue,
                ArkitAU.browInnerUp.rawValue
            ]
        case .angry:
            return [
                ArkitAU.browDownLeft.rawValue,
                ArkitAU.browDownRight.rawValue,
                ArkitAU.mouthPressLeft.rawValue,
                ArkitAU.mouthPressRight.rawValue
            ]
        case .surprised:
            return [
                ArkitAU.browInnerUp.rawValue,
                ArkitAU.browOuterUpLeft.rawValue,
                ArkitAU.browOuterUpRight.rawValue,
                ArkitAU.eyeWideLeft.rawValue,
                ArkitAU.eyeWideRight.rawValue,
                ArkitAU.jawOpen.rawValue
            ]
        case .disgusted:
            return [
                ArkitAU.noseSneerLeft.rawValue,
                ArkitAU.noseSneerRight.rawValue,
                ArkitAU.mouthUpperUpLeft.rawValue,
                ArkitAU.mouthUpperUpRight.rawValue
            ]
        case .fearful:
            return [
                ArkitAU.browInnerUp.rawValue,
                ArkitAU.browOuterUpLeft.rawValue,
                ArkitAU.browOuterUpRight.rawValue,
                ArkitAU.eyeWideLeft.rawValue,
                ArkitAU.eyeWideRight.rawValue,
                ArkitAU.mouthStretchLeft.rawValue,
                ArkitAU.mouthStretchRight.rawValue
            ]
        case .thinking:
            return [
                ArkitAU.browDownLeft.rawValue,
                ArkitAU.browDownRight.rawValue,
                ArkitAU.eyeLookUpLeft.rawValue,
                ArkitAU.eyeLookUpRight.rawValue
            ]
        case .sleepy:
            return [
                ArkitAU.eyeBlinkLeft.rawValue,
                ArkitAU.eyeBlinkRight.rawValue
            ]
        case .confused:
            return [
                ArkitAU.browOuterUpLeft.rawValue,
                ArkitAU.browDownRight.rawValue,
                ArkitAU.mouthLeft.rawValue
            ]
        case .bored:
            return []
        case .winkLeft:
            return [ArkitAU.eyeBlinkLeft.rawValue]
        case .winkRight:
            return [ArkitAU.eyeBlinkRight.rawValue]
        case .browUpLeft:
            return [ArkitAU.browOuterUpLeft.rawValue]
        case .browUpRight:
            return [ArkitAU.browOuterUpRight.rawValue]
        case .halfSmileLeft:
            return [ArkitAU.mouthSmileLeft.rawValue]
        case .halfSmileRight:
            return [ArkitAU.mouthSmileRight.rawValue]
        case .laugh:
            return [
                ArkitAU.cheekSquintLeft.rawValue,
                ArkitAU.cheekSquintRight.rawValue,
                ArkitAU.mouthSmileLeft.rawValue,
                ArkitAU.mouthSmileRight.rawValue,
                ArkitAU.jawOpen.rawValue
            ]
        case .kiss:
            return [ArkitAU.mouthPucker.rawValue]
        case .gasp:
            return [
                ArkitAU.jawOpen.rawValue,
                ArkitAU.browInnerUp.rawValue,
                ArkitAU.browOuterUpLeft.rawValue,
                ArkitAU.browOuterUpRight.rawValue
            ]
        case .smirk:
            return [ArkitAU.mouthSmileLeft.rawValue]
        }
    }

    /// Oczekiwane AU, które dla asymetrycznego presetu MUSZĄ zostać wyciszone
    /// (np. dla wink_left — eyeBlinkRight powinno być bliskie zera).
    public var forbiddenDominantAUs: [Int] {
        switch self {
        case .winkLeft:        return [ArkitAU.eyeBlinkRight.rawValue]
        case .winkRight:       return [ArkitAU.eyeBlinkLeft.rawValue]
        case .browUpLeft:      return [ArkitAU.browOuterUpRight.rawValue]
        case .browUpRight:     return [ArkitAU.browOuterUpLeft.rawValue]
        case .halfSmileLeft:   return [ArkitAU.mouthSmileRight.rawValue]
        case .halfSmileRight:  return [ArkitAU.mouthSmileLeft.rawValue]
        default:               return []
        }
    }

    /// Łatwość wykonania: `1` = bardzo łatwe, `5` = trudne (np. kontrola pojedynczej brwi).
    public var difficulty: Int {
        switch self {
        case .happy, .sad, .surprised, .laugh, .kiss, .gasp:
            return 1
        case .angry, .disgusted, .fearful, .bored, .sleepy, .smirk:
            return 2
        case .thinking, .confused:
            return 3
        case .winkLeft, .winkRight, .halfSmileLeft, .halfSmileRight:
            return 4
        case .browUpLeft, .browUpRight:
            return 5
        }
    }

    /// Symbol SF Symbols używany w ikonie obok nazwy presetu.
    public var iconSymbolName: String {
        switch self {
        case .happy:           return "face.smiling"
        case .sad:             return "cloud.rain"
        case .angry:           return "flame"
        case .surprised:       return "exclamationmark.circle"
        case .disgusted:       return "nose"
        case .fearful:         return "eye.trianglebadge.exclamationmark"
        case .thinking:        return "brain"
        case .sleepy:          return "moon.zzz"
        case .confused:        return "questionmark.circle"
        case .bored:           return "hourglass"
        case .winkLeft:        return "eye"
        case .winkRight:       return "eye.fill"
        case .browUpLeft:      return "arrow.up.left.circle"
        case .browUpRight:     return "arrow.up.right.circle"
        case .halfSmileLeft:   return "arrow.down.left.circle"
        case .halfSmileRight:  return "arrow.down.right.circle"
        case .laugh:           return "face.smiling.inverse"
        case .kiss:            return "heart"
        case .gasp:            return "bubble.left"
        case .smirk:           return "bolt.horizontal"
        }
    }
}
