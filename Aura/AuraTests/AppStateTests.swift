import XCTest
@testable import AuraCore

final class AppStateTests: XCTestCase {
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
