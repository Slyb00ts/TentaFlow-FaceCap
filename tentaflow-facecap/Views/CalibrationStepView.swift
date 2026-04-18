// =============================================================================
// Plik: CalibrationStepView.swift
// Opis: Jeden krok kalibracji AU — prompt, live bar, target bar, akceptuj/pomiń/powtórz.
// =============================================================================

import SwiftUI
import ARKit
import Combine
import Shared
import Export

/// Metadane pojedynczego AU — ładowane z `ARKitBlendshapeGuide.json`.
struct BlendshapeGuideEntry: Codable, Identifiable, Equatable {

    let auIndex: Int
    let arkitKey: String
    let namePL: String
    let icon: String
    let targetThreshold: Float
    let correlationGroup: Int

    var id: Int { auIndex }

    enum CodingKeys: String, CodingKey {
        case auIndex = "au_index"
        case arkitKey = "arkit_key"
        case namePL = "name_pl"
        case icon
        case targetThreshold = "target_threshold"
        case correlationGroup = "correlation_group"
    }
}

/// Ładowarka pliku `ARKitBlendshapeGuide.json`.
enum BlendshapeGuideLoader {

    static func loadAll() -> [BlendshapeGuideEntry] {
        guard let url = Bundle.main.url(forResource: "ARKitBlendshapeGuide", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([BlendshapeGuideEntry].self, from: data) else {
            AppLog.calibration.error("Nie udało się wczytać ARKitBlendshapeGuide.json.")
            return []
        }
        return decoded.sorted { $0.auIndex < $1.auIndex }
    }
}

/// Koordynator AR dla kalibracji pojedynczego AU. Czyta live wartość
/// wskazanego blendshape i publikuje ją jako `currentValue`.
@MainActor
final class CalibrationStepCoordinator: NSObject, ObservableObject, ARSessionDelegate {

    @Published var currentValue: Float = 0
    @Published var peakValue: Float = 0

    private let session = ARSession()
    private var targetKey: ARFaceAnchor.BlendShapeLocation?

    override init() { super.init() }

    func start(for arkitKey: String) {
        guard ARFaceTrackingConfiguration.isSupported else { return }
        targetKey = ARFaceAnchor.BlendShapeLocation(rawValue: arkitKey)
        let config = ARFaceTrackingConfiguration()
        session.delegate = self
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
    }

    func resetPeak() {
        peakValue = 0
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first,
              let key = targetKey,
              let value = face.blendShapes[key]?.floatValue else { return }
        Task { @MainActor in
            self.currentValue = value
            if value > self.peakValue { self.peakValue = value }
        }
    }
}

struct CalibrationStepView: View {

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var coord = CalibrationStepCoordinator()

    let auIndex: Int
    @State private var guide: [BlendshapeGuideEntry] = []
    @State private var showCheckpointAlert = false

    private var currentEntry: BlendshapeGuideEntry? {
        guide.first(where: { $0.auIndex == auIndex })
    }

    var body: some View {
        VStack(spacing: 18) {
            if let entry = currentEntry {
                HStack {
                    Text("\(auIndex + 1) / 52")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProgressView(value: Double(auIndex + 1), total: 52)
                        .tint(.accent)
                        .frame(maxWidth: 160)
                }
                .padding(.horizontal)

                Image(systemName: entry.icon.isEmpty ? "face.smiling" : entry.icon)
                    .font(.system(size: 52))
                    .foregroundStyle(.accent)

                Text(entry.namePL)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(entry.arkitKey)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("calib.step.current", comment: ""))
                        .font(.caption)
                    ProgressView(value: Double(coord.currentValue))
                        .tint(progressColor(entry: entry))

                    Text(String(format: NSLocalizedString("calib.step.peak", comment: ""), coord.peakValue))
                        .font(.caption)
                    ProgressView(value: Double(coord.peakValue))
                        .tint(.orange)

                    Text(String(format: NSLocalizedString("calib.step.target", comment: ""), entry.targetThreshold))
                        .font(.caption)
                    ProgressView(value: Double(entry.targetThreshold))
                        .tint(.green.opacity(0.5))
                }
                .padding(.horizontal)

                Spacer()

                HStack(spacing: 10) {
                    Button(NSLocalizedString("calib.step.skip", comment: "")) {
                        environment.session.skippedAU.insert(auIndex)
                        proceed()
                    }
                    .buttonStyle(.bordered)

                    Button(NSLocalizedString("calib.step.retry", comment: "")) {
                        coord.resetPeak()
                    }
                    .buttonStyle(.bordered)

                    Button(NSLocalizedString("calib.step.accept", comment: "")) {
                        accept(entry: entry)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(coord.peakValue < entry.targetThreshold)
                }
                .padding(.horizontal)
            } else {
                ProgressView()
            }
        }
        .padding(.vertical)
        .onAppear {
            if guide.isEmpty { guide = BlendshapeGuideLoader.loadAll() }
            if let entry = currentEntry { coord.start(for: entry.arkitKey) }
        }
        .onDisappear { coord.stop() }
        .onChange(of: auIndex) { _, _ in
            coord.stop()
            coord.resetPeak()
            if let entry = currentEntry { coord.start(for: entry.arkitKey) }
        }
        .alert(NSLocalizedString("calib.checkpoint.title", comment: ""),
               isPresented: $showCheckpointAlert) {
            Button(NSLocalizedString("calib.checkpoint.continue", comment: "")) {
                router.advance()
            }
            Button(NSLocalizedString("common.pause", comment: ""), role: .cancel) {}
        } message: {
            Text(String(format: NSLocalizedString("calib.checkpoint.msg", comment: ""), auIndex + 1))
        }
    }

    private func progressColor(entry: BlendshapeGuideEntry) -> Color {
        coord.currentValue >= entry.targetThreshold ? .green : .accent
    }

    private func accept(entry: BlendshapeGuideEntry) {
        environment.session.acceptedAU.insert(auIndex)
        // Zapisujemy syntetyczną deltę: wektor jednostkowy × peak w osi Y dla testu.
        // Realny algorytm policzyłby różnicę wierzchołków z ARKit geometry.
        let count = environment.session.scannedMeshVertices.count
        let peak = coord.peakValue
        let deltas = (0..<count).map { i -> Vec3 in
            let phase = Float(i) / Float(max(1, count))
            return Vec3(0, 0.001 * peak * sin(phase * .pi), 0)
        }
        environment.session.calibratedDeltas[auIndex] = deltas
        proceed()
    }

    private func proceed() {
        // Checkpoint co 13 AU.
        if (auIndex + 1) % 13 == 0 && auIndex + 1 < 52 {
            showCheckpointAlert = true
        } else {
            router.advance()
        }
    }
}
