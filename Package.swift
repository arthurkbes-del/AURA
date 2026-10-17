// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
    name: "Aura",
    platforms: [.macOS(.v15)],
    products: [.library(name: "AuraCore", targets: ["AuraCore"]),
               .executable(name: "AURA", targets: ["AuraApp"])],
    targets: [
        .target(name: "AuraCore", path: "Aura/Aura",
                exclude: ["App/AuraApp.swift", "App/AppCommands.swift", "Views", "Resources"]),
        .executableTarget(name: "AuraApp", dependencies: ["AuraCore"], path: "Aura/Aura",
                          exclude: ["Audio", "Models", "Persistence", "Branding", "App/AppState.swift", "Resources"],
                          sources: ["App/AuraApp.swift", "App/AppCommands.swift", "Views"]),
        .executableTarget(name: "AuraValidation", dependencies: ["AuraCore"], path: "Validation",
                          exclude: ["EQCapabilityProbe.swift", "GenerateIcons.swift", "ProcessTapProbe.swift", "run-process-tap-probe.sh"], sources: ["EngineValidation.swift"]),
        .executableTarget(name: "AuraIconGenerator", dependencies: ["AuraCore"], path: "Validation",
                          exclude: ["EQCapabilityProbe.swift", "EngineValidation.swift", "ProcessTapProbe.swift", "run-process-tap-probe.sh"], sources: ["GenerateIcons.swift"]),
        .testTarget(name: "AuraCoreTests", dependencies: ["AuraCore"], path: "Aura/AuraTests")
    ],
    swiftLanguageModes: [.v6]
)
