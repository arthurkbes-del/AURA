// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum FrequencyResponseCalculator {
    public static func decibels(_ module: EqualizerModule, at frequency: Double, sampleRate: Double) -> Double {
        guard module.enabled && !module.bypassed else { return 0 }
        return module.bands.reduce(module.outputGain) {
            $0 + BiquadCoefficients.make($1, sampleRate: sampleRate).decibels(at: frequency, sampleRate: sampleRate)
        }
    }

    public static func decibels(_ config: AudioConfiguration, at frequency: Double, sampleRate: Double) -> Double {
        config.inputGain + config.masterGain + (config.processingEnabled
            ? config.modules.reduce(0) { $0 + decibels($1, at: frequency, sampleRate: sampleRate) } : 0)
    }
}
