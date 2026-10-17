// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import XCTest
@testable import AuraCore

final class SystemAudioRenderTests: XCTestCase {
    private func buffer(_ frames: Int, interleaved: Bool = false) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: interleaved)!
        let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        result.frameLength = AVAudioFrameCount(frames)
        return result
    }
    private var unity: AudioConfiguration {
        var value = AudioConfiguration(); value.inputGain = 0; value.masterGain = 0; return value
    }

    func testPlanarAndInterleavedPreserveChannelsAndHeadroom() throws {
        for interleaved in [true, false] {
            let input = buffer(4, interleaved: interleaved), output = buffer(4, interleaved: !interleaved)
            let samples: [Float] = [0.02, 0.04, -0.08, 0.16]
            for frame in 0..<4 {
                input.floatChannelData![0][frame * input.stride] = samples[frame]
                input.floatChannelData![interleaved ? 0 : 1][frame * input.stride + (interleaved ? 1 : 0)] = -samples[frame]
            }
            var configuration = unity; configuration.inputGain = -6.020599913279624
            let bridge = try SystemAudioRenderBridge(sampleRate: 48_000, maximumFrames: 512, configuration: configuration)
            bridge.render(input: input.audioBufferList, output: output.mutableAudioBufferList)
            for frame in 0..<4 {
                XCTAssertEqual(output.floatChannelData![0][frame * output.stride], samples[frame] / 2, accuracy: 1e-7)
                XCTAssertEqual(output.floatChannelData![!interleaved ? 0 : 1][frame * output.stride + (!interleaved ? 1 : 0)], -samples[frame] / 2, accuracy: 1e-7)
            }
        }
    }

    func testAll128NonflatBandsProcessCapturedPCM() throws {
        var configuration = unity
        for index in 0..<4 {
            configuration.modules[index].bands = (0..<32).map { _ in EqualizerBand(frequency: 1_000, gain: 0.09375) }
        }
        let bridge = try SystemAudioRenderBridge(sampleRate: 48_000, maximumFrames: 512, configuration: configuration)
        let input = buffer(512), output = buffer(512, interleaved: true)
        var energy = 0.0, count = 0
        for start in stride(from: 0, to: 48_000, by: 512) {
            let frames = min(512, 48_000 - start)
            input.frameLength = AVAudioFrameCount(frames); output.frameLength = AVAudioFrameCount(frames)
            for index in 0..<frames {
                let value = Float(0.00001 * sin(2 * .pi * 1_000 * Double(start + index) / 48_000))
                input.floatChannelData![0][index] = value; input.floatChannelData![1][index] = value
            }
            bridge.render(input: input.audioBufferList, output: output.mutableAudioBufferList)
            for index in 0..<frames where start + index >= 12_000 {
                let value = Double(output.floatChannelData![0][index * 2]); energy += value * value; count += 1
            }
        }
        XCTAssertEqual(20 * log10(sqrt(energy / Double(count)) / (0.00001 / sqrt(2))), 12, accuracy: 0.02)
        XCTAssertEqual(bridge.metrics.frames, 48_000)
        XCTAssertEqual(bridge.metrics.invalidBuffers, 0)
    }

    func testOversizedAndMismatchedBuffersBecomeSilenceWithoutReadingPastBounds() throws {
        let bridge = try SystemAudioRenderBridge(sampleRate: 48_000, maximumFrames: 32, configuration: unity)
        let input = buffer(64), output = buffer(64)
        for index in 0..<64 { output.floatChannelData![0][index] = 1; output.floatChannelData![1][index] = 1 }
        bridge.render(input: input.audioBufferList, output: output.mutableAudioBufferList)
        XCTAssertEqual(bridge.metrics.invalidBuffers, 1)
        for index in 0..<64 { XCTAssertEqual(output.floatChannelData![0][index], 0) }
        input.frameLength = 16; output.frameLength = 32
        bridge.render(input: input.audioBufferList, output: output.mutableAudioBufferList)
        XCTAssertEqual(bridge.metrics.invalidBuffers, 2)
        XCTAssertEqual(bridge.metrics.frames, 0)
    }

    func testInvalidFormatAndFrameCapacityAreRejectedBeforeStartingHardware() {
        XCTAssertThrowsError(try SystemAudioRenderBridge(sampleRate: 0, maximumFrames: 512, configuration: unity))
        XCTAssertThrowsError(try SystemAudioRenderBridge(sampleRate: 48_000, maximumFrames: 0, configuration: unity))
        XCTAssertThrowsError(try SystemAudioRenderBridge(sampleRate: 48_000, maximumFrames: 65_537, configuration: unity))
    }

    func testLiveGlobalBypassAndNonfiniteInputRemainFinite() throws {
        var configuration = unity; configuration.modules[0].outputGain = 6.020599913279624
        let bridge = try SystemAudioRenderBridge(sampleRate: 48_000, maximumFrames: 2_048, configuration: configuration)
        let input = buffer(2_048), output = buffer(2_048)
        input.floatChannelData![0].update(repeating: 0.01, count: 2_048)
        input.floatChannelData![1].update(repeating: 0.01, count: 2_048)
        bridge.render(input: input.audioBufferList, output: output.mutableAudioBufferList)
        XCTAssertEqual(output.floatChannelData![0][2_047], 0.02, accuracy: 1e-6)
        configuration.processingEnabled = false
        XCTAssertTrue(bridge.apply(configuration))
        input.floatChannelData![0][0] = .nan; input.floatChannelData![1][0] = .infinity
        bridge.render(input: input.audioBufferList, output: output.mutableAudioBufferList)
        XCTAssertEqual(output.floatChannelData![0][0], 0)
        XCTAssertEqual(output.floatChannelData![1][0], 0)
        XCTAssertEqual(output.floatChannelData![0][2_047], 0.01, accuracy: 1e-6)
    }
}
