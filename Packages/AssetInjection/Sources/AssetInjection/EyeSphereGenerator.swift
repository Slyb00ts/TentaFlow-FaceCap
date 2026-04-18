// =============================================================================
// Plik: EyeSphereGenerator.swift
// Opis: Generator proceduralnej sfery oka (UV sphere 16×8) z radialnym UV dla tęczówki.
// =============================================================================

import Foundation
import simd

/// Mesh sfery oka.
public struct EyeSphereMesh: Sendable {
    public let verts: [SIMD3<Float>]
    public let uvs: [SIMD2<Float>]
    public let normals: [SIMD3<Float>]
    public let tris: [SIMD3<UInt16>]

    public init(verts: [SIMD3<Float>], uvs: [SIMD2<Float>], normals: [SIMD3<Float>], tris: [SIMD3<UInt16>]) {
        self.verts = verts
        self.uvs = uvs
        self.normals = normals
        self.tris = tris
    }
}

/// Generator UV sphere.
public struct EyeSphereGenerator: Sendable {
    public let radius: Float
    public let longitudeSegments: Int
    public let latitudeSegments: Int

    public init(radius: Float = 0.012, longitudeSegments: Int = 16, latitudeSegments: Int = 8) {
        self.radius = radius
        self.longitudeSegments = max(4, longitudeSegments)
        self.latitudeSegments = max(3, latitudeSegments)
    }

    /// Generuje mesh sfery oka. UV mapowane radialnie — centrum = tęczówka.
    public func generate() -> EyeSphereMesh {
        var verts: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var normals: [SIMD3<Float>] = []
        var tris: [SIMD3<UInt16>] = []

        let longCount = longitudeSegments
        let latCount = latitudeSegments

        for lat in 0...latCount {
            let phi = Float(lat) / Float(latCount) * Float.pi  // 0..π
            let sinPhi = sin(phi)
            let cosPhi = cos(phi)
            for long in 0...longCount {
                let theta = Float(long) / Float(longCount) * 2.0 * Float.pi  // 0..2π
                let sinTheta = sin(theta)
                let cosTheta = cos(theta)
                let x = radius * cosTheta * sinPhi
                let y = radius * cosPhi
                let z = radius * sinTheta * sinPhi
                verts.append(SIMD3<Float>(x, y, z))
                normals.append(SIMD3<Float>(cosTheta * sinPhi, cosPhi, sinTheta * sinPhi))

                // UV radialne — środek = szczyt (lat=0), krawędź = dół (lat=latCount).
                // Dla tęczówki: lat < 2 = iris cap (mały pierścień), reszta = sklera.
                let radialR = Float(lat) / Float(latCount) * 0.5
                let u = 0.5 + radialR * cosTheta
                let v = 0.5 + radialR * sinTheta
                uvs.append(SIMD2<Float>(u, v))
            }
        }

        // Trójkąty — standardowe owijanie UV sphere.
        let stride = longCount + 1
        for lat in 0..<latCount {
            for long in 0..<longCount {
                let a = UInt16(lat * stride + long)
                let b = UInt16(lat * stride + long + 1)
                let c = UInt16((lat + 1) * stride + long)
                let d = UInt16((lat + 1) * stride + long + 1)
                tris.append(SIMD3<UInt16>(a, c, b))
                tris.append(SIMD3<UInt16>(b, c, d))
            }
        }

        return EyeSphereMesh(verts: verts, uvs: uvs, normals: normals, tris: tris)
    }
}
