// =============================================================================
// Plik: PerformancePlayer.swift
// Opis: Odtwarzanie klipu performance – timeline AU synchronizowany z audio.
// =============================================================================

import Foundation
import AVFoundation
import Combine
import QuartzCore
import simd
import os

/// Odtwarzacz klipu performance — oddaje wartości AU per klatka razem z audio.
///
/// Działa na `@MainActor` bo używa `CADisplayLink` (zsynchronizowane z VSync
/// wyświetlacza). Callback `onUpdate` dostaje aktualny wektor AU oraz czas
/// odtwarzania audio — konsument (np. `FacePreviewRenderer`) aktualizuje mesh.
@MainActor
public final class PerformancePlayer: ObservableObject {

    /// Status odtwarzania.
    public enum Status: Equatable {
        case idle
        case playing
        case paused
    }

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var currentTime: Double = 0.0
    @Published public private(set) var duration: Double = 0.0

    /// Callback wywoływany per klatka: (wagi AU, czas audio w sekundach).
    public typealias OnUpdate = (SIMD64<Float>, Double) -> Void

    private let log = Logger(subsystem: "pl.tentaflow.facecap", category: "performance-player")

    private var clip: PerformanceClip?
    private var onUpdate: OnUpdate?
    private var displayLink: CADisplayLink?
    private var startHostTime: CFTimeInterval = 0.0
    private var pauseAccumulator: Double = 0.0
    private var lastPauseHostTime: CFTimeInterval = 0.0

    // Audio
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var audioEngineAttached = false

    public init() {}

    /// Wczytuje klip i uruchamia odtwarzanie.
    public func play(clip: PerformanceClip, onUpdate: @escaping OnUpdate) {
        stopInternal(resetTime: true)
        self.clip = clip
        self.onUpdate = onUpdate
        self.duration = clip.durationSec
        self.currentTime = 0.0

        if let url = clip.audioURL {
            configureAudioEngine()
            do {
                let file = try AVAudioFile(forReading: url)
                self.audioFile = file
                player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task { @MainActor in
                        self?.handleAudioFinished()
                    }
                }
                if !engine.isRunning {
                    try engine.start()
                }
                player.play()
            } catch {
                log.error("Nie udało się uruchomić audio: \(error.localizedDescription, privacy: .public)")
            }
        }

        startHostTime = CACurrentMediaTime()
        pauseAccumulator = 0.0
        status = .playing
        startDisplayLink()
    }

    /// Pauzuje odtwarzanie (audio + timeline). `resume()` wraca do tego samego miejsca.
    public func pause() {
        guard status == .playing else { return }
        player.pause()
        lastPauseHostTime = CACurrentMediaTime()
        displayLink?.isPaused = true
        status = .paused
    }

    /// Wznawia odtwarzanie po `pause()`.
    public func resume() {
        guard status == .paused else { return }
        let pausedFor = CACurrentMediaTime() - lastPauseHostTime
        pauseAccumulator += pausedFor
        player.play()
        displayLink?.isPaused = false
        status = .playing
    }

    /// Zatrzymuje odtwarzanie, reset do 0.
    public func stop() {
        stopInternal(resetTime: true)
    }

    /// Przewija do konkretnego czasu (sekundy). Restartuje audio od tego offsetu.
    public func seek(to time: Double) {
        guard let clip else { return }
        let t = max(0.0, min(time, clip.durationSec))
        currentTime = t

        if let url = clip.audioURL, let _ = audioFile {
            player.stop()
            do {
                let file = try AVAudioFile(forReading: url)
                let sr = file.processingFormat.sampleRate
                let startFrame = AVAudioFramePosition(t * sr)
                let remaining = AVAudioFrameCount(max(0, file.length - startFrame))
                if remaining > 0 {
                    player.scheduleSegment(file,
                                            startingFrame: startFrame,
                                            frameCount: remaining,
                                            at: nil)
                    if status == .playing {
                        player.play()
                    }
                }
            } catch {
                log.error("seek – błąd reschedulingu audio: \(error.localizedDescription, privacy: .public)")
            }
        }

        startHostTime = CACurrentMediaTime() - t
        pauseAccumulator = 0.0
    }

    // MARK: - Prywatne

    private func configureAudioEngine() {
        if !audioEngineAttached {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: nil)
            audioEngineAttached = true
        }
    }

    private func startDisplayLink() {
        displayLink?.invalidate()
        let link = CADisplayLink(target: DisplayLinkProxy { [weak self] in
            self?.tick()
        }, selector: #selector(DisplayLinkProxy.invoke))
        // Preferujemy fps klipu (zwykle 60).
        if let fps = clip?.fps {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: Float(fps),
                                                             maximum: Float(fps),
                                                             preferred: Float(fps))
        }
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    private func tick() {
        guard status == .playing, let clip else { return }
        let t = CACurrentMediaTime() - startHostTime - pauseAccumulator
        if t >= clip.durationSec {
            currentTime = clip.durationSec
            onUpdate?(clip.frame(at: clip.durationSec), clip.durationSec)
            stopInternal(resetTime: false)
            return
        }
        currentTime = t
        let weights = clip.frame(at: t)
        onUpdate?(weights, t)
    }

    private func handleAudioFinished() {
        // Audio skończyło się wcześniej niż timeline — tick() sam dojedzie do końca.
    }

    private func stopInternal(resetTime: Bool) {
        displayLink?.invalidate()
        displayLink = nil
        if player.isPlaying {
            player.stop()
        }
        if engine.isRunning {
            engine.stop()
        }
        audioFile = nil
        status = .idle
        if resetTime {
            currentTime = 0.0
            pauseAccumulator = 0.0
        }
    }
}

/// Proxy do `CADisplayLink` – zamienia closure w selector (DisplayLink wymaga NSObject target).
private final class DisplayLinkProxy: NSObject {
    private let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
}
