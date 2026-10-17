// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum FilterType: String, Codable, CaseIterable, Identifiable, Sendable {
    case bell, lowShelf, highShelf, highPass, lowPass, notch
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .bell: "Bell"
        case .lowShelf: "Low shelf"
        case .highShelf: "High shelf"
        case .highPass: "High-pass"
        case .lowPass: "Low-pass"
        case .notch: "Notch"
        }
    }
    public var supportsGain: Bool { self == .bell || self == .lowShelf || self == .highShelf }
}

public func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
    min(range.upperBound, max(range.lowerBound, value.isFinite ? value : fallback))
}

public struct EqualizerBand: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var type: FilterType
    public var frequency: Double
    public var gain: Double
    public var q: Double
    public var enabled: Bool

    public init(id: UUID = UUID(), type: FilterType = .bell, frequency: Double = 1_000,
                gain: Double = 0, q: Double = 1, enabled: Bool = true) {
        self.id = id; self.type = type; self.frequency = frequency
        self.gain = gain; self.q = q; self.enabled = enabled
    }

    public mutating func normalize(sampleRate: Double = 48_000) {
        let rate = sampleRate.isFinite && sampleRate >= 8_000 ? sampleRate : 48_000
        frequency = clamped(frequency, to: 20...min(20_000, rate * 0.49), fallback: 1_000)
        gain = clamped(gain, to: -24...24, fallback: 0)
        q = clamped(q, to: 0.1...30, fallback: 1)
    }
}
