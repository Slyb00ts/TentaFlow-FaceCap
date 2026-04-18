// =============================================================================
// Plik: IrisColorSampler.swift
// Opis: Sampluje średni kolor tęczówki z tekstury skanu (CoreImage CIAreaAverage).
// =============================================================================

import Foundation
import CoreImage
import CoreGraphics
import simd

/// Kolor RGB565 dla display ESP32-P4.
public struct Rgb565: Sendable, Equatable {
    public let value: UInt16

    public init(value: UInt16) { self.value = value }

    public static func fromRgb888(r: UInt8, g: UInt8, b: UInt8) -> Rgb565 {
        let r5 = UInt16(r >> 3) & 0x1F
        let g6 = UInt16(g >> 2) & 0x3F
        let b5 = UInt16(b >> 3) & 0x1F
        return Rgb565(value: (r5 << 11) | (g6 << 5) | b5)
    }
}

/// Próbki kolorów tęczówek.
public struct IrisColors: Sendable {
    public let left: Rgb565
    public let right: Rgb565

    public init(left: Rgb565, right: Rgb565) { self.left = left; self.right = right }
}

/// Sampler średniego koloru z regionu tęczówki.
public struct IrisColorSampler {
    public let context: CIContext
    public let irisRadiusUV: Float

    public init(context: CIContext? = nil, irisRadiusUV: Float = 0.02) {
        self.context = context ?? CIContext(options: [.cacheIntermediates: false])
        self.irisRadiusUV = irisRadiusUV
    }

    /// Sampluje średni kolor z okręgu UV wokół podanego środka.
    public func sample(texture: CGImage, centerUV: SIMD2<Float>) -> Rgb565 {
        let width = CGFloat(texture.width)
        let height = CGFloat(texture.height)
        let centerPx = CGPoint(x: CGFloat(centerUV.x) * width,
                               y: CGFloat(1.0 - centerUV.y) * height)  // Flip Y dla UV.
        let radiusPx = CGFloat(irisRadiusUV) * min(width, height)
        let rect = CGRect(
            x: max(0, centerPx.x - radiusPx),
            y: max(0, centerPx.y - radiusPx),
            width: min(width - max(0, centerPx.x - radiusPx), radiusPx * 2),
            height: min(height - max(0, centerPx.y - radiusPx), radiusPx * 2)
        )

        let ciImage = CIImage(cgImage: texture)
        let filter = CIFilter(name: "CIAreaAverage")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgRect: rect), forKey: kCIInputExtentKey)

        guard let outputImage = filter?.outputImage else {
            return Rgb565(value: 0x8410) // neutral gray fallback.
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let outRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        context.render(outputImage,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: outRect,
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        return Rgb565.fromRgb888(r: bitmap[0], g: bitmap[1], b: bitmap[2])
    }

    /// Sampluje kolory dla obu oczu.
    public func sampleBothEyes(
        texture: CGImage,
        leftCenterUV: SIMD2<Float>,
        rightCenterUV: SIMD2<Float>
    ) -> IrisColors {
        let leftColor = sample(texture: texture, centerUV: leftCenterUV)
        let rightColor = sample(texture: texture, centerUV: rightCenterUV)
        return IrisColors(left: leftColor, right: rightColor)
    }
}
