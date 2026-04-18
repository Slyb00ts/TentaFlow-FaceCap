// =============================================================================
// Plik: FacecapError.swift
// Opis: Wspólna hierarchia błędów aplikacji z opisami lokalizowanymi na polski.
// =============================================================================

import Foundation

/// Zbiór błędów projektu. Każdy wariant ma sensowny `errorDescription` po polsku.
public enum FacecapError: LocalizedError, Equatable {

    // MARK: — Uprawnienia / urządzenie

    case permissionDenied(String)
    case trueDepthUnsupported
    case thermalThrottled

    // MARK: — Skan głowy

    case headScanFailed(String)
    case meshInvalid(String)
    case coverageTooLow(Double)

    // MARK: — Kalibracja

    case neutralNotStable
    case calibrationTargetNotReached(auIndex: Int, reached: Double, target: Double)

    // MARK: — Eksport / plik .face v3

    case textureConversionFailed
    case writerOutOfBounds(offset: Int, requested: Int)
    case crcMismatch(expected: UInt32, got: UInt32)
    case validatorMismatch(section: UInt32, field: String)
    case fileWriteFailed(String)

    // MARK: — Transfer

    case noTransferReceiver
    case uploadFailed(String)

    // MARK: — Ogólne

    case ioError(String)
    case malformed(String)
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let what):
            return "Brak zgody na dostęp do: \(what)."
        case .trueDepthUnsupported:
            return "To urządzenie nie ma kamery TrueDepth wymaganej przez aplikację."
        case .thermalThrottled:
            return "Urządzenie jest zbyt gorące — przerywam akcję, aby uniknąć throttlingu."
        case .headScanFailed(let detail):
            return "Skan głowy nie powiódł się: \(detail)."
        case .meshInvalid(let detail):
            return "Wygenerowana siatka jest niepoprawna: \(detail)."
        case .coverageTooLow(let percent):
            return "Pokrycie skanu zbyt niskie (\(Int(percent * 100))%). Wymagane min. 85%."
        case .neutralNotStable:
            return "Nie udało się ustabilizować neutralnej miny. Spróbuj ponownie."
        case .calibrationTargetNotReached(let au, let reached, let target):
            return "AU #\(au) nie osiągnęło progu (osiągnięto \(String(format: "%.2f", reached)), cel \(String(format: "%.2f", target)))."
        case .textureConversionFailed:
            return "Konwersja tekstury do RGB565 nie powiodła się."
        case .writerOutOfBounds(let offset, let requested):
            return "Zapis poza granice bufora: offset=\(offset), req=\(requested)."
        case .crcMismatch(let expected, let got):
            return "CRC32 nie zgadza się (oczekiwano 0x\(String(expected, radix: 16)), otrzymano 0x\(String(got, radix: 16)))."
        case .validatorMismatch(let section, let field):
            return "Walidator wykrył różnicę w sekcji 0x\(String(section, radix: 16)), pole \(field)."
        case .fileWriteFailed(let detail):
            return "Zapis pliku .face nie powiódł się: \(detail)."
        case .noTransferReceiver:
            return "Nie znaleziono urządzenia docelowego w sieci lokalnej."
        case .uploadFailed(let detail):
            return "Transfer nie powiódł się: \(detail)."
        case .ioError(let detail):
            return "Błąd wejścia/wyjścia: \(detail)."
        case .malformed(let detail):
            return "Niepoprawne dane: \(detail)."
        case .invalidArgument(let detail):
            return "Niepoprawny argument: \(detail)."
        }
    }
}
