// =============================================================================
// Plik: TextureConverter.swift
// Opis: Konwersja CGImage → 512×512 RGB565 LE (Data) z użyciem CoreImage + CVPixelBuffer.
// =============================================================================

import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Accelerate
import CoreVideo
import Shared

/// Konwerter tekstury do formatu wymaganego przez Tab5 (512×512 RGB565 LE).
public enum TextureConverter {

    /// Rozdzielczość docelowa tekstury.
    public static let targetSize: Int = 512

    /// Konwertuje wejściowy obraz do `512×512` RGB565 LE.
    /// Zwraca surowe bajty (`targetSize * targetSize * 2`).
    public static func convert(_ image: CGImage) throws -> Data {
        let sideCG = targetSize

        // 1. Skalowanie przez CoreImage (filtr Lanczos).
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let inputCI = CIImage(cgImage: image)
        let scale = CGFloat(sideCG) / CGFloat(max(image.width, image.height))
        let scaleFilter = CIFilter.lanczosScaleTransform()
        scaleFilter.inputImage = inputCI
        scaleFilter.scale = Float(scale)
        scaleFilter.aspectRatio = 1.0
        guard let scaledCI = scaleFilter.outputImage else {
            throw FacecapError.textureConversionFailed
        }

        // Wycinamy dokładnie 512×512 ze środka.
        let ext = scaledCI.extent
        let originX = (ext.width - CGFloat(sideCG)) * 0.5 + ext.origin.x
        let originY = (ext.height - CGFloat(sideCG)) * 0.5 + ext.origin.y
        let cropRect = CGRect(x: originX, y: originY,
                              width: CGFloat(sideCG), height: CGFloat(sideCG))
        let croppedCI = scaledCI.cropped(to: cropRect)

        // 2. Renderujemy do CVPixelBuffer BGRA8 (CoreImage nie renderuje natywnie do 16LE565).
        let pbAttrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        var bgraPB: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            sideCG, sideCG,
            kCVPixelFormatType_32BGRA,
            pbAttrs as CFDictionary,
            &bgraPB
        )
        guard status == kCVReturnSuccess, let bgra = bgraPB else {
            throw FacecapError.textureConversionFailed
        }
        let renderRect = CGRect(x: 0, y: 0, width: sideCG, height: sideCG)
        context.render(croppedCI,
                       to: bgra,
                       bounds: renderRect,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        // 3. Konwersja BGRA → RGB565 LE. Używamy vImage (szybkie SIMD).
        CVPixelBufferLockBaseAddress(bgra, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(bgra, .readOnly) }

        guard let bgraBase = CVPixelBufferGetBaseAddress(bgra) else {
            throw FacecapError.textureConversionFailed
        }
        let bgraStride = CVPixelBufferGetBytesPerRow(bgra)
        var srcBuffer = vImage_Buffer(
            data: bgraBase,
            height: vImagePixelCount(sideCG),
            width: vImagePixelCount(sideCG),
            rowBytes: bgraStride
        )

        var dstData = Data(count: sideCG * sideCG * 2)
        let dstRow = sideCG * 2
        try dstData.withUnsafeMutableBytes { rawBuf -> Void in
            guard let dstBase = rawBuf.baseAddress else {
                throw FacecapError.textureConversionFailed
            }
            var dstBuffer = vImage_Buffer(
                data: dstBase,
                height: vImagePixelCount(sideCG),
                width: vImagePixelCount(sideCG),
                rowBytes: dstRow
            )
            // vImage konwertuje BGRA8888 → RGB565 (big endian wewnętrznie),
            // po czym my bajtowo zapewniamy LE (na Apple Silicon bajty są już LE).
            let err = vImageConvert_BGRA8888toRGB565(&srcBuffer, &dstBuffer, vImage_Flags(kvImageNoFlags))
            if err != kvImageNoError {
                throw FacecapError.textureConversionFailed
            }
        }

        // Gwarantujemy LE: na Apple Silicon CoreVideo zwraca już LE, ale na wszelki
        // wypadek upewniamy się samodzielnie, bajt po bajcie.
        dstData = ensureLittleEndianU16(dstData)
        return dstData
    }

    /// Zamienia bajty każdej pary 16-bitowej, jeśli trzeba wymusić LE.
    /// Apple Silicon jest LE, więc w praktyce to no-op — ale trzymamy dla pewności.
    private static func ensureLittleEndianU16(_ data: Data) -> Data {
        #if _endian(little)
        return data
        #else
        var result = Data(count: data.count)
        data.withUnsafeBytes { src in
            result.withUnsafeMutableBytes { dst in
                let count = data.count / 2
                let srcPtr = src.bindMemory(to: UInt16.self)
                let dstPtr = dst.bindMemory(to: UInt16.self)
                for i in 0..<count {
                    dstPtr[i] = srcPtr[i].byteSwapped
                }
            }
        }
        return result
        #endif
    }
}
