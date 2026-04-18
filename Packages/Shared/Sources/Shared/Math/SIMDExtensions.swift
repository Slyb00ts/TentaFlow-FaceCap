// =============================================================================
// Plik: SIMDExtensions.swift
// Opis: Pomocnicze operacje na typach SIMD (iloczyn, cross, norm, slerp kwaternionu).
// =============================================================================

import Foundation
import simd

public extension SIMD3 where Scalar == Float {

    /// Długość wektora.
    var length: Float { sqrt(simd_dot(self, self)) }

    /// Wektor jednostkowy. Dla wektora zerowego zwraca `self`.
    var unit: SIMD3<Float> {
        let len = length
        return len > 1e-8 ? self / len : self
    }

    /// Odległość euklidesowa do innego wektora.
    @inline(__always)
    func distance(to other: SIMD3<Float>) -> Float {
        simd_distance(self, other)
    }

    /// Iloczyn wektorowy.
    @inline(__always)
    func cross(_ other: SIMD3<Float>) -> SIMD3<Float> {
        simd_cross(self, other)
    }

    /// Iloczyn skalarny.
    @inline(__always)
    func dot(_ other: SIMD3<Float>) -> Float {
        simd_dot(self, other)
    }
}

public extension SIMD4 where Scalar == Float {

    /// Rzuca SIMD4 jako punkt jednorodny i zwraca wektor 3D po podziale przez w.
    var projected: SIMD3<Float> {
        let invW = abs(w) > 1e-8 ? 1.0 / w : 1.0
        return SIMD3<Float>(x * invW, y * invW, z * invW)
    }
}

public extension simd_float4x4 {

    /// Mnoży macierz 4×4 przez punkt 3D (z jednostkową współrzędną homogeniczną).
    @inline(__always)
    func transform(point: SIMD3<Float>) -> SIMD3<Float> {
        let h = SIMD4<Float>(point, 1)
        let r = self * h
        return r.projected
    }

    /// Mnoży macierz 4×4 przez wektor 3D (bez translacji — w=0).
    @inline(__always)
    func transform(direction: SIMD3<Float>) -> SIMD3<Float> {
        let h = SIMD4<Float>(direction, 0)
        let r = self * h
        return SIMD3<Float>(r.x, r.y, r.z)
    }
}

/// Interpolacja sferyczna kwaternionów (SLERP). Używamy `simd_slerp`, który zachowuje
/// numeryczną stabilność przy dużych i małych kątach.
@inline(__always)
public func quaternionSlerp(_ a: simd_quatf, _ b: simd_quatf, t: Float) -> simd_quatf {
    simd_slerp(a, b, t)
}
