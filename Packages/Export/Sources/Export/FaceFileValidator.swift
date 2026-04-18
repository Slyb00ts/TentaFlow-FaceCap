// =============================================================================
// Plik: FaceFileValidator.swift
// Opis: Re-parsuje plik .face v3 i porównuje z wejściowym FaceAssetData.
// =============================================================================

import Foundation
import simd
import Shared

/// Prosty walidator — ładuje plik z dysku, parsuje nagłówek, sprawdza CRC32
/// i porównuje kluczowe metryki (vertex count, blendshape count, flagi) z
/// oczekiwanym `FaceAssetData`. Dzięki temu każda rozbieżność wynikająca z
/// błędu w writer zostanie zauważona zanim trafi do urządzenia Tab5.
public struct FaceFileValidator {

    public init() {}

    public func validate(fileURL: URL, expected asset: FaceAssetData) throws {
        let data = try Data(contentsOf: fileURL)

        guard data.count >= FaceFileFormat.fileHeaderSize else {
            throw FacecapError.malformed("Plik za mały.")
        }

        // 1. Magic.
        let magicBytes = [UInt8](data[0..<4])
        guard magicBytes == FaceFileFormat.magic else {
            throw FacecapError.malformed("Zły MAGIC.")
        }

        // 2. Wersja.
        let verMajor = readU16(data, at: 4)
        let verMinor = readU16(data, at: 6)
        guard verMajor == FaceFileFormat.versionMajor,
              verMinor == FaceFileFormat.versionMinor else {
            throw FacecapError.malformed("Zła wersja (\(verMajor).\(verMinor)).")
        }

        // 3. Flagi.
        let flagsRaw = readU32(data, at: 8)
        let flags = FaceFlags(rawValue: flagsRaw)

        // 4. section_count + total_size.
        let sectionCount = readU16(data, at: 12)
        let totalSize = readU64(data, at: 16)
        guard UInt64(data.count) == totalSize else {
            throw FacecapError.malformed("total_size (\(totalSize)) != file (\(data.count)).")
        }

        // 5. CRC32 — pole crc32 wyzerowane przy liczeniu.
        let expectedCRC = readU32(data, at: 24)
        let computedCRC = CRC32.compute(data, skipping: 24..<28)
        guard expectedCRC == computedCRC else {
            throw FacecapError.crcMismatch(expected: expectedCRC, got: computedCRC)
        }

        // 6. Dyrektorium sekcji.
        var sectionMap: [UInt32: (off: UInt64, size: UInt64)] = [:]
        let dirStart = FaceFileFormat.fileHeaderSize
        for i in 0..<Int(sectionCount) {
            let base = dirStart + i * FaceFileFormat.sectionDirEntrySize
            let id = readU32(data, at: base)
            let off = readU64(data, at: base + 8)
            let size = readU64(data, at: base + 16)
            guard off + size <= UInt64(data.count) else {
                throw FacecapError.malformed("Sekcja 0x\(String(id, radix: 16)) wychodzi poza plik.")
            }
            guard off % UInt64(FaceFileFormat.sectionAlignment) == 0 else {
                throw FacecapError.malformed("Sekcja 0x\(String(id, radix: 16)) niewyrównana.")
            }
            sectionMap[id] = (off, size)
        }

        // 7. Porównanie metryk z FaceAssetData.
        try compare(asset: asset, flags: flags, data: data, map: sectionMap)
    }

    private func compare(asset: FaceAssetData,
                         flags: FaceFlags,
                         data: Data,
                         map: [UInt32: (off: UInt64, size: UInt64)]) throws {

        // Mesh geometry.
        guard let geom = map[SectionID.meshGeometry.rawValue] else {
            throw FacecapError.validatorMismatch(section: SectionID.meshGeometry.rawValue, field: "missing")
        }
        let vertexCount = readU32(data, at: Int(geom.off))
        guard Int(vertexCount) == asset.vertices.count else {
            throw FacecapError.validatorMismatch(section: SectionID.meshGeometry.rawValue, field: "vertex_count")
        }

        // Normals.
        if let norm = map[SectionID.meshNormals.rawValue] {
            let normCount = readU32(data, at: Int(norm.off))
            guard Int(normCount) == asset.normals.count else {
                throw FacecapError.validatorMismatch(section: SectionID.meshNormals.rawValue, field: "normal_count")
            }
        }

        // UVs.
        if let uv = map[SectionID.meshUVs.rawValue] {
            let uvCount = readU32(data, at: Int(uv.off))
            guard Int(uvCount) == asset.uvs.count else {
                throw FacecapError.validatorMismatch(section: SectionID.meshUVs.rawValue, field: "uv_count")
            }
        }

        // Triangles.
        if let tris = map[SectionID.meshTriangles.rawValue] {
            let triCount = readU32(data, at: Int(tris.off))
            guard Int(triCount) == asset.triangles.count else {
                throw FacecapError.validatorMismatch(section: SectionID.meshTriangles.rawValue, field: "tri_count")
            }
        }

        // Blendshape table.
        if let tab = map[SectionID.blendshapeTable.rawValue] {
            let bsCount = readU32(data, at: Int(tab.off))
            guard Int(bsCount) == asset.blendshapes.count else {
                throw FacecapError.validatorMismatch(section: SectionID.blendshapeTable.rawValue, field: "count")
            }
        }

        // Flagi.
        let expectedFlags: FaceFlags = {
            var f: FaceFlags = []
            if asset.textureImage != nil { f.insert(.hasTexture) }
            if !asset.performanceClips.isEmpty { f.insert(.hasPerformance) }
            if asset.eyes != nil { f.insert(.hasEyes) }
            if asset.teeth != nil { f.insert(.hasTeeth) }
            if asset.tongue != nil { f.insert(.hasTongue) }
            if asset.mouthCavity != nil { f.insert(.hasMouthCavity) }
            if let snaps = asset.expressionSnapshots, !snaps.isEmpty { f.insert(.hasExpressions) }
            if asset.lidarUsed { f.insert(.hasLiDAR) }
            return f
        }()
        guard flags.rawValue == expectedFlags.rawValue else {
            throw FacecapError.validatorMismatch(section: 0, field: "flags")
        }

        // Liczba snapshotów — jeżeli asset je dostarczył, sprawdź nagłówek sekcji.
        if let snaps = asset.expressionSnapshots, !snaps.isEmpty {
            guard let snapSection = map[SectionID.expressionSnapshots.rawValue] else {
                throw FacecapError.validatorMismatch(section: SectionID.expressionSnapshots.rawValue, field: "missing")
            }
            let snapCount = readU32(data, at: Int(snapSection.off))
            guard Int(snapCount) == snaps.count else {
                throw FacecapError.validatorMismatch(section: SectionID.expressionSnapshots.rawValue, field: "snapshot_count")
            }
        }
    }

    // MARK: — Odczyt skalarów LE

    private func readU16(_ data: Data, at offset: Int) -> UInt16 {
        data.withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    private func readU32(_ data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }

    private func readU64(_ data: Data, at offset: Int) -> UInt64 {
        data.withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt64.self).littleEndian
        }
    }
}
