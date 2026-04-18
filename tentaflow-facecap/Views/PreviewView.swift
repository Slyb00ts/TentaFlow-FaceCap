// =============================================================================
// Plik: PreviewView.swift
// Opis: Podgląd twarzy — 52 slidery + presety emocji + odtwarzanie klipu performance.
// =============================================================================

import SwiftUI
import RealityKit
import Shared
import Export

/// Proste presety emocji — aplikują sensowne wartości wag do predefiniowanych AU.
enum EmotionPreset: String, CaseIterable, Identifiable {
    case neutral, happy, sad, angry, surprised

    var id: String { rawValue }

    /// Zwraca wagi (52 × Float) dla presetu.
    func weights() -> [Float] {
        var w = [Float](repeating: 0, count: 52)
        switch self {
        case .neutral:
            break
        case .happy:
            w[safe: 42] = 0.8    // mouthSmileLeft
            w[safe: 43] = 0.8    // mouthSmileRight
            w[safe: 4] = 0.3     // browInnerUp
            w[safe: 18] = 0.3    // eyeSquintLeft
            w[safe: 19] = 0.3    // eyeSquintRight
        case .sad:
            w[safe: 28] = 0.7    // mouthFrownLeft
            w[safe: 29] = 0.7    // mouthFrownRight
            w[safe: 0] = 0.5     // browDownLeft
            w[safe: 1] = 0.5     // browDownRight
        case .angry:
            w[safe: 0] = 0.9
            w[safe: 1] = 0.9
            w[safe: 33] = 0.5    // mouthLowerDownLeft
            w[safe: 34] = 0.5    // mouthLowerDownRight
            w[safe: 24] = 0.4    // jawOpen
        case .surprised:
            w[safe: 2] = 0.9     // browInnerUp
            w[safe: 20] = 0.8    // eyeWideLeft
            w[safe: 21] = 0.8    // eyeWideRight
            w[safe: 24] = 0.7    // jawOpen
        }
        return w
    }
}

private extension Array where Element == Float {
    subscript(safe index: Int) -> Element {
        get { indices.contains(index) ? self[index] : 0 }
        set { if indices.contains(index) { self[index] = newValue } }
    }
}

struct PreviewView: View {

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var environment: AppEnvironment

    @State private var weights: [Float] = [Float](repeating: 0, count: 52)
    @State private var selectedPreset: EmotionPreset = .neutral
    @State private var playingClipIndex: Int? = nil
    @State private var playbackFrame: Int = 0
    @State private var playbackTimer: Timer?

    private let guide: [BlendshapeGuideEntry] = BlendshapeGuideLoader.loadAll()

    var body: some View {
        VStack(spacing: 10) {
            Text(NSLocalizedString("preview.title", comment: ""))
                .font(.title2.bold())

            // Podgląd 3D — renderujemy mesh z aplikowanymi wagami (uproszczenie:
            // pokazujemy sferę z kolorem, który mruga przy sumie wag).
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.4))
                RealityView { content in
                    let mesh = MeshResource.generateSphere(radius: 0.1)
                    let intensity = Float(weights.reduce(0, +) / Float(weights.count))
                    let color = UIColor(hue: 0.7, saturation: 0.4, brightness: 0.7 + CGFloat(intensity) * 0.3, alpha: 1)
                    let mat = SimpleMaterial(color: color, isMetallic: false)
                    let entity = ModelEntity(mesh: mesh, materials: [mat])
                    let anchor = AnchorEntity(world: .zero)
                    anchor.addChild(entity)
                    content.add(anchor)
                }
                .aspectRatio(1.6, contentMode: .fit)
            }
            .padding(.horizontal)

            Picker(NSLocalizedString("preview.preset", comment: ""), selection: $selectedPreset) {
                ForEach(EmotionPreset.allCases) { preset in
                    Text(NSLocalizedString("preset.\(preset.rawValue)", comment: ""))
                        .tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedPreset) { _, new in
                weights = new.weights()
            }
            .padding(.horizontal)

            // Lista klipów performance do odtworzenia.
            if !environment.session.performanceClips.isEmpty {
                HStack {
                    Text(NSLocalizedString("preview.play", comment: ""))
                        .font(.headline)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { playingClipIndex ?? -1 },
                        set: { newVal in
                            if newVal < 0 { stopPlayback() }
                            else { startPlayback(index: newVal) }
                        }
                    )) {
                        Text(NSLocalizedString("preview.play.none", comment: "")).tag(-1)
                        ForEach(Array(environment.session.performanceClips.enumerated()), id: \.offset) { idx, clip in
                            Text(clip.name).tag(idx)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(0..<min(weights.count, guide.count), id: \.self) { i in
                        sliderRow(index: i)
                    }
                }
                .padding(.horizontal)
            }

            HStack {
                Button(NSLocalizedString("common.back", comment: "")) {
                    router.back()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button(NSLocalizedString("preview.export.cta", comment: "")) {
                    router.advance()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .onDisappear { stopPlayback() }
    }

    private func sliderRow(index: Int) -> some View {
        let name = guide[index].namePL
        return HStack {
            Text(name).font(.caption).frame(width: 110, alignment: .leading)
            Slider(value: Binding(
                get: { Double(weights[safe: index]) },
                set: { weights[safe: index] = Float($0) }
            ), in: 0...1)
            Text(String(format: "%.2f", weights[safe: index]))
                .font(.caption.monospacedDigit())
                .frame(width: 40)
        }
    }

    private func startPlayback(index: Int) {
        guard environment.session.performanceClips.indices.contains(index) else { return }
        playingClipIndex = index
        playbackFrame = 0
        stopPlayback(resetTimer: true)
        let clip = environment.session.performanceClips[index]
        let interval = 1.0 / Double(max(1, clip.fps))
        playbackTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
            DispatchQueue.main.async {
                guard playbackFrame < clip.weights.count else {
                    t.invalidate()
                    playbackTimer = nil
                    playingClipIndex = nil
                    return
                }
                weights = clip.weights[playbackFrame]
                playbackFrame += 1
            }
        }
    }

    private func stopPlayback(resetTimer: Bool = false) {
        playbackTimer?.invalidate()
        playbackTimer = nil
        if resetTimer == false {
            playingClipIndex = nil
        }
    }
}
