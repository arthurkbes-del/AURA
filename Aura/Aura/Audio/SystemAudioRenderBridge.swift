// SPDX-License-Identifier: GPL-3.0-or-later
import CoreAudio
import Foundation
import Synchronization

/// One control producer and one HAL render consumer. Construct while stopped;
/// release only after AudioDeviceStop + DestroyIOProcID have quiesced callbacks.
/// Supports stereo Float32 (planar/interleaved) at one common stream rate.
public final class SystemAudioRenderBridge: @unchecked Sendable {
    private let processor: EqualizerProcessor
    private let maximumFrames: Int
    private let frames = Atomic<Int>(0)
    private let blocks = Atomic<Int>(0)
    private let invalid = Atomic<Int>(0)
    private let inputPeak = Atomic<UInt64>(0)
    private let outputPeak = Atomic<UInt64>(0)
    private let overRange = Atomic<Bool>(false)
    private let missingInput = Atomic<Int>(0)
    private let timingGaps = Atomic<Int>(0)
    private let overloads = Atomic<Int>(0)
    private let outputEnabled: Atomic<Bool>
    private var outputEnvelope: Double
    private let envelopeStep: Double
    private var lastSampleTime: Double?
    private var lastFrameCount = 0

    public init(sampleRate: Double, maximumFrames: Int, configuration: AudioConfiguration, outputEnabled: Bool = true) throws {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate), (1...65_536).contains(maximumFrames) else {
            throw SystemAudioError("Unsupported system-audio sample rate or callback capacity.")
        }
        self.maximumFrames = maximumFrames
        self.outputEnabled = Atomic(outputEnabled)
        outputEnvelope = outputEnabled ? 1 : 0
        envelopeStep = 1 / max(1, sampleRate * 0.02)
        processor = EqualizerProcessor(sampleRate: sampleRate)
        processor.configureImmediately(configuration)
    }

    public var metrics: SystemAudioMetrics {
        var result = SystemAudioMetrics()
        result.frames = frames.load(ordering: .relaxed); result.blocks = blocks.load(ordering: .relaxed)
        result.invalidBuffers = invalid.load(ordering: .relaxed)
        result.inputPeak = Double(bitPattern: inputPeak.exchange(0, ordering: .relaxed))
        result.outputPeak = Double(bitPattern: outputPeak.exchange(0, ordering: .relaxed))
        result.overRange = overRange.load(ordering: .relaxed)
        result.missingInputBlocks = missingInput.load(ordering: .relaxed)
        result.timingDiscontinuities = timingGaps.load(ordering: .relaxed)
        result.overloadEvents = overloads.load(ordering: .relaxed)
        return result
    }

    public func setOutputEnabled(_ enabled: Bool) { outputEnabled.store(enabled, ordering: .relaxed) }
    public func recordOverload() { _ = overloads.wrappingAdd(1, ordering: .relaxed) }

    @discardableResult public func apply(_ configuration: AudioConfiguration) -> Bool { processor.submit(configuration) }

    private func frameCount(_ buffers: UnsafeMutableAudioBufferListPointer) -> Int? {
        guard (buffers.count == 1 && buffers[0].mNumberChannels == 2)
            || (buffers.count == 2 && buffers[0].mNumberChannels == 1 && buffers[1].mNumberChannels == 1) else { return nil }
        let bytes = 4 * Int(buffers[0].mNumberChannels)
        let count = Int(buffers[0].mDataByteSize) / bytes
        guard count > 0, count <= maximumFrames else { return nil }
        for buffer in buffers {
            guard Int(buffer.mDataByteSize) == count * Int(buffer.mNumberChannels) * 4 else { return nil }
        }
        return count
    }

    @inline(__always) private func sample(_ buffers: UnsafeMutableAudioBufferListPointer, _ frame: Int, _ channel: Int) -> Double {
        let index = buffers.count == 1 ? 0 : channel
        guard let data = buffers[index].mData?.assumingMemoryBound(to: Float.self) else { return 0 }
        let value = data[frame * Int(buffers[index].mNumberChannels) + (buffers.count == 1 ? channel : 0)]
        return value.isFinite ? Double(value) : 0
    }

    @inline(__always) private func write(_ buffers: UnsafeMutableAudioBufferListPointer, _ frame: Int, _ channel: Int, _ value: Double) {
        let index = buffers.count == 1 ? 0 : channel
        // Structural checks above establish nonnil output pointers and capacity.
        let data = buffers[index].mData!.assumingMemoryBound(to: Float.self)
        let bounded = value.isFinite ? max(-Double(Float.greatestFiniteMagnitude), min(Double(Float.greatestFiniteMagnitude), value)) : 0
        data[frame * Int(buffers[index].mNumberChannels) + (buffers.count == 1 ? channel : 0)] = Float(bounded)
    }

    public func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>, sampleTime: Double? = nil) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        for buffer in outputs { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
        _ = blocks.wrappingAdd(1, ordering: .relaxed)
        guard let count = frameCount(outputs), outputs.allSatisfy({ $0.mData != nil }) else {
            _ = invalid.wrappingAdd(1, ordering: .relaxed); return
        }
        let absent = inputs.isEmpty || inputs.allSatisfy { $0.mData == nil && $0.mDataByteSize == 0 }
        guard absent || frameCount(inputs) == count else {
            _ = invalid.wrappingAdd(1, ordering: .relaxed); return
        }
        if inputs.isEmpty || inputs.contains(where: { $0.mData == nil }) { _ = missingInput.wrappingAdd(1, ordering: .relaxed) }
        if let sampleTime, sampleTime.isFinite {
            if let lastSampleTime, abs(sampleTime - lastSampleTime - Double(lastFrameCount)) > 1.5 {
                _ = timingGaps.wrappingAdd(1, ordering: .relaxed)
            }
            lastSampleTime = sampleTime; lastFrameCount = count
        } else { lastSampleTime = nil }
        processor.beginBlock()
        let enabled = outputEnabled.load(ordering: .relaxed)
        var peakIn = 0.0, peakOut = 0.0
        for frame in 0..<count {
            let left = absent ? 0 : sample(inputs, frame, 0)
            let right = absent ? 0 : sample(inputs, frame, 1)
            peakIn = max(peakIn, max(abs(left), abs(right)))
            let value = processor.processStereo(left, right)
            outputEnvelope = enabled ? min(1, outputEnvelope + envelopeStep) : 0
            let leftOut = value.0 * outputEnvelope, rightOut = value.1 * outputEnvelope
            peakOut = max(peakOut, max(abs(leftOut), abs(rightOut)))
            write(outputs, frame, 0, leftOut); write(outputs, frame, 1, rightOut)
        }
        _ = frames.wrappingAdd(count, ordering: .relaxed)
        _ = inputPeak.max(peakIn.bitPattern, ordering: .relaxed)
        _ = outputPeak.max(peakOut.bitPattern, ordering: .relaxed)
        if peakOut > 1 { overRange.store(true, ordering: .relaxed) }
    }
}
