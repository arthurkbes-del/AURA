// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import AuraCore

final class PresetStoreTests: XCTestCase {
    func testVersionTwoWithoutCapturePreferencesMigratesWithoutLosingEQ() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var configuration = AudioConfiguration(); configuration.modules[2].bands[0].gain = 7
        let data = try JSONEncoder().encode(configuration)
        let object: [String: Any] = ["version": 2, "configuration": try JSONSerialization.jsonObject(with: data), "presets": []]
        let store = PresetStore(directory: directory)
        try JSONSerialization.data(withJSONObject: object).write(to: store.fileURL)
        let result = try store.load()
        XCTAssertEqual(result.state.version, SavedState.currentVersion)
        XCTAssertEqual(result.state.configuration.modules[2].bands[0].gain, 7)
        XCTAssertEqual(result.state.systemAudioPreferences.outputUID, "aura.system-default")
        XCTAssertNil(result.state.systemAudioPreferences.applicationBundleID)
    }
    func withStore(_ body: (PresetStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(PresetStore(directory: directory), directory)
    }

    func testRoundTripPreservesBypassAndCustomPresets() throws {
        try withStore { store, _ in
            var state = SavedState()
            state.configuration.modules[2].bypassed = true
            state.configuration.modules[1].enabled = false
            state.presets = [EqualizerPreset(name: "Mine", bands: [EqualizerBand(gain: 7)])]
            try store.save(state)
            let loaded = try store.load()
            XCTAssertTrue(loaded.state.configuration.modules[2].bypassed)
            XCTAssertFalse(loaded.state.configuration.modules[1].enabled)
            XCTAssertEqual(loaded.state.presets.first?.bands.first?.gain, 7)
        }
    }

    func testCorruptFileIsQuarantinedAndRecoversDefaults() throws {
        try withStore { store, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("broken".utf8).write(to: store.fileURL)
            let loaded = try store.load()
            XCTAssertNotNil(loaded.warning)
            XCTAssertEqual(loaded.state.configuration.modules.count, 4)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains { $0.hasPrefix("configuration.corrupt-") })
        }
    }

    func testFutureVersionIsPreservedAndCannotBeOverwritten() throws {
        try withStore { store, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bytes = Data("{\"version\":999}".utf8)
            try bytes.write(to: store.fileURL)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save(SavedState()))
            XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)
        }
    }

    func testVersionOneMigratesWithoutLosingParameters() throws {
        try withStore { store, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var state = SavedState()
            state.version = 1
            state.configuration.masterGain = -11
            try JSONEncoder().encode(state).write(to: store.fileURL)
            let loaded = try store.load()
            XCTAssertEqual(loaded.state.version, SavedState.currentVersion)
            XCTAssertEqual(loaded.state.configuration.masterGain, -11)
        }
    }
}
