// SPDX-License-Identifier: GPL-3.0-or-later
// Local acceptance harness. Never linked into AuraCore or the app.
import AppKit
import AuraCore
import CoreAudio
import Foundation
import Darwin

@MainActor enum NativeAcceptance {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw SystemAudioError(message) }
    }
    static func log(_ message: String) { FileHandle.standardOutput.write(Data((message + "\n").utf8)) }
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T) throws -> T {
        var a = address(selector, scope), value = initial, size = UInt32(MemoryLayout<T>.size)
        let result = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0) }
        try require(result == noErr, "HAL read \(selector): \(result)")
        return value
    }
    static func ids(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
        var a = address(selector, scope), size: UInt32 = 0
        try require(AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr && size < 1_048_576 && size % 4 == 0, "HAL inventory size")
        if size == 0 { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / 4)
        let result = values.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0.baseAddress!) }
        try require(result == noErr, "HAL inventory read")
        return Array(values.prefix(Int(size) / 4))
    }
    static func resources() throws -> Set<String> {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var result = Set<String>()
        for id in try ids(system, kAudioHardwarePropertyDevices) {
            let uid: CFString? = try read(id, kAudioDevicePropertyDeviceUID, initial: Optional<CFString>.none)
            if let uid, (uid as String).hasPrefix("com.evoluere.aura.session.") { result.insert(uid as String) }
        }
        // Private resources are visible in this caller's HAL inventory only.
        for id in try ids(system, kAudioHardwarePropertyTapList) { result.insert("tap:\(id)") }
        return result
    }
    static func verifyResources(_ baseline: Set<String>, _ stage: String) async throws {
        for tick in 0..<50 {
            if try resources() == baseline {
                if tick > 0 { log("HAL inventory settled after \(tick * 100)ms: \(stage)") }
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        let after = try resources()
        throw SystemAudioError("Resource mismatch at \(stage): baseline=\(baseline.sorted()), after=\(after.sorted())")
    }
    static func configuration() -> AudioConfiguration {
        var config = AudioConfiguration(); config.inputGain = 0; config.masterGain = 0
        for index in 0..<4 { config.modules[index].bands = (0..<32).map { _ in EqualizerBand(frequency: 1_000, gain: 0.046875) } }
        return config
    }
    static func source(_ root: URL) throws -> Process {
        let process = Process(); process.executableURL = root.appendingPathComponent("build/P1/AURATestSource")
        process.arguments = ["--source", "--duration", "600"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); return process
    }
    static func application(_ process: Process) async throws -> SystemAudioApplication {
        for _ in 0..<50 {
            if let app = try SystemAudioInventory.applications().first(where: { $0.pid == process.processIdentifier }) { return app }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw SystemAudioError("Controlled source absent")
    }
    static func wait(_ session: SystemAudioSession, _ message: String, until predicate: () -> Bool) async throws {
        for _ in 0..<60 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw SystemAudioError("Timeout: \(message), state=\(session.state), error=\(session.errorMessage ?? "none")")
    }
    static func latencyInventory(_ output: SystemOutputDevice) throws -> [String: Any] {
        let device = output.objectID, scope = kAudioObjectPropertyScopeOutput
        let rate = try read(device, kAudioDevicePropertyNominalSampleRate, initial: Double(0))
        let buffer = try read(device, kAudioDevicePropertyBufferFrameSize, initial: UInt32(0))
        let latency = try read(device, kAudioDevicePropertyLatency, scope: scope, initial: UInt32(0))
        let safety = try read(device, kAudioDevicePropertySafetyOffset, scope: scope, initial: UInt32(0))
        let streams = try ids(device, kAudioDevicePropertyStreams, scope: scope)
        let streamFrames = try streams.map { try read($0, kAudioStreamPropertyLatency, initial: UInt32(0)) }
        return ["output": output.name, "rate": rate, "deviceLatencyFrames": latency, "safetyOffsetFrames": safety,
                "bufferFrames": buffer, "streamLatencyFrames": streamFrames,
                "scope": "HAL-reported components only; not measured acoustic or round-trip latency"]
    }
    static func setRate(_ device: AudioObjectID, _ rate: Double) throws {
        var rangesAddress = address(kAudioDevicePropertyAvailableNominalSampleRates), size: UInt32 = 0
        try require(AudioObjectGetPropertyDataSize(device, &rangesAddress, 0, nil, &size) == noErr && size > 0 && size < 65536 && Int(size) % MemoryLayout<AudioValueRange>.size == 0, "Rate inventory unavailable")
        var ranges = [AudioValueRange](repeating: .init(mMinimum: 0, mMaximum: 0), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        let status = ranges.withUnsafeMutableBytes { AudioObjectGetPropertyData(device, &rangesAddress, 0, nil, &size, $0.baseAddress!) }
        try require(status == noErr && ranges.contains { $0.mMinimum <= rate && rate <= $0.mMaximum }, "Rate not advertised by output")
        var a = address(kAudioDevicePropertyNominalSampleRate), value = rate
        let result = withUnsafePointer(to: &value) { AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Double>.size), $0) }
        try require(result == noErr, "Set rate failed: \(result)")
    }
    static func verifyRate(_ device: AudioObjectID, _ rate: Double) async throws {
        for _ in 0..<50 {
            if try read(device, kAudioDevicePropertyNominalSampleRate, initial: Double(0)) == rate { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw SystemAudioError("Output rate did not settle to \(rate)")
    }
    static func worker(_ root: URL, pid: Int32) async throws {
        let session = SystemAudioSession(makeBackend: { ProcessTapBackend() })
        try await session.start(selection: .init(deviceUID: SystemAudioInventory.defaultOutputUID, applicationPID: pid), configuration: {
            var value = configuration()
            if CommandLine.arguments.contains("--unity-worker") { value.processingEnabled = false }
            return value
        }())
        try await wait(session, "worker signal") { session.metrics.processingOutputActive }
        let data = try JSONSerialization.data(withJSONObject: ["ready": true, "pid": getpid(), "rate": session.sampleRate])
        try data.write(to: root.appendingPathComponent("build/P1/acceptance-worker.json"), options: .atomic)
        for _ in 0..<1200 {
            try await Task.sleep(for: .milliseconds(100))
            try require(session.state == .running, session.errorMessage ?? "Worker stopped")
        }
        await session.stop()
    }
    static func run(_ root: URL) async throws {
        var children: [Process] = []
        defer { for child in children where child.isRunning { child.terminate(); child.waitUntilExit() } }
        let session = SystemAudioSession(makeBackend: { ProcessTapBackend() })
        defer { session.stopImmediately() }
        let initialDefault = try SystemAudioInventory.defaultOutputID()
        let outputs = try SystemAudioInventory.outputs()
        let latency = try outputs.map(latencyInventory)
        let baseline = try resources()
        var fixture = try source(root); children.append(fixture)
        var app = try await application(fixture)
        func selection() -> SystemAudioSelection { .init(deviceUID: SystemAudioInventory.defaultOutputUID, applicationPID: app.pid) }
        var results: [[String: Any]] = []
        for cycle in 1...20 {
            try await session.start(selection: selection(), configuration: configuration())
            try await wait(session, "signal cycle \(cycle)") { session.metrics.processingOutputActive || session.state == .failed }
            try require(session.state == .running && session.metrics.invalidBuffers == 0 && session.metrics.inputPeak > 0.0001, "Cycle \(cycle) did not capture")
            await session.stop()
            try require(session.state == .idle, "Cycle \(cycle) cleanup state=\(session.state), \(session.errorMessage ?? "")")
            try await verifyResources(baseline, "cycle \(cycle)")
        }
        results.append(["test": "20 native start-stop cycles with128 bands", "result": "PASS", "ownedInventoryReturnedToBaseline": true])
        log("PASS: 20 repeated native sessions, baseline restored")
        try await session.start(selection: selection(), configuration: configuration())
        try await wait(session, "source exit setup") { session.metrics.processingOutputActive }
        fixture.terminate(); fixture.waitUntilExit()
        try await wait(session, "process-exit listener") { session.state == .failed }
        try await verifyResources(baseline, "process exit")
        results.append(["test": "actual selected process exit", "result": "PASS", "message": session.errorMessage ?? ""])
        fixture = try source(root); children.append(fixture); app = try await application(fixture)
        try await session.start(selection: selection(), configuration: configuration())
        try await wait(session, "source restart") { session.metrics.processingOutputActive }
        await session.stop(); try require(session.state == .idle, "Restart cleanup")
        log("PASS: actual source exit and fresh-process restart")
        // Deliver the exact native workspace notification to the registered production listener.
        // This is listener integration, not a claim that the Mac physically slept.
        try await session.start(selection: selection(), configuration: configuration())
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await wait(session, "sleep listener") { session.state == .failed }
        try await verifyResources(baseline, "sleep event")
        results.append(["test": "native workspace sleep notification delivery", "result": "PASS", "physicalSleep": "not exercised" ])
        log("PASS: native sleep-notification listener and cleanup")
        // Kill only this harness's child worker. The GUI and personal applications are untouched.
        let statusURL = root.appendingPathComponent("build/P1/acceptance-worker.json")
        try? FileManager.default.removeItem(at: statusURL)
        let worker = Process(); worker.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        worker.arguments = ["--worker", String(app.pid)]; worker.standardOutput = FileHandle.nullDevice
        try worker.run(); children.append(worker)
        for _ in 0..<80 {
            if FileManager.default.fileExists(atPath: statusURL.path) { break }
            try require(worker.isRunning, "Worker exited before capture readiness")
            try await Task.sleep(for: .milliseconds(100))
        }
        try require(FileManager.default.fileExists(atPath: statusURL.path), "Worker never captured")
        try require(kill(worker.processIdentifier, SIGKILL) == 0, "Could not kill owned worker")
        worker.waitUntilExit()
        try require(worker.terminationReason == .uncaughtSignal && worker.terminationStatus == SIGKILL && fixture.isRunning, "Forced-exit fixture invalid")
        try await session.start(selection: selection(), configuration: configuration())
        try await wait(session, "capture after worker SIGKILL") { session.metrics.processingOutputActive }
        await session.stop()
        try require(session.state == .idle, "Post-crash cleanup: \(session.errorMessage ?? "")")
        try await verifyResources(baseline, "post-crash restart")
        results.append(["test": "production backend worker SIGKILL then capture restart", "result": "PASS", "physicalDryRestoration": "requires listening; not inferred from restart", "crossProcessPrivateInventory": "not observable"])
        log("PASS: SIGKILL of capturing worker and new capture session")
        // Rate mutation is opt-in and restricted to the built-in device, with restoration.
        if CommandLine.arguments.contains("--rate-change"), let output = outputs.first(where: { $0.objectID == initialDefault }), output.uid.contains("BuiltIn") {
            let original = try read(initialDefault, kAudioDevicePropertyNominalSampleRate, initial: Double(0))
            let alternate = original == 48_000 ? 44_100.0 : 48_000.0
            var a = address(kAudioDevicePropertyNominalSampleRate), settable = DarwinBoolean(false)
            try require(AudioObjectIsPropertySettable(initialDefault, &a, &settable) == noErr && settable.boolValue, "Built-in output rate not settable")
            do {
                try await session.start(selection: selection(), configuration: configuration())
                try await wait(session, "rate-change setup") { session.metrics.processingOutputActive }
                try setRate(initialDefault, alternate); try await verifyRate(initialDefault, alternate)
                try await wait(session, "actual rate listener") { session.state == .failed }
                try await verifyResources(baseline, "rate event")
                fixture.terminate(); fixture.waitUntilExit()
                fixture = try source(root); children.append(fixture); app = try await application(fixture)
                try await session.start(selection: selection(), configuration: configuration())
                try await wait(session, "capture at changed rate") { session.metrics.processingOutputActive }
                try require(session.sampleRate == alternate, "Session did not adopt actual changed rate")
                await session.stop()
                try setRate(initialDefault, original); try await verifyRate(initialDefault, original)
                results.append(["test": "actual built-in rate change and restart", "result": "PASS", "original": original, "alternate": alternate, "restored": original])
                log("PASS: actual rate change, restart and exact rate restoration")
            } catch {
                session.stopImmediately()
                try setRate(initialDefault, original); try await verifyRate(initialDefault, original)
                throw error
            }
        } else { results.append(["test": "actual rate change", "result": "NOT RUN", "reason": "requires --rate-change on built-in output"]) }
        try require(try SystemAudioInventory.defaultOutputID() == initialDefault, "Default output unexpectedly changed")
        let data = try JSONSerialization.data(withJSONObject: ["results": results, "halReportedLatency": latency, "physicalLatency": "not measured; requires independent output reference", "permission": "existing development host permission; clean denial/revocation not tested"], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("evidence/p1/acceptance-native-result.json"))
        FileHandle.standardOutput.write(data); log("\nNATIVE ACCEPTANCE RUN PASS (see explicit untested cells)")
    }
}
