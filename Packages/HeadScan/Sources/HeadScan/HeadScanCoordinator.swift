// =============================================================================
// Plik: HeadScanCoordinator.swift
// Opis: Koordynator całego pipeline'u skanu głowy — ObjectCapture, fotogrametria, decymacja.
// =============================================================================

import Foundation
import Combine
import ARKit
import RealityKit
import CoreGraphics
import simd

/// Stan sesji skanu.
public enum HeadScanState: Sendable, Equatable {
    case idle
    case capturing(progress: Float)
    case processing(progress: Float, stage: String)
    case completed
    case failed(String)
}

/// Główny koordynator skanu głowy.
@available(iOS 17.0, *)
@MainActor
public final class HeadScanCoordinator: ObservableObject {
    @Published public private(set) var state: HeadScanState = .idle
    @Published public private(set) var guidancePrompt: GuidancePrompt = GuidancePrompt(
        message: "Naciśnij start, żeby rozpocząć skan.",
        severity: .info,
        progress: 0.0
    )
    @Published public private(set) var capturedFrameCount: Int = 0

    private let workingDirectory: URL
    private let imagesDirectory: URL
    private let checkpointDirectory: URL
    private let outputURL: URL

    private var sessionWrapper: ObjectCaptureSessionWrapper?
    private var pumpTask: Task<Void, Never>?
    private let guidance: CaptureGuidance
    private let qualityAnalyzer = ScanQualityAnalyzer()
    private var targetVertexCount: Int = 2000

    /// Preferowane indeksy zachowywanych wierzchołków (landmarki twarzy).
    public var preservedVertexIndices: Set<Int> = []

    /// Tworzy koordynator z katalogiem roboczym w `tmp/`.
    public init(workingDirectory: URL? = nil, targetVertexCount: Int = 2000) throws {
        let baseDir: URL
        if let workingDirectory {
            baseDir = workingDirectory
        } else {
            baseDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("tentaflow-headscan", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        self.workingDirectory = baseDir
        self.imagesDirectory = baseDir.appendingPathComponent("images", isDirectory: true)
        self.checkpointDirectory = baseDir.appendingPathComponent("checkpoint", isDirectory: true)
        self.outputURL = baseDir.appendingPathComponent("head.usdz")
        self.guidance = CaptureGuidance(targetFrameCount: 50)
        self.targetVertexCount = targetVertexCount
    }

    /// Startuje sesję ObjectCapture.
    public func start() throws {
        guard case .idle = state else { return }
        let wrapper = ObjectCaptureSessionWrapper(
            imagesDirectory: imagesDirectory,
            checkpointDirectory: checkpointDirectory
        )
        try wrapper.start()
        sessionWrapper = wrapper
        capturedFrameCount = 0
        qualityAnalyzer.reset()
        state = .capturing(progress: 0.0)

        pumpTask = Task { [weak self] in
            guard let self else { return }
            await self.pump(wrapper: wrapper)
        }
    }

    /// Pauzuje sesję.
    public func pause() {
        sessionWrapper?.pause()
    }

    /// Wznawia sesję po pauzie.
    public func resume() {
        sessionWrapper?.resume()
    }

    /// Anuluje sesję i czyści stan.
    public func cancel() {
        sessionWrapper?.cancel()
        sessionWrapper = nil
        pumpTask?.cancel()
        pumpTask = nil
        state = .idle
    }

    /// Wykonuje pełen pipeline: finalizacja capture -> fotogrametria -> decymacja -> rezultat.
    public func finalize() async throws -> HeadScanResult {
        guard let wrapper = sessionWrapper else {
            throw HeadScanError.processingFailed("Brak aktywnej sesji.")
        }
        wrapper.finish()

        // Czekaj na finalizację capture w strumieniu.
        state = .processing(progress: 0.05, stage: "Finalizacja capture")

        // Uruchamiamy fotogrametrię.
        let runner = PhotogrammetrySessionRunner(
            inputDirectory: imagesDirectory,
            outputURL: outputURL,
            detail: .reduced
        )

        let usdz: URL
        do {
            usdz = try await runner.run { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    self.state = .processing(
                        progress: Float(0.1 + progress.fractionComplete * 0.7),
                        stage: progress.processingStage
                    )
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }

        state = .processing(progress: 0.8, stage: "Ekstrakcja mesh")

        let extractor = USDZMeshExtractor()
        let extracted: USDZMeshExtractor.ExtractedMesh
        do {
            extracted = try extractor.extract(from: usdz)
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }

        state = .processing(progress: 0.9, stage: "Decymacja mesh")

        let decimator = MeshDecimator(
            targetVertexCount: targetVertexCount,
            preservedIndices: preservedVertexIndices
        )
        let decimated = decimator.decimate(
            verts: extracted.verts,
            normals: extracted.normals,
            uvs: extracted.uvs,
            triangles: extracted.triangles
        )

        // Konwersja indeksów do UInt16 (musimy zejść poniżej 65k).
        var trianglesU16: [SIMD3<UInt16>] = []
        trianglesU16.reserveCapacity(decimated.triangles.count)
        for tri in decimated.triangles {
            if tri.x < 65_536 && tri.y < 65_536 && tri.z < 65_536 {
                trianglesU16.append(SIMD3<UInt16>(
                    UInt16(tri.x), UInt16(tri.y), UInt16(tri.z)
                ))
            }
        }

        let texture: CGImage
        if let extractedTexture = extracted.texture {
            texture = extractedTexture
        } else {
            texture = try Self.makePlaceholderTexture()
        }
        let report = qualityAnalyzer.finalize()

        state = .completed

        return HeadScanResult(
            usdzURL: usdz,
            meshVerts: decimated.verts,
            meshNormals: decimated.normals,
            meshUVs: decimated.uvs,
            meshTriangles: trianglesU16,
            textureCGImage: texture,
            scanQuality: report
        )
    }

    // MARK: - Pump zdarzeń

    private func pump(wrapper: ObjectCaptureSessionWrapper) async {
        for await event in wrapper.events {
            switch event {
            case .stateChanged(let captureState):
                updateState(for: captureState)
            case .feedback(let fb):
                let prompt = guidance.prompt(for: fb, capturedFrameCount: capturedFrameCount)
                guidancePrompt = prompt
            case .frameCaptured(let count):
                capturedFrameCount = count
                state = .capturing(progress: Float(count) / Float(guidance.targetFrameCount))
            case .error(let message):
                state = .failed(message)
            case .finished:
                state = .processing(progress: 0.05, stage: "Finalizacja capture")
            }
        }
    }

    private func updateState(for captureState: ObjectCaptureSession.CaptureState) {
        switch captureState {
        case .initializing:
            state = .capturing(progress: 0.0)
        case .ready:
            state = .capturing(progress: 0.0)
        case .detecting:
            state = .capturing(progress: 0.1)
        case .capturing:
            let progress = Float(capturedFrameCount) / Float(guidance.targetFrameCount)
            state = .capturing(progress: min(1.0, progress))
        case .finishing:
            state = .processing(progress: 0.05, stage: "Finalizacja capture")
        case .completed:
            state = .processing(progress: 0.1, stage: "Gotowe do fotogrametrii")
        case .failed(let error):
            state = .failed(String(describing: error))
        @unknown default:
            break
        }
    }

    private static func makePlaceholderTexture() throws -> CGImage {
        let width = 256
        let height = 256
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw HeadScanError.meshLoadFailed("Nie udało się utworzyć CGContext placeholder tekstury.")
        }
        ctx.setFillColor(red: 0.78, green: 0.7, blue: 0.62, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = ctx.makeImage() else {
            throw HeadScanError.meshLoadFailed("Nie udało się wyrenderować placeholder tekstury.")
        }
        return image
    }
}
