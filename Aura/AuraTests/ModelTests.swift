import XCTest
@testable import AuraCore

final class ModelTests: XCTestCase {
    func testConfigurationNormalizesToFourIndependentModules() {
        var config = AudioConfiguration()
        XCTAssertEqual(config.modules.count, 4)
        config.modules[0].name = "Voice"
        config.modules[0].bypassed = true
        XCTAssertEqual(config.modules[1].name, "EQ 2")
        XCTAssertFalse(config.modules[1].bypassed)
        config.modules.removeAll()
        config.normalize()
        XCTAssertEqual(config.modules.count, 4)
    }

    func testBandCapacityAndLastBandProtection() {
        var module = EqualizerModule(name: "EQ")
        for _ in 0..<40 { module.addBand() }
        XCTAssertEqual(module.bands.count, 32)
        for _ in 0..<40 { module.removeBand(id: module.bands[0].id) }
        XCTAssertEqual(module.bands.count, 1)
    }

    func testInvalidParametersAreFiniteAndClampedBelowNyquist() {
        var band = EqualizerBand(frequency: .infinity, gain: .nan, q: -9)
        band.normalize(sampleRate: 32_000)
        XCTAssertTrue(band.frequency.isFinite)
        XCTAssertEqual(band.gain, 0)
        XCTAssertEqual(band.q, 0.1)
        band.frequency = 20_000
        band.gain = 90
        band.q = 100
        band.normalize(sampleRate: 32_000)
        XCTAssertLessThan(band.frequency, 16_000)
        XCTAssertEqual(band.gain, 24)
        XCTAssertEqual(band.q, 30)
    }

    func testNormalizationRepairsDuplicateIdentifiersAndEmptyBands() {
        var config = AudioConfiguration()
        config.modules = Array(repeating: config.modules[0], count: 6)
        config.modules[0].bands = []
        config.normalize()
        XCTAssertEqual(config.modules.count, 4)
        XCTAssertEqual(Set(config.modules.map(\.id)).count, 4)
        XCTAssertEqual(config.modules[0].bands.count, 1)
    }

    func testFactoryPresetsContainActualDistinctParameters() {
        XCTAssertEqual(EqualizerPreset.factory.map(\.name),
                       ["Flat", "Bass Boost", "Vocal Clarity", "Warm", "Bright", "Music", "Cinema"])
        for preset in EqualizerPreset.factory.dropFirst() {
            XCTAssertTrue(preset.bands.contains { $0.gain != 0 || $0.type == .highPass })
        }
    }
}
