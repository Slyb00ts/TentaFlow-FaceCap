// =============================================================================
// Plik: PreviewError.swift
// Opis: Typy błędów warstwy Preview (Metal renderer avatara).
// =============================================================================

import Foundation

/// Zbiór błędów związanych z inicjalizacją i działaniem Metal-based podglądu avatara.
public enum PreviewError: Error, Sendable, Equatable {

    /// Nie udało się uzyskać `MTLDevice` (symulator bez GPU lub urządzenie bez Metal).
    case metalDeviceNotAvailable

    /// Kompilacja shadera się nie powiodła.
    case shaderCompilationFailed(String)

    /// Nie udało się wczytać tekstury (albedo/normal) dla mesha.
    case textureLoadFailed(String)

    /// Niepoprawny stan mesha (np. vertexCount == 0, brak indeksów).
    case invalidMeshBundle(String)

    /// Brak wymaganego zasobu (np. FaceCalibrationResult nie wypełniony).
    case missingResource(String)
}

extension PreviewError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .metalDeviceNotAvailable:
            return "Urządzenie nie obsługuje Metal lub symulator bez GPU."
        case .shaderCompilationFailed(let msg):
            return "Kompilacja shadera nie powiodła się: \(msg)"
        case .textureLoadFailed(let name):
            return "Nie można wczytać tekstury: \(name)"
        case .invalidMeshBundle(let msg):
            return "Niepoprawny mesh bundle: \(msg)"
        case .missingResource(let name):
            return "Brak zasobu: \(name)"
        }
    }
}
