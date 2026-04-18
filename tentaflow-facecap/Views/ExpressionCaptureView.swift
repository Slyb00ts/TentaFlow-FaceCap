// =============================================================================
// Plik: ExpressionCaptureView.swift
// Opis: Ekran fazy F9 — 20 snapshotów wyrazów twarzy z prowadzeniem usera,
//       live podglądem wag ARKit oraz zapisem jakości per preset.
// =============================================================================

import SwiftUI
import ARKit
import Combine
import Shared
import FaceCalibration
import PerformanceCapture

// MARK: — Koordynator ARKit dla fazy snapshotów

/// Lokalny koordynator AR dla ekranu snapshotów. Publikuje aktualny wektor 52
/// wag (indeksowany wg `ArkitAU.rawValue`) i udostępnia `AsyncStream` dla
/// aktora `ExpressionSnapshotCapturer`.
@MainActor
final class ExpressionCaptureCoordinator: NSObject, ObservableObject, ARSessionDelegate {

    /// Ostatnio zaobserwowany wektor 52 wag AU.
    @Published var currentWeights: [Float] = [Float](repeating: 0, count: 52)

    /// Sesja AR.
    private let session = ARSession()

    /// Strumienie konsumujące klatki AU — każdy zapis (capture) rejestruje tymczasowy subskrybentów.
    private var streamContinuations: [UUID: AsyncStream<[Float]>.Continuation] = [:]

    /// Czy AR jest aktualnie uruchomione.
    @Published var running: Bool = false

    override init() { super.init() }

    func start() {
        guard ARFaceTrackingConfiguration.isSupported else {
            AppLog.perf.error("ARKit Face Tracking nieobsługiwane na tym urządzeniu.")
            return
        }
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        session.delegate = self
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        running = true
    }

    func stop() {
        for (_, continuation) in streamContinuations {
            continuation.finish()
        }
        streamContinuations.removeAll()
        session.pause()
        running = false
    }

    /// Zwraca świeży `AsyncStream` klatek 52 wag — każde wywołanie daje niezależny
    /// strumień. Strumień zamyka się po wywołaniu `finishStream(_:)` lub po `stop()`.
    func makeFrameStream() -> (id: UUID, stream: AsyncStream<[Float]>) {
        let id = UUID()
        let stream = AsyncStream<[Float]> { continuation in
            streamContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.streamContinuations.removeValue(forKey: id)
                }
            }
        }
        return (id, stream)
    }

    /// Jawnie kończy strumień o podanym identyfikatorze.
    func finishStream(_ id: UUID) {
        if let c = streamContinuations.removeValue(forKey: id) {
            c.finish()
        }
    }

    // MARK: — ARSessionDelegate

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let face = anchor as? ARFaceAnchor else { continue }
            let blendshapes = face.blendShapes
            var row = [Float](repeating: 0, count: 52)
            for au in ArkitAU.allCases {
                if let v = blendshapes[au.arkitKey]?.floatValue {
                    row[au.rawValue] = v
                }
            }
            Task { @MainActor [row] in
                self.currentWeights = row
                for (_, continuation) in self.streamContinuations {
                    continuation.yield(row)
                }
            }
        }
    }
}

// MARK: — Widok główny

struct ExpressionCaptureView: View {

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var environment: AppEnvironment

    @StateObject private var coord = ExpressionCaptureCoordinator()

    /// Aktualnie wybrany preset.
    @State private var selectedPreset: ExpressionPreset = .happy

    /// Stan przechwytu — idle / countdown / capturing / preview.
    @State private var captureState: CaptureState = .idle

    /// Ostatni wynik rejestracji — używany do podglądu po capture.
    @State private var lastResult: ExpressionSnapshotCapturer.CaptureResult?

    /// Komunikat błędu (np. brak ARKit, słaba jakość snapshotu).
    @State private var errorMessage: String?

    /// Stan rozwinięcia kategorii w liście (domyślnie pierwsza otwarta).
    @State private var expandedCategories: Set<ExpressionCategory> = [.basic]

    private let capturer = ExpressionSnapshotCapturer()

    private enum CaptureState: Equatable {
        case idle
        case countdown(remaining: Int)
        case capturing
        case preview
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    detailPanel
                    Divider().padding(.vertical, 4)
                    categoryList
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            footerBar
        }
        .onAppear {
            coord.start()
        }
        .onDisappear {
            coord.stop()
        }
        .alert(
            NSLocalizedString("expr.error.title", comment: ""),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: — Banner postępu

    private var header: some View {
        let stats = environment.expressionLibrary.completionCount()
        let total = ExpressionPreset.allCases.count
        let fraction = total > 0 ? Double(stats.completed) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(NSLocalizedString("expr.title", comment: ""))
                    .font(.title3.bold())
                Spacer()
                Text(String(
                    format: NSLocalizedString("expr.progress.counter", comment: ""),
                    stats.completed, total
                ))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
                .tint(stats.completed == total ? .green : .accentColor)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: — Detal wybranego presetu

    private var detailPanel: some View {
        let library = environment.expressionLibrary
        let isStored = library.has(preset: selectedPreset)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selectedPreset.iconSymbolName)
                    .font(.title2)
                    .foregroundStyle(.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedPreset.titleForUI)
                        .font(.title3.bold())
                    Text(String(
                        format: NSLocalizedString("expr.difficulty", comment: ""),
                        selectedPreset.difficulty
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedPreset.isRequired {
                    Label(
                        NSLocalizedString("expr.badge.required", comment: ""),
                        systemImage: "star.fill"
                    )
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.yellow)
                }
            }

            Text(selectedPreset.instructionForUser)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if !selectedPreset.expectedDominantAUs.isEmpty {
                expectedAUBars
            }

            captureControls

            if let result = lastResult, captureState == .preview {
                resultPreview(result: result)
            } else if isStored, captureState == .idle {
                storedSnapshotInfo
            }
        }
    }

    private var expectedAUBars: some View {
        let weights = coord.currentWeights
        return VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("expr.expected.aus", comment: ""))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(selectedPreset.expectedDominantAUs, id: \.self) { idx in
                if let au = ArkitAU(rawValue: idx) {
                    let value = idx < weights.count ? weights[idx] : 0
                    HStack(spacing: 8) {
                        Text(au.nameForUI)
                            .font(.caption)
                            .frame(maxWidth: 170, alignment: .leading)
                        ProgressView(value: Double(value))
                            .tint(value >= 0.3 ? .green : .orange)
                        Text(String(format: "%.2f", value))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var captureControls: some View {
        HStack {
            switch captureState {
            case .idle:
                Button(NSLocalizedString("expr.record", comment: "")) {
                    startCountdown()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            case .countdown(let remaining):
                Text(String(remaining))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.accent)
            case .capturing:
                HStack(spacing: 8) {
                    ProgressView()
                    Text(NSLocalizedString("expr.capturing", comment: ""))
                }
                .frame(maxWidth: .infinity)
            case .preview:
                HStack(spacing: 10) {
                    Button(NSLocalizedString("expr.save", comment: "")) {
                        saveCurrentResult()
                    }
                    .buttonStyle(.borderedProminent)
                    Button(NSLocalizedString("expr.retry", comment: "")) {
                        lastResult = nil
                        captureState = .idle
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func resultPreview(result: ExpressionSnapshotCapturer.CaptureResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(NSLocalizedString("expr.quality", comment: ""))
                    .font(.caption.bold())
                Spacer()
                Text(String(format: "%.0f%%", Double(result.snapshot.qualityScore) * 100.0))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(result.snapshot.qualityScore >= 0.5 ? .green : .orange)
            }
            ProgressView(value: Double(result.snapshot.qualityScore))
                .tint(result.snapshot.qualityScore >= 0.5 ? .green : .orange)
            Text(String(
                format: NSLocalizedString("expr.frames", comment: ""),
                result.framesConsumed
            ))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var storedSnapshotInfo: some View {
        let snap = environment.expressionLibrary.snapshot(for: selectedPreset)
        return HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            Text(String(
                format: NSLocalizedString("expr.stored.quality", comment: ""),
                Double(snap?.qualityScore ?? 0) * 100.0
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Button(NSLocalizedString("expr.remove", comment: "")) {
                environment.expressionLibrary.remove(preset: selectedPreset)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }

    // MARK: — Lista kategorii

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ExpressionCategory.allCases, id: \.self) { category in
                let presetsInCategory = ExpressionPreset.allCases.filter { $0.category == category }
                let completedInCategory = presetsInCategory.filter { environment.expressionLibrary.has(preset: $0) }.count

                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedCategories.contains(category) },
                        set: { expanded in
                            if expanded {
                                expandedCategories.insert(category)
                            } else {
                                expandedCategories.remove(category)
                            }
                        }
                    )
                ) {
                    VStack(spacing: 2) {
                        ForEach(presetsInCategory, id: \.self) { preset in
                            presetRow(preset: preset)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Text(category.titleForUI).font(.headline)
                        Spacer()
                        Text("\(completedInCategory)/\(presetsInCategory.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(
                                completedInCategory == presetsInCategory.count ? .green : .secondary
                            )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func presetRow(preset: ExpressionPreset) -> some View {
        let stored = environment.expressionLibrary.has(preset: preset)
        let isSelected = preset == selectedPreset
        return Button {
            selectedPreset = preset
            captureState = .idle
            lastResult = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: preset.iconSymbolName)
                    .foregroundStyle(.accent)
                    .frame(width: 22)
                Text(preset.titleForUI)
                    .foregroundStyle(.primary)
                Spacer()
                if preset.isRequired {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
                if stored {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: — Pasek nawigacji

    private var footerBar: some View {
        let requiredDone = environment.expressionLibrary.isRequiredComplete()
        return HStack(spacing: 10) {
            Button(NSLocalizedString("common.back", comment: "")) {
                router.back()
            }
            .buttonStyle(.bordered)

            Button(NSLocalizedString("expr.skip", comment: "")) {
                router.advance()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                router.advance()
            } label: {
                Text(NSLocalizedString("expr.next", comment: ""))
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!requiredDone)
        }
        .padding()
        .background(.bar)
    }

    // MARK: — Logika rejestracji

    private func startCountdown() {
        // Zabezpieczenie: jeśli ARKit nie działa, pokazujemy błąd zamiast głuchego capture.
        guard coord.running else {
            errorMessage = NSLocalizedString("expr.error.ar", comment: "")
            return
        }
        lastResult = nil
        captureState = .countdown(remaining: 3)
        Task { @MainActor in
            // Odliczanie 3 → 2 → 1 co 1 s. W każdym kroku sprawdzamy, czy user
            // nie przerwał procedury (stan mógł się zmienić np. po wybraniu innego presetu).
            for step in stride(from: 3, through: 1, by: -1) {
                guard case .countdown = captureState else { return }
                captureState = .countdown(remaining: step)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard case .countdown = captureState else { return }
            captureState = .capturing
            performCapture()
        }
    }

    private func performCapture() {
        let (id, stream) = coord.makeFrameStream()
        let preset = selectedPreset
        Task {
            defer { coord.finishStream(id) }
            do {
                let result = try await capturer.capture(preset: preset, source: stream)
                await MainActor.run {
                    self.lastResult = result
                    self.captureState = .preview
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.captureState = .idle
                }
            }
        }
    }

    private func saveCurrentResult() {
        guard let result = lastResult else { return }
        environment.expressionLibrary.save(result.snapshot)
        lastResult = nil
        captureState = .idle
        advanceToNextUnstored()
    }

    /// Po zapisaniu presetu automatycznie przełączamy UI na następny niezapisany
    /// preset (z tej samej kategorii, a jeśli wszystkie zapisane — szukamy dalej).
    private func advanceToNextUnstored() {
        let all = ExpressionPreset.allCases
        guard let startIndex = all.firstIndex(of: selectedPreset) else { return }
        let rotated = all[(startIndex + 1)...] + all[..<startIndex]
        if let next = rotated.first(where: { !environment.expressionLibrary.has(preset: $0) }) {
            selectedPreset = next
            expandedCategories.insert(next.category)
        }
    }
}
