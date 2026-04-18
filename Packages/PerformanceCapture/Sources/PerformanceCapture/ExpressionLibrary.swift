// =============================================================================
// Plik: ExpressionLibrary.swift
// Opis: @MainActor biblioteka snapshotów w sesji — perzystencja JSON w Documents.
// Przykład: expressionLibrary.save(snapshot); expressionLibrary.has(preset: .happy)
// =============================================================================

import Foundation
import Shared

/// Biblioteka wyrazów twarzy trzymana w sesji. Snapshoty są utrwalane w pliku
/// `Documents/expressions.json` — dzięki temu przeżywają restart aplikacji.
@MainActor
public final class ExpressionLibrary: ObservableObject {

    /// Mapa `storageName -> ExpressionSnapshot`. Opublikowana — UI odświeża się automatycznie.
    @Published public private(set) var snapshots: [String: ExpressionSnapshot] = [:]

    /// URL pliku JSON z utrwalonymi snapshotami.
    public let persistenceURL: URL

    /// Tworzy bibliotekę z domyślnym plikiem w `Documents/expressions.json`.
    public init() {
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            self.persistenceURL = docs.appendingPathComponent("expressions.json", isDirectory: false)
        } else {
            let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            self.persistenceURL = home
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("expressions.json", isDirectory: false)
        }
        loadPersisted()
    }

    /// Tworzy bibliotekę z własną lokalizacją pliku (używane w testach).
    public init(persistenceURL: URL) {
        self.persistenceURL = persistenceURL
        loadPersisted()
    }

    // MARK: — API mutujące

    /// Zapisuje (nadpisuje) snapshot w bibliotece. Perzystencja wykonuje się
    /// synchronicznie po każdej mutacji — plik nie jest duży, więc nie robimy debounce.
    public func save(_ snapshot: ExpressionSnapshot) {
        snapshots[snapshot.name] = snapshot
        persist()
        AppLog.perf.info("ExpressionLibrary: saved \(snapshot.name, privacy: .public), quality=\(snapshot.qualityScore, privacy: .public)")
    }

    /// Usuwa snapshot zadanego presetu.
    public func remove(preset: ExpressionPreset) {
        snapshots.removeValue(forKey: preset.storageName)
        persist()
        AppLog.perf.info("ExpressionLibrary: removed \(preset.storageName, privacy: .public)")
    }

    /// Czyści całą bibliotekę (również plik JSON).
    public func removeAll() {
        snapshots.removeAll()
        persist()
    }

    // MARK: — API odczytu

    /// Czy preset ma już zapisany snapshot.
    public func has(preset: ExpressionPreset) -> Bool {
        snapshots[preset.storageName] != nil
    }

    /// Snapshot danego presetu (albo `nil`).
    public func snapshot(for preset: ExpressionPreset) -> ExpressionSnapshot? {
        snapshots[preset.storageName]
    }

    /// Statystyki ukończenia fazy — wymagane, opcjonalne i suma wykonanych.
    public func completionCount() -> (completed: Int, required: Int, optional: Int) {
        let completed = snapshots.count
        let required = ExpressionPreset.allCases.filter(\.isRequired).count
        let optional = ExpressionPreset.allCases.count - required
        return (completed, required, optional)
    }

    /// Czy wszystkie presety wymagane są już zapisane.
    public func isRequiredComplete() -> Bool {
        ExpressionPreset.allCases.filter(\.isRequired).allSatisfy(has)
    }

    /// Eksport w kolejności `ExpressionPreset.allCases` — pomija presety bez snapshotów.
    public func exportAsArray() -> [ExpressionSnapshot] {
        ExpressionPreset.allCases.compactMap { snapshots[$0.storageName] }
    }

    // MARK: — Perzystencja

    private func loadPersisted() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            let decoded = try JSONDecoder().decode([String: ExpressionSnapshot].self, from: data)
            self.snapshots = decoded
            AppLog.perf.info("ExpressionLibrary: loaded \(decoded.count, privacy: .public) snapshots.")
        } catch {
            AppLog.perf.error("ExpressionLibrary load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshots)
            let dir = persistenceURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            AppLog.perf.error("ExpressionLibrary persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
