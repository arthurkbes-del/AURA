// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import XCTest
@testable import AuraCore

final class OfflineGraphTests: XCTestCase {
    func testMonoPlayerFeedsBothStereoEQChannels() throws {
        let graph = try AudioGraphManager(sampleRate: 44_100, sourceChannels: 1)
        var config = AudioConfiguration(); config.inputGain = 0; config.masterGain = 0
        graph.processor.configureImmediately(config, sampleRate: 44_100)
        let mono = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let input = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: 4_096)!
        input.frameLength = 4_096
        input.floatChannelData![0].update(repeating: 0.01, count: 4_096)
        try graph.engine.enableManualRenderingMode(.offline, format: graph.format, maximumFrameCount: 256)
        defer { graph.player.stop(); graph.engine.stop(); graph.engine.disableManualRenderingMode() }
        graph.player.scheduleBuffer(input); try graph.engine.start(); graph.player.play()
        let output = AVAudioPCMBuffer(pcmFormat: graph.format, frameCapacity: 256)!
        for _ in 0..<8 { XCTAssertEqual(try graph.engine.renderOffline(256, to: output), .success) }
        XCTAssertGreaterThan(abs(output.floatChannelData![0][255]), 0.001)
        XCTAssertEqual(output.floatChannelData![0][255], output.floatChannelData![1][255], accuracy: 1e-7)
    }

    func testRenderedGraphReleasesItsAudioUnit() throws {
        weak var releasedUnit: AuraAudioUnit?
        try autoreleasepool {
            let graph = try AudioGraphManager(sampleRate: 48_000)
            releasedUnit = graph.unit
            try graph.engine.enableManualRenderingMode(.offline, format: graph.format, maximumFrameCount: 128)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: graph.format, frameCapacity: 128))
            buffer.frameLength = 128
            buffer.floatChannelData![0].update(repeating: 0, count: 128)
            buffer.floatChannelData![1].update(repeating: 0, count: 128)
            graph.player.scheduleBuffer(buffer)
            try graph.engine.start(); graph.player.play()
            _ = try graph.engine.renderOffline(128, to: buffer)
            graph.player.stop(); graph.engine.stop(); graph.engine.disableManualRenderingMode()
        }
        XCTAssertNil(releasedUnit, "The cached render block must not retain the Audio Unit")
    }

    func testNativeAudioUnitProcessesAll128BandsFromActualPlayerSamples() throws {
        let graph = try AudioGraphManager(sampleRate: 48_000)
        var config = AudioConfiguration()
        config.inputGain = 0; config.masterGain = 0
        // Four modules × 32 bells × 0.09375 dB = +12 dB at 1 kHz.
        for index in 0..<4 {
            config.modules[index].bands = (0..<32).map { _ in EqualizerBand(gain: 0.09375) }
        }
        graph.processor.configureImmediately(config)
        let format = graph.format
        let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        source.frameLength = source.frameCapacity
        for channel in 0..<2 {
            for frame in 0..<48_000 {
                source.floatChannelData![channel][frame] = Float(0.005 * sin(2 * .pi * 1_000 * Double(frame) / 48_000))
            }
        }
        try graph.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1_024)
        defer { graph.player.stop(); graph.engine.stop(); graph.engine.disableManualRenderingMode() }
        graph.player.scheduleBuffer(source)
        try graph.engine.start(); graph.player.play()
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024))
        var sum = 0.0, samples = 0, retries = 0
        while graph.engine.manualRenderingSampleTime < 48_000 {
            let start = graph.engine.manualRenderingSampleTime
            let status = try graph.engine.renderOffline(AVAudioFrameCount(min(1_024, 48_000 - start)), to: buffer)
            if status == .cannotDoInCurrentContext {
                retries += 1; XCTAssertLessThan(retries, 100)
                if retries >= 100 { break }; continue
            }
            XCTAssertEqual(status, .success)
            guard status == .success else { break }
            for frame in 0..<Int(buffer.frameLength) where start + Int64(frame) >= 12_000 {
                let sample = Double(buffer.floatChannelData![0][frame])
                XCTAssertTrue(sample.isFinite)
                sum += sample * sample; samples += 1
            }
        }
        XCTAssertGreaterThan(samples, 30_000)
        let measured = 20 * log10(sqrt(sum / Double(max(1, samples))) / (0.005 / sqrt(2)))
        XCTAssertEqual(measured, 12, accuracy: 0.02)
    }
}
