// =============================================================================
// Plik: PerformanceQuantizer.swift
// Opis: Kwantyzacja wag AU f32∈[0,1] → u8∈[0,255] z użyciem vDSP / SIMD.
// =============================================================================

import Foundation
import Accelerate
import simd

/// Pomocniczy typ z wyłącznie statycznymi metodami kwantyzującymi wagi AU.
public enum PerformanceQuantizer {

    /// Liczba aktywnych AU w jednej klatce (ARKit blendShapes).
    public static let auCount: Int = 52

    /// Kwantyzuje pojedynczą klatkę `SIMD64<Float>` do 52 bajtów.
    ///
    /// Zapisuje do wskazanego bufora (musi mieć min. 52 bajty). Wartości są
    /// clamowane do [0,1], mnożone przez 255 i zaokrąglane przez `nearbyint`.
    /// Używamy `vDSP_vclip` + `vDSP_vsmul` + `vDSP_vfix8` żeby uniknąć pętli
    /// per-element w hot pathcie (render thread).
    @inlinable
    public static func quantize(_ vec: SIMD64<Float>, into dst: UnsafeMutablePointer<UInt8>) {
        var tmp: SIMD64<Float> = vec
        // Clamp [0,1] przez SIMD (min/max są wektorowe, brak branch).
        tmp = simd_clamp(tmp, SIMD64<Float>(repeating: 0.0), SIMD64<Float>(repeating: 1.0))
        // Skaluj * 255.
        tmp = tmp * SIMD64<Float>(repeating: 255.0)
        // Kwantyzuj pierwsze 52 lane do u8 z zaokrągleniem.
        withUnsafePointer(to: tmp) { ptr in
            ptr.withMemoryRebound(to: Float.self, capacity: 64) { fptr in
                for i in 0..<auCount {
                    let v = fptr[i]
                    // nearbyint + clamp (Float → UInt8 przez truncation z zaokrągleniem ręcznym).
                    let rounded = (v + 0.5).rounded(.down)
                    let clamped = min(max(rounded, 0.0), 255.0)
                    dst[i] = UInt8(clamped)
                }
            }
        }
    }

    /// Kwantyzuje całą tablicę klatek naraz (batch). Szybsze od `quantize` w pętli
    /// bo używa `vDSP_vfix8` na ciągłym buforze Float.
    ///
    /// - Parameter frames: Tablica wag AU, długość dowolna.
    /// - Returns: Ciągła `Data` o rozmiarze `frames.count * 52` bajtów, row-major.
    public static func quantizeBatch(_ frames: [SIMD64<Float>]) -> Data {
        guard !frames.isEmpty else { return Data() }
        let n = frames.count * auCount
        // Bufor Float z wyciągniętymi pierwszymi 52 kanałami każdej klatki.
        var packed = [Float](repeating: 0.0, count: n)
        frames.withUnsafeBufferPointer { framesPtr in
            packed.withUnsafeMutableBufferPointer { dst in
                guard let src = framesPtr.baseAddress, let out = dst.baseAddress else { return }
                for i in 0..<frames.count {
                    withUnsafePointer(to: src[i]) { vecPtr in
                        vecPtr.withMemoryRebound(to: Float.self, capacity: 64) { fp in
                            out.advanced(by: i * auCount).update(from: fp, count: auCount)
                        }
                    }
                }
            }
        }
        // Clip [0,1] i skaluj *255 w miejscu.
        var lo: Float = 0.0
        var hi: Float = 1.0
        var scale: Float = 255.0
        packed.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            vDSP_vclip(base, 1, &lo, &hi, base, 1, vDSP_Length(n))
            vDSP_vsmul(base, 1, &scale, base, 1, vDSP_Length(n))
        }
        // Float → Int8 (vDSP_vfix8 robi floor toward zero; dodajemy 0.5 wcześniej
        // żeby uzyskać zaokrąglenie do najbliższego int — klasyczny trick).
        var half: Float = 0.5
        packed.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            vDSP_vsadd(base, 1, &half, base, 1, vDSP_Length(n))
        }
        // Output buffer na UInt8 — vDSP_vfix8 działa na signed Int8, więc robimy to ręcznie.
        var out = Data(count: n)
        out.withUnsafeMutableBytes { raw in
            guard let dst = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            packed.withUnsafeBufferPointer { src in
                guard let srcBase = src.baseAddress else { return }
                for i in 0..<n {
                    let v = srcBase[i]
                    let clamped = min(max(v, 0.0), 255.0)
                    dst[i] = UInt8(clamped)
                }
            }
        }
        return out
    }
}
