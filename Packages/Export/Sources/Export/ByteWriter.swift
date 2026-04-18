// =============================================================================
// Plik: ByteWriter.swift
// Opis: Klasa do budowania binarnego bufora w little-endian z śledzeniem offsetu.
// =============================================================================

import Foundation
import simd
import Shared

/// Referencyjny writer bajtowy — rośnie w miarę potrzeb, wszystko LE.
public final class ByteWriter {

    /// Bufor bajtów.
    public private(set) var data: Data

    public init(reserving: Int = 0) {
        var d = Data()
        d.reserveCapacity(reserving)
        self.data = d
    }

    /// Aktualny offset (czyli rozmiar buforu).
    public var offset: Int { data.count }

    // MARK: — Typy skalarne (LE)

    public func writeU8(_ v: UInt8) {
        data.append(v)
    }

    public func writeU16(_ v: UInt16) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    public func writeI16(_ v: Int16) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    public func writeU32(_ v: UInt32) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    public func writeU64(_ v: UInt64) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    public func writeF32(_ v: Float) {
        var bits = v.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    public func writeF16(_ v: Float16) {
        var bits = v.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    // MARK: — Wektory

    public func writeVec3(_ v: Vec3) {
        writeF32(v.x); writeF32(v.y); writeF32(v.z)
    }

    public func writeVec2(_ v: Vec2) {
        writeF32(v.x); writeF32(v.y)
    }

    /// Zapisz trójkąt trzech indeksów.
    public func writeTri(_ t: SIMD3<UInt16>) {
        writeU16(t.x); writeU16(t.y); writeU16(t.z)
    }

    // MARK: — Blok bajtów

    public func writeBytes(_ bytes: [UInt8]) {
        data.append(contentsOf: bytes)
    }

    public func writeBytes(_ d: Data) {
        data.append(d)
    }

    public func writeZeros(_ count: Int) {
        guard count > 0 else { return }
        data.append(Data(repeating: 0, count: count))
    }

    // MARK: — String ASCII null-padded

    /// Zapisuje string jako dokładnie `length` bajtów ASCII, null-padded lub przycięty.
    public func writeFixedAscii(_ s: String, length: Int) {
        var bytes = Array(s.utf8.prefix(length))
        if bytes.count < length {
            bytes.append(contentsOf: [UInt8](repeating: 0, count: length - bytes.count))
        }
        data.append(contentsOf: bytes)
    }

    /// Zapisuje string z prefixem długości (u8) + same bajty bez terminatora.
    public func writePrefixedString(_ s: String, maxLen: Int = 255) {
        let bytes = Array(s.utf8.prefix(maxLen))
        writeU8(UInt8(bytes.count))
        data.append(contentsOf: bytes)
    }

    // MARK: — Padding wyrównania

    /// Dopisuje zera, tak aby offset był wielokrotnością `alignment`.
    public func padTo(alignment: Int) {
        let rem = offset % alignment
        if rem != 0 {
            writeZeros(alignment - rem)
        }
    }

    public func padPad32() {
        padTo(alignment: 32)
    }

    // MARK: — Nadpisywanie pod offsetem (np. CRC32 w nagłówku)

    /// Nadpisuje 4 bajty na danym offsecie wartością U32 LE.
    public func overwriteU32(at off: Int, value: UInt32) throws {
        guard off + 4 <= data.count else {
            throw FacecapError.writerOutOfBounds(offset: off, requested: 4)
        }
        let le = value.littleEndian
        withUnsafeBytes(of: le) { ptr in
            data.replaceSubrange(off..<(off + 4), with: ptr)
        }
    }

    /// Nadpisuje 8 bajtów na danym offsecie wartością U64 LE.
    public func overwriteU64(at off: Int, value: UInt64) throws {
        guard off + 8 <= data.count else {
            throw FacecapError.writerOutOfBounds(offset: off, requested: 8)
        }
        let le = value.littleEndian
        withUnsafeBytes(of: le) { ptr in
            data.replaceSubrange(off..<(off + 8), with: ptr)
        }
    }

    /// Nadpisuje blok bajtów na danym offsecie.
    public func overwriteBytes(at off: Int, bytes: Data) throws {
        guard off + bytes.count <= data.count else {
            throw FacecapError.writerOutOfBounds(offset: off, requested: bytes.count)
        }
        data.replaceSubrange(off..<(off + bytes.count), with: bytes)
    }
}
