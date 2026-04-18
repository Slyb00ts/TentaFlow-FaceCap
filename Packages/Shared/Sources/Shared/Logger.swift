// =============================================================================
// Plik: Logger.swift
// Opis: Cienka nakładka na os.Logger z predefiniowanymi kategoriami projektu.
// =============================================================================

import Foundation
import os

/// Wrapper wokół `os.Logger` z ustalonym subsystemem `pl.tentaflow.facecap`.
public struct AppLog {

    /// Nazwa subsystemu logów — trafia do Console.app i sysdiagnose.
    public static let subsystem: String = "pl.tentaflow.facecap"

    /// Kategorie używane w całym projekcie. Trzymanie ich w enumie pilnuje spójności.
    public enum Category: String, CaseIterable, Sendable {
        case app
        case headscan
        case calibration
        case export
        case transfer
        case perf
    }

    /// Zwraca instancję `os.Logger` dla wybranej kategorii.
    public static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    public static let app: Logger = logger(.app)
    public static let headscan: Logger = logger(.headscan)
    public static let calibration: Logger = logger(.calibration)
    public static let export: Logger = logger(.export)
    public static let transfer: Logger = logger(.transfer)
    public static let perf: Logger = logger(.perf)
}

/// Pomocnicza rzutka czasu — log czasu wykonania bloku.
public func measure<T>(_ label: String,
                       logger: Logger = AppLog.perf,
                       _ body: () throws -> T) rethrows -> T {
    let start = DispatchTime.now().uptimeNanoseconds
    let result = try body()
    let end = DispatchTime.now().uptimeNanoseconds
    let ms = Double(end - start) / 1_000_000.0
    logger.debug("\(label, privacy: .public): \(ms, format: .fixed(precision: 2), privacy: .public) ms")
    return result
}
