// =============================================================================
// Plik: AssetInjectionResult.swift
// Opis: Zbiorczy wynik injekcji assetów — oczy, zęby, język, wnętrze ust.
// =============================================================================

import Foundation
import CoreGraphics
import simd

/// Para sfer oczu + placement.
public struct EyeSpheresAsset: Sendable {
    public let leftMesh: EyeSphereMesh
    public let rightMesh: EyeSphereMesh
    public let placement: EyeSpherePlacement
    public let irisColors: IrisColors

    public init(leftMesh: EyeSphereMesh, rightMesh: EyeSphereMesh, placement: EyeSpherePlacement, irisColors: IrisColors) {
        self.leftMesh = leftMesh
        self.rightMesh = rightMesh
        self.placement = placement
        self.irisColors = irisColors
    }
}

/// Para łuków zębów + placement.
public struct TeethAsset: Sendable {
    public let mesh: TeethRowMesh
    public let placement: TeethPlacement

    public init(mesh: TeethRowMesh, placement: TeethPlacement) {
        self.mesh = mesh
        self.placement = placement
    }
}

/// Język + placement.
public struct TongueAsset: Sendable {
    public let mesh: TongueMesh
    public let placement: TonguePlacement

    public init(mesh: TongueMesh, placement: TonguePlacement) {
        self.mesh = mesh
        self.placement = placement
    }
}

/// Wnętrze jamy ustnej + placement.
public struct MouthCavityAsset: Sendable {
    public let mesh: MouthCavityMesh
    public let placement: MouthCavityPlacement

    public init(mesh: MouthCavityMesh, placement: MouthCavityPlacement) {
        self.mesh = mesh
        self.placement = placement
    }
}

/// Zbiorczy wynik injekcji rigid pieces.
public struct AssetInjectionResult: Sendable {
    public let eyes: EyeSpheresAsset
    public let teeth: TeethAsset
    public let tongue: TongueAsset
    public let mouthCavity: MouthCavityAsset

    public init(eyes: EyeSpheresAsset, teeth: TeethAsset, tongue: TongueAsset, mouthCavity: MouthCavityAsset) {
        self.eyes = eyes
        self.teeth = teeth
        self.tongue = tongue
        self.mouthCavity = mouthCavity
    }
}

/// Landmarki ust używane przez pozycjonery.
public struct MouthLandmarks: Sendable {
    public let upperLipInner: SIMD3<Float>
    public let lowerLipInner: SIMD3<Float>
    public let cornerLeft: SIMD3<Float>
    public let cornerRight: SIMD3<Float>

    public init(upperLipInner: SIMD3<Float>, lowerLipInner: SIMD3<Float>, cornerLeft: SIMD3<Float>, cornerRight: SIMD3<Float>) {
        self.upperLipInner = upperLipInner
        self.lowerLipInner = lowerLipInner
        self.cornerLeft = cornerLeft
        self.cornerRight = cornerRight
    }
}

/// Landmarki oczu dla pozycjonera.
public struct EyeLandmarks: Sendable {
    public let leftEyeTransform: simd_float4x4
    public let rightEyeTransform: simd_float4x4
    public let faceTransform: simd_float4x4

    public init(leftEyeTransform: simd_float4x4, rightEyeTransform: simd_float4x4, faceTransform: simd_float4x4) {
        self.leftEyeTransform = leftEyeTransform
        self.rightEyeTransform = rightEyeTransform
        self.faceTransform = faceTransform
    }
}

/// Wysokopoziomowy koordynator injekcji rigid pieces.
public struct AssetInjectionPipeline: Sendable {
    public init() {}

    /// Tworzy komplet rigid pieces.
    public func run(
        eyeLandmarks: EyeLandmarks,
        mouthLandmarks: MouthLandmarks,
        scanTexture: CGImage,
        leftIrisUV: SIMD2<Float>,
        rightIrisUV: SIMD2<Float>
    ) -> AssetInjectionResult {
        let eyeGen = EyeSphereGenerator()
        let eyePositioner = EyePositioner()
        let eyePlacement = eyePositioner.placement(
            leftEyeTransform: eyeLandmarks.leftEyeTransform,
            rightEyeTransform: eyeLandmarks.rightEyeTransform,
            faceTransform: eyeLandmarks.faceTransform
        )
        let eyeMesh = eyeGen.generate()
        let sampler = IrisColorSampler()
        let iris = sampler.sampleBothEyes(
            texture: scanTexture,
            leftCenterUV: leftIrisUV,
            rightCenterUV: rightIrisUV
        )
        let eyes = EyeSpheresAsset(
            leftMesh: eyeMesh,
            rightMesh: eyeMesh,
            placement: eyePlacement,
            irisColors: iris
        )

        let teethGen = TeethRowGenerator()
        let teethMesh = teethGen.generate()
        let teethPositioner = TeethPositioner()
        let teethPlacement = teethPositioner.placement(
            upperLipInner: mouthLandmarks.upperLipInner,
            lowerLipInner: mouthLandmarks.lowerLipInner,
            mouthCornerLeft: mouthLandmarks.cornerLeft,
            mouthCornerRight: mouthLandmarks.cornerRight
        )
        let teeth = TeethAsset(mesh: teethMesh, placement: teethPlacement)

        let tongueGen = TongueGenerator()
        let tongueMesh = tongueGen.generate()
        let tonguePositioner = TonguePositioner()
        let tonguePlacement = tonguePositioner.placement(
            lowerLipInner: mouthLandmarks.lowerLipInner,
            upperLipInner: mouthLandmarks.upperLipInner,
            mouthCornerLeft: mouthLandmarks.cornerLeft,
            mouthCornerRight: mouthLandmarks.cornerRight
        )
        let tongue = TongueAsset(mesh: tongueMesh, placement: tonguePlacement)

        let cavityGen = MouthCavityGenerator()
        let cavityMesh = cavityGen.generate()
        let cavityPositioner = MouthCavityPositioner()
        let cavityPlacement = cavityPositioner.placement(
            upperLipInner: mouthLandmarks.upperLipInner,
            lowerLipInner: mouthLandmarks.lowerLipInner,
            mouthCornerLeft: mouthLandmarks.cornerLeft,
            mouthCornerRight: mouthLandmarks.cornerRight
        )
        let cavity = MouthCavityAsset(mesh: cavityMesh, placement: cavityPlacement)

        return AssetInjectionResult(
            eyes: eyes,
            teeth: teeth,
            tongue: tongue,
            mouthCavity: cavity
        )
    }
}
