// =============================================================================
// Plik: PerformanceQuantizer.swift
// Opis: Kwantyzuje klipy performance – wagi 52×f32 → u8, audio f32 → s16 16 kHz.
// =============================================================================

import Foundation
import Accelerate

/// Konwersje wag blendshape i audio do formy docelowej (u8 dla wag, s16le 16 kHz dla audio).
public enum PerformanceQuantizer {

    /// Kwantyzuje pojedynczą klatkę (52 wagi w 0…1) do 52 bajtów.
    public static func quantizeFrame(_ weights: [Float]) -> [UInt8] {
        precondition(weights.count == 52, "Ramka musi mieć 52 wagi.")
        var out = [UInt8](repeating: 0, count: 52)
        for (i, w) in weights.enumerated() {
            let clamped = max(0, min(1, w))
            out[i] = UInt8(round(clamped * 255.0))
        }
        return out
    }

    /// Kwantyzuje cały klip wag. Zwraca sklejone bajty `count × 52`.
    public static func quantizeWeights(_ frames: [[Float]]) -> Data {
        var out = Data()
        out.reserveCapacity(frames.count * 52)
        for frame in frames {
            out.append(contentsOf: quantizeFrame(frame))
        }
        return out
    }

    /// Konwertuje audio PCM float32 mono do PCM s16le. Zakłada, że częstotliwość
    /// próbkowania wejścia jest już 16 000 Hz (upstream musi to zapewnić przez
    /// `AVAudioEngine` z `AVAudioFormat(commonFormat:.pcmFormatFloat32, sampleRate: 16000, channels: 1)`).
    public static func convertAudioToS16LE(_ pcm: [Float]) -> Data {
        var out = Data(count: pcm.count * 2)
        out.withUnsafeMutableBytes { rawBuf in
            guard let dst = rawBuf.bindMemory(to: Int16.self).baseAddress else { return }
            for (i, sample) in pcm.enumerated() {
                let clamped = max(-1.0, min(1.0, sample))
                // Symetryczne skalowanie, aby -1.0 trafiło w INT16_MIN + 1 (unikamy przepełnienia).
                let scaled = Int32(clamped * 32767.0)
                dst[i] = Int16(truncatingIfNeeded: scaled).littleEndian
            }
        }
        return out
    }
}
