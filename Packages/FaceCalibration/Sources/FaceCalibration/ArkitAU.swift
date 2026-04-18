// =============================================================================
// Plik: ArkitAU.swift
// Opis: Enum 52 jednostek akcji ARKit z mapowaniem do BlendShapeLocation i grup korelacji.
// =============================================================================

import Foundation
import ARKit

/// Grupa korelacji — AU w tej samej grupie często aktywują się razem.
public enum CorrelationGroup: Int, Sendable, CaseIterable {
    case eyes
    case brows
    case mouth
    case cheeks
    case nose
    case tongue
    case jaw
}

/// 52 jednostki akcji (blendshape locations) obsługiwane przez ARKit.
public enum ArkitAU: Int, Sendable, CaseIterable {
    case eyeBlinkLeft = 0
    case eyeLookDownLeft
    case eyeLookInLeft
    case eyeLookOutLeft
    case eyeLookUpLeft
    case eyeSquintLeft
    case eyeWideLeft
    case eyeBlinkRight
    case eyeLookDownRight
    case eyeLookInRight
    case eyeLookOutRight
    case eyeLookUpRight
    case eyeSquintRight
    case eyeWideRight
    case jawForward
    case jawLeft
    case jawRight
    case jawOpen
    case mouthClose
    case mouthFunnel
    case mouthPucker
    case mouthLeft
    case mouthRight
    case mouthSmileLeft
    case mouthSmileRight
    case mouthFrownLeft
    case mouthFrownRight
    case mouthDimpleLeft
    case mouthDimpleRight
    case mouthStretchLeft
    case mouthStretchRight
    case mouthRollLower
    case mouthRollUpper
    case mouthShrugLower
    case mouthShrugUpper
    case mouthPressLeft
    case mouthPressRight
    case mouthLowerDownLeft
    case mouthLowerDownRight
    case mouthUpperUpLeft
    case mouthUpperUpRight
    case browDownLeft
    case browDownRight
    case browInnerUp
    case browOuterUpLeft
    case browOuterUpRight
    case cheekPuff
    case cheekSquintLeft
    case cheekSquintRight
    case noseSneerLeft
    case noseSneerRight
    case tongueOut

    /// Klucz ARKit BlendShapeLocation.
    public var arkitKey: ARFaceAnchor.BlendShapeLocation {
        switch self {
        case .eyeBlinkLeft: return .eyeBlinkLeft
        case .eyeLookDownLeft: return .eyeLookDownLeft
        case .eyeLookInLeft: return .eyeLookInLeft
        case .eyeLookOutLeft: return .eyeLookOutLeft
        case .eyeLookUpLeft: return .eyeLookUpLeft
        case .eyeSquintLeft: return .eyeSquintLeft
        case .eyeWideLeft: return .eyeWideLeft
        case .eyeBlinkRight: return .eyeBlinkRight
        case .eyeLookDownRight: return .eyeLookDownRight
        case .eyeLookInRight: return .eyeLookInRight
        case .eyeLookOutRight: return .eyeLookOutRight
        case .eyeLookUpRight: return .eyeLookUpRight
        case .eyeSquintRight: return .eyeSquintRight
        case .eyeWideRight: return .eyeWideRight
        case .jawForward: return .jawForward
        case .jawLeft: return .jawLeft
        case .jawRight: return .jawRight
        case .jawOpen: return .jawOpen
        case .mouthClose: return .mouthClose
        case .mouthFunnel: return .mouthFunnel
        case .mouthPucker: return .mouthPucker
        case .mouthLeft: return .mouthLeft
        case .mouthRight: return .mouthRight
        case .mouthSmileLeft: return .mouthSmileLeft
        case .mouthSmileRight: return .mouthSmileRight
        case .mouthFrownLeft: return .mouthFrownLeft
        case .mouthFrownRight: return .mouthFrownRight
        case .mouthDimpleLeft: return .mouthDimpleLeft
        case .mouthDimpleRight: return .mouthDimpleRight
        case .mouthStretchLeft: return .mouthStretchLeft
        case .mouthStretchRight: return .mouthStretchRight
        case .mouthRollLower: return .mouthRollLower
        case .mouthRollUpper: return .mouthRollUpper
        case .mouthShrugLower: return .mouthShrugLower
        case .mouthShrugUpper: return .mouthShrugUpper
        case .mouthPressLeft: return .mouthPressLeft
        case .mouthPressRight: return .mouthPressRight
        case .mouthLowerDownLeft: return .mouthLowerDownLeft
        case .mouthLowerDownRight: return .mouthLowerDownRight
        case .mouthUpperUpLeft: return .mouthUpperUpLeft
        case .mouthUpperUpRight: return .mouthUpperUpRight
        case .browDownLeft: return .browDownLeft
        case .browDownRight: return .browDownRight
        case .browInnerUp: return .browInnerUp
        case .browOuterUpLeft: return .browOuterUpLeft
        case .browOuterUpRight: return .browOuterUpRight
        case .cheekPuff: return .cheekPuff
        case .cheekSquintLeft: return .cheekSquintLeft
        case .cheekSquintRight: return .cheekSquintRight
        case .noseSneerLeft: return .noseSneerLeft
        case .noseSneerRight: return .noseSneerRight
        case .tongueOut: return .tongueOut
        }
    }

    /// Grupa korelacji dla cross-talk analysis.
    public var correlationGroup: CorrelationGroup {
        switch self {
        case .eyeBlinkLeft, .eyeLookDownLeft, .eyeLookInLeft, .eyeLookOutLeft, .eyeLookUpLeft,
             .eyeSquintLeft, .eyeWideLeft,
             .eyeBlinkRight, .eyeLookDownRight, .eyeLookInRight, .eyeLookOutRight, .eyeLookUpRight,
             .eyeSquintRight, .eyeWideRight:
            return .eyes
        case .browDownLeft, .browDownRight, .browInnerUp, .browOuterUpLeft, .browOuterUpRight:
            return .brows
        case .jawForward, .jawLeft, .jawRight, .jawOpen:
            return .jaw
        case .mouthClose, .mouthFunnel, .mouthPucker, .mouthLeft, .mouthRight,
             .mouthSmileLeft, .mouthSmileRight, .mouthFrownLeft, .mouthFrownRight,
             .mouthDimpleLeft, .mouthDimpleRight, .mouthStretchLeft, .mouthStretchRight,
             .mouthRollLower, .mouthRollUpper, .mouthShrugLower, .mouthShrugUpper,
             .mouthPressLeft, .mouthPressRight, .mouthLowerDownLeft, .mouthLowerDownRight,
             .mouthUpperUpLeft, .mouthUpperUpRight:
            return .mouth
        case .cheekPuff, .cheekSquintLeft, .cheekSquintRight:
            return .cheeks
        case .noseSneerLeft, .noseSneerRight:
            return .nose
        case .tongueOut:
            return .tongue
        }
    }

    /// Etykieta UI po polsku.
    public var nameForUI: String {
        switch self {
        case .eyeBlinkLeft: return "Mrugnięcie lewe"
        case .eyeLookDownLeft: return "Spojrzenie w dół (L)"
        case .eyeLookInLeft: return "Spojrzenie do wewnątrz (L)"
        case .eyeLookOutLeft: return "Spojrzenie na zewnątrz (L)"
        case .eyeLookUpLeft: return "Spojrzenie w górę (L)"
        case .eyeSquintLeft: return "Zmrużenie lewe"
        case .eyeWideLeft: return "Szeroko otwarte (L)"
        case .eyeBlinkRight: return "Mrugnięcie prawe"
        case .eyeLookDownRight: return "Spojrzenie w dół (R)"
        case .eyeLookInRight: return "Spojrzenie do wewnątrz (R)"
        case .eyeLookOutRight: return "Spojrzenie na zewnątrz (R)"
        case .eyeLookUpRight: return "Spojrzenie w górę (R)"
        case .eyeSquintRight: return "Zmrużenie prawe"
        case .eyeWideRight: return "Szeroko otwarte (R)"
        case .jawForward: return "Żuchwa do przodu"
        case .jawLeft: return "Żuchwa w lewo"
        case .jawRight: return "Żuchwa w prawo"
        case .jawOpen: return "Otwarcie ust"
        case .mouthClose: return "Zamknięcie warg"
        case .mouthFunnel: return "Usta w trąbkę"
        case .mouthPucker: return "Cmok"
        case .mouthLeft: return "Usta w lewo"
        case .mouthRight: return "Usta w prawo"
        case .mouthSmileLeft: return "Uśmiech lewy"
        case .mouthSmileRight: return "Uśmiech prawy"
        case .mouthFrownLeft: return "Grymas lewy"
        case .mouthFrownRight: return "Grymas prawy"
        case .mouthDimpleLeft: return "Dołek lewy"
        case .mouthDimpleRight: return "Dołek prawy"
        case .mouthStretchLeft: return "Rozciągnięcie (L)"
        case .mouthStretchRight: return "Rozciągnięcie (R)"
        case .mouthRollLower: return "Dolna warga zwinięta"
        case .mouthRollUpper: return "Górna warga zwinięta"
        case .mouthShrugLower: return "Dolna warga wysunięta"
        case .mouthShrugUpper: return "Górna warga wysunięta"
        case .mouthPressLeft: return "Zaciśnięcie (L)"
        case .mouthPressRight: return "Zaciśnięcie (R)"
        case .mouthLowerDownLeft: return "Dolna w dół (L)"
        case .mouthLowerDownRight: return "Dolna w dół (R)"
        case .mouthUpperUpLeft: return "Górna w górę (L)"
        case .mouthUpperUpRight: return "Górna w górę (R)"
        case .browDownLeft: return "Brew w dół (L)"
        case .browDownRight: return "Brew w dół (R)"
        case .browInnerUp: return "Brwi do góry (środek)"
        case .browOuterUpLeft: return "Brew zew. w górę (L)"
        case .browOuterUpRight: return "Brew zew. w górę (R)"
        case .cheekPuff: return "Nadmuchane policzki"
        case .cheekSquintLeft: return "Zmarszczenie policzka (L)"
        case .cheekSquintRight: return "Zmarszczenie policzka (R)"
        case .noseSneerLeft: return "Zmarszczenie nosa (L)"
        case .noseSneerRight: return "Zmarszczenie nosa (R)"
        case .tongueOut: return "Wystawiony język"
        }
    }

    /// Próg detekcji peak — domyślny dla walidatora.
    public var detectionThreshold: Float {
        switch self {
        case .eyeBlinkLeft, .eyeBlinkRight: return 0.85
        case .jawOpen, .mouthFunnel, .mouthPucker, .tongueOut: return 0.7
        default: return 0.6
        }
    }
}
