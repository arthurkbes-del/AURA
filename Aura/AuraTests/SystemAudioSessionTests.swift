// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import XCTest
@testable import AuraCore

@MainActor private final class HardwareFixture: SystemAudioBackend {
    enum Failure: Error { case injected }
    var failAt: String?
    var resources = Set<String>()
    var released: [String] = []
    var starts = 0
    var failReleaseIO = false
    var change: (@MainActor (String) -> Void)?
    var sampleRate = 48_000.0
    var outputName = "Test output"
    var metrics = SystemAudioMetrics()

    func acquire(_ name: String) throws {
        resources.insert(name) // Simulate an API that allocates before reporting failure.
        if failAt == name { throw Failure.injected }
    }
    func resolve(_ selection: SystemAudioSelection) throws { try acquire("registration") }
    func createTap() throws { try acquire("tap") }
    func createAggregate() throws { try acquire("aggregate") }
    func prepareIO(_ configuration: AudioConfiguration) throws { try acquire("io") }
    func addListeners(_ changed: @escaping @MainActor (String) -> Void) throws {
        change = changed; try acquire("listeners")
    }
    func start() throws { starts += 1; try acquire("started") }
    func apply(_ configuration: AudioConfiguration) -> Bool { true }
    func release(_ name: String) { if resources.remove(name) != nil { released.append(name) } }
    func stop() throws { release("started") }
    func removeListeners() { release("listeners") }
    func destroyIO() throws {
        if failReleaseIO { throw Failure.injected }
        release("io")
    }
    func destroyAggregate() throws { release("aggregate") }
    func destroyTap() throws { release("tap") }
    func releaseRegistration() throws { release("registration") }
}

final class SystemAudioSessionTests: XCTestCase {
    @MainActor func testAppSwitchesSourcesExclusivelyAndUsesActualCaptureSampleRate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hardware = HardwareFixture(); hardware.sampleRate = 32_000
        let session = SystemAudioSession(makeBackend: { hardware })
        let model = AppState(store: PresetStore(directory: directory), systemAudio: session)
        await model.restore()
        model.editModule { $0.bands[0].frequency = 20_000 }
        await model.startSystemAudio(selection: .init(deviceUID: "test"))
        XCTAssertEqual(model.sourceMode, .systemAudio)
        XCTAssertEqual(session.state, .running)
        XCTAssertFalse(model.audio.engineRunning)
        XCTAssertEqual(model.activeSampleRate, 32_000)
        XCTAssertEqual(model.module.bands[0].frequency, 15_680)
        model.setSourceMode(.localFile)
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(hardware.resources.isEmpty)
        XCTAssertFalse(model.audio.engineRunning)
        await model.flush(); model.stopAllAudio()
    }

    @MainActor func testCaptureSelectionPersistsStableHintsWithoutAutomaticallyStartingAfterRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hardware = HardwareFixture()
        let model = AppState(store: PresetStore(directory: directory), systemAudio: SystemAudioSession(makeBackend: { hardware }))
        await model.restore()
        await model.startSystemAudio(selection: .init(deviceUID: "usb-output", applicationPID: 200, applicationBundleID: "example.player"))
        await model.flush(); model.stopAllAudio()
        let restored = AppState(store: PresetStore(directory: directory))
        await restored.restore()
        XCTAssertEqual(restored.saved.systemAudioPreferences.outputUID, "usb-output")
        XCTAssertEqual(restored.saved.systemAudioPreferences.applicationBundleID, "example.player")
        XCTAssertEqual(restored.systemAudio.state, .idle)
        XCTAssertFalse(restored.audio.engineRunning)
        restored.stopAllAudio()
    }
    @MainActor func testCleanupFailureKeepsOwnerAndPreventsStartingAnotherSessionUntilRetrySucceeds() async throws {
        let hardware = HardwareFixture()
        var owners = 0
        let session = SystemAudioSession(makeBackend: { owners += 1; return hardware })
        try await session.start(selection: .init(deviceUID: "test"), configuration: AudioConfiguration())
        hardware.failReleaseIO = true
        await session.stop()
        XCTAssertEqual(session.state, .failed)
        XCTAssertTrue(hardware.resources.contains("io"))
        do { try await session.start(selection: .init(deviceUID: "other"), configuration: AudioConfiguration()); XCTFail() }
        catch { }
        XCTAssertEqual(owners, 1)
        hardware.failReleaseIO = false
        await session.stop()
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(hardware.resources.isEmpty)
    }
    @MainActor func testFailureAtEveryStartupStepRollsBackInReverseOrder() async {
        let steps = ["registration", "tap", "aggregate", "io", "listeners", "started"]
        for (index, step) in steps.enumerated() {
            let hardware = HardwareFixture(); hardware.failAt = step
            let session = SystemAudioSession(makeBackend: { hardware })
            do { try await session.start(selection: .init(deviceUID: "test"), configuration: AudioConfiguration()); XCTFail("Expected failure at \(step)") }
            catch { }
            XCTAssertEqual(session.state, .failed)
            XCTAssertNotNil(session.errorMessage)
            XCTAssertTrue(hardware.resources.isEmpty, step)
            XCTAssertEqual(hardware.released, Array(steps[0...index].reversed()))
        }
    }

    @MainActor func testStopIsIdempotent() async throws {
        let hardware = HardwareFixture(), selection = SystemAudioSelection(deviceUID: "test")
        let session = SystemAudioSession(makeBackend: { hardware })
        try await session.start(selection: selection, configuration: AudioConfiguration())
        try await session.start(selection: selection, configuration: AudioConfiguration())
        XCTAssertEqual(session.state, .running)
        XCTAssertEqual(hardware.starts, 1)
        await session.stop(); let releases = hardware.released
        await session.stop()
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(hardware.resources.isEmpty)
        XCTAssertEqual(hardware.released, releases)
    }

    @MainActor func testStaleGenerationCannotStopNewSession() async throws {
        let old = HardwareFixture(), current = HardwareFixture()
        var count = 0
        let session = SystemAudioSession(makeBackend: { count += 1; return count == 1 ? old : current })
        try await session.start(selection: .init(deviceUID: "old"), configuration: AudioConfiguration())
        let stale = try XCTUnwrap(old.change)
        await session.stop()
        try await session.start(selection: .init(deviceUID: "new"), configuration: AudioConfiguration())
        stale("Old device vanished")
        XCTAssertEqual(session.state, .running)
        XCTAssertTrue(current.resources.contains("started"))
        await session.stop()
    }

    @MainActor func testPermissionDeniedDoesNotMuteOrStartOutput() async {
        let hardware = HardwareFixture(); hardware.failAt = "tap"
        let session = SystemAudioSession(makeBackend: { hardware })
        do { try await session.start(selection: .init(deviceUID: "test"), configuration: AudioConfiguration()); XCTFail() }
        catch { }
        XCTAssertEqual(hardware.starts, 0)
        XCTAssertTrue(hardware.resources.isEmpty)
        XCTAssertEqual(session.state, .failed)
    }

    @MainActor func testOnlyOwnedResourcesAreDestroyed() async throws {
        let hardware = HardwareFixture(), foreignHardware = HardwareFixture()
        let session = SystemAudioSession(makeBackend: { foreignHardware })
        try await session.start(selection: .init(deviceUID: "foreign"), configuration: AudioConfiguration())
        let owned = SystemAudioSession(makeBackend: { hardware })
        try await owned.start(selection: .init(deviceUID: "test"), configuration: AudioConfiguration())
        await owned.stop()
        XCTAssertTrue(hardware.resources.isEmpty)
        XCTAssertEqual(session.state, .running)
        XCTAssertTrue(foreignHardware.resources.contains("started"))
        await session.stop()
    }

    @MainActor func testProcessDisappearanceOrPermissionRevocationStopsAndReleasesSession() async throws {
        for reason in ["Selected process exited", "Capture permission was revoked", "Output disconnected",
                       "Output sample rate changed", "Mac is going to sleep", "System output changed"] {
            let hardware = HardwareFixture()
            let session = SystemAudioSession(makeBackend: { hardware })
            try await session.start(selection: .init(deviceUID: "test"), configuration: AudioConfiguration())
            hardware.change?(reason)
            XCTAssertEqual(session.state, .failed)
            XCTAssertEqual(session.errorMessage, reason)
            XCTAssertTrue(hardware.resources.isEmpty)
        }
    }
}
