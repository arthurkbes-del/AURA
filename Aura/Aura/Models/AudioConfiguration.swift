// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct AudioConfiguration: Codable, Equatable, Sendable {
    public var modules: [EqualizerModule] = (1...4).map { EqualizerModule(name: "EQ \($0)") }
    public var processingEnabled = true
    public var inputGain: Double = -6
    public var masterGain: Double = -6

    public init() {}

    public mutating func normalize(sampleRate: Double = 48_000) {
        modules = Array(modules.prefix(4))
        while modules.count < 4 { modules.append(EqualizerModule(name: "EQ \(modules.count + 1)")) }
        var seen = Set<UUID>()
        for index in modules.indices {
            if !seen.insert(modules[index].id).inserted { modules[index].id = UUID() }
            modules[index].normalize(sampleRate: sampleRate)
        }
        inputGain = clamped(inputGain, to: -48...0, fallback: -6)
        masterGain = clamped(masterGain, to: -60...12, fallback: -6)
    }
}
