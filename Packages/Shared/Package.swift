// swift-tools-version:5.10
// =============================================================================
// Plik: Package.swift
// Opis: Manifest SPM dla pakietu Shared – wspólne narzędzia (Logger, math, UI).
// =============================================================================

import PackageDescription

let package = Package(
    name: "Shared",
    defaultLocalization: "pl",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Shared",
            targets: ["Shared"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Shared",
            dependencies: [],
            path: "Sources/Shared"
        )
    ]
)
