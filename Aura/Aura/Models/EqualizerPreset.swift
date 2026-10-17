// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct EqualizerPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var bands: [EqualizerBand]
    public var outputGain: Double
    public var isFactory: Bool

    public init(id: UUID = UUID(), name: String, bands: [EqualizerBand],
                outputGain: Double = 0, isFactory: Bool = false) {
        self.id = id; self.name = name; self.bands = bands
        self.outputGain = outputGain; self.isFactory = isFactory
    }

    public static let factory: [EqualizerPreset] = {
        let definitions: [(String, [EqualizerBand])] = [
            ("Flat", [EqualizerBand()]),
            ("Bass Boost", [EqualizerBand(type: .lowShelf, frequency: 100, gain: 5, q: 0.707)]),
            ("Vocal Clarity", [EqualizerBand(type: .highPass, frequency: 75, q: 0.707),
                              EqualizerBand(frequency: 300, gain: -2), EqualizerBand(frequency: 2_800, gain: 3)]),
            ("Warm", [EqualizerBand(type: .lowShelf, frequency: 180, gain: 3, q: 0.707),
                      EqualizerBand(type: .highShelf, frequency: 6_000, gain: -2, q: 0.707)]),
            ("Bright", [EqualizerBand(type: .highShelf, frequency: 4_500, gain: 4, q: 0.707)]),
            ("Music", [EqualizerBand(type: .lowShelf, frequency: 90, gain: 2, q: 0.707),
                       EqualizerBand(frequency: 600, gain: -1.5),
                       EqualizerBand(type: .highShelf, frequency: 8_000, gain: 2, q: 0.707)]),
            ("Cinema", [EqualizerBand(type: .lowShelf, frequency: 70, gain: 4, q: 0.707),
                        EqualizerBand(frequency: 2_000, gain: 2),
                        EqualizerBand(type: .highShelf, frequency: 9_000, gain: 1.5, q: 0.707)])
        ]
        return definitions.enumerated().map { index, item in
            EqualizerPreset(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!,
                            name: item.0, bands: item.1, isFactory: true)
        }
    }()
}
