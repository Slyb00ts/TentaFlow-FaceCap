// =============================================================================
// Plik: LiveFaceDriver.swift
// Opis: Pass-through z FaceTrackingSession → wektor AU dla Preview renderera.
// =============================================================================

import Foundation
import Combine
import simd

/// Źródło klatek AU live – uwspólnione z `PerformanceRecorder`, tutaj reużywamy
/// kontrakt przez zewnętrzny protokół, więc `Preview` może działać nawet bez
/// sesji ARKit (np. same presety + slidery).
public protocol PreviewAUSource: AnyObject {
    /// Publisher par (timestamp, weights[64]).
    var framePublisher: AnyPublisher<(Double, SIMD64<Float>), Never> { get }
}

/// Driver przepuszczający wektor AU z ARKit do `@Published` pola konsumowanego przez UI.
///
/// Używamy `simd_copy` semantyki (pojedyncza asygnacja = memcpy 64*4 B) zamiast
/// pętli po 52 wartościach — GPU i pracuje na tej samej reprezentacji.
public final class LiveFaceDriver: ObservableObject {

    /// Ostatnio odebrany wektor AU.
    @Published public private(set) var weights: SIMD64<Float> = .zero

    /// Ostatni timestamp klatki (sekundy).
    @Published public private(set) var lastTimestamp: Double = 0.0

    private var bag: Set<AnyCancellable> = []

    public init() {}

    /// Podpina driver do źródła klatek. Wywołaj raz po utworzeniu sesji ARKit.
    public func bind(source: PreviewAUSource) {
        bag.removeAll()
        source.framePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (ts, w) in
                guard let self else { return }
                self.weights = w
                self.lastTimestamp = ts
            }
            .store(in: &bag)
    }

    /// Rozłącza driver (zatrzymuje subskrypcję).
    public func unbind() {
        bag.removeAll()
    }
}
