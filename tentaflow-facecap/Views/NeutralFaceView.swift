// =============================================================================
// Plik: NeutralFaceView.swift
// Opis: 3-sekundowe utrzymanie neutralnej miny z walidacją (wszystkie AU < 0.05).
// =============================================================================

import SwiftUI
import ARKit
import Combine
import Shared

/// Lokalny koordynator ARKit — czyta wagi 52 blendshape i publikuje sumę.
@MainActor
final class NeutralFaceCoordinator: NSObject, ObservableObject, ARSessionDelegate {

    @Published var currentMax: Float = 1.0
    @Published var holdFractionDone: Double = 0
    @Published var succeeded: Bool = false
    @Published var running: Bool = false

    private let session = ARSession()
    private let holdRequired: TimeInterval = 3.0
    private var holdStart: Date?

    override init() { super.init() }

    func start() {
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = true
        session.delegate = self
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        running = true
        succeeded = false
        holdStart = nil
        holdFractionDone = 0
    }

    func stop() {
        session.pause()
        running = false
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        let blendshapes = face.blendShapes
        var maxVal: Float = 0
        for (_, value) in blendshapes {
            let v = value.floatValue
            if v > maxVal { maxVal = v }
        }
        Task { @MainActor in
            self.currentMax = maxVal
            self.evaluate(maxVal: maxVal)
        }
    }

    private func evaluate(maxVal: Float) {
        let threshold: Float = 0.05
        if maxVal < threshold {
            if holdStart == nil {
                holdStart = Date()
            }
            let elapsed = Date().timeIntervalSince(holdStart ?? Date())
            holdFractionDone = min(1.0, elapsed / holdRequired)
            if elapsed >= holdRequired {
                succeeded = true
                stop()
            }
        } else {
            holdStart = nil
            holdFractionDone = 0
        }
    }
}

struct NeutralFaceView: View {

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var coord = NeutralFaceCoordinator()

    var body: some View {
        VStack(spacing: 24) {
            Text(NSLocalizedString("neutral.title", comment: ""))
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text(NSLocalizedString("neutral.desc", comment: ""))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 12)
                    .frame(width: 220, height: 220)
                Circle()
                    .trim(from: 0, to: CGFloat(coord.holdFractionDone))
                    .stroke(Color.accentColor,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 220, height: 220)
                Text(String(format: "%.0f%%", coord.holdFractionDone * 100))
                    .font(.largeTitle.monospacedDigit().bold())
            }

            VStack {
                Text(NSLocalizedString("neutral.max", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(coord.currentMax))
                    .tint(coord.currentMax < 0.05 ? .green : .orange)
                    .frame(maxWidth: 260)
            }

            Spacer()

            if coord.succeeded {
                Button(NSLocalizedString("neutral.continue", comment: "")) {
                    environment.session.neutralValidated = true
                    router.advance()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
            } else {
                Text(NSLocalizedString("neutral.hint", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button(NSLocalizedString("common.back", comment: "")) {
                router.back()
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
        }
        .onAppear { coord.start() }
        .onDisappear { coord.stop() }
    }
}
