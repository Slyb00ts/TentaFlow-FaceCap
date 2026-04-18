// swift-tools-version:5.10
// =============================================================================
// Plik: Package.swift
// Opis: Manifest SPM dla modułu HeadScan — skan głowy oparty o ARKit/RealityKit.
// =============================================================================

import PackageDescription

let package = Package(
    name: "HeadScan",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "HeadScan",
            targets: ["HeadScan"]
        )
    ],
    dependencies: [
        .package(path: "../Shared")
    ],
    targets: [
        .target(
            name: "HeadScan",
            dependencies: [
                .product(name: "Shared", package: "Shared")
            ],
            path: "Sources/HeadScan"
        )
    ]
)
