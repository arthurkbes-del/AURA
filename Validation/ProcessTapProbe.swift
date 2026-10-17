// SPDX-License-Identifier: GPL-3.0-or-later
// Development-only hardware experiment; does not participate in production.
import AppKit
import AVFoundation
import CoreAudio
import Foundation

private struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func check(_ status: OSStatus, _ action: String) throws {
    guard status == noErr else { throw ProbeError("\(action): OSStatus \(status)") }
}

private func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         initial: T) throws -> T {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                            mElement: kAudioObjectPropertyElementMain)
    var value = initial, size = UInt32(MemoryLayout<T>.size)
    try check(withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
    }, "Read property \(selector)")
    return value
}

private func objects(_ selector: AudioObjectPropertySelector) throws -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                            mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size), "List size")
    var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    try check(result.withUnsafeMutableBytes {
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!)
    }, "List objects")
    return result
}

private func channelCount(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) throws -> Int {
    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                            mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size), "Channel size")
    let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { storage.deallocate() }
    try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage), "Channels")
    return UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
        .reduce(0) { $0 + Int($1.mNumberChannels) }
}

// Written only by the IOProc; read only after Stop + DestroyIOProcID quiesce it.
private final class ProbeMetrics: @unchecked Sendable {
    var blocks = 0, frames = 0, invalid = 0
    var inputEnergy = 0.0, outputEnergy = 0.0, peak = 0.0
    func render(_ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        for buffer in outputs { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
        blocks += 1
        // Exact stream configuration was verified to be stereo Float32 before Start.
        guard let first = inputs.first, first.mNumberChannels > 0 else { invalid += 1; return }
        let count = Int(first.mDataByteSize) / (4 * Int(first.mNumberChannels))
        guard count > 0 else { return }
        for frame in 0..<count {
            var stereo = (Float(0), Float(0)), channel = 0
            for buffer in inputs {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self), buffer.mNumberChannels > 0,
                      (frame + 1) * Int(buffer.mNumberChannels) * 4 <= Int(buffer.mDataByteSize) else { invalid += 1; return }
                for index in 0..<Int(buffer.mNumberChannels) {
                    if channel == 0 { stereo.0 = data[frame * Int(buffer.mNumberChannels) + index] }
                    if channel == 1 { stereo.1 = data[frame * Int(buffer.mNumberChannels) + index] }
                    channel += 1
                }
            }
            guard stereo.0.isFinite, stereo.1.isFinite else { invalid += 1; continue }
            inputEnergy += Double(stereo.0 * stereo.0 + stereo.1 * stereo.1)
            stereo.0 *= 0.5; stereo.1 *= 0.5
            outputEnergy += Double(stereo.0 * stereo.0 + stereo.1 * stereo.1)
            peak = max(peak, Double(max(abs(stereo.0), abs(stereo.1))))
            channel = 0
            for buffer in outputs {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self),
                      (frame + 1) * Int(buffer.mNumberChannels) * 4 <= Int(buffer.mDataByteSize) else { invalid += 1; return }
                for index in 0..<Int(buffer.mNumberChannels) {
                    if channel < 2 { data[frame * Int(buffer.mNumberChannels) + index] = channel == 0 ? stereo.0 : stereo.1 }
                    channel += 1
                }
            }
            frames += 1
        }
    }
}

@main private struct ProcessTapProbe {
    static func log(_ value: String) { FileHandle.standardOutput.write(Data((value + "\n").utf8)) }

    nonisolated static func callback(_ metrics: ProbeMetrics) -> AudioDeviceIOBlock {
        { @Sendable _, input, _, output, _ in metrics.render(input, output) }
    }

    static func main() async {
        do {
            if CommandLine.arguments.contains("--source") { try await source(); return }
            try await probe()
        } catch { log("PROBE FAILED: \(error)"); exit(1) }
    }

    static func source() async throws {
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        var seed: UInt32 = 0x51A7
        for frame in 0..<48_000 {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            let value = CommandLine.arguments.contains("--marker")
                ? Float(Int32(bitPattern: seed)) / Float(Int32.max) * 0.001
                : Float(0.001 * sin(2 * .pi * 1_000 * Double(frame) / 48_000))
            buffer.floatChannelData![0][frame] = value; buffer.floatChannelData![1][frame] = value
        }
        engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: format)
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        try engine.start(); player.play()
        defer { player.stop(); engine.stop() }
        log("Controlled 1 kHz stereo source ready (amplitude 0.001)")
        let duration: Double
        if let index = CommandLine.arguments.firstIndex(of: "--duration"), index + 1 < CommandLine.arguments.count,
           let requested = Double(CommandLine.arguments[index + 1]), requested.isFinite, (1...900).contains(requested) {
            duration = requested
        } else { duration = 90 }
        try await Task.sleep(for: .seconds(duration))
    }

    @MainActor static func probe() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resultURL = root.appendingPathComponent("evidence/p1/probe-result.json")
        let child = Process()
        child.executableURL = Bundle.main.executableURL
        child.arguments = ["--source"]
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        try await Task.sleep(for: .seconds(1))
        let process = try objects(kAudioHardwarePropertyProcessObjectList).first {
            (try? property($0, kAudioProcessPropertyPID, initial: pid_t(0))) == child.processIdentifier
        }
        guard let process else { throw ProbeError("Controlled source absent from HAL inventory") }
        let output = try property(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(0))
        let uid = try property(output, kAudioDevicePropertyDeviceUID, initial: Optional<CFString>.none)
        let name = try property(output, kAudioObjectPropertyName, initial: Optional<CFString>.none)
        guard let uid else { throw ProbeError("No output UID") }
        var tap: AudioObjectID = 0, aggregate: AudioObjectID = 0, io: AudioDeviceIOProcID?
        defer {
            if let io { log("stop=\(AudioDeviceStop(aggregate, io)); destroyIO=\(AudioDeviceDestroyIOProcID(aggregate, io))") }
            if aggregate != 0 { log("destroyAggregate=\(AudioHardwareDestroyAggregateDevice(aggregate))") }
            if tap != 0 { log("destroyTap=\(AudioHardwareDestroyProcessTap(tap))") }
        }
        let description = CATapDescription(processes: [process], deviceUID: uid as String, stream: 0)
        description.name = "AURA controlled feasibility tap"
        description.isPrivate = true; description.muteBehavior = .mutedWhenTapped
        try check(AudioHardwareCreateProcessTap(description, &tap), "Create private tap")
        let format = try property(tap, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
        log("tap=\(tap), sourcePID=\(child.processIdentifier), rate=\(format.mSampleRate), channels=\(format.mChannelsPerFrame), flags=\(format.mFormatFlags)")
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mChannelsPerFrame == 2 else { throw ProbeError("Unsupported probe tap format") }
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AURA Probe (temporary)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid, kAudioSubDeviceInputChannelsKey: 0]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                             kAudioSubTapDriftCompensationKey: true]]
        ]
        try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate), "Create private aggregate")
        let inputChannels = try channelCount(aggregate, kAudioObjectPropertyScopeInput)
        let outputChannels = try channelCount(aggregate, kAudioObjectPropertyScopeOutput)
        log("aggregate=\(aggregate), inputChannels=\(inputChannels), outputChannels=\(outputChannels)")
        guard inputChannels == 2, outputChannels == 2 else { throw ProbeError("Probe requires stereo tap-only input and stereo output; no microphone capture") }
        let outputFormat = try property(aggregate, kAudioDevicePropertyStreamFormat, scope: kAudioObjectPropertyScopeOutput,
                                        initial: AudioStreamBasicDescription())
        log("output format: id=\(outputFormat.mFormatID), rate=\(outputFormat.mSampleRate), flags=\(outputFormat.mFormatFlags), bits=\(outputFormat.mBitsPerChannel), channels=\(outputFormat.mChannelsPerFrame)")
        let inputFormat = try property(aggregate, kAudioDevicePropertyStreamFormat, scope: kAudioObjectPropertyScopeInput,
                                       initial: AudioStreamBasicDescription())
        log("aggregate input format: rate=\(inputFormat.mSampleRate), flags=\(inputFormat.mFormatFlags), bits=\(inputFormat.mBitsPerChannel), channels=\(inputFormat.mChannelsPerFrame)")
        guard outputFormat.mFormatID == kAudioFormatLinearPCM, outputFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              outputFormat.mBitsPerChannel == 32, inputFormat.mFormatID == kAudioFormatLinearPCM,
              inputFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0, inputFormat.mBitsPerChannel == 32,
              outputFormat.mSampleRate == inputFormat.mSampleRate else {
            throw ProbeError("Probe needs same-clock Float32 input/output; conversion not assumed")
        }
        let metrics = ProbeMetrics()
        try check(AudioDeviceCreateIOProcIDWithBlock(&io, aggregate, nil, callback(metrics)), "Create I/O callback")
        log("Starting controlled capture; macOS may request system audio recording permission")
        try check(AudioDeviceStart(aggregate, io), "Start aggregate")
        try await Task.sleep(for: .seconds(4))
        try check(AudioDeviceStop(aggregate, io), "Stop aggregate")
        if let current = io { try check(AudioDeviceDestroyIOProcID(aggregate, current), "Destroy callback"); io = nil }
        let ratio = metrics.inputEnergy > 0 ? sqrt(metrics.outputEnergy / metrics.inputEnergy) : 0
        let result: [String: Any] = ["blocks": metrics.blocks, "frames": metrics.frames,
            "inputEnergy": metrics.inputEnergy, "outputGain": ratio, "peak": metrics.peak,
            "invalidBuffers": metrics.invalid, "tapRate": format.mSampleRate, "aggregateRate": inputFormat.mSampleRate,
            "output": name.map { $0 as String } ?? "Unknown", "topology": "one private aggregate, tap + physical output",
            "source": "controlled child process only; not global/personal audio",
            "latency": "not measured", "dryDuplication": "requires output observation; not inferred from callback gain"]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: resultURL)
        log(String(data: try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted), encoding: .utf8)!)
        guard metrics.frames > 0, metrics.inputEnergy > 1e-6, metrics.invalid == 0, abs(ratio - 0.5) < 1e-6 else {
            throw ProbeError("Captured signal assertion failed; zero buffers may indicate denied capture permission")
        }
        log("PROBE PASS: captured nonzero controlled audio, wrote half-amplitude output")
    }
}
