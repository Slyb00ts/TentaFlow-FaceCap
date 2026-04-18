// =============================================================================
// Plik: PerformanceCaptureError.swift
// Opis: Typy błędów zwracane przez warstwę nagrywania performance (audio + AU).
// =============================================================================

import Foundation

/// Zbiór błędów modułu `PerformanceCapture`. Każdy przypadek niesie krótki,
/// lokalizowany opis — nadaje się do wyświetlenia w UI oraz zapisania w logu.
public enum PerformanceCaptureError: Error, Sendable, Equatable {

    /// Nie udało się skonfigurować sesji audio (kategoria, sampleRate itp.).
    case audioSessionFailed(String)

    /// Resampling do 16 kHz nie powiódł się (konwerter AVAudioConverter).
    case resampleFailed(String)

    /// Ring-buffer klatek AU przepełniony — nagrywanie zbyt długie lub fps > 60.
    case bufferOverflow(capacity: Int)

    /// Nazwa klipu jest pusta, zbyt długa lub zawiera niedozwolone znaki.
    case invalidClipName

    /// Nie udało się zapisać/odczytać klipu z dysku.
    case persistenceFailed(String)

    /// Nie znaleziono klipu o podanym identyfikatorze.
    case clipNotFound(UUID)

    /// Próba odtworzenia audio bez dostępnego pliku źródłowego.
    case audioFileMissing

    /// Osiągnięto limit liczby klipów w sesji (5).
    case clipLimitReached
}

extension PerformanceCaptureError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .audioSessionFailed(let reason):
            return "Konfiguracja sesji audio nie powiodła się: \(reason)"
        case .resampleFailed(let reason):
            return "Resampling audio nie powiódł się: \(reason)"
        case .bufferOverflow(let cap):
            return "Przepełnienie bufora klatek AU (pojemność: \(cap))."
        case .invalidClipName:
            return "Nieprawidłowa nazwa klipu."
        case .persistenceFailed(let reason):
            return "Zapis/odczyt klipu nie powiódł się: \(reason)"
        case .clipNotFound(let id):
            return "Nie znaleziono klipu \(id.uuidString)."
        case .audioFileMissing:
            return "Brak pliku audio powiązanego z klipem."
        case .clipLimitReached:
            return "Osiągnięto limit 5 klipów w sesji."
        }
    }
}
