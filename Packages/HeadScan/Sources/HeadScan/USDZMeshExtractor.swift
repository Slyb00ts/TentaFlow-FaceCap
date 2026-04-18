// =============================================================================
// Plik: USDZMeshExtractor.swift
// Opis: Ekstrahuje geometrię i teksturę z pliku USDZ wygenerowanego przez PhotogrammetrySession.
// =============================================================================

import Foundation
import RealityKit
import ModelIO
import Metal
import CoreGraphics
import ImageIO
import simd

/// Ekstraktor mesh z USDZ.
public struct USDZMeshExtractor {
    public struct ExtractedMesh: Sendable {
        public let verts: [SIMD3<Float>]
        public let normals: [SIMD3<Float>]
        public let uvs: [SIMD2<Float>]
        public let triangles: [SIMD3<UInt32>]
        public let texture: CGImage?
    }

    public init() {}

    /// Ładuje USDZ przez ModelIO (niezależne od MainActor RealityKit).
    public func extract(from url: URL) throws -> ExtractedMesh {
        let asset = MDLAsset(url: url)
        asset.loadTextures()

        guard asset.count > 0 else {
            throw HeadScanError.meshLoadFailed("USDZ nie zawiera obiektów MDLAsset.")
        }

        var allVerts: [SIMD3<Float>] = []
        var allNormals: [SIMD3<Float>] = []
        var allUVs: [SIMD2<Float>] = []
        var allTriangles: [SIMD3<UInt32>] = []
        var firstTexture: CGImage?

        for i in 0..<asset.count {
            guard let object = asset.object(at: i) as? MDLObject else { continue }
            traverse(object: object,
                     verts: &allVerts,
                     normals: &allNormals,
                     uvs: &allUVs,
                     triangles: &allTriangles,
                     texture: &firstTexture)
        }

        if allVerts.isEmpty {
            throw HeadScanError.meshLoadFailed("USDZ: nie wyekstraktowano żadnego wierzchołka.")
        }

        return ExtractedMesh(
            verts: allVerts,
            normals: allNormals,
            uvs: allUVs,
            triangles: allTriangles,
            texture: firstTexture
        )
    }

    // MARK: - Traversal MDL

    private func traverse(
        object: MDLObject,
        verts: inout [SIMD3<Float>],
        normals: inout [SIMD3<Float>],
        uvs: inout [SIMD2<Float>],
        triangles: inout [SIMD3<UInt32>],
        texture: inout CGImage?
    ) {
        if let mesh = object as? MDLMesh {
            extractMesh(mesh,
                        baseVertexIndex: UInt32(verts.count),
                        verts: &verts,
                        normals: &normals,
                        uvs: &uvs,
                        triangles: &triangles,
                        texture: &texture)
        }

        for child in object.children.objects {
            traverse(object: child,
                     verts: &verts,
                     normals: &normals,
                     uvs: &uvs,
                     triangles: &triangles,
                     texture: &texture)
        }
    }

    private func extractMesh(
        _ mesh: MDLMesh,
        baseVertexIndex: UInt32,
        verts: inout [SIMD3<Float>],
        normals: inout [SIMD3<Float>],
        uvs: inout [SIMD2<Float>],
        triangles: inout [SIMD3<UInt32>],
        texture: inout CGImage?
    ) {
        // Zapewnij że są normalne.
        if mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal) == nil {
            mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.2)
        }

        let vertexCount = mesh.vertexCount

        // Pozycje
        if let posData = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) {
            verts.reserveCapacity(verts.count + vertexCount)
            let stride = posData.stride
            let bytes = posData.dataStart
            for v in 0..<vertexCount {
                let ptr = bytes.advanced(by: v * stride).assumingMemoryBound(to: Float.self)
                verts.append(SIMD3<Float>(ptr[0], ptr[1], ptr[2]))
            }
        }

        // Normalne
        if let normData = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float3) {
            normals.reserveCapacity(normals.count + vertexCount)
            let stride = normData.stride
            let bytes = normData.dataStart
            for v in 0..<vertexCount {
                let ptr = bytes.advanced(by: v * stride).assumingMemoryBound(to: Float.self)
                normals.append(SIMD3<Float>(ptr[0], ptr[1], ptr[2]))
            }
        } else {
            normals.append(contentsOf: Array(repeating: SIMD3<Float>(0, 1, 0), count: vertexCount))
        }

        // UV
        if let uvData = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeTextureCoordinate, as: .float2) {
            uvs.reserveCapacity(uvs.count + vertexCount)
            let stride = uvData.stride
            let bytes = uvData.dataStart
            for v in 0..<vertexCount {
                let ptr = bytes.advanced(by: v * stride).assumingMemoryBound(to: Float.self)
                uvs.append(SIMD2<Float>(ptr[0], ptr[1]))
            }
        } else {
            uvs.append(contentsOf: Array(repeating: SIMD2<Float>(0, 0), count: vertexCount))
        }

        // Indeksy trójkątów
        guard let submeshes = mesh.submeshes as? [MDLSubmesh] else { return }
        for submesh in submeshes {
            if submesh.geometryType != .triangles {
                continue
            }
            let indexCount = submesh.indexCount
            let triCount = indexCount / 3
            let buffer = submesh.indexBuffer(asIndexType: .uInt32)
            let map = buffer.map()
            let ptr = map.bytes.assumingMemoryBound(to: UInt32.self)
            triangles.reserveCapacity(triangles.count + triCount)
            for t in 0..<triCount {
                let i0 = ptr[t * 3 + 0] &+ baseVertexIndex
                let i1 = ptr[t * 3 + 1] &+ baseVertexIndex
                let i2 = ptr[t * 3 + 2] &+ baseVertexIndex
                triangles.append(SIMD3<UInt32>(i0, i1, i2))
            }

            // Tekstura z materiału
            if texture == nil, let material = submesh.material {
                texture = Self.loadTextureFromMaterial(material)
            }
        }
    }

    private static func loadTextureFromMaterial(_ material: MDLMaterial) -> CGImage? {
        let candidateSemantics: [MDLMaterialSemantic] = [.baseColor, .emission]
        for semantic in candidateSemantics {
            for property in material.properties(with: semantic) {
                if property.type == .texture, let sampler = property.textureSamplerValue, let texture = sampler.texture {
                    if let cgImage = texture.imageFromTexture()?.takeRetainedValue() {
                        return cgImage
                    }
                }
                if property.type == .URL, let url = property.urlValue {
                    if let cgImage = Self.loadCGImage(from: url) {
                        return cgImage
                    }
                }
                if property.type == .string, let name = property.stringValue {
                    if let cgImage = Self.loadCGImage(from: URL(fileURLWithPath: name)) {
                        return cgImage
                    }
                }
            }
        }
        return nil
    }

    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
