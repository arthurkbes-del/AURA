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

    public init(sampleRate: Double, maximumFrames: Int, configuration: AudioConfiguration) throws {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate), (1...65_536).contains(maximumFrames) else {
            throw SystemAudioError("Unsupported system-audio sample rate or callback capacity.")
        }
        self.maximumFrames = maximumFrames
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
        return result
    }

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

    public func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
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
        processor.beginBlock()
        var peakIn = 0.0, peakOut = 0.0
        for frame in 0..<count {
            let left = absent ? 0 : sample(inputs, frame, 0)
            let right = absent ? 0 : sample(inputs, frame, 1)
            peakIn = max(peakIn, max(abs(left), abs(right)))
            let value = processor.processStereo(left, right)
            peakOut = max(peakOut, max(abs(value.0), abs(value.1)))
            write(outputs, frame, 0, value.0); write(outputs, frame, 1, value.1)
        }
        _ = frames.wrappingAdd(count, ordering: .relaxed)
        _ = inputPeak.max(peakIn.bitPattern, ordering: .relaxed)
        _ = outputPeak.max(peakOut.bitPattern, ordering: .relaxed)
        if peakOut > 1 { overRange.store(true, ordering: .relaxed) }
    }
}
