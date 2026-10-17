// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import XCTest
@testable import AuraCore

final class AppStateTests: XCTestCase {
    @MainActor func testGraphStyleEditCanReadSourceStateWhileUpdatingBand() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppState(store: PresetStore(directory: directory))
        await model.restore()
        let id = try XCTUnwrap(model.selectedBand?.id)
        for frequency in [100.0, 1_000, 20_000] {
            model.editBand(id) { band in
                band.frequency = min(model.activeSampleRate * 0.49, frequency)
                band.gain = model.saved.configuration.masterGain
            }
        }
        model.editConfiguration { configuration in
            configuration.masterGain = model.saved.configuration.inputGain
        }
        XCTAssertEqual(model.selectedBand?.frequency, 20_000)
        XCTAssertEqual(model.saved.configuration.masterGain, model.saved.configuration.inputGain)
        await model.flush(); model.stopAllAudio()
    }
    @MainActor func testTypingPresetRenamePreservesInteriorSpaces() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppState(store: PresetStore(directory: directory))
        await model.restore(); model.savePreset(name: "V")
        let id = try XCTUnwrap(model.saved.presets.first?.id)
        for character in "oice EQ" {
            let current = try XCTUnwrap(model.saved.presets.first?.name)
            model.renamePreset(id: id, name: current + String(character))
        }
        XCTAssertEqual(model.saved.presets.first?.name, "Voice EQ")
        await model.flush(); model.audio.shutdown()
    }

    @MainActor func testFileRateChangeClampsEditableConfigurationToNyquist() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("rate32.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 32_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)!
        buffer.frameLength = 320
        buffer.floatChannelData![0].update(repeating: 0, count: 320)
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        let model = AppState(store: PresetStore(directory: directory.appendingPathComponent("settings")))
        await model.restore()
        model.editModule { $0.bands[0].frequency = 20_000 }
        try model.loadAudio(url)
        XCTAssertEqual(model.audio.sampleRate, 32_000)
        XCTAssertEqual(model.module.bands[0].frequency, 15_680)
        await model.flush(); model.audio.shutdown()
    }

    @MainActor func testPresetRenameDeleteAndResetPreserveIndependentModules() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppState(store: PresetStore(directory: directory))
        await model.restore()
        model.editModule { $0.bands[0].gain = 8; $0.bypassed = true }
        model.savePreset(name: "Mine")
        let id = try XCTUnwrap(model.saved.presets.first?.id)
        model.renamePreset(id: id, name: "Renamed")
        XCTAssertEqual(model.saved.presets.first?.name, "Renamed")
        model.selectedModule = 1
        model.applyPreset(id: id)
        XCTAssertEqual(model.saved.configuration.modules[1].bands[0].gain, 8)
        XCTAssertTrue(model.saved.configuration.modules[0].bypassed)
        XCTAssertFalse(model.saved.configuration.modules[1].bypassed)
        model.deletePreset(id: id)
        XCTAssertTrue(model.saved.presets.isEmpty)
        XCTAssertEqual(model.saved.configuration.modules[1].bands[0].gain, 8)
        model.resetAll()
        XCTAssertEqual(model.saved.configuration.modules.count, 4)
        XCTAssertEqual(model.saved.configuration.modules[1].bands[0].gain, 0)
        await model.flush()
        model.audio.shutdown()
    }

    @MainActor func testFlushPersistsLatestChangeAndRelaunchRestoresIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PresetStore(directory: directory)
        let model = AppState(store: store)
        await model.restore()
        for value in 1...20 { model.editModule { $0.outputGain = Double(-value) } }
        await model.flush()
        let restored = AppState(store: store)
        await restored.restore()
        XCTAssertEqual(restored.saved.configuration.modules[0].outputGain, -20)
        XCTAssertNil(restored.persistenceMessage)
        model.audio.shutdown(); restored.audio.shutdown()
    }
}
