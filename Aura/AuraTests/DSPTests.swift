// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import AuraCore

final class DSPTests: XCTestCase {
    func testAll128NonflatBandsProcessActualSamples() {
        var config = AudioConfiguration()
        config.inputGain = 0; config.masterGain = 0
        for module in 0..<4 {
            config.modules[module].bands = (0..<32).map { _ in EqualizerBand(frequency: 1_000, gain: 0.25) }
        }
        let kernel = EqualizerProcessor()
        kernel.configureImmediately(config)
        var energy = 0.0
        for frame in 0..<48_000 {
            let input = 0.00001 * sin(2 * .pi * 1_000 * Double(frame) / 48_000)
            let output = kernel.processStereo(input, input)
            XCTAssertTrue(output.0.isFinite && output.1.isFinite)
            if frame >= 12_000 { energy += output.0 * output.0 }
        }
        // 128 bells × 0.25 dB at their common center = +32 dB.
        XCTAssertEqual(20 * log10(sqrt(energy / 36_000) / (0.00001 / sqrt(2))), 32, accuracy: 0.02)
    }

    func testNonfiniteInputIsSanitizedDuringGainTransition() {
        let processor = EqualizerProcessor()
        var config = AudioConfiguration()
        processor.configureImmediately(config)
        config.masterGain = -12
        XCTAssertTrue(processor.submit(config)); processor.beginBlock()
        let output = processor.processStereo(.nan, .infinity)
        XCTAssertEqual(output.0, 0)
        XCTAssertEqual(output.1, 0)
    }

    func testLargeHighQFrequencyChangeDoesNotReuseIncompatibleHistory() {
        var config = AudioConfiguration()
        config.inputGain = 0; config.masterGain = 0
        config.modules[0].bands = [EqualizerBand(type: .lowPass, frequency: 20_000, q: 30)]
        let kernel = EqualizerProcessor()
        kernel.configureImmediately(config)
        for frame in 0..<48_000 {
            let input = 0.001 * sin(2 * .pi * 20_000 * Double(frame) / 48_000)
            _ = kernel.processStereo(input, input)
        }
        config.modules[0].bands[0].frequency = 20
        XCTAssertTrue(kernel.submit(config)); kernel.beginBlock()
        var peak = 0.0
        for frame in 48_000..<96_000 {
            let input = 0.001 * sin(2 * .pi * 20_000 * Double(frame) / 48_000)
            peak = max(peak, abs(kernel.processStereo(input, input).0))
        }
        XCTAssertLessThan(peak, 0.05)
    }

    func testMetadataEditsPreserveEstablishedHighQFilterState() {
        var configuration = AudioConfiguration()
        configuration.inputGain = 0; configuration.masterGain = 0
        configuration.modules[0].bands = [EqualizerBand(type: .lowPass, frequency: 20, q: 30)]
        let reference = EqualizerProcessor()
        let edited = EqualizerProcessor()
        reference.configureImmediately(configuration); edited.configureImmediately(configuration)
        var maximumDifference = 0.0
        for sample in 0..<240_000 {
            if sample > 96_000 && sample.isMultiple(of: 1_600) {
                configuration.modules[0].name = "Rename \(sample)"
                configuration.modules[0].presetName = "Custom \(sample)"
                XCTAssertTrue(edited.submit(configuration))
                edited.beginBlock()
            }
            let input = 0.001 * sin(2 * .pi * 20 * Double(sample) / 48_000)
            let expected = reference.processStereo(input, input)
            let actual = edited.processStereo(input, input)
            maximumDifference = max(maximumDifference, abs(expected.0 - actual.0))
        }
        XCTAssertLessThan(maximumDifference, 1e-12)
    }

    func testFlatBellIsUnityAtAllFrequencies() {
        let coefficients = BiquadCoefficients.make(EqualizerBand(), sampleRate: 48_000)
        for frequency in [20.0, 100, 1_000, 10_000, 20_000] {
            XCTAssertEqual(coefficients.decibels(at: frequency, sampleRate: 48_000), 0, accuracy: 1e-8)
        }
    }

    func testBellCenterAndShelvesHaveSpecifiedGain() {
        let bell = BiquadCoefficients.make(EqualizerBand(gain: 6, q: 3), sampleRate: 48_000)
        XCTAssertEqual(bell.decibels(at: 1_000, sampleRate: 48_000), 6, accuracy: 1e-8)
        let low = BiquadCoefficients.make(EqualizerBand(type: .lowShelf, frequency: 1_000, gain: 6, q: 0.707), sampleRate: 48_000)
        let high = BiquadCoefficients.make(EqualizerBand(type: .highShelf, frequency: 1_000, gain: -6, q: 0.707), sampleRate: 48_000)
        XCTAssertEqual(low.decibels(at: 0, sampleRate: 48_000), 6, accuracy: 1e-8)
        XCTAssertEqual(high.decibels(at: 24_000, sampleRate: 48_000), -6, accuracy: 1e-8)
    }

    func testPassCutoffAndNotch() {
        for type in [FilterType.highPass, .lowPass] {
            let filter = BiquadCoefficients.make(EqualizerBand(type: type, q: 1 / sqrt(2)), sampleRate: 48_000)
            XCTAssertEqual(filter.decibels(at: 1_000, sampleRate: 48_000), -3.0103, accuracy: 0.0001)
        }
        let notch = BiquadCoefficients.make(EqualizerBand(type: .notch), sampleRate: 48_000)
        XCTAssertLessThan(notch.decibels(at: 1_000, sampleRate: 48_000), -100)
    }

    func testAllFiltersStableAtParameterExtremes() {
        for rate in [8_000.0, 44_100, 48_000, 96_000] {
            for type in FilterType.allCases {
                for frequency in [20.0, 20_000] {
                    for q in [0.1, 30.0] {
                        for gain in [-24.0, 24] {
                            let filter = BiquadCoefficients.make(EqualizerBand(type: type, frequency: frequency, gain: gain, q: q), sampleRate: rate)
                            XCTAssertTrue(filter.isStable, "\(rate) \(type) \(frequency) \(q) \(gain)")
                            XCTAssertTrue(filter.decibels(at: 500, sampleRate: rate).isFinite)
                        }
                    }
                }
            }
        }
    }

    func testCombinedResponseRespectsModuleAndGlobalBypass() {
        var configuration = AudioConfiguration()
        configuration.inputGain = 0; configuration.masterGain = 0
        for index in 0..<4 { configuration.modules[index].bands[0].gain = 6 }
        XCTAssertEqual(FrequencyResponseCalculator.decibels(configuration, at: 1_000, sampleRate: 48_000), 24, accuracy: 1e-7)
        configuration.modules[1].bypassed = true
        XCTAssertEqual(FrequencyResponseCalculator.decibels(configuration, at: 1_000, sampleRate: 48_000), 18, accuracy: 1e-7)
        configuration.processingEnabled = false
        XCTAssertEqual(FrequencyResponseCalculator.decibels(configuration, at: 1_000, sampleRate: 48_000), 0, accuracy: 1e-7)
    }

    func testKernelRendersGainAndSmoothsBypassWithoutNonfiniteSamples() {
        let kernel = EqualizerProcessor(sampleRate: 48_000)
        var configuration = AudioConfiguration()
        configuration.inputGain = 0; configuration.masterGain = 0
        configuration.modules[0].bands[0].gain = 6
        kernel.configureImmediately(configuration)
        var energy = 0.0
        for sample in 0..<48_000 {
            let input = 0.01 * sin(2 * .pi * 1_000 * Double(sample) / 48_000)
            let output = kernel.processStereo(input, input).0
            if sample > 12_000 { energy += output * output }
        }
        let rms = sqrt(energy / 35_999)
        XCTAssertEqual(20 * log10(rms / (0.01 / sqrt(2))), 6, accuracy: 0.01)
        configuration.processingEnabled = false
        XCTAssertTrue(kernel.submit(configuration))
        kernel.beginBlock()
        var last = 0.0
        var maximumDelta = 0.0
        for sample in 0..<4_096 {
            let input = 0.01 * sin(2 * .pi * 1_000 * Double(sample) / 48_000)
            let output = kernel.processStereo(input, input).0
            XCTAssertTrue(output.isFinite)
            maximumDelta = max(maximumDelta, abs(output - last)); last = output
        }
        XCTAssertLessThan(maximumDelta, 0.004)
        let result = kernel.processStereo(0.01, 0.01).0
        XCTAssertEqual(result, 0.01, accuracy: 1e-10)
    }
}
