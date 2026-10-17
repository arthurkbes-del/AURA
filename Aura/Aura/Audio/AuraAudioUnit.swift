import AVFoundation
import AudioToolbox
import Synchronization

/// One in-process Audio Unit hosts four logical EQ stages. The render block
/// only pulls PCM, processes preallocated state and writes PCM.
public final class AuraAudioUnit: AUAudioUnit, @unchecked Sendable {
    public let processor = EqualizerProcessor()
    public let overRange = Atomic<Bool>(false)
    private var inputs: AUAudioUnitBusArray!
    private var outputs: AUAudioUnitBusArray!
    private let scratch: AVAudioPCMBuffer

    public static let component = AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: 0x61756571,
        componentManufacturer: 0x41757261, componentFlags: 0, componentFlagsMask: 0
    )

    private static let registration: Void = {
        AUAudioUnit.registerSubclass(AuraAudioUnit.self, as: component, name: "AURA: Parametric EQ", version: 1)
    }()

    public static func register() { _ = registration }

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        scratch = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536)!
        scratch.frameLength = scratch.frameCapacity
        try super.init(componentDescription: componentDescription, options: options)
        maximumFramesToRender = 4_096
        inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [try AUAudioUnitBus(format: format)])
        outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [try AUAudioUnitBus(format: format)])
    }

    public override var inputBusses: AUAudioUnitBusArray { inputs }
    public override var outputBusses: AUAudioUnitBusArray { outputs }

    public override func allocateRenderResources() throws {
        let format = outputBusses[0].format
        guard format.channelCount == 2, format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved, inputBusses[0].format == format,
              (8_000...192_000).contains(format.sampleRate), maximumFramesToRender <= 65_536,
              processor.sampleRate == format.sampleRate else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        try super.allocateRenderResources()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        let kernel = processor
        let leftScratch = scratch.floatChannelData![0]
        let rightScratch = scratch.floatChannelData![1]
        return { [self] flags, timestamp, frames, bus, output, _, pullInput in
            guard bus == 0, frames <= 65_536, let pullInput else { return kAudioUnitErr_NoConnection }
            let buffers = UnsafeMutableAudioBufferListPointer(output)
            guard buffers.count == 2 else { return kAudioUnitErr_FormatNotSupported }
            if buffers[0].mData == nil { buffers[0].mData = UnsafeMutableRawPointer(leftScratch) }
            if buffers[1].mData == nil { buffers[1].mData = UnsafeMutableRawPointer(rightScratch) }
            buffers[0].mDataByteSize = frames * 4; buffers[1].mDataByteSize = frames * 4
            let status = pullInput(flags, timestamp, frames, 0, output)
            guard status == noErr else { return status }
            guard let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
                return kAudioUnitErr_InvalidPropertyValue
            }
            kernel.beginBlock()
            var exceeded = false
            for frame in 0..<Int(frames) {
                let result = kernel.processStereo(Double(left[frame]), Double(right[frame]))
                exceeded = exceeded || abs(result.0) > 1 || abs(result.1) > 1
                let bound = Double(Float.greatestFiniteMagnitude)
                left[frame] = Float(min(bound, max(-bound, result.0)))
                right[frame] = Float(min(bound, max(-bound, result.1)))
            }
            if exceeded { self.overRange.store(true, ordering: .relaxed) }
            return noErr
        }
    }
}
