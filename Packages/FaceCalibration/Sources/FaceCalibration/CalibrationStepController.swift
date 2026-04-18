// =============================================================================
// Plik: CalibrationStepController.swift
// Opis: State machine kroków kalibracji — prompt/hold/measure/validate dla każdego AU.
// =============================================================================

import Foundation
import Combine

/// Wynik kroku kalibracji dla konkretnej AU.
public struct CalibrationStep: Sendable {
    public let au: ArkitAU
    public let recording: [FaceFrame]
    public let peakFrame: FaceFrame?
    public let validation: ValidationResult
    public let skipped: Bool
    public let retries: Int

    public init(au: ArkitAU, recording: [FaceFrame], peakFrame: FaceFrame?, validation: ValidationResult, skipped: Bool, retries: Int) {
        self.au = au
        self.recording = recording
        self.peakFrame = peakFrame
        self.validation = validation
        self.skipped = skipped
        self.retries = retries
    }
}

/// Stan state machine kontrolera kroków.
public enum CalibrationState: Sendable, Equatable {
    case idle
    case prompt(au: ArkitAU)
    case hold(au: ArkitAU, remainingSeconds: Double)
    case measure(au: ArkitAU)
    case validate(au: ArkitAU)
    case accepted(au: ArkitAU, peak: Float)
    case retry(au: ArkitAU, attempt: Int, reason: String)
    case skipped(au: ArkitAU)
    case completed
}

/// Kontroler sekwencyjnej kalibracji 52 AU.
@MainActor
public final class CalibrationStepController: ObservableObject {
    @Published public private(set) var state: CalibrationState = .idle
    @Published public private(set) var results: [ArkitAU: CalibrationStep] = [:]
    @Published public private(set) var currentIndex: Int = 0

    public let maxRetries: Int
    public let holdDurationSeconds: Double
    public let measureDurationSeconds: Double
    public let auSequence: [ArkitAU]
    private let reader: BlendshapeReader
    private let validator: CalibrationValidator

    private var activeTask: Task<Void, Never>?
    private var currentRetries: Int = 0

    public init(
        reader: BlendshapeReader,
        validator: CalibrationValidator = CalibrationValidator(),
        sequence: [ArkitAU] = ArkitAU.allCases,
        maxRetries: Int = 3,
        holdDurationSeconds: Double = 3.0,
        measureDurationSeconds: Double = 2.0
    ) {
        self.reader = reader
        self.validator = validator
        self.auSequence = sequence
        self.maxRetries = maxRetries
        self.holdDurationSeconds = holdDurationSeconds
        self.measureDurationSeconds = measureDurationSeconds
    }

    /// Startuje sekwencję kalibracji od początku.
    public func start() {
        activeTask?.cancel()
        results.removeAll()
        currentIndex = 0
        currentRetries = 0
        state = .idle
        activeTask = Task { [weak self] in
            await self?.runSequence()
        }
    }

    /// Przerywa kalibrację.
    public func cancel() {
        activeTask?.cancel()
        activeTask = nil
        state = .idle
    }

    /// Pomija aktualną AU.
    public func skipCurrent() {
        activeTask?.cancel()
        guard currentIndex < auSequence.count else { return }
        let au = auSequence[currentIndex]
        let step = CalibrationStep(
            au: au,
            recording: [],
            peakFrame: nil,
            validation: .insufficientData,
            skipped: true,
            retries: currentRetries
        )
        results[au] = step
        state = .skipped(au: au)
        currentIndex += 1
        currentRetries = 0
        activeTask = Task { [weak self] in
            await self?.runSequence()
        }
    }

    // MARK: - Pętla sekwencji

    private func runSequence() async {
        while currentIndex < auSequence.count {
            if Task.isCancelled { return }
            let au = auSequence[currentIndex]
            let outcome = await runStep(for: au)
            switch outcome {
            case .accepted:
                currentIndex += 1
                currentRetries = 0
            case .retryNeeded:
                if currentRetries >= maxRetries {
                    let step = CalibrationStep(
                        au: au,
                        recording: [],
                        peakFrame: nil,
                        validation: .insufficientData,
                        skipped: true,
                        retries: currentRetries
                    )
                    results[au] = step
                    state = .skipped(au: au)
                    currentIndex += 1
                    currentRetries = 0
                } else {
                    currentRetries += 1
                }
            case .cancelled:
                return
            }
        }
        state = .completed
    }

    private enum StepOutcome {
        case accepted
        case retryNeeded
        case cancelled
    }

    private func runStep(for au: ArkitAU) async -> StepOutcome {
        state = .prompt(au: au)
        // Prompt 1.5s.
        if (try? await Task.sleep(nanoseconds: 1_500_000_000)) == nil { return .cancelled }

        // Hold — countdown 3s.
        var remaining = holdDurationSeconds
        let tick: Double = 0.1
        while remaining > 0 {
            state = .hold(au: au, remainingSeconds: remaining)
            if (try? await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))) == nil { return .cancelled }
            remaining -= tick
        }

        // Measure — resetujemy bufor i nagrywamy measureDurationSeconds.
        reader.reset()
        state = .measure(au: au)
        if (try? await Task.sleep(nanoseconds: UInt64(measureDurationSeconds * 1_000_000_000))) == nil { return .cancelled }

        // Validate.
        state = .validate(au: au)
        let recording = reader.snapshot(lastN: Int(measureDurationSeconds * 60.0))
        let result = validator.validate(recording: recording, targetAU: au)
        let peak = reader.peakFrame(for: au, lastN: recording.count)

        switch result {
        case .ok(let value):
            let step = CalibrationStep(
                au: au,
                recording: recording,
                peakFrame: peak,
                validation: result,
                skipped: false,
                retries: currentRetries
            )
            results[au] = step
            state = .accepted(au: au, peak: value)
            if (try? await Task.sleep(nanoseconds: 500_000_000)) == nil { return .cancelled }
            return .accepted
        case .peakTooLow(let value, let threshold):
            state = .retry(au: au, attempt: currentRetries + 1, reason: "Peak \(value) < \(threshold)")
            if (try? await Task.sleep(nanoseconds: 1_500_000_000)) == nil { return .cancelled }
            return .retryNeeded
        case .correlated(let list):
            let names = list.map { $0.nameForUI }.joined(separator: ", ")
            state = .retry(au: au, attempt: currentRetries + 1, reason: "Cross-talk: \(names)")
            if (try? await Task.sleep(nanoseconds: 1_500_000_000)) == nil { return .cancelled }
            return .retryNeeded
        case .insufficientData:
            state = .retry(au: au, attempt: currentRetries + 1, reason: "Za mało próbek")
            if (try? await Task.sleep(nanoseconds: 1_500_000_000)) == nil { return .cancelled }
            return .retryNeeded
        }
    }
}
