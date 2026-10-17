import XCTest
@testable import AuraCore

final class DSPTests: XCTestCase {
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
