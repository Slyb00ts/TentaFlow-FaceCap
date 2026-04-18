// =============================================================================
// Plik: TongueGenerator.swift
// Opis: Generator proceduralnego języka — low-poly ellipsoid ~50 verts.
// =============================================================================

import Foundation
import simd

/// Mesh języka.
public struct TongueMesh: Sendable {
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

/// Generator języka — ellipsoid.
public struct TongueGenerator: Sendable {
    public let radiiMeters: SIMD3<Float>
    public let longitudeSegments: Int
    public let latitudeSegments: Int

    public init(
        radiiMeters: SIMD3<Float> = SIMD3<Float>(0.012, 0.006, 0.018),
        longitudeSegments: Int = 10,
        latitudeSegments: Int = 5
    ) {
        self.radiiMeters = radiiMeters
        self.longitudeSegments = max(4, longitudeSegments)
        self.latitudeSegments = max(3, latitudeSegments)
    }

    public func generate() -> TongueMesh {
        var verts: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var normals: [SIMD3<Float>] = []
        var tris: [SIMD3<UInt16>] = []

        let lon = longitudeSegments
        let lat = latitudeSegments

        for i in 0...lat {
            let phi = Float(i) / Float(lat) * Float.pi
            let sinPhi = sin(phi)
            let cosPhi = cos(phi)
            for j in 0...lon {
                let theta = Float(j) / Float(lon) * 2.0 * Float.pi
                let sinTheta = sin(theta)
                let cosTheta = cos(theta)
                let x = radiiMeters.x * cosTheta * sinPhi
                let y = radiiMeters.y * cosPhi
                let z = radiiMeters.z * sinTheta * sinPhi
                verts.append(SIMD3<Float>(x, y, z))
                // Normalna — gradient równania elipsoidy, znormalizowany.
                let raw = SIMD3<Float>(x / (radiiMeters.x * radiiMeters.x),
                                       y / (radiiMeters.y * radiiMeters.y),
                                       z / (radiiMeters.z * radiiMeters.z))
                normals.append(simd_normalize(raw))
                uvs.append(SIMD2<Float>(Float(j) / Float(lon), Float(i) / Float(lat)))
            }
        }

        let stride = lon + 1
        for i in 0..<lat {
            for j in 0..<lon {
                let a = UInt16(i * stride + j)
                let b = UInt16(i * stride + j + 1)
                let c = UInt16((i + 1) * stride + j)
                let d = UInt16((i + 1) * stride + j + 1)
                tris.append(SIMD3<UInt16>(a, c, b))
                tris.append(SIMD3<UInt16>(b, c, d))
            }
        }
        return TongueMesh(verts: verts, uvs: uvs, normals: normals, tris: tris)
    }
}
