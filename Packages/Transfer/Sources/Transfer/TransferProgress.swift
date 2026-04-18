// =============================================================================
// Plik: TransferProgress.swift
// Opis: ObservableObject publikujący postęp i status transferu pliku .face.
// =============================================================================

import Foundation
import Combine

/// Status wysokopoziomowy transferu.
public enum TransferStatus: Equatable, Sendable {
    case idle
    case preparing
    case transferring
    case finished
    case failed(String)
}

/// Publikuje aktualny postęp (0…1) i status. Używany przez View w aplikacji.
@MainActor
public final class TransferProgress: ObservableObject {

    @Published public private(set) var progress: Double = 0
    @Published public private(set) var status: TransferStatus = .idle
    @Published public private(set) var detail: String = ""

    public init() {}

    public func update(progress: Double, detail: String = "") {
        self.progress = max(0, min(1, progress))
        if !detail.isEmpty { self.detail = detail }
    }

    public func setStatus(_ status: TransferStatus) {
        self.status = status
    }

    public func reset() {
        self.progress = 0
        self.status = .idle
        self.detail = ""
    }
}
