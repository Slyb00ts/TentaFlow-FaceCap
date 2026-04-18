// =============================================================================
// Plik: ClipLibrary.swift
// Opis: Biblioteka klipów performance – persystencja na dysku (Documents/...).
// =============================================================================

import Foundation
import Combine
import simd
import os

/// Biblioteka klipów performance zarządzająca listą i zapisem/odczytem z dysku.
///
/// Klipy trzymane są w katalogu `Documents/PerformanceClips/`, każdy jako
/// para plików:
///  - `<id>.json` – metadane + surowa tablica wag (binary blob base64 w JSON),
///  - `<id>.wav`  – plik audio (opcjonalny).
@MainActor
public final class ClipLibrary: ObservableObject {

    /// Limit liczby klipów w bibliotece (per sesja użytkownika).
    public static let maxClips: Int = 5

    @Published public private(set) var clips: [PerformanceClip] = []

    private let log = Logger(subsystem: "pl.tentaflow.facecap", category: "clip-library")
    private let fs = FileManager.default
    private let root: URL

    public init(rootDirectory: URL? = nil) {
        if let r = rootDirectory {
            self.root = r
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory,
                                                 in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.root = docs.appendingPathComponent("PerformanceClips", isDirectory: true)
        }
        ensureDirectory()
        loadFromDisk()
    }

    /// Dodaje nowy klip do biblioteki. Rzuca gdy nazwa nieprawidłowa lub przekroczono limit.
    public func add(_ clip: PerformanceClip) throws {
        try validateName(clip.name)
        if clips.count >= Self.maxClips {
            throw PerformanceCaptureError.clipLimitReached
        }
        try persist(clip)
        clips.append(clip)
        log.info("Dodano klip \(clip.name, privacy: .public) id=\(clip.id.uuidString, privacy: .public)")
    }

    /// Usuwa klip o podanym id.
    public func remove(id: UUID) throws {
        guard let idx = clips.firstIndex(where: { $0.id == id }) else {
            throw PerformanceCaptureError.clipNotFound(id)
        }
        let clip = clips[idx]
        removeFiles(for: clip)
        clips.remove(at: idx)
        log.info("Usunięto klip \(clip.name, privacy: .public)")
    }

    /// Zmienia nazwę klipu.
    public func rename(id: UUID, to newName: String) throws {
        try validateName(newName)
        guard let idx = clips.firstIndex(where: { $0.id == id }) else {
            throw PerformanceCaptureError.clipNotFound(id)
        }
        var clip = clips[idx]
        clip.name = newName
        try persist(clip)
        clips[idx] = clip
    }

    /// Przeładowuje zawartość z dysku (np. po imporcie ręcznym).
    public func reload() {
        clips.removeAll(keepingCapacity: true)
        loadFromDisk()
    }

    // MARK: - Prywatne

    private func ensureDirectory() {
        if !fs.fileExists(atPath: root.path) {
            try? fs.createDirectory(at: root, withIntermediateDirectories: true)
        }
    }

    private func validateName(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count > 64 {
            throw PerformanceCaptureError.invalidClipName
        }
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_()[]."))
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            throw PerformanceCaptureError.invalidClipName
        }
    }

    private func persist(_ clip: PerformanceClip) throws {
        let jsonURL = root.appendingPathComponent("\(clip.id.uuidString).json")
        let dto = ClipDTO(from: clip)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(dto)
            try data.write(to: jsonURL, options: .atomic)
        } catch {
            throw PerformanceCaptureError.persistenceFailed("\(error)")
        }
    }

    private func removeFiles(for clip: PerformanceClip) {
        let jsonURL = root.appendingPathComponent("\(clip.id.uuidString).json")
        try? fs.removeItem(at: jsonURL)
        if let audio = clip.audioURL, audio.path.hasPrefix(root.path) {
            try? fs.removeItem(at: audio)
        }
    }

    private func loadFromDisk() {
        guard let items = try? fs.contentsOfDirectory(at: root,
                                                       includingPropertiesForKeys: nil) else {
            return
        }
        let decoder = JSONDecoder()
        var loaded: [PerformanceClip] = []
        for url in items where url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: url)
                let dto = try decoder.decode(ClipDTO.self, from: data)
                loaded.append(dto.toClip())
            } catch {
                log.error("Nie udało się wczytać klipu \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        loaded.sort { $0.startedAt < $1.startedAt }
        self.clips = loaded
    }
}

// MARK: - DTO

/// Reprezentacja klipu na dysku – JSON-friendly.
private struct ClipDTO: Codable {
    let id: UUID
    let name: String
    let fps: UInt8
    let startedAt: Date
    let durationSec: Double
    /// Surowe bajty wag (kwantyzowane u8 × 52 × frames) base64-encoded w JSON.
    let weightsQuantized: Data
    let frameCount: Int
    let audioPath: String?

    init(from clip: PerformanceClip) {
        self.id = clip.id
        self.name = clip.name
        self.fps = clip.fps
        self.startedAt = clip.startedAt
        self.durationSec = clip.durationSec
        self.weightsQuantized = clip.weightsAsData
        self.frameCount = clip.weights.count
        self.audioPath = clip.audioURL?.path
    }

    func toClip() -> PerformanceClip {
        let frames = Self.dequantize(data: weightsQuantized, count: frameCount)
        let audioURL: URL?
        if let path = audioPath, !path.isEmpty {
            audioURL = URL(fileURLWithPath: path)
        } else {
            audioURL = nil
        }
        return PerformanceClip(id: id,
                                name: name,
                                fps: fps,
                                startedAt: startedAt,
                                durationSec: durationSec,
                                weights: frames,
                                audioURL: audioURL)
    }

    /// Dekwantyzacja u8→Float – używana tylko przy odczycie z dysku (rzadko).
    static func dequantize(data: Data, count: Int) -> [SIMD64<Float>] {
        var out: [SIMD64<Float>] = []
        out.reserveCapacity(count)
        let stride = 52
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for i in 0..<count {
                var vec = SIMD64<Float>(repeating: 0)
                for k in 0..<stride {
                    vec[k] = Float(base[i * stride + k]) / 255.0
                }
                out.append(vec)
            }
        }
        return out
    }
}
