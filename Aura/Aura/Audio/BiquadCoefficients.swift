// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Normalized RBJ biquads. Q controls damping for all six types, including
/// resonant shelves. Source: https://www.w3.org/TR/audio-eq-cookbook/
public struct BiquadCoefficients: Equatable, Sendable {
    public var b0: Double = 1
    public var b1: Double = 0
    public var b2: Double = 0
    public var a1: Double = 0
    public var a2: Double = 0
    public static let identity = BiquadCoefficients()

    public var isStable: Bool {
        b0.isFinite && b1.isFinite && b2.isFinite && a1.isFinite && a2.isFinite &&
        abs(a2) < 1 && 1 + a1 + a2 > 0 && 1 - a1 + a2 > 0
    }

    public static func make(_ value: EqualizerBand, sampleRate: Double) -> Self {
        var band = value; band.normalize(sampleRate: sampleRate)
        guard band.enabled else { return .identity }
        let rate = sampleRate.isFinite && sampleRate >= 8_000 ? sampleRate : 48_000
        let omega = 2 * Double.pi * band.frequency / rate
        let c = cos(omega), s = sin(omega), alpha = s / (2 * band.q)
        let a = pow(10, band.gain / 40)
        let beta = 2 * sqrt(a) * alpha
        let b0, b1, b2, a0, a1, a2: Double
        switch band.type {
        case .bell:
            b0 = 1 + alpha * a; b1 = -2 * c; b2 = 1 - alpha * a
            a0 = 1 + alpha / a; a1 = -2 * c; a2 = 1 - alpha / a
        case .lowPass:
            b0 = (1 - c) / 2; b1 = 1 - c; b2 = b0
            a0 = 1 + alpha; a1 = -2 * c; a2 = 1 - alpha
        case .highPass:
            b0 = (1 + c) / 2; b1 = -(1 + c); b2 = b0
            a0 = 1 + alpha; a1 = -2 * c; a2 = 1 - alpha
        case .notch:
            b0 = 1; b1 = -2 * c; b2 = 1
            a0 = 1 + alpha; a1 = -2 * c; a2 = 1 - alpha
        case .lowShelf:
            b0 = a * ((a + 1) - (a - 1) * c + beta)
            b1 = 2 * a * ((a - 1) - (a + 1) * c)
            b2 = a * ((a + 1) - (a - 1) * c - beta)
            a0 = (a + 1) + (a - 1) * c + beta
            a1 = -2 * ((a - 1) + (a + 1) * c)
            a2 = (a + 1) + (a - 1) * c - beta
        case .highShelf:
            b0 = a * ((a + 1) + (a - 1) * c + beta)
            b1 = -2 * a * ((a - 1) + (a + 1) * c)
            b2 = a * ((a + 1) + (a - 1) * c - beta)
            a0 = (a + 1) - (a - 1) * c + beta
            a1 = 2 * ((a - 1) - (a + 1) * c)
            a2 = (a + 1) - (a - 1) * c - beta
        }
        return Self(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    public func decibels(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        let nr = b0 + b1 * cos(w) + b2 * cos(2 * w)
        let ni = -b1 * sin(w) - b2 * sin(2 * w)
        let dr = 1 + a1 * cos(w) + a2 * cos(2 * w)
        let di = -a1 * sin(w) - a2 * sin(2 * w)
        return 10 * log10(max(1e-30, (nr * nr + ni * ni) / max(1e-30, dr * dr + di * di)))
    }
}
