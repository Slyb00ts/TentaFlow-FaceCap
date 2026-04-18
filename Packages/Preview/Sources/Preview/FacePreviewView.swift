// =============================================================================
// Plik: FacePreviewView.swift
// Opis: SwiftUI UIViewRepresentable owijający MTKView z FacePreviewRenderer.
// =============================================================================

import SwiftUI
import MetalKit
import simd

/// Widok podglądu avatara w Metal – owija `MTKView` i przekazuje wagi AU
/// oraz opcjonalny preset do renderera.
///
/// Binding `mimicry` musi zawierać 52 elementy (0..1). Wartości poza zakresem
/// są klamowane w shaderze (przez blendshape deltas).
public struct FacePreviewView: UIViewRepresentable {

    /// 52-elementowy wektor AU weights (binding z UI – slidery / ARKit / klip).
    @Binding public var mimicry: [Float]

    /// Opcjonalny preset – nadpisuje `mimicry` gdy nie-nil (np. preview presetu).
    @Binding public var selectedPreset: EmotionPreset?

    /// Bundle meshy – przekazywany raz po zakończeniu kalibracji.
    public let bundle: PreviewMeshBundle?

    public init(mimicry: Binding<[Float]>,
                selectedPreset: Binding<EmotionPreset?>,
                bundle: PreviewMeshBundle?) {
        self._mimicry = mimicry
        self._selectedPreset = selectedPreset
        self.bundle = bundle
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60

        do {
            let renderer = try FacePreviewRenderer(pixelFormat: view.colorPixelFormat,
                                                     depthFormat: view.depthStencilPixelFormat)
            context.coordinator.renderer = renderer
            view.device = renderer.device
            view.delegate = renderer
            if let bundle {
                renderer.configure(bundle: bundle)
            }
        } catch {
            context.coordinator.initError = error
            view.device = MTLCreateSystemDefaultDevice()
        }

        return view
    }

    public func updateUIView(_ view: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        if let bundle, renderer.bundle !== bundle {
            renderer.configure(bundle: bundle)
        }
        // Preset nadpisuje mimicry gdy aktywny.
        if let preset = selectedPreset {
            renderer.weights = preset.auWeights
        } else {
            renderer.weights = Self.vector(from: mimicry)
        }
    }

    /// Konwertuje `[Float]` (52 el.) na `SIMD64<Float>` (reszta zerowana).
    private static func vector(from arr: [Float]) -> SIMD64<Float> {
        var v = SIMD64<Float>(repeating: 0)
        let n = min(arr.count, 52)
        for i in 0..<n { v[i] = arr[i] }
        return v
    }

    /// Koordynator trzyma referencję do renderera (żeby przeżył między updateUIView).
    public final class Coordinator {
        public var renderer: FacePreviewRenderer?
        public var initError: Error?
    }
}
