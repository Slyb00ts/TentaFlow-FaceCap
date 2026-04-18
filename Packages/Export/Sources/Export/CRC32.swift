// =============================================================================
// Plik: CRC32.swift
// Opis: Pełna implementacja CRC32 IEEE 802.3 z tablicą 256 wpisów (little-endian).
// =============================================================================

import Foundation

/// CRC32 w wariancie IEEE 802.3 (polynomial 0xEDB88320, init 0xFFFFFFFF, xorOut 0xFFFFFFFF).
public enum CRC32 {

    /// Tablica 256 wpisów obliczana raz podczas inicjalizacji.
    private static let table: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        let polynomial: UInt32 = 0xEDB88320
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                if (c & 1) != 0 {
                    c = polynomial ^ (c >> 1)
                } else {
                    c >>= 1
                }
            }
            t[i] = c
        }
        return t
    }()

    /// Liczy CRC32 całego bufora.
    public static func compute(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            for byte in ptr {
                let idx = Int((crc ^ UInt32(byte)) & 0xFF)
                crc = (crc >> 8) ^ table[idx]
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    /// Liczy CRC32, ale pomija N bajtów zaczynając od `skipOffset` — używane do
    /// policzenia CRC pliku, gdzie pole `crc32` w nagłówku musi być wyzerowane.
    public static func compute(_ data: Data, skipping range: Range<Int>) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            for i in 0..<data.count {
                let byte: UInt8
                if range.contains(i) {
                    byte = 0
                } else {
                    byte = ptr[i]
                }
                let idx = Int((crc ^ UInt32(byte)) & 0xFF)
                crc = (crc >> 8) ^ table[idx]
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}
