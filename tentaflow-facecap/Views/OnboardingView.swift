// =============================================================================
// Plik: OnboardingView.swift
// Opis: Splash + trzy punkty opisu + prośba o uprawnienia + sprawdzenie TrueDepth.
// =============================================================================

import SwiftUI
import ARKit
import Shared

struct OnboardingView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var router: AppRouter

    @State private var showUnsupportedAlert = false
    @State private var showPermissionsAlert = false
    @State private var isRequestingPermissions = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.02, blue: 0.15), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "face.dashed.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .foregroundStyle(Color.accentColor)

                Text(NSLocalizedString("onboarding.title", comment: ""))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("onboarding.subtitle", comment: ""))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 16) {
                    bulletRow(icon: "rotate.3d", text: NSLocalizedString("onboarding.point1", comment: ""))
                    bulletRow(icon: "face.smiling", text: NSLocalizedString("onboarding.point2", comment: ""))
                    bulletRow(icon: "paperplane.fill", text: NSLocalizedString("onboarding.point3", comment: ""))
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                Spacer()

                Button {
                    startFlow()
                } label: {
                    HStack {
                        if isRequestingPermissions {
                            ProgressView().tint(.white)
                        }
                        Text(NSLocalizedString("onboarding.cta", comment: ""))
                            .font(.title3.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .disabled(isRequestingPermissions)

                Text(NSLocalizedString("onboarding.privacy", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 12)
            }
            .padding(.horizontal)
        }
        .alert(NSLocalizedString("alert.unsupported.title", comment: ""),
               isPresented: $showUnsupportedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(NSLocalizedString("alert.unsupported.msg", comment: ""))
        }
        .alert(NSLocalizedString("alert.permissions.title", comment: ""),
               isPresented: $showPermissionsAlert) {
            Button(NSLocalizedString("alert.openSettings", comment: "")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(NSLocalizedString("alert.permissions.msg", comment: ""))
        }
    }

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(.accent)
                .font(.title3)
                .frame(width: 28)
            Text(text)
                .foregroundStyle(.white)
                .font(.body)
        }
    }

    private func startFlow() {
        guard ARFaceTrackingConfiguration.isSupported else {
            showUnsupportedAlert = true
            return
        }
        Task {
            isRequestingPermissions = true
            await environment.requestPermissions()
            isRequestingPermissions = false
            if environment.cameraAuthorized && environment.microphoneAuthorized {
                router.advance()
            } else {
                showPermissionsAlert = true
            }
        }
    }
}
