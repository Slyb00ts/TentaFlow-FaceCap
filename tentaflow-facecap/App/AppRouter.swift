// =============================================================================
// Plik: AppRouter.swift
// Opis: Router aplikacji — 12 kroków flow + persistent state w UserDefaults (JSON).
// =============================================================================

import Foundation
import Combine
import Shared

/// Kroki flow. `calibrationStep(index)` przechodzi przez 52 AU.
public enum AppStep: Equatable, Codable, Hashable, Sendable {

    case onboarding
    case headScanBrief
    case headScanCapture
    case headScanPreview
    case calibrationBrief
    case neutralFace
    case calibrationStep(index: Int)
    case performanceCapture
    case expressionCapture
    case preview
    case export
    case transfer
    case done

    /// Kolejność kroków w głównym flow.
    public static let orderedList: [AppStep] = {
        var steps: [AppStep] = [
            .onboarding,
            .headScanBrief,
            .headScanCapture,
            .headScanPreview,
            .calibrationBrief,
            .neutralFace
        ]
        for i in 0..<52 {
            steps.append(.calibrationStep(index: i))
        }
        steps.append(contentsOf: [
            .performanceCapture,
            .expressionCapture,
            .preview,
            .export,
            .transfer,
            .done
        ])
        return steps
    }()
}

/// Router aplikacji. Trzyma aktualny krok i serializuje go do UserDefaults.
@MainActor
public final class AppRouter: ObservableObject {

    /// Aktualny krok.
    @Published public private(set) var currentStep: AppStep

    private let storageKey = "pl.tentaflow.facecap.router.state"

    public init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(AppStep.self, from: data) {
            self.currentStep = decoded
        } else {
            self.currentStep = .onboarding
        }
    }

    /// Przejście do konkretnego kroku.
    public func go(to step: AppStep) {
        currentStep = step
        persist()
        AppLog.app.info("Router -> \(String(describing: step), privacy: .public)")
    }

    /// Następny krok w liście. Dla `calibrationStep(i)` przechodzi do `calibrationStep(i+1)`.
    public func advance() {
        let list = AppStep.orderedList
        guard let idx = list.firstIndex(of: currentStep) else {
            currentStep = .onboarding
            persist()
            return
        }
        let next = list.index(after: idx)
        if next < list.endIndex {
            currentStep = list[next]
        } else {
            currentStep = .done
        }
        persist()
        AppLog.app.info("Router advance -> \(String(describing: self.currentStep), privacy: .public)")
    }

    /// Cofnij jeden krok.
    public func back() {
        let list = AppStep.orderedList
        guard let idx = list.firstIndex(of: currentStep), idx > 0 else { return }
        currentStep = list[list.index(before: idx)]
        persist()
    }

    /// Reset do pierwszego kroku i usunięcie cache.
    public func reset() {
        currentStep = .onboarding
        UserDefaults.standard.removeObject(forKey: storageKey)
        AppLog.app.info("Router reset.")
    }

    /// Zapisuje aktualny stan w UserDefaults jako JSON.
    private func persist() {
        do {
            let data = try JSONEncoder().encode(currentStep)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            AppLog.app.error("Router persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
