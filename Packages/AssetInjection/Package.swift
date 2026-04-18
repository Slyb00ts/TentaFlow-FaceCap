// swift-tools-version:5.10
// =============================================================================
// Plik: Package.swift
// Opis: Manifest SPM dla modułu AssetInjection — rigid pieces (oczy/zęby/język/wnętrze ust).
// =============================================================================

import PackageDescription

let package = Package(
    name: "AssetInjection",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "AssetInjection",
            targets: ["AssetInjection"]
        )
    ],
    dependencies: [
        .package(path: "../Shared")
    ],
    targets: [
        .target(
            name: "AssetInjection",
            dependencies: [
                .product(name: "Shared", package: "Shared")
            ],
            path: "Sources/AssetInjection"
        )
    ]
)
