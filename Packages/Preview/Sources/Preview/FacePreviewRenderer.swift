// =============================================================================
// Plik: FacePreviewRenderer.swift
// Opis: Metal renderer avatara – MTKViewDelegate, multi-mesh + blendshape skinning.
// =============================================================================

import Foundation
import Metal
import MetalKit
import simd
import os

/// Renderer avatara – implementuje `MTKViewDelegate` i zarządza całą ścieżką draw.
///
/// Wzorowany na software rasterizerze Tab5 (kolejność rysowania,
/// model oświetlenia) – tak żeby iOS preview dawał „sanity check" finalnego
/// wyglądu na ESP32-P4.
public final class FacePreviewRenderer: NSObject, MTKViewDelegate {

    // MARK: - Public state

    /// Aktualny wektor AU (64 lane, 52 aktywne) – zapisywany przez UI/driver.
    public var weights: SIMD64<Float> = .zero

    /// Bundle meshy (ustawiony po `configure(bundle:)`).
    public private(set) var bundle: PreviewMeshBundle?

    /// Domyślny kierunek światła w world space.
    public var lightDirection: SIMD3<Float> = SIMD3<Float>(-0.3, -0.8, -0.5)

    /// Kamera: prosta perspektywa patrząca na origin z z=1.5.
    public var cameraPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 1.5)

    // MARK: - Private

    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let gouraudPSO: MTLRenderPipelineState
    private let eyePSO: MTLRenderPipelineState
    private let flatPSO: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let sampler: MTLSamplerState

    private let log = Logger(subsystem: "pl.tentaflow.facecap", category: "preview-renderer")

    /// Rozmiar drawable – aktualizowany w `mtkView(_:drawableSizeWillChange:)`.
    private var drawableSize: SIMD2<Float> = SIMD2<Float>(1, 1)

    /// Reusable builder (do `updateVertices`).
    private let builder: PreviewMeshBuilder

    /// Kolor bazowy dla meshy „flat" (teeth / mouth_cavity / tongue) w kolejności rysowania.
    private static let flatColors: [PreviewMeshKind: SIMD3<Float>] = [
        .mouthCavity: SIMD3<Float>(0.05, 0.02, 0.02),
        .teeth: SIMD3<Float>(0.95, 0.93, 0.88),
        .tongue: SIMD3<Float>(0.78, 0.28, 0.32),
        .eyeSockets: SIMD3<Float>(0.08, 0.04, 0.04)
    ]

    // MARK: - Init

    /// Tworzy renderer. Rzuca gdy Metal niedostępny lub kompilacja shadera padnie.
    public init(pixelFormat: MTLPixelFormat = .bgra8Unorm,
                depthFormat: MTLPixelFormat = .depth32Float) throws {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            throw PreviewError.metalDeviceNotAvailable
        }
        guard let cq = dev.makeCommandQueue() else {
            throw PreviewError.metalDeviceNotAvailable
        }
        self.device = dev
        self.commandQueue = cq
        self.builder = PreviewMeshBuilder(device: dev)

        // Wczytaj default library z bundle (pakiet Swift – automatyczna kompilacja .metal).
        let library: MTLLibrary
        do {
            library = try dev.makeDefaultLibrary(bundle: Bundle.module)
        } catch {
            throw PreviewError.shaderCompilationFailed("\(error)")
        }

        let vtxDesc = Self.makeVertexDescriptor()

        self.gouraudPSO = try Self.makePipeline(device: dev,
                                                 library: library,
                                                 vtxFunc: "vertex_main",
                                                 fragFunc: "fragment_gouraud",
                                                 vtxDesc: vtxDesc,
                                                 pixelFormat: pixelFormat,
                                                 depthFormat: depthFormat)
        self.eyePSO = try Self.makePipeline(device: dev,
                                             library: library,
                                             vtxFunc: "vertex_main",
                                             fragFunc: "fragment_eye",
                                             vtxDesc: vtxDesc,
                                             pixelFormat: pixelFormat,
                                             depthFormat: depthFormat)
        self.flatPSO = try Self.makePipeline(device: dev,
                                              library: library,
                                              vtxFunc: "vertex_main",
                                              fragFunc: "fragment_flat",
                                              vtxDesc: vtxDesc,
                                              pixelFormat: pixelFormat,
                                              depthFormat: depthFormat)

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        guard let ds = dev.makeDepthStencilState(descriptor: depthDesc) else {
            throw PreviewError.metalDeviceNotAvailable
        }
        self.depthState = ds

        let sDesc = MTLSamplerDescriptor()
        sDesc.minFilter = .linear
        sDesc.magFilter = .linear
        sDesc.mipFilter = .linear
        sDesc.sAddressMode = .clampToEdge
        sDesc.tAddressMode = .clampToEdge
        guard let smp = dev.makeSamplerState(descriptor: sDesc) else {
            throw PreviewError.metalDeviceNotAvailable
        }
        self.sampler = smp

        super.init()
    }

    // MARK: - Public API

    /// Podmienia aktywny bundle meshy (np. po zakończeniu kalibracji lub AssetInjection).
    public func configure(bundle: PreviewMeshBundle) {
        self.bundle = bundle
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    public func draw(in view: MTKView) {
        guard let bundle else { return }
        guard let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
            return
        }

        enc.setDepthStencilState(depthState)
        enc.setCullMode(.back)
        enc.setFrontFacing(.counterClockwise)

        var mvp = makeMVP()
        var model = matrix_identity_float4x4
        var light = lightDirection
        var sampler = self.sampler

        enc.setVertexBytes(&mvp, length: MemoryLayout<float4x4>.stride, index: 1)
        enc.setVertexBytes(&model, length: MemoryLayout<float4x4>.stride, index: 2)
        _ = sampler

        // Hot path – skin każdego mesha z weights i aktualizuj vertex buffer, potem draw.
        for mesh in bundle.meshes {
            // Skinning CPU (jeśli mesh ma blendshape'y)
            if let skinner = mesh.skinner {
                mesh.baseVerts.withUnsafeBufferPointer { bvBuf in
                    mesh.deltas.withUnsafeBufferPointer { dBuf in
                        guard let bv = bvBuf.baseAddress, let d = dBuf.baseAddress else { return }
                        let posed = skinner.skin(baseVerts: bv, deltas: d, weights: weights)
                        builder.updateVertices(mesh, posed: posed)
                    }
                }
            }

            enc.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)

            switch mesh.kind {
            case .eyeSpheres:
                enc.setRenderPipelineState(eyePSO)
                enc.setFragmentBytes(&light, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
                var iris = mesh.irisColor
                enc.setFragmentBytes(&iris, length: MemoryLayout<SIMD3<Float>>.stride, index: 1)

            case .faceSkin:
                if let albedo = mesh.albedo {
                    enc.setRenderPipelineState(gouraudPSO)
                    enc.setFragmentBytes(&light, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
                    enc.setFragmentTexture(albedo, index: 0)
                    enc.setFragmentSamplerState(self.sampler, index: 0)
                } else {
                    // Brak albedo → flat color fallback (beżowa skóra).
                    enc.setRenderPipelineState(flatPSO)
                    enc.setFragmentBytes(&light, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
                    var skin = SIMD3<Float>(0.85, 0.72, 0.62)
                    enc.setFragmentBytes(&skin, length: MemoryLayout<SIMD3<Float>>.stride, index: 1)
                }

            case .mouthCavity, .teeth, .tongue, .eyeSockets:
                enc.setRenderPipelineState(flatPSO)
                enc.setFragmentBytes(&light, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
                var color = Self.flatColors[mesh.kind] ?? SIMD3<Float>(0.5, 0.5, 0.5)
                enc.setFragmentBytes(&color, length: MemoryLayout<SIMD3<Float>>.stride, index: 1)
            }

            enc.drawIndexedPrimitives(type: .triangle,
                                       indexCount: mesh.indexCount,
                                       indexType: .uint32,
                                       indexBuffer: mesh.indexBuffer,
                                       indexBufferOffset: 0)
        }

        enc.endEncoding()
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: - Helpers

    private func makeMVP() -> float4x4 {
        let aspect = drawableSize.x > 0 ? drawableSize.x / max(drawableSize.y, 1) : 1.0
        let proj = Self.perspective(fovyRadians: Float.pi / 3.0,
                                     aspect: aspect,
                                     near: 0.01,
                                     far: 20.0)
        let view = Self.lookAt(eye: cameraPosition,
                                target: SIMD3<Float>(0, 0, 0),
                                up: SIMD3<Float>(0, 1, 0))
        return proj * view
    }

    private static func makeVertexDescriptor() -> MTLVertexDescriptor {
        let d = MTLVertexDescriptor()
        d.attributes[0].format = .float3
        d.attributes[0].offset = 0
        d.attributes[0].bufferIndex = 0
        d.attributes[1].format = .float3
        d.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        d.attributes[1].bufferIndex = 0
        d.attributes[2].format = .float2
        d.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        d.attributes[2].bufferIndex = 0
        d.layouts[0].stride = MemoryLayout<PreviewVertex>.stride
        d.layouts[0].stepFunction = .perVertex
        d.layouts[0].stepRate = 1
        return d
    }

    private static func makePipeline(device: MTLDevice,
                                      library: MTLLibrary,
                                      vtxFunc: String,
                                      fragFunc: String,
                                      vtxDesc: MTLVertexDescriptor,
                                      pixelFormat: MTLPixelFormat,
                                      depthFormat: MTLPixelFormat) throws -> MTLRenderPipelineState {
        guard let vFn = library.makeFunction(name: vtxFunc) else {
            throw PreviewError.shaderCompilationFailed("brak funkcji \(vtxFunc)")
        }
        guard let fFn = library.makeFunction(name: fragFunc) else {
            throw PreviewError.shaderCompilationFailed("brak funkcji \(fragFunc)")
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vFn
        desc.fragmentFunction = fFn
        desc.vertexDescriptor = vtxDesc
        desc.colorAttachments[0].pixelFormat = pixelFormat
        desc.depthAttachmentPixelFormat = depthFormat
        do {
            return try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            throw PreviewError.shaderCompilationFailed("\(vtxFunc)/\(fragFunc): \(error)")
        }
    }

    private static func perspective(fovyRadians fovy: Float, aspect: Float,
                                     near: Float, far: Float) -> float4x4 {
        let ys = 1.0 / tan(fovy * 0.5)
        let xs = ys / aspect
        let zs = far / (near - far)
        return float4x4(columns: (
            SIMD4<Float>(xs,  0,   0,  0),
            SIMD4<Float>(0,   ys,  0,  0),
            SIMD4<Float>(0,   0,   zs, -1),
            SIMD4<Float>(0,   0,   zs * near, 0)
        ))
    }

    private static func lookAt(eye: SIMD3<Float>,
                                target: SIMD3<Float>,
                                up: SIMD3<Float>) -> float4x4 {
        let z = normalize(eye - target)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        let t = SIMD3<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye))
        return float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        ))
    }
}
