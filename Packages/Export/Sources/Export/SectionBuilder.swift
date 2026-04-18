// =============================================================================
// Plik: SectionBuilder.swift
// Opis: Budowanie ciał kolejnych sekcji formatu .face v3 (każda zwraca Data).
// =============================================================================

import Foundation
import simd
import Shared

/// Zestaw funkcji, z których każda buduje Data jednej sekcji.
public enum SectionBuilder {

    // MARK: — 0x0001 MESH_GEOMETRY

    public static func buildMeshGeometry(_ vertices: [Vec3]) -> Data {
        let w = ByteWriter(reserving: 16 + vertices.count * 12)
        w.writeU32(UInt32(vertices.count))
        w.writeZeros(12)
        for v in vertices { w.writeVec3(v) }
        w.padPad32()
        return w.data
    }

    // MARK: — 0x0002 MESH_NORMALS

    public static func buildMeshNormals(_ normals: [Vec3]) -> Data {
        // Identyczna budowa jak geometry.
        buildMeshGeometry(normals)
    }

    // MARK: — 0x0003 MESH_UVS

    public static func buildMeshUVs(_ uvs: [Vec2]) -> Data {
        let w = ByteWriter(reserving: 16 + uvs.count * 8)
        w.writeU32(UInt32(uvs.count))
        w.writeZeros(12)
        for uv in uvs { w.writeVec2(uv) }
        w.padPad32()
        return w.data
    }

    // MARK: — 0x0004 MESH_TRIANGLES

    public static func buildMeshTriangles(_ tris: [SIMD3<UInt16>],
                                          uvTris: [SIMD3<UInt16>]?) -> Data {
        let hasUV: UInt8 = (uvTris != nil) ? 1 : 0
        let w = ByteWriter(reserving: 16 + tris.count * 6 + (uvTris?.count ?? 0) * 6)
        w.writeU32(UInt32(tris.count))
        w.writeU8(hasUV)
        w.writeZeros(11)
        for t in tris { w.writeTri(t) }
        w.padPad32()
        if let uvTris {
            for t in uvTris { w.writeTri(t) }
            w.padPad32()
        }
        return w.data
    }

    // MARK: — 0x0005 VERTEX_GROUPS

    public static func buildVertexGroups(_ groups: [UInt8]) -> Data {
        let w = ByteWriter(reserving: 16 + groups.count)
        w.writeU32(UInt32(groups.count))
        w.writeZeros(12)
        w.writeBytes(groups)
        w.padPad32()
        return w.data
    }

    // MARK: — 0x0010 TEXTURE_RGB565

    public static func buildTextureRGB565(width: UInt16,
                                          height: UInt16,
                                          pixelsRGB565LE: Data) -> Data {
        let w = ByteWriter(reserving: 16 + pixelsRGB565LE.count)
        w.writeU16(width)
        w.writeU16(height)
        w.writeU8(0)            // format = 0 (RGB565 LE)
        w.writeU8(1)            // mip_count = 1
        w.writeZeros(10)        // pad do 16 bajtów nagłówka sekcji
        w.writeBytes(pixelsRGB565LE)
        w.padPad32()
        return w.data
    }

    // MARK: — 0x0020 BLENDSHAPE_TABLE (+ 0x0021 DELTAS razem)

    /// Buduje tabelę blendshape oraz strumień delt. Zwraca dwie Data.
    /// Offsety i counts w tabeli wskazują na pozycje w strumieniu delt.
    public static func buildBlendshapeTableAndDeltas(
        _ entries: [BlendshapeEntry]
    ) -> (table: Data, deltas: Data) {

        let tableW = ByteWriter(reserving: 16 + entries.count * 32)
        let deltaW = ByteWriter(reserving: entries.count * 1024)

        tableW.writeU32(UInt32(entries.count))
        tableW.writeZeros(12)

        for entry in entries {
            let startOffset = UInt32(deltaW.offset)
            let encoded: (data: Data, count: UInt32)
            if entry.sparse {
                encoded = SparseDeltaEncoder.encode(deltas: entry.deltas)
            } else {
                encoded = SparseDeltaEncoder.encodeDense(deltas: entry.deltas)
            }
            deltaW.writeBytes(encoded.data)
            // Wyrównanie strumienia delt co 4 bajty – utrzymuje naturalne granice f16×3.
            deltaW.padTo(alignment: 4)

            var flags: BlendshapeFlags = []
            if entry.sparse { flags.insert(.sparse) }
            if entry.maskLeft != nil { flags.insert(.hasMaskL) }
            if entry.maskRight != nil { flags.insert(.hasMaskR) }

            tableW.writeU8(entry.arkitIndex)
            tableW.writeU8(flags.rawValue)
            let nameBytes = Array(entry.name.utf8.prefix(24))
            tableW.writeU8(UInt8(nameBytes.count))
            tableW.writeU8(0)               // pad
            // [u8;24] — ASCII, null-padded.
            let paddedName = nameBytes + [UInt8](repeating: 0, count: 24 - nameBytes.count)
            tableW.writeBytes(paddedName)
            tableW.writeU32(startOffset)
            tableW.writeU32(encoded.count)
        }
        tableW.padPad32()
        deltaW.padPad32()
        return (tableW.data, deltaW.data)
    }

    // MARK: — 0x0022 MASKS

    public static func buildMasks(left: [UInt8], right: [UInt8]) -> Data {
        let w = ByteWriter(reserving: 16 + left.count + right.count + 64)
        w.writeU32(UInt32(left.count))
        w.writeZeros(12)
        w.writeBytes(left)
        w.padPad32()
        w.writeBytes(right)
        w.padPad32()
        return w.data
    }

    // MARK: — 0x0030 PERFORMANCE_CLIPS

    public static func buildPerformanceClips(_ clips: [PerformanceClip]) -> Data {
        let w = ByteWriter(reserving: 16 + clips.count * 44 + 1024)
        w.writeU16(UInt16(clips.count))
        w.writeZeros(14)

        // Kanoniczny layout wpisu klipu (FORMAT_SPEC §16.2) — 44 B:
        //   0..24  name (u8[24])
        //   24     fps (u8)
        //   25     _pad (u8 = 0)
        //   26..30 frame_count (u32)
        //   30..34 weights_offset (u32, patch później)
        //   34..38 audio_offset (u32, patch później)
        //   38..42 audio_size (u32, patch później)
        //   42..44 _pad_tail (u16 = 0)

        // Zapamiętujemy offsety wpisów w tabeli (do późniejszego patchowania).
        var entryStarts = [Int]()
        for clip in clips {
            entryStarts.append(w.offset)
            var nameBytes = Array(clip.name.utf8.prefix(24))
            if nameBytes.count < 24 {
                nameBytes.append(contentsOf: [UInt8](repeating: 0, count: 24 - nameBytes.count))
            }
            w.writeBytes(nameBytes)             // 24
            w.writeU8(clip.fps)                 // 25
            w.writeU8(0)                        // 26 pad
            w.writeU32(clip.frameCount)         // 30
            w.writeU32(0)                       // 34 weights_offset (patch później)
            w.writeU32(0)                       // 38 audio_offset (patch później)
            w.writeU32(0)                       // 42 audio_size (patch później)
            w.writeU16(0)                       // 44 _pad_tail
        }
        w.padPad32()

        // Dalej: sklejone bajty wag (52 × suma frameCount), potem audio.
        var weightsOffsets = [UInt32]()
        let weightsBlobStart = w.offset
        for clip in clips {
            weightsOffsets.append(UInt32(w.offset - weightsBlobStart))
            let blob = PerformanceQuantizer.quantizeWeights(clip.weights)
            w.writeBytes(blob)
        }
        w.padPad32()

        var audioOffsets = [UInt32]()
        var audioSizes = [UInt32]()
        let audioBlobStart = w.offset
        for clip in clips {
            if let pcm = clip.audioPCM {
                audioOffsets.append(UInt32(w.offset - audioBlobStart))
                let blob = PerformanceQuantizer.convertAudioToS16LE(pcm)
                audioSizes.append(UInt32(blob.count))
                w.writeBytes(blob)
                w.padTo(alignment: 2)
            } else {
                audioOffsets.append(0)
                audioSizes.append(0)
            }
        }
        w.padPad32()

        // Patchujemy offsety weights/audio/size w każdym wpisie.
        for (i, start) in entryStarts.enumerated() {
            // weights_offset jest liczony względem początku blobu wag.
            let weightsAbs = UInt32(weightsBlobStart) + weightsOffsets[i]
            try? w.overwriteU32(at: start + 30, value: weightsAbs)
            if audioSizes[i] > 0 {
                let audioAbs = UInt32(audioBlobStart) + audioOffsets[i]
                try? w.overwriteU32(at: start + 34, value: audioAbs)
                try? w.overwriteU32(at: start + 38, value: audioSizes[i])
            }
        }
        return w.data
    }

    // MARK: — 0x0041 EYE_SPHERES

    public static func buildEyeSpheres(_ eyes: EyeSpheres) -> Data {
        let w = ByteWriter(reserving: 256)
        w.writeU32(UInt32(eyes.leftVertices.count))
        for v in eyes.leftVertices { w.writeVec3(v) }
        for v in eyes.rightVertices { w.writeVec3(v) }
        for uv in eyes.leftUVs { w.writeVec2(uv) }
        for uv in eyes.rightUVs { w.writeVec2(uv) }
        w.writeVec3(eyes.leftCenter)
        w.writeVec3(eyes.rightCenter)
        w.writeF32(eyes.radius)
        w.writeU16(eyes.irisColorLeft)
        w.writeU16(eyes.irisColorRight)
        w.padPad32()
        return w.data
    }

    // MARK: — 0x0042 TEETH_ROW

    public static func buildTeethRow(_ teeth: TeethRow) -> Data {
        let w = ByteWriter(reserving: 128)
        w.writeU32(UInt32(teeth.upperVertices.count))
        for v in teeth.upperVertices { w.writeVec3(v) }
        w.writeU32(UInt32(teeth.lowerVertices.count))
        for v in teeth.lowerVertices { w.writeVec3(v) }
        for t in teeth.triangles { w.writeTri(t) }
        w.padPad32()
        return w.data
    }

    // MARK: — 0x0043 TONGUE

    public static func buildTongue(_ tongue: Tongue) -> Data {
        let w = ByteWriter(reserving: 128)
        w.writeU32(UInt32(tongue.vertices.count))
        for v in tongue.vertices { w.writeVec3(v) }
        for t in tongue.triangles { w.writeTri(t) }
        w.padPad32()
        return w.data
    }

    // MARK: — 0x0044 MOUTH_CAVITY

    public static func buildMouthCavity(_ mouth: MouthCavity) -> Data {
        let w = ByteWriter(reserving: 128)
        w.writeU32(UInt32(mouth.vertices.count))
        for v in mouth.vertices { w.writeVec3(v) }
        for t in mouth.triangles { w.writeTri(t) }
        w.writeU16(mouth.colorRGB565)
        w.padPad32()
        return w.data
    }
}
