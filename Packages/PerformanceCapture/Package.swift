// swift-tools-version:5.10
// =============================================================================
// Plik: Package.swift
// Opis: Manifest SPM dla pakietu PerformanceCapture – nagrywanie timeline AU
//       (52 blendshapes @60Hz) + audio PCM, odtwarzanie klipów.
// =============================================================================

import PackageDescription

let package = Package(
    name: "PerformanceCapture",
    defaultLocalization: "pl",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "PerformanceCapture",
            targets: ["PerformanceCapture"]
        )
    ],
    dependencies: [
        .package(path: "../Shared"),
        .package(path: "../FaceCalibration")
    ],
    targets: [
        .target(
            name: "PerformanceCapture",
            dependencies: [
                .product(name: "Shared", package: "Shared"),
                .product(name: "FaceCalibration", package: "FaceCalibration")
            ],
            path: "Sources/PerformanceCapture"
        )
    ]
)
