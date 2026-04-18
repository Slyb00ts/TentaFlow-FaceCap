// swift-tools-version:5.10
// =============================================================================
// Plik: Package.swift
// Opis: Manifest SPM dla modułu FaceCalibration — kalibracja 52 AU ARKit z NNLS.
// =============================================================================

import PackageDescription

let package = Package(
    name: "FaceCalibration",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "FaceCalibration",
            targets: ["FaceCalibration"]
        )
    ],
    dependencies: [
        .package(path: "../Shared")
    ],
    targets: [
        .target(
            name: "FaceCalibration",
            dependencies: [
                .product(name: "Shared", package: "Shared")
            ],
            path: "Sources/FaceCalibration"
        )
    ]
)
