// =============================================================================
// Plik: BlendshapeReader.swift
// Opis: Ring buffer ostatnich 120 klatek face trackingu (2s @ 60fps) — subskrybuje FaceTrackingSession.
// =============================================================================

import Foundation
import Combine
import simd
import os.lock

/// Thread-safe ring buffer na klatki twarzy.
public final class BlendshapeReader: @unchecked Sendable {
    public static let defaultCapacity: Int = 120
    private let capacity: Int
    private var storage: [FaceFrame?]
    private var head: Int = 0
    private var filled: Int = 0
    private var lock = os_unfair_lock_s()
    private var subscription: AnyCancellable?

    public init(capacity: Int = BlendshapeReader.defaultCapacity) {
        self.capacity = max(1, capacity)
        self.storage = [FaceFrame?](repeating: nil, count: self.capacity)
    }

    /// Podpina reader do sesji trackingowej.
    @MainActor
    public func attach(to session: FaceTrackingSession) {
        subscription = session.framePublisher
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .sink { [weak self] frame in
                self?.append(frame)
            }
    }

    /// Odpina subskrypcję.
    public func detach() {
        subscription?.cancel()
        subscription = nil
    }

    /// Wkłada klatkę do bufora.
    public func append(_ frame: FaceFrame) {
        os_unfair_lock_lock(&lock)
        storage[head] = frame
        head = (head + 1) % capacity
        if filled < capacity { filled += 1 }
        os_unfair_lock_unlock(&lock)
    }

    /// Zwraca kopię ostatnich `count` klatek (najnowsza na końcu).
    public func snapshot(lastN count: Int) -> [FaceFrame] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        let n = min(count, filled)
        guard n > 0 else { return [] }
        var result: [FaceFrame] = []
        result.reserveCapacity(n)
        // head wskazuje na następną wolną pozycję — ostatnia to head-1.
        let startOffset = (head - n + capacity) % capacity
        for i in 0..<n {
            let idx = (startOffset + i) % capacity
            if let frame = storage[idx] {
                result.append(frame)
            }
        }
        return result
    }

    /// Zwraca klatkę z peakiem AU w oknie.
    public func peakFrame(for au: ArkitAU, lastN count: Int) -> FaceFrame? {
        let window = snapshot(lastN: count)
        guard !window.isEmpty else { return nil }
        var best: FaceFrame?
        var bestValue: Float = -.infinity
        for frame in window {
            let value = frame.blendWeights[au.rawValue]
            if value > bestValue {
                bestValue = value
                best = frame
            }
        }
        return best
    }

    /// Czyści bufor.
    public func reset() {
        os_unfair_lock_lock(&lock)
        for i in 0..<storage.count { storage[i] = nil }
        head = 0
        filled = 0
        os_unfair_lock_unlock(&lock)
    }

    /// Liczba klatek w buforze.
    public var count: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return filled
    }
}
