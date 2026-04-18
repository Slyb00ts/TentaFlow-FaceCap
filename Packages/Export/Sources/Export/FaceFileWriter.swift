// =============================================================================
// Plik: FaceFileWriter.swift
// Opis: Publiczne API pisania pliku .face v3 z pełną walidacją i CRC32.
// =============================================================================

import Foundation
import simd
import Shared

/// Kompozytor pliku `.face v3`. Ładuje wszystkie sekcje, oblicza tabelę sekcji,
/// pisze nagłówek, liczy CRC32 i zapisuje plik na dysk (`Documents/Faces/`).
public struct FaceFileWriter {

    /// Katalog, do którego trafiają zapisane profile. Tworzony on-demand.
    public let outputDirectory: URL

    public init(outputDirectory: URL? = nil) {
        if let outputDirectory {
            self.outputDirectory = outputDirectory
        } else {
            // Szukamy katalogu Documents przez API systemowe. Gdyby (hipotetycznie)
            // lista była pusta, fallback opiera się na `NSHomeDirectory()/Documents`,
            // który na iOS zawsze zwraca ścieżkę sandboxa aplikacji.
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                self.outputDirectory = docs.appendingPathComponent("Faces", isDirectory: true)
            } else {
                let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                self.outputDirectory = home
                    .appendingPathComponent("Documents", isDirectory: true)
                    .appendingPathComponent("Faces", isDirectory: true)
            }
        }
    }

    /// Pisze plik `.face v3` dla danego assetu i zwraca URL pliku wynikowego.
    public func write(_ asset: FaceAssetData) throws -> URL {
        AppLog.export.info("Writer: start, profile=\(asset.profileName, privacy: .public)")

        // 1. Zbieramy sekcje (id, data).
        var sections: [(SectionID, Data)] = []

        // Obowiązkowe.
        sections.append((.meshGeometry, SectionBuilder.buildMeshGeometry(asset.vertices)))
        sections.append((.meshNormals, SectionBuilder.buildMeshNormals(asset.normals)))
        sections.append((.meshUVs, SectionBuilder.buildMeshUVs(asset.uvs)))
        sections.append((.meshTriangles, SectionBuilder.buildMeshTriangles(asset.triangles, uvTris: asset.triangleUVIndices)))
        sections.append((.vertexGroups, SectionBuilder.buildVertexGroups(asset.vertexGroups)))

        // Tekstura — opcjonalna.
        var flags: FaceFlags = []
        if let tex = asset.textureImage {
            let texData = try TextureConverter.convert(tex)
            sections.append((.textureRGB565, SectionBuilder.buildTextureRGB565(
                width: UInt16(TextureConverter.targetSize),
                height: UInt16(TextureConverter.targetSize),
                pixelsRGB565LE: texData
            )))
            flags.insert(.hasTexture)
        }

        // Blendshapes i delty.
        let (table, deltas) = SectionBuilder.buildBlendshapeTableAndDeltas(asset.blendshapes)
        sections.append((.blendshapeTable, table))
        sections.append((.blendshapeDeltas, deltas))

        // Maski L/R (dzielone przez wszystkie blendshape – same 2 maski).
        // Sekcję zapisujemy tylko, gdy choć jeden blendshape dostarcza maski;
        // w przeciwnym wypadku sekcja 0x0022 jest pominięta (reader i tak traktuje
        // ją jako opcjonalną, patrz FORMAT_SPEC §15).
        let hasAnyMask = asset.blendshapes.contains { $0.maskLeft != nil || $0.maskRight != nil }
        if hasAnyMask {
            let emptyMask = [UInt8](repeating: 0, count: asset.vertices.count)
            let maskL: [UInt8] = asset.blendshapes.first(where: { $0.maskLeft != nil })?.maskLeft ?? emptyMask
            let maskR: [UInt8] = asset.blendshapes.first(where: { $0.maskRight != nil })?.maskRight ?? emptyMask
            if maskL.count == asset.vertices.count && maskR.count == asset.vertices.count {
                sections.append((.masks, SectionBuilder.buildMasks(left: maskL, right: maskR)))
            }
        }

        // Performance clips.
        if !asset.performanceClips.isEmpty {
            sections.append((.performanceClips, SectionBuilder.buildPerformanceClips(asset.performanceClips)))
            flags.insert(.hasPerformance)
        }

        // Rigid pieces.
        if let eyes = asset.eyes {
            sections.append((.eyeSpheres, SectionBuilder.buildEyeSpheres(eyes)))
            flags.insert(.hasEyes)
        }
        if let teeth = asset.teeth {
            sections.append((.teethRow, SectionBuilder.buildTeethRow(teeth)))
            flags.insert(.hasTeeth)
        }
        if let tongue = asset.tongue {
            sections.append((.tongue, SectionBuilder.buildTongue(tongue)))
            flags.insert(.hasTongue)
        }
        if let mouth = asset.mouthCavity {
            sections.append((.mouthCavity, SectionBuilder.buildMouthCavity(mouth)))
            flags.insert(.hasMouthCavity)
        }

        if asset.lidarUsed { flags.insert(.hasLiDAR) }

        // 2. Liczymy offsety sekcji (32B-aligned). Layout:
        //    [header 48B] [section_dir N×32B] [pad do 32B] [sekcje…]
        let headerSize = FaceFileFormat.fileHeaderSize
        let dirSize = sections.count * FaceFileFormat.sectionDirEntrySize
        var cursor = headerSize + dirSize
        cursor = alignUp(cursor, to: FaceFileFormat.sectionAlignment)

        var dirEntries: [(SectionID, UInt32, UInt64, UInt64, UInt64)] = []
        // (id, flags, offset, size, uncompressed_size)
        for (id, data) in sections {
            let off = UInt64(cursor)
            let size = UInt64(data.count)
            dirEntries.append((id, 0, off, size, size))
            cursor += data.count
            cursor = alignUp(cursor, to: FaceFileFormat.sectionAlignment)
        }
        let totalSize = cursor

        // 3. Budujemy nagłówek i dyrektorium sekcji.
        let w = ByteWriter(reserving: totalSize)

        // Nagłówek — 48B.
        w.writeBytes(FaceFileFormat.magic)              // 0..4
        w.writeU16(FaceFileFormat.versionMajor)         // 4..6
        w.writeU16(FaceFileFormat.versionMinor)         // 6..8
        w.writeU32(flags.rawValue)                      // 8..12
        w.writeU16(UInt16(sections.count))              // 12..14
        w.writeU16(0)                                   // 14..16 _pad0
        w.writeU64(UInt64(totalSize))                   // 16..24
        let crcOffset = w.offset
        w.writeU32(0)                                   // 24..28 crc32 placeholder
        w.writeU32(0)                                   // 28..32 _pad1
        w.writeU64(UInt64(asset.createdAt.timeIntervalSince1970)) // 32..40
        w.writeFixedAscii(FaceFileFormat.producerTag, length: 8)  // 40..48

        // Dyrektorium sekcji.
        for (id, f, off, size, uncSize) in dirEntries {
            w.writeU32(id.rawValue)
            w.writeU32(f)
            w.writeU64(off)
            w.writeU64(size)
            w.writeU64(uncSize)
        }
        w.padTo(alignment: FaceFileFormat.sectionAlignment)

        // Body sekcji.
        for (_, data) in sections {
            w.writeBytes(data)
            w.padTo(alignment: FaceFileFormat.sectionAlignment)
        }

        // 4. CRC32 po wszystkim (z wyzerowanym polem crc32).
        let crcRange = crcOffset..<(crcOffset + 4)
        let crc = CRC32.compute(w.data, skipping: crcRange)
        try w.overwriteU32(at: crcOffset, value: crc)

        // 5. Zapis do pliku.
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let fileName = safeFileName(asset.profileName) + ".face"
        let url = outputDirectory.appendingPathComponent(fileName)

        do {
            try w.data.write(to: url, options: .atomic)
        } catch {
            throw FacecapError.fileWriteFailed(error.localizedDescription)
        }
        AppLog.export.info("Writer: done, file=\(url.lastPathComponent, privacy: .public), size=\(totalSize)")
        return url
    }

    // MARK: — Pomocnicze

    private func alignUp(_ value: Int, to alignment: Int) -> Int {
        let rem = value % alignment
        return rem == 0 ? value : value + (alignment - rem)
    }

    private func safeFileName(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let joined = String(scalars)
        return joined.isEmpty ? "profile" : joined
    }
}
