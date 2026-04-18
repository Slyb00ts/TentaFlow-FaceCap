// swift-tools-version:5.10
// =============================================================================
// Plik: Package.swift
// Opis: Manifest SPM dla pakietu Preview – Metal renderer avatara (live podgląd).
// =============================================================================

import PackageDescription

let package = Package(
    name: "Preview",
    defaultLocalization: "pl",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Preview",
            targets: ["Preview"]
        )
    ],
    dependencies: [
        .package(path: "../Shared"),
        .package(path: "../Export"),
        .package(path: "../FaceCalibration"),
        .package(path: "../AssetInjection"),
        .package(path: "../PerformanceCapture")
    ],
    targets: [
        .target(
            name: "Preview",
            dependencies: [
                .product(name: "Shared", package: "Shared"),
                .product(name: "Export", package: "Export"),
                .product(name: "FaceCalibration", package: "FaceCalibration"),
                .product(name: "AssetInjection", package: "AssetInjection"),
                .product(name: "PerformanceCapture", package: "PerformanceCapture")
            ],
            path: "Sources/Preview"
        )
    ]
)
