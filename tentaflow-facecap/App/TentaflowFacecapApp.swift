// =============================================================================
// Plik: TentaflowFacecapApp.swift
// Opis: Punkt wejścia aplikacji SwiftUI — wstrzykuje AppEnvironment + AppRouter.
// =============================================================================

import SwiftUI
import Shared

@main
struct TentaflowFacecapApp: App {

    @StateObject private var environment: AppEnvironment
    @StateObject private var router: AppRouter

    init() {
        // DI — tworzymy raz, trzymamy w StateObject aby przeżyły rebuild hierarchii.
        let env = AppEnvironment()
        let r = AppRouter()
        _environment = StateObject(wrappedValue: env)
        _router = StateObject(wrappedValue: r)
        AppLog.app.info("App init: \(DeviceCapabilities.deviceModel, privacy: .public) / \(DeviceCapabilities.systemVersion, privacy: .public)")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(router)
                .preferredColorScheme(.dark)
        }
    }
}

/// Root widok — przełącza ekrany na podstawie `AppRouter.currentStep`.
struct RootView: View {

    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack {
            currentScreen
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: router.currentStep)
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch router.currentStep {
        case .onboarding:
            OnboardingView()
        case .headScanBrief:
            HeadScanBriefView()
        case .headScanCapture:
            HeadScanCaptureView()
        case .headScanPreview:
            HeadScanPreviewView()
        case .calibrationBrief:
            CalibrationBriefView()
        case .neutralFace:
            NeutralFaceView()
        case .calibrationStep(let index):
            CalibrationStepView(auIndex: index)
        case .performanceCapture:
            PerformanceCaptureView()
        case .preview:
            PreviewView()
        case .export:
            ExportView()
        case .transfer:
            TransferProgressView()
        case .done:
            DoneView()
        }
    }
}

/// Prosty ekran końcowy.
private struct DoneView: View {

    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundStyle(.green)
            Text("Gotowe!")
                .font(.largeTitle.bold())
            Text("Profil twarzy został zapisany i przesłany.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Zacznij od nowa") {
                router.reset()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}
