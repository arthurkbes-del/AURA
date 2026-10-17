import AVFoundation
import XCTest
@testable import AuraCore

final class OfflineGraphTests: XCTestCase {
    func testNativeAudioUnitProcessesActualPlayerSamples() throws {
        let graph = try AudioGraphManager(sampleRate: 48_000)
        var config = AudioConfiguration()
        config.inputGain = 0; config.masterGain = 0
        for index in 0..<4 { config.modules[index].bands[0].gain = 3 }
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
