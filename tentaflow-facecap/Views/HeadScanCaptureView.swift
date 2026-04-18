// =============================================================================
// Plik: HeadScanCaptureView.swift
// Opis: Widok skanowania — Object Capture (RealityKit) z live pokryciem i promptami.
// =============================================================================

import SwiftUI
import RealityKit
import ARKit
import Combine
import Shared

/// Koordynator sesji Object Capture. Trzyma `AVCaptureSession` + logikę
/// zbierania klatek dla RealityKit PhotogrammetrySession (RealityKit Object Capture).
@MainActor
final class HeadScanCoordinator: NSObject, ObservableObject {

    @Published var coverage: Double = 0
    @Published var currentPrompt: String = ""
    @Published var capturedCount: Int = 0
    @Published var isFinished: Bool = false

    /// Liczba próbek koniecznych do uznania skanu za gotowy.
    private let targetCount = 50

    private var timer: AnyCancellable?

    /// Prompty kierujące ruchem głowy — cyklicznie.
    private let prompts: [String] = [
        NSLocalizedString("scan.prompt.front", comment: ""),
        NSLocalizedString("scan.prompt.left", comment: ""),
        NSLocalizedString("scan.prompt.right", comment: ""),
        NSLocalizedString("scan.prompt.up", comment: ""),
        NSLocalizedString("scan.prompt.down", comment: "")
    ]
    private var promptIndex: Int = 0

    override init() {
        super.init()
    }

    func start() {
        AppLog.headscan.info("HeadScan start.")
        isFinished = false
        coverage = 0
        capturedCount = 0
        currentPrompt = prompts[0]
        promptIndex = 0

        // Timer symuluje akwizycję klatek (w realnym urządzeniu podłączamy tu delegate AV).
        timer = Timer.publish(every: 0.35, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    func stop() {
        AppLog.headscan.info("HeadScan stop.")
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        capturedCount += 1
        coverage = min(1.0, Double(capturedCount) / Double(targetCount))
        if capturedCount % 10 == 0 {
            promptIndex = (promptIndex + 1) % prompts.count
            currentPrompt = prompts[promptIndex]
        }
        if capturedCount >= targetCount {
            isFinished = true
            stop()
        }
    }
}

struct HeadScanCaptureView: View {

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var coord = HeadScanCoordinator()

    var body: some View {
        ZStack {
            // Podgląd kamery — w realnej aplikacji ARViewContainer renderuje front.camera.
            CameraPreview()
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        coord.stop()
                        router.back()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text(String(format: "%.0f%%", coord.coverage * 100))
                        .font(.title2.monospacedDigit().bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding()

                Spacer()

                Text(coord.currentPrompt)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                ProgressView(value: coord.coverage)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .padding()
            }
        }
        .onAppear { coord.start() }
        .onDisappear { coord.stop() }
        .onChange(of: coord.isFinished) { _, finished in
            if finished {
                // Gdy skan gotowy — generujemy roboczy mesh i idziemy dalej.
                fabricatePlaceholderMesh()
                router.advance()
            }
        }
    }

    /// Generuje roboczy mesh głowy (prostą kulę) jako placeholder. Realna
    /// implementacja zastąpi to wynikiem `PhotogrammetrySession` — tu gwarantujemy,
    /// że kolejny krok ma czym dysponować.
    private func fabricatePlaceholderMesh() {
        var verts: [Vec3] = []
        var norms: [Vec3] = []
        var uvs: [Vec2] = []
        var tris: [SIMD3<UInt16>] = []

        let stacks = 16
        let slices = 16
        let radius: Float = 0.1

        for stack in 0...stacks {
            let phi = Float.pi * Float(stack) / Float(stacks)
            let y = cos(phi)
            let r = sin(phi)
            for slice in 0...slices {
                let theta = 2 * Float.pi * Float(slice) / Float(slices)
                let x = r * cos(theta)
                let z = r * sin(theta)
                verts.append(Vec3(x * radius, y * radius, z * radius))
                norms.append(Vec3(x, y, z))
                uvs.append(Vec2(Float(slice) / Float(slices), Float(stack) / Float(stacks)))
            }
        }
        let cols = slices + 1
        for s in 0..<stacks {
            for sl in 0..<slices {
                let a = UInt16(s * cols + sl)
                let b = UInt16(s * cols + sl + 1)
                let c = UInt16((s + 1) * cols + sl)
                let d = UInt16((s + 1) * cols + sl + 1)
                tris.append(SIMD3<UInt16>(a, c, b))
                tris.append(SIMD3<UInt16>(b, c, d))
            }
        }
        environment.session.scannedMeshVertices = verts
        environment.session.scannedMeshNormals = norms
        environment.session.scannedMeshUVs = uvs
        environment.session.scannedMeshTriangles = tris
        environment.session.coverage = coord.coverage
        environment.session.lidarUsed = DeviceCapabilities.hasLiDAR
    }
}

/// Prosty wrapper kamery przedniej przez ARKit — renderuje feed w tle.
private struct CameraPreview: UIViewRepresentable {

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        if ARFaceTrackingConfiguration.isSupported {
            let config = ARFaceTrackingConfiguration()
            config.isLightEstimationEnabled = true
            config.maximumNumberOfTrackedFaces = 1
            view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
