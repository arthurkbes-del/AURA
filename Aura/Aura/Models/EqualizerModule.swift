// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct EqualizerModule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var enabled = true
    public var bypassed = false
    public var bands: [EqualizerBand]
    public var outputGain: Double = 0
    public var presetName = "Flat"
    public var presetID: UUID?

    public init(id: UUID = UUID(), name: String, bands: [EqualizerBand] = [EqualizerBand()]) {
        self.id = id; self.name = name; self.bands = bands
    }

    public mutating func addBand() {
        guard bands.count < 32 else { return }
        bands.append(EqualizerBand())
        presetName = "Custom"
    }

    public mutating func removeBand(id: UUID) {
        guard bands.count > 1 else { return }
        bands.removeAll { $0.id == id }
        presetName = "Custom"
    }

    public mutating func normalize(sampleRate: Double = 48_000) {
        name = String(name.prefix(64))
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = "Equalizer" }
        bands = Array(bands.prefix(32))
        if bands.isEmpty { bands = [EqualizerBand()] }
        var seen = Set<UUID>()
        for index in bands.indices {
            if !seen.insert(bands[index].id).inserted { bands[index].id = UUID() }
            bands[index].normalize(sampleRate: sampleRate)
        }
        outputGain = clamped(outputGain, to: -24...24, fallback: 0)
    }

    public mutating func apply(_ preset: EqualizerPreset) {
        bands = preset.bands.map {
            var band = $0; band.id = UUID(); return band
        }
        outputGain = preset.outputGain
        presetName = preset.name
        presetID = preset.id
        normalize()
    }

    public mutating func reset() {
        bands = [EqualizerBand()]; outputGain = 0
        enabled = true; bypassed = false; presetName = "Flat"; presetID = nil
    }
}
