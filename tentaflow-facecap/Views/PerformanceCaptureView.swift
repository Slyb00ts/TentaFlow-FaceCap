// =============================================================================
// Plik: PerformanceCaptureView.swift
// Opis: REC + timeline nagrywania klipów performance (max 5 × 60 s).
// =============================================================================

import SwiftUI
import ARKit
import AVFoundation
import Combine
import Shared
import Export

/// Koordynator nagrywania klipu performance. Synchronicznie zbiera 52 wagi na
/// klatkę (z ARKit) oraz audio PCM float32 mono 16 kHz przez AVAudioEngine.
@MainActor
final class PerformanceRecorder: NSObject, ObservableObject, ARSessionDelegate {

    @Published var isRecording: Bool = false
    @Published var elapsed: TimeInterval = 0
    @Published var framesCaptured: Int = 0
    @Published var clips: [PerformanceClip] = []

    private let maxDuration: TimeInterval = 60
    private let maxClipCount: Int = 5

    private let arSession = ARSession()
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private let targetSampleRate: Double = 16_000

    private var startDate: Date?
    private var tickTimer: AnyCancellable?
    private var currentWeights: [[Float]] = []
    private var currentAudio: [Float] = []
    private var pendingClipName: String = "perf_01"

    override init() { super.init() }

    var canRecordMore: Bool { clips.count < maxClipCount }

    func startRecording(name: String) {
        guard canRecordMore, !isRecording else { return }
        pendingClipName = name
        currentWeights = []
        currentAudio = []
        framesCaptured = 0
        elapsed = 0
        startDate = Date()

        let config = ARFaceTrackingConfiguration()
        arSession.delegate = self
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])

        setupAudio()

        tickTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }

        isRecording = true
        AppLog.calibration.info("Performance REC start: \(name, privacy: .public)")
    }

    func stopRecording() {
        guard isRecording else { return }
        tickTimer?.cancel()
        tickTimer = nil
        arSession.pause()
        audioEngine?.stop()
        audioEngine = nil
        audioConverter = nil
        isRecording = false

        let clip = PerformanceClip(
            name: pendingClipName,
            fps: 60,
            weights: currentWeights,
            audioPCM: currentAudio.isEmpty ? nil : currentAudio
        )
        clips.append(clip)
        AppLog.calibration.info("Performance REC stop: frames=\(self.currentWeights.count), audio=\(self.currentAudio.count)")
    }

    func deleteClip(at index: Int) {
        guard clips.indices.contains(index) else { return }
        clips.remove(at: index)
    }

    // MARK: — ARKit

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard isRecording,
              let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }

        // Mapujemy blendshape dictionary na uporządkowaną listę 52 wartości.
        let orderedKeys = ARKitBlendshapeOrder.allKeys
        var row = [Float](repeating: 0, count: 52)
        for (idx, key) in orderedKeys.enumerated() where idx < 52 {
            row[idx] = face.blendShapes[key]?.floatValue ?? 0
        }
        Task { @MainActor in
            self.currentWeights.append(row)
            self.framesCaptured = self.currentWeights.count
        }
    }

    // MARK: — Audio

    private func setupAudio() {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            return
        }
        self.audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.audioConverter else { return }
            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let outCap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let outBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outCap
            ) else { return }
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, status in
                status.pointee = .haveData
                return buffer
            }
            converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
            if let error {
                AppLog.calibration.error("Audio convert: \(error.localizedDescription, privacy: .public)")
                return
            }
            if let channelData = outBuffer.floatChannelData?[0] {
                let n = Int(outBuffer.frameLength)
                let slice = Array(UnsafeBufferPointer(start: channelData, count: n))
                Task { @MainActor in
                    self.currentAudio.append(contentsOf: slice)
                }
            }
        }
        do {
            try engine.start()
            self.audioEngine = engine
        } catch {
            AppLog.calibration.error("AudioEngine start: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: — Timer

    private func tick() {
        guard let start = startDate else { return }
        elapsed = Date().timeIntervalSince(start)
        if elapsed >= maxDuration {
            stopRecording()
        }
    }
}

/// Uporządkowane klucze ARKit w kolejności zgodnej z indeksacją Apple (52 AU).
enum ARKitBlendshapeOrder {
    static let allKeys: [ARFaceAnchor.BlendShapeLocation] = [
        .browDownLeft, .browDownRight, .browInnerUp, .browOuterUpLeft, .browOuterUpRight,
        .cheekPuff, .cheekSquintLeft, .cheekSquintRight,
        .eyeBlinkLeft, .eyeBlinkRight, .eyeLookDownLeft, .eyeLookDownRight,
        .eyeLookInLeft, .eyeLookInRight, .eyeLookOutLeft, .eyeLookOutRight,
        .eyeLookUpLeft, .eyeLookUpRight, .eyeSquintLeft, .eyeSquintRight,
        .eyeWideLeft, .eyeWideRight,
        .jawForward, .jawLeft, .jawOpen, .jawRight,
        .mouthClose, .mouthDimpleLeft, .mouthDimpleRight, .mouthFrownLeft, .mouthFrownRight,
        .mouthFunnel, .mouthLeft, .mouthLowerDownLeft, .mouthLowerDownRight,
        .mouthPressLeft, .mouthPressRight, .mouthPucker, .mouthRight,
        .mouthRollLower, .mouthRollUpper, .mouthShrugLower, .mouthShrugUpper,
        .mouthSmileLeft, .mouthSmileRight, .mouthStretchLeft, .mouthStretchRight,
        .mouthUpperUpLeft, .mouthUpperUpRight,
        .noseSneerLeft, .noseSneerRight,
        .tongueOut
    ]
}

struct PerformanceCaptureView: View {

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var recorder = PerformanceRecorder()

    @State private var clipName: String = "perf_01"

    var body: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("perf.title", comment: ""))
                .font(.title2.bold())

            HStack {
                TextField(NSLocalizedString("perf.name.placeholder", comment: ""), text: $clipName)
                    .textFieldStyle(.roundedBorder)
                Text(String(format: NSLocalizedString("perf.elapsed", comment: ""), recorder.elapsed))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Button {
                if recorder.isRecording {
                    recorder.stopRecording()
                    environment.session.performanceClips = recorder.clips
                } else {
                    recorder.startRecording(name: clipName)
                }
            } label: {
                ZStack {
                    Circle().fill(recorder.isRecording ? Color.red : Color.accentColor)
                        .frame(width: 96, height: 96)
                    Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                }
            }
            .disabled(!recorder.canRecordMore && !recorder.isRecording)

            Text(String(format: NSLocalizedString("perf.frames", comment: ""), recorder.framesCaptured))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("perf.clips", comment: "")).font(.headline)
                ForEach(Array(recorder.clips.enumerated()), id: \.offset) { idx, clip in
                    HStack {
                        Image(systemName: "waveform").foregroundStyle(.accent)
                        VStack(alignment: .leading) {
                            Text(clip.name).font(.body)
                            Text(String(format: NSLocalizedString("perf.frames.count", comment: ""), clip.frameCount))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            recorder.deleteClip(at: idx)
                            environment.session.performanceClips = recorder.clips
                            nextClipName()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal)
                }
            }

            Spacer()

            HStack {
                Button(NSLocalizedString("common.back", comment: "")) {
                    router.back()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button(NSLocalizedString("perf.continue", comment: "")) {
                    environment.session.performanceClips = recorder.clips
                    router.advance()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .padding(.top)
        .onAppear {
            recorder.clips = environment.session.performanceClips
            nextClipName()
            activateAudioSession()
        }
        .onDisappear {
            deactivateAudioSession()
        }
    }

    /// Aktywuje sesję audio — `playAndRecord` pozwala jednocześnie mikrofonować
    /// (do PCM 16 kHz) i odtwarzać dźwięki systemowe po kapcie.
    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            AppLog.perf.error("Nie udało się aktywować AVAudioSession: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Zwalnia sesję audio, informując inne aplikacje o deaktywacji.
    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func nextClipName() {
        let nextIdx = recorder.clips.count + 1
        clipName = String(format: "perf_%02d", nextIdx)
    }
}
