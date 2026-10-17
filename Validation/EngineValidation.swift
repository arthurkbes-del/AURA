// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import AuraCore
import Darwin
import Foundation

enum ValidationError: Error { case failed(String) }

@main struct EngineValidation {
    static func require(_ value: Bool, _ message: String) throws {
        guard value else { throw ValidationError.failed(message) }
    }

    @MainActor static func pump(_ seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.02))) }
    }

    static func fixture(at url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 192_000)!
        buffer.frameLength = buffer.frameCapacity
        for frame in 0..<Int(buffer.frameLength) {
            let time = Double(frame) / 48_000
            let envelope = min(1, time / 0.02, (4 - time) / 0.02)
            let value = Float(envelope * 0.01 * (sin(2 * .pi * 120 * time) + sin(2 * .pi * 1_000 * time) + sin(2 * .pi * 8_000 * time)))
            buffer.floatChannelData![0][frame] = value
            buffer.floatChannelData![1][frame] = value
        }
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/Validation", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("AURA-Test-Tones.wav")
        try fixture(at: url)
        var report: [String: Any] = ["fixture": url.path, "fixtureDescription": "4-second stereo 120/1000/8000 Hz synthesized test tones, 48 kHz; not a measurement"]

        if CommandLine.arguments.contains("--benchmark") {
            var config = AudioConfiguration()
            for module in 0..<4 {
                config.modules[module].bands = (0..<32).map { band in
                    EqualizerBand(frequency: 25 * pow(760, Double(band) / 31),
                                  gain: band.isMultiple(of: 2) ? 0.25 : -0.25, q: 1)
                }
            }
            let kernel = EqualizerProcessor()
            kernel.configureImmediately(config)
            var usageBefore = rusage(), usageAfter = rusage()
            getrusage(RUSAGE_SELF, &usageBefore)
            let start = DispatchTime.now().uptimeNanoseconds
            var energy = 0.0
            for frame in 0..<480_000 {
                let value = 0.01 * sin(2 * .pi * 1_000 * Double(frame) / 48_000)
                let output = kernel.processStereo(value, value)
                try require(output.0.isFinite && output.1.isFinite, "Nonfinite benchmark samples")
                energy += output.0 * output.0
            }
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
            getrusage(RUSAGE_SELF, &usageAfter)
            let userCPU = Double(usageAfter.ru_utime.tv_sec - usageBefore.ru_utime.tv_sec)
                + Double(usageAfter.ru_utime.tv_usec - usageBefore.ru_utime.tv_usec) / 1e6
            report["benchmark"] = ["bands": 128, "audioSeconds": 10, "wallSeconds": seconds,
                                    "userCPUSeconds": userCPU, "processPeakResidentBytes": usageAfter.ru_maxrss,
                                    "outputEnergy": energy,
                                    "scope": "Offline Swift kernel; one thread, no graph/UI/hardware. Not a latency measurement."]
        }

        if CommandLine.arguments.contains("--play") {
            let manager = AudioEngineManager()
            defer { manager.shutdown() }
            try manager.load(url)
            manager.play(); manager.play()
            pump(0.8)
            try require(manager.state == .playing && manager.engineRunning && manager.position > 0.3,
                        "Playback did not start/advance: \(manager.state), \(manager.errorMessage ?? "")")
            manager.pause()
            let paused = manager.position
            pump(0.2)
            try require(manager.state == .paused && !manager.engineRunning && manager.position == paused, "Pause did not suspend rendering")
            manager.play(); pump(0.4)
            try require(manager.position > paused, "Resume lost position")
            var config = AudioConfiguration()
            for module in 0..<4 { config.modules[module].bands[0].gain = 6 }
            manager.apply(config); pump(0.3)
            config.modules[1].bypassed = true
            manager.apply(config); pump(0.3)
            try require(manager.state == .playing && manager.engineRunning, "Live EQ interrupted playback")
            manager.stop()
            try require(manager.position == 0 && !manager.engineRunning && manager.state == .stopped, "Stop did not rewind/shut down")
            manager.play()
            let completionStart = Date()
            let completionDeadline = completionStart.addingTimeInterval(manager.duration + 5)
            while manager.state == .playing && Date() < completionDeadline { pump(0.05) }
            try require(manager.state == .completed && !manager.engineRunning,
                        "Natural completion failed: state=\(manager.state), running=\(manager.engineRunning), position=\(manager.position)/\(manager.duration), error=\(manager.errorMessage ?? "none")")
            report["hardwarePlayback"] = ["output": manager.outputName, "sampleRate": manager.sampleRate,
                                           "duplicatePlay": "verified", "pauseResume": "verified", "stopRewind": "verified",
                                           "liveEQAndBypass": "verified engine remained running",
                                           "completion": "verified engine stopped",
                                           "completionWaitSeconds": Date().timeIntervalSince(completionStart),
                                           "listening": "requires Product Owner; no human listening claim"]
        }
        let output = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: directory.appendingPathComponent("engine-validation.json"), options: .atomic)
        print(String(decoding: output, as: UTF8.self))
    }
}
