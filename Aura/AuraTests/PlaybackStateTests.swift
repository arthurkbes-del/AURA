// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import XCTest
@testable import AuraCore

final class PlaybackStateTests: XCTestCase {
    func testDelayedOldCompletionCannotOverwriteNewestCompletion() {
        let signal = PlaybackCompletionSignal()
        signal.publish(5)
        signal.publish(3)
        XCTAssertEqual(signal.consume(), 5)
        XCTAssertEqual(signal.consume(), 0)
    }

    @MainActor func testEmptyPlaybackProducesRecoverableError() async {
        let manager = AudioEngineManager()
        manager.play()
        XCTAssertEqual(manager.state, .failed)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertFalse(manager.engineRunning)
        manager.stop()
        XCTAssertEqual(manager.state, .empty)
    }

    @MainActor func testInvalidAndMissingFileDoNotStartEngine() async throws {
        let manager = AudioEngineManager()
        XCTAssertThrowsError(try manager.load(URL(fileURLWithPath: "/no-such-aura-file.wav")))
        XCTAssertFalse(manager.engineRunning)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not audio".utf8).write(to: file)
        XCTAssertThrowsError(try manager.load(file))
        XCTAssertFalse(manager.engineRunning)
        manager.shutdown()
    }

    @MainActor func testLoadingRealWAVAndStopStateWithoutHardwarePlayback() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410)!
        buffer.frameLength = 4_410
        for frame in 0..<4_410 { buffer.floatChannelData![0][frame] = 0.001 }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let manager = AudioEngineManager()
        try manager.load(url)
        XCTAssertEqual(manager.state, .ready)
        XCTAssertEqual(manager.sampleRate, 44_100)
        XCTAssertEqual(manager.duration, 0.1, accuracy: 0.001)
        manager.stop()
        XCTAssertEqual(manager.state, .stopped)
        XCTAssertEqual(manager.position, 0)
        XCTAssertFalse(manager.engineRunning)
        manager.shutdown()
    }

    func testTransportRejectsStaleCompletionAndMakesPlayIdempotent() {
        var transport = PlaybackTransport()
        transport.loaded()
        let first = transport.beginPlayback()
        XCTAssertEqual(first, transport.beginPlayback())
        transport.stop(hasFile: true)
        transport.loaded()
        let second = transport.beginPlayback()
        XCTAssertFalse(transport.complete(generation: first))
        XCTAssertEqual(transport.state, .playing)
        XCTAssertTrue(transport.complete(generation: second))
        XCTAssertEqual(transport.state, .completed)
    }
}
