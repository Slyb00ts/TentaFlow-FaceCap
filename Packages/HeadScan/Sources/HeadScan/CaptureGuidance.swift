// =============================================================================
// Plik: CaptureGuidance.swift
// Opis: Logika promptów UI dla użytkownika podczas skanu oparta o feedback z ObjectCaptureSession.
// =============================================================================

import Foundation
import RealityKit

/// Pojedynczy komunikat dla użytkownika.
public struct GuidancePrompt: Sendable, Equatable {
    public enum Severity: Sendable, Equatable {
        case info
        case warning
        case critical
    }

    public let message: String
    public let severity: Severity
    public let progress: Float

    public init(message: String, severity: Severity, progress: Float) {
        self.message = message
        self.severity = severity
        self.progress = progress
    }
}

/// Generator komunikatów guidance oparty o feedback ObjectCaptureSession (iOS 17+).
@available(iOS 17.0, *)
public struct CaptureGuidance: Sendable {
    /// Docelowa liczba klatek referencyjnych.
    public let targetFrameCount: Int

    public init(targetFrameCount: Int = 50) {
        self.targetFrameCount = targetFrameCount
    }

    /// Wyprowadza komunikat UI z zestawu feedbacków ObjectCaptureSession.
    public func prompt(
        for feedback: Set<ObjectCaptureSession.Feedback>,
        capturedFrameCount: Int
    ) -> GuidancePrompt {
        let progress = min(1.0, Float(capturedFrameCount) / Float(max(1, targetFrameCount)))

        if feedback.contains(.objectNotFlippable) {
            return GuidancePrompt(
                message: "Ta głowa nie nadaje się do obrotu — przesuń urządzenie wokół obiektu.",
                severity: .critical,
                progress: progress
            )
        }
        if feedback.contains(.environmentLowLight) {
            return GuidancePrompt(
                message: "Za mało światła — podejdź bliżej okna lub włącz oświetlenie.",
                severity: .warning,
                progress: progress
            )
        }
        if feedback.contains(.environmentTooDark) {
            return GuidancePrompt(
                message: "Zbyt ciemno — fotogrametria nie zadziała.",
                severity: .critical,
                progress: progress
            )
        }
        if feedback.contains(.movingTooFast) {
            return GuidancePrompt(
                message: "Zbyt szybki ruch — obracaj głowę wolniej.",
                severity: .warning,
                progress: progress
            )
        }
        if feedback.contains(.outOfFieldOfView) {
            return GuidancePrompt(
                message: "Głowa poza kadrem — wycentruj twarz w ramce.",
                severity: .warning,
                progress: progress
            )
        }
        if feedback.contains(.objectTooFar) {
            return GuidancePrompt(
                message: "Za daleko — podejdź bliżej.",
                severity: .info,
                progress: progress
            )
        }
        if feedback.contains(.objectTooClose) {
            return GuidancePrompt(
                message: "Za blisko — oddal się o 30 cm.",
                severity: .info,
                progress: progress
            )
        }
        if capturedFrameCount < targetFrameCount / 4 {
            return GuidancePrompt(
                message: "Obróć głowę w lewo o 30 stopni.",
                severity: .info,
                progress: progress
            )
        } else if capturedFrameCount < targetFrameCount / 2 {
            return GuidancePrompt(
                message: "Teraz powoli w prawo.",
                severity: .info,
                progress: progress
            )
        } else if capturedFrameCount < (targetFrameCount * 3) / 4 {
            return GuidancePrompt(
                message: "Unieś podbródek i pokaż szyję.",
                severity: .info,
                progress: progress
            )
        } else if capturedFrameCount < targetFrameCount {
            return GuidancePrompt(
                message: "Teraz pochyl głowę lekko w dół.",
                severity: .info,
                progress: progress
            )
        }
        return GuidancePrompt(
            message: "Skanowanie zakończone — przetwarzanie modelu.",
            severity: .info,
            progress: 1.0
        )
    }
}
