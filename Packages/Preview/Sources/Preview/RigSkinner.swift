// =============================================================================
// Plik: RigSkinner.swift
// Opis: CPU-side blendshape skinning (linear-blend) z SIMD FMA i parallel-for.
// =============================================================================

import Foundation
import simd

/// Skinner CPU – oblicza finalną pozycję każdego wierzchołka jako:
///  `pose[i] = base[i] + Σ_b weights[b] * deltas[b][i]`
///
/// Delty są przechowywane jako ciągła tablica `[SIMD3<Float>]` o layoutzie
/// `deltas[b * vertexCount + i]` (row-major per blendshape). To pozwala na
/// jeden pointer i liniowe adresowanie.
///
/// Optymalizacje:
///  - preallocated `posedBuffer` (brak alokacji w `skin`),
///  - skip blendshape'a gdy `weight < threshold` (0.01),
///  - `DispatchQueue.concurrentPerform` dla równoległości per-vertex batch,
///  - SIMD3 FMA (`a + b * c`).
public final class RigSkinner {

    public let vertexCount: Int
    public let blendshapeCount: Int

    /// Próg poniżej którego ignorujemy wagę blendshape'a.
    public var threshold: Float = 0.01

    /// Liczba podziałów pracy dla `concurrentPerform`. Zbyt duża → overhead synchr.
    public var parallelChunks: Int = 4

    /// Bufor na pozycje wierzchołków po skinningu. Trzymamy go jako surowy
    /// `UnsafeMutablePointer`, nie `Array`, żeby gwarantować stały adres
    /// dla pointerów zwracanych z `skin(...)`.
    private let posedBuffer: UnsafeMutablePointer<SIMD3<Float>>

    public init(vertexCount: Int, blendshapeCount: Int) {
        self.vertexCount = vertexCount
        self.blendshapeCount = blendshapeCount
        self.posedBuffer = UnsafeMutablePointer<SIMD3<Float>>.allocate(capacity: vertexCount)
        self.posedBuffer.initialize(repeating: .zero, count: vertexCount)
    }

    deinit {
        posedBuffer.deinitialize(count: vertexCount)
        posedBuffer.deallocate()
    }

    /// Wykonuje skinning. Zwraca wskaźnik do wewnętrznego bufora – ważny do
    /// następnego wywołania `skin` (nie trzymaj go dłużej).
    ///
    /// - Parameters:
    ///   - baseVerts: pointer do bazowych pozycji (długość `vertexCount`),
    ///   - deltas: pointer do delt (`blendshapeCount * vertexCount`),
    ///   - weights: wektor 64-elementowy; aktywnych 52 (zgodne z ARKit).
    public func skin(baseVerts: UnsafePointer<SIMD3<Float>>,
                      deltas: UnsafePointer<SIMD3<Float>>,
                      weights: SIMD64<Float>) -> UnsafePointer<SIMD3<Float>> {

        // 1) Kopiuj bazę do bufora – pojedynczy memcpy.
        posedBuffer.update(from: baseVerts, count: vertexCount)

        // 2) Wyciągnij ważne blendshape'y do lokalnej listy (skip < threshold).
        //    To unika kosztu sprawdzenia wagi dla każdego wierzchołka.
        var activeBlends: [(Int, Float)] = []
        activeBlends.reserveCapacity(blendshapeCount)
        withUnsafePointer(to: weights) { ptr in
            ptr.withMemoryRebound(to: Float.self, capacity: 64) { fp in
                for b in 0..<blendshapeCount {
                    let w = fp[b]
                    if w > threshold {
                        activeBlends.append((b, w))
                    }
                }
            }
        }

        if activeBlends.isEmpty {
            return UnsafePointer(posedBuffer)
        }

        // 3) Parallel-for na wierzchołkach – partycja na `parallelChunks`.
        let chunks = max(1, parallelChunks)
        let chunkSize = (vertexCount + chunks - 1) / chunks
        let active = activeBlends
        let vCount = vertexCount
        let posedBase = posedBuffer
        DispatchQueue.concurrentPerform(iterations: chunks) { chunkIdx in
            let start = chunkIdx * chunkSize
            let end = min(start + chunkSize, vCount)
            if start >= end { return }
            for (b, w) in active {
                let base = deltas.advanced(by: b * vCount)
                let wv = SIMD3<Float>(repeating: w)
                // FMA per wierzchołek: posed[i] += delta[i] * w
                for i in start..<end {
                    posedBase[i] = posedBase[i] + base[i] * wv
                }
            }
        }

        return UnsafePointer(posedBuffer)
    }

    /// Wariant „safe" zwracający kopię tablicy (dla UI / debuga).
    public func skinCopy(baseVerts: [SIMD3<Float>],
                         deltas: [SIMD3<Float>],
                         weights: SIMD64<Float>) -> [SIMD3<Float>] {
        precondition(baseVerts.count == vertexCount, "baseVerts.count != vertexCount")
        precondition(deltas.count == vertexCount * blendshapeCount,
                     "deltas.count != vertexCount * blendshapeCount")
        return baseVerts.withUnsafeBufferPointer { bvBuf in
            deltas.withUnsafeBufferPointer { dBuf in
                guard let bvBase = bvBuf.baseAddress, let dBase = dBuf.baseAddress else {
                    return Array(repeating: SIMD3<Float>(repeating: 0), count: vertexCount)
                }
                let ptr = skin(baseVerts: bvBase, deltas: dBase, weights: weights)
                return Array(UnsafeBufferPointer(start: ptr, count: vertexCount))
            }
        }
    }
}
