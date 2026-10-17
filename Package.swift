// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Aura",
    platforms: [.macOS(.v15)],
    products: [.library(name: "AuraCore", targets: ["AuraCore"])],
    targets: [
        .target(name: "AuraCore", path: "Aura/Aura",
                exclude: ["App/AuraApp.swift", "App/AppCommands.swift", "Views", "Resources"]),
        .testTarget(name: "AuraCoreTests", dependencies: ["AuraCore"], path: "Aura/AuraTests")
    ],
    swiftLanguageModes: [.v6]
)
