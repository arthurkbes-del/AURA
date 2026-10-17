// SPDX-License-Identifier: GPL-3.0-or-later
import AuraCore
import Foundation
import Darwin

@main struct SystemAudioValidation {
    @MainActor static func main() async {
        do { try await execute() }
        catch { NativeAcceptance.log("VALIDATION FAILED: \(error)"); exit(1) }
    }
    @MainActor static func execute() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if CommandLine.arguments.contains("--digital-latency") { try await DigitalLatencyProbe.run(root); return }
        if CommandLine.arguments.contains("--acceptance") { try await NativeAcceptance.run(root); return }
        if let index = CommandLine.arguments.firstIndex(of: "--worker"), index + 1 < CommandLine.arguments.count, let pid = Int32(CommandLine.arguments[index + 1]) {
            try await NativeAcceptance.worker(root, pid: pid); return
        }
        var outputDirectory = root.appendingPathComponent("evidence/p1")
        if let index = CommandLine.arguments.firstIndex(of: "--output-dir"), index + 1 < CommandLine.arguments.count {
            outputDirectory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true, relativeTo: root).standardizedFileURL
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var observationCount = CommandLine.arguments.contains("--soak") ? 300 : 15
        if let index = CommandLine.arguments.firstIndex(of: "--seconds"), index + 1 < CommandLine.arguments.count,
           let seconds = Int(CommandLine.arguments[index + 1]), (1...300).contains(seconds) { observationCount = seconds * 10 }
        let source = Process()
        source.executableURL = root.appendingPathComponent("build/P1/AURATestSource")
        source.arguments = ["--source", "--duration", String(observationCount / 5 + 30)]
        try source.run()
        defer { if source.isRunning { source.terminate(); source.waitUntilExit() } }
        try await Task.sleep(for: .seconds(1))
        let inventory = try SystemAudioInventory.applications()
        guard let application = inventory.first(where: { $0.pid == source.processIdentifier }) else { throw SystemAudioError("Controlled source did not appear.") }
        let session = SystemAudioSession(makeBackend: { ProcessTapBackend() })
        var configuration = AudioConfiguration()
        configuration.inputGain = 0; configuration.masterGain = 0
        for index in 0..<4 {
            configuration.modules[index].bands = (0..<32).map { _ in EqualizerBand(frequency: 1_000, gain: 0.046875) }
        }
        var results: [[String: Any]] = []
        do {
            for global in (CommandLine.arguments.contains("--selected-only") ? [false] : [false, true]) {
                let selection = SystemAudioSelection(deviceUID: SystemAudioInventory.defaultOutputUID,
                    applicationPID: global ? nil : application.pid,
                    applicationBundleID: global ? nil : application.bundleID)
                try await session.start(selection: selection, configuration: configuration)
                var usageBefore = rusage(), usageAfter = rusage()
                getrusage(RUSAGE_SELF, &usageBefore)
                let begin = Date()
                var maxInput = 0.0, maxOutput = 0.0
                for tick in 0..<observationCount {
                    try await Task.sleep(for: .milliseconds(100))
                    guard session.state == .running else { throw SystemAudioError(session.errorMessage ?? "Session stopped") }
                    maxInput = max(maxInput, session.metrics.inputPeak); maxOutput = max(maxOutput, session.metrics.outputPeak)
                    // Controlled fixture is quiet; abort promptly if a recursive
                    // path or unrelated loud source invalidates this experiment.
                    if tick > 0 && tick % 300 == 0 { NativeAcceptance.log("Progress: \(global ? "all-app" : "selected") \(tick / 10)s, frames=\(session.metrics.frames), gaps=\(session.metrics.timingDiscontinuities), overloads=\(session.metrics.overloadEvents)") }
                    guard maxInput < 0.01, maxOutput < 0.03 else { throw SystemAudioError("Unexpected level input=\(maxInput), output=\(maxOutput): other audio or recursive capture cannot be excluded. Test stopped.") }
                }
                let stats = session.metrics
                getrusage(RUSAGE_SELF, &usageAfter)
                let userCPU = Double(usageAfter.ru_utime.tv_sec - usageBefore.ru_utime.tv_sec)
                    + Double(usageAfter.ru_utime.tv_usec - usageBefore.ru_utime.tv_usec) / 1_000_000
                guard stats.frames > 0, stats.invalidBuffers == 0, stats.processingOutputActive, maxInput > 0.0001,
                      maxOutput > maxInput * 1.8, maxOutput < maxInput * 2.3 else {
                    throw SystemAudioError("Nonzero capture / four-stage +6 dB assertion failed.")
                }
                results.append(["scope": global ? "all applications except AURA" : "controlled process", "output": session.outputName,
                                "sampleRate": session.sampleRate, "frames": stats.frames, "blocks": stats.blocks,
                                "invalidBuffers": stats.invalidBuffers, "inputPeak": maxInput, "outputPeak": maxOutput,
                                "processingOutputActive": stats.processingOutputActive,
                                "missingInputBlocks": stats.missingInputBlocks, "timestampGaps": stats.timingDiscontinuities,
                                "halOverloadEvents": stats.overloadEvents, "halOverloadMonitoring": stats.overloadMonitoringAvailable,
                                "peakGainDB": 20 * log10(maxOutput / maxInput), "bands": 128,
                                "observationWallSeconds": Date().timeIntervalSince(begin), "processUserCPUSeconds": userCPU,
                                "processPeakResidentBytes": usageAfter.ru_maxrss,
                                "performanceScope": "validator process including HAL/control/metrics, not callback-only CPU or hardware latency"])
                configuration.processingEnabled = false; session.apply(configuration)
                try await Task.sleep(for: .milliseconds(200))
                guard session.state == .running else { throw SystemAudioError("Live bypass stopped the session") }
                await session.stop()
                guard session.state == .idle else { throw SystemAudioError(session.errorMessage ?? "Cleanup failed") }
                configuration.processingEnabled = true
            }
        } catch {
            await session.stop()
            let partial = try JSONSerialization.data(withJSONObject: ["status": "INCOMPLETE", "completedScopes": results, "failure": error.localizedDescription], options: [.prettyPrinted, .sortedKeys])
            try partial.write(to: outputDirectory.appendingPathComponent("native-session-incomplete.json"))
            throw error
        }
        let data = try JSONSerialization.data(withJSONObject: ["results": results, "scopeSelection": CommandLine.arguments.contains("--selected-only") ? "selected process only" : "selected and all applications", "listening": "not human verified", "latency": "not measured"], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outputDirectory.appendingPathComponent("native-session-result.json"))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\nNATIVE SESSION PASS: requested scopes completed, four-stage EQ, live bypass and cleanup\n".utf8))
    }
}
