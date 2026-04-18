// swift-tools-version:5.10
// =============================================================================
// Plik: Package.swift
// Opis: Manifest SPM dla pakietu Export — writer, CRC32, konwersja tekstur.
// =============================================================================

import PackageDescription

let package = Package(
    name: "Export",
    defaultLocalization: "pl",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Export",
            targets: ["Export"]
        )
    ],
    dependencies: [
        .package(path: "../Shared")
    ],
    targets: [
        .target(
            name: "Export",
            dependencies: ["Shared"],
            path: "Sources/Export"
        )
    ]
)
