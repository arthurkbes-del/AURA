// SPDX-License-Identifier: GPL-3.0-or-later
// Controlled source/return tap comparison. No microphone, audio file or physical-loopback claim.
import AuraCore
import CoreAudio
import Foundation

private final class MarkerCapture: @unchecked Sendable {
    let capacity = 384_000
    let source: UnsafeMutablePointer<Float>
    let returned: UnsafeMutablePointer<Float>
    var frames = 0, invalid = 0
    init() {
        source = .allocate(capacity: capacity); returned = .allocate(capacity: capacity)
        source.initialize(repeating: 0, count: capacity); returned.initialize(repeating: 0, count: capacity)
    }
    deinit { source.deallocate(); returned.deallocate() }
    func render(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard buffers.reduce(0, { $0 + Int($1.mNumberChannels) }) == 4, let first = buffers.first,
              first.mNumberChannels > 0 else { invalid += 1; return }
        let count = Int(first.mDataByteSize) / (4 * Int(first.mNumberChannels))
        guard count > 0, buffers.allSatisfy({ $0.mData != nil && Int($0.mDataByteSize) == count * 4 * Int($0.mNumberChannels) }) else { invalid += 1; return }
        guard frames + count <= capacity else { return }
        for frame in 0..<count {
            var channel = 0
            for buffer in buffers {
                let data = buffer.mData!.assumingMemoryBound(to: Float.self)
                for index in 0..<Int(buffer.mNumberChannels) {
                    if channel == 0 { source[frames + frame] = data[frame * Int(buffer.mNumberChannels) + index] }
                    if channel == 2 { returned[frames + frame] = data[frame * Int(buffer.mNumberChannels) + index] }
                    channel += 1
                }
            }
        }
        frames += count
    }
}

@MainActor enum DigitalLatencyProbe {
    nonisolated private static func callback(_ capture: MarkerCapture) -> AudioDeviceIOBlock {
        { @Sendable _, input, _, _, _ in capture.render(input) }
    }
    static func run(_ root: URL) async throws {
        let source = Process(); source.executableURL = root.appendingPathComponent("build/P1/AURATestSource")
        source.arguments = ["--source", "--marker", "--duration", "30"]
        source.standardOutput = FileHandle.nullDevice
        try source.run()
        defer { if source.isRunning { source.terminate(); source.waitUntilExit() } }
        let app = try await NativeAcceptance.application(source)
        let worker = Process(); worker.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        worker.arguments = ["--worker", String(app.pid), "--unity-worker"]; worker.standardOutput = FileHandle.nullDevice
        let ready = root.appendingPathComponent("build/P1/acceptance-worker.json")
        try? FileManager.default.removeItem(at: ready)
        try worker.run()
        defer { if worker.isRunning { worker.terminate(); worker.waitUntilExit() } }
        for _ in 0..<70 {
            if FileManager.default.fileExists(atPath: ready.path) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try NativeAcceptance.require(FileManager.default.fileExists(atPath: ready.path), "Unity worker not ready")
        let workerApp = try await NativeAcceptance.application(worker)
        var taps: [AudioObjectID] = [], aggregate: AudioObjectID = 0, io: AudioDeviceIOProcID?
        var attemptedStart = false
        defer {
            if attemptedStart, let io { _ = AudioDeviceStop(aggregate, io) }
            if let io { _ = AudioDeviceDestroyIOProcID(aggregate, io) }
            if aggregate != 0 { _ = AudioHardwareDestroyAggregateDevice(aggregate) }
            for tap in taps.reversed() { _ = AudioHardwareDestroyProcessTap(tap) }
        }
        var tapEntries: [[String: Any]] = []
        for process in [app.objectID, workerApp.objectID] {
            let description = CATapDescription(stereoMixdownOfProcesses: [process])
            description.isPrivate = true; description.muteBehavior = .unmuted
            var tap: AudioObjectID = 0
            try NativeAcceptance.require(AudioHardwareCreateProcessTap(description, &tap) == noErr, "Create marker tap")
            taps.append(tap)
            let uid: CFString? = try NativeAcceptance.read(tap, kAudioTapPropertyUID, initial: Optional<CFString>.none)
            try NativeAcceptance.require(uid != nil, "Marker tap UID")
            tapEntries.append([kAudioSubTapUIDKey: uid! as String, kAudioSubTapDriftCompensationKey: true])
        }
        let description: [String: Any] = [kAudioAggregateDeviceNameKey: "AURA controlled latency observer",
            kAudioAggregateDeviceUIDKey: "com.evoluere.aura.measurement.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: tapEntries]
        try NativeAcceptance.require(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate) == noErr, "Create capture-only observer")
        let format = try NativeAcceptance.read(aggregate, kAudioDevicePropertyStreamFormat, scope: kAudioObjectPropertyScopeInput, initial: AudioStreamBasicDescription())
        let streams = try NativeAcceptance.ids(aggregate, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        let formats = try streams.map { try NativeAcceptance.read($0, kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription()) }
        try NativeAcceptance.require(formats.reduce(0, { $0 + Int($1.mChannelsPerFrame) }) == 4 && formats.allSatisfy {
            $0.mFormatID == kAudioFormatLinearPCM && $0.mFormatFlags & kAudioFormatFlagIsFloat != 0 && $0.mBitsPerChannel == 32 && $0.mSampleRate == format.mSampleRate
        }, "Observer stream formats unsupported: \(formats)")
        let capture = MarkerCapture()
        try NativeAcceptance.require(AudioDeviceCreateIOProcIDWithBlock(&io, aggregate, nil, callback(capture)) == noErr, "Observer callback")
        attemptedStart = true
        try NativeAcceptance.require(AudioDeviceStart(aggregate, io) == noErr, "Start observer")
        try await Task.sleep(for: .seconds(5))
        try NativeAcceptance.require(AudioDeviceStop(aggregate, io) == noErr, "Stop observer")
        attemptedStart = false
        try NativeAcceptance.require(capture.invalid == 0 && capture.frames > Int(format.mSampleRate * 3), "Missing marker channels")
        let reference = Array(UnsafeBufferPointer(start: capture.source, count: capture.frames))
        let returned = Array(UnsafeBufferPointer(start: capture.returned, count: capture.frames))
        var results: [[String: Any]] = []
        for second in [1, 2, 3] {
            let value = try LatencyCorrelation.estimate(reference: reference, returned: returned,
                start: Int(format.mSampleRate) * second, window: 4096, maximumLag: Int(format.mSampleRate * 0.1))
            results.append(["referenceSecond": second, "lagFrames": value.lagFrames, "correlation": value.correlation,
                            "lagMilliseconds": Double(value.lagFrames) * 1000 / format.mSampleRate])
        }
        let data = try JSONSerialization.data(withJSONObject: ["scope": "Controlled source process tap to unity AURA return process tap, capture-only observer. Includes tap/aggregate scheduling and conversion; excludes DAC, speaker and acoustic path.",
            "physicalEndToEndLatency": "not measured", "observerRate": format.mSampleRate, "frames": capture.frames, "invalidBuffers": capture.invalid, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("evidence/p1/digital-latency-result.json"))
        FileHandle.standardOutput.write(data); NativeAcceptance.log("\nCONTROLLED DIGITAL MARKER MEASUREMENT COMPLETE")
    }
}
