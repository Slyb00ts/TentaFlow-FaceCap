// swift-tools-version:5.10
// =============================================================================
// Plik: Package.swift
// Opis: Manifest SPM dla pakietu Transfer — AirDrop/Files/Wi-Fi upload.
// =============================================================================

import PackageDescription

let package = Package(
    name: "Transfer",
    defaultLocalization: "pl",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Transfer",
            targets: ["Transfer"]
        )
    ],
    dependencies: [
        .package(path: "../Shared")
    ],
    targets: [
        .target(
            name: "Transfer",
            dependencies: ["Shared"],
            path: "Sources/Transfer"
        )
    ]
)
