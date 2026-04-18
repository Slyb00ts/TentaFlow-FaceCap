// =============================================================================
// Plik: FaceFileFormat.swift
// Opis: Stałe i enumeracje formatu binarnego .face v3 (magic, section ID, flagi).
// =============================================================================

import Foundation

/// Namespace z parametrami formatu binarnego `.face v3`. Wartości muszą być
/// identyczne po stronie iOS (writer) i po stronie ESP32-P4 (reader).
public enum FaceFileFormat {

    /// Sygnatura pliku — 4 bajty ASCII „FACE”.
    public static let magic: [UInt8] = [0x46, 0x41, 0x43, 0x45]

    /// Wersja formatu — major/minor.
    public static let versionMajor: UInt16 = 3
    public static let versionMinor: UInt16 = 0

    /// Rozmiar nagłówka pliku.
    public static let fileHeaderSize: Int = 48

    /// Rozmiar wpisu w tabeli sekcji.
    public static let sectionDirEntrySize: Int = 32

    /// Wyrównanie każdej sekcji do 32 bajtów.
    public static let sectionAlignment: Int = 32

    /// Etykieta producenta (ASCII, 8 B, null-padded).
    public static let producerTag: String = "iOSv1.00"
}

/// Identyfikatory sekcji w pliku `.face v3`.
public enum SectionID: UInt32, CaseIterable {
    case meshGeometry       = 0x0001
    case meshNormals        = 0x0002
    case meshUVs            = 0x0003
    case meshTriangles      = 0x0004
    case vertexGroups       = 0x0005

    case textureRGB565      = 0x0010

    case blendshapeTable    = 0x0020
    case blendshapeDeltas   = 0x0021
    case masks              = 0x0022

    case performanceClips   = 0x0030

    case eyeSpheres         = 0x0041
    case teethRow           = 0x0042
    case tongue             = 0x0043
    case mouthCavity        = 0x0044
}

/// Flagi zapisywane w nagłówku pliku.
public struct FaceFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let hasPerformance   = FaceFlags(rawValue: 1 << 0)
    public static let hasLiDAR         = FaceFlags(rawValue: 1 << 1)
    public static let hasTexture       = FaceFlags(rawValue: 1 << 2)
    public static let hasEyes          = FaceFlags(rawValue: 1 << 3)
    public static let hasTeeth         = FaceFlags(rawValue: 1 << 4)
    public static let hasTongue        = FaceFlags(rawValue: 1 << 5)
    public static let hasMouthCavity   = FaceFlags(rawValue: 1 << 6)
}

/// Flagi pojedynczego wpisu blendshape.
public struct BlendshapeFlags: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let sparse   = BlendshapeFlags(rawValue: 1 << 0)
    public static let hasMaskL = BlendshapeFlags(rawValue: 1 << 1)
    public static let hasMaskR = BlendshapeFlags(rawValue: 1 << 2)
}
