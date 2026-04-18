// =============================================================================
// Plik: SparseDeltaEncoder.swift
// Opis: Koduje delty blendshape jako sparse (idx u16 + Δ f16×3 + pad u16).
// =============================================================================

import Foundation
import simd

/// Enkoder rzadki dla delt blendshape. Dla każdego wierzchołka, który
/// zmienia się powyżej progu (domyślnie 0.001), zapisujemy:
/// - index (u16 LE),
/// - Δx, Δy, Δz (f16 LE każde),
/// - pad (u16) — aby rekord miał równe 10 bajtów.
///
/// Zapis sparse pozwala zmieścić 52 blendshape w pamięci Tab5 bez overheadu
/// pełnej macierzy.
public enum SparseDeltaEncoder {

    /// Próg poniżej którego zmiana uznawana jest za szum.
    public static let defaultThreshold: Float = 0.001

    /// Koduje tablicę delt (jedna delta na wierzchołek) jako strumień sparse.
    /// Zwraca `(data, count)`.
    public static func encode(deltas: [Vec3],
                              threshold: Float = defaultThreshold) -> (data: Data, count: UInt32) {
        var out = Data()
        out.reserveCapacity(deltas.count * 8)
        var count: UInt32 = 0

        for (idx, d) in deltas.enumerated() {
            let mag = simd_length(d)
            if mag < threshold { continue }

            var leIdx = UInt16(truncatingIfNeeded: idx).littleEndian
            withUnsafeBytes(of: &leIdx) { out.append(contentsOf: $0) }

            let dxh = Float16(d.x)
            let dyh = Float16(d.y)
            let dzh = Float16(d.z)

            var dxBits = dxh.bitPattern.littleEndian
            var dyBits = dyh.bitPattern.littleEndian
            var dzBits = dzh.bitPattern.littleEndian

            withUnsafeBytes(of: &dxBits) { out.append(contentsOf: $0) }
            withUnsafeBytes(of: &dyBits) { out.append(contentsOf: $0) }
            withUnsafeBytes(of: &dzBits) { out.append(contentsOf: $0) }

            // Padding u16, aby wpis miał 10 bajtów równo.
            var pad: UInt16 = 0
            withUnsafeBytes(of: &pad) { out.append(contentsOf: $0) }

            count += 1
        }
        return (out, count)
    }

    /// Koduje delty bez odsiewu — wersja gęsta. Każdy wierzchołek zapisywany.
    public static func encodeDense(deltas: [Vec3]) -> (data: Data, count: UInt32) {
        var out = Data()
        out.reserveCapacity(deltas.count * 6)
        for d in deltas {
            let dxh = Float16(d.x)
            let dyh = Float16(d.y)
            let dzh = Float16(d.z)
            var dxBits = dxh.bitPattern.littleEndian
            var dyBits = dyh.bitPattern.littleEndian
            var dzBits = dzh.bitPattern.littleEndian
            withUnsafeBytes(of: &dxBits) { out.append(contentsOf: $0) }
            withUnsafeBytes(of: &dyBits) { out.append(contentsOf: $0) }
            withUnsafeBytes(of: &dzBits) { out.append(contentsOf: $0) }
        }
        return (out, UInt32(deltas.count))
    }
}
