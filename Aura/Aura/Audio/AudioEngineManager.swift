// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import Foundation
import Observation
import Synchronization

final class PlaybackCompletionSignal: Sendable {
    private let generation = Atomic<Int>(0)
    // A delayed callback from a stopped schedule must never erase a newer
    // completion before the main actor consumes it.
    func publish(_ value: Int) { _ = generation.max(value, ordering: .releasing) }
    func consume() -> Int { generation.exchange(0, ordering: .acquiringAndReleasing) }
    func clear() { generation.store(0, ordering: .relaxed) }
}

@MainActor @Observable public final class AudioEngineManager {
    public private(set) var state: PlaybackState = .empty
    public private(set) var errorMessage: String?
    public private(set) var fileName = "No local file"
    public private(set) var sampleRate = 48_000.0
    public private(set) var duration = 0.0
    public private(set) var position = 0.0
    public private(set) var engineRunning = false
    public private(set) var outputName = AudioDeviceManager.currentOutputName()
    public private(set) var overRange = false

    @ObservationIgnored private var graph: AudioGraphManager?
    @ObservationIgnored private var file: AVAudioFile?
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var configuration = AudioConfiguration()
    @ObservationIgnored private var transport = PlaybackTransport()
    @ObservationIgnored private let completion = PlaybackCompletionSignal()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var startFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var resumeFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var needsReconnect = false
    @ObservationIgnored private var pendingConfiguration: AudioConfiguration?

    public init() {}

    public func refreshOutput() { outputName = AudioDeviceManager.currentOutputName() }

    public func load(_ url: URL) throws {
        stop()
        let secured = url.startAccessingSecurityScopedResource()
        do {
            let candidate = try AVAudioFile(forReading: url)
            guard candidate.length > 0, candidate.length <= Int64(UInt32.max) else {
                throw NSError(domain: "AURA", code: 3, userInfo: [NSLocalizedDescriptionKey: "The file must contain 1…4,294,967,295 audio frames."])
            }
            let newGraph = try AudioGraphManager(sampleRate: candidate.processingFormat.sampleRate,
                                                sourceChannels: candidate.processingFormat.channelCount)
            newGraph.processor.configureImmediately(configuration, sampleRate: candidate.processingFormat.sampleRate)
            releaseFileAccess()
            scopedURL = secured ? url : nil
            file = candidate; graph = newGraph
            fileName = url.lastPathComponent; sampleRate = candidate.processingFormat.sampleRate
            duration = Double(candidate.length) / sampleRate
            position = 0; resumeFrame = 0; needsReconnect = false; errorMessage = nil
            transport.loaded(); state = transport.state
            observeGraph(); refreshOutput()
        } catch {
            if secured { url.stopAccessingSecurityScopedResource() }
            fail(error.localizedDescription)
            throw error
        }
    }

    public func apply(_ value: AudioConfiguration) {
        configuration = value; configuration.normalize(sampleRate: sampleRate)
        guard let graph else { return }
        if graph.engine.isRunning {
            pendingConfiguration = graph.processor.submit(configuration) ? nil : configuration
        } else {
            graph.processor.configureImmediately(configuration, sampleRate: sampleRate)
            pendingConfiguration = nil
        }
    }

    public func play() {
        guard state != .playing else { return }
        guard let file else { fail("Choose a local audio file before playing."); return }
        do {
            if needsReconnect || graph == nil {
                graph = try AudioGraphManager(sampleRate: sampleRate, sourceChannels: file.processingFormat.channelCount)
                needsReconnect = false; observeGraph()
            }
            guard let graph else { return }
            if resumeFrame >= file.length { resumeFrame = 0 }
            startFrame = resumeFrame
            graph.processor.configureImmediately(configuration, sampleRate: sampleRate)
            let generation = transport.beginPlayback()
            let signal = completion
            signal.clear()
            graph.player.scheduleSegment(file, startingFrame: startFrame,
                                         frameCount: AVAudioFrameCount(file.length - startFrame),
                                         at: nil, completionCallbackType: .dataPlayedBack) { _ in
                // Scheduling completion never touches UI or dispatches work.
                signal.publish(generation)
            }
            graph.engine.prepare()
            try graph.engine.start()
            graph.player.play()
            state = transport.state; engineRunning = graph.engine.isRunning
            errorMessage = nil; overRange = false
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                MainActor.assumeIsolated {
                    self.tick()
                }
            }
        } catch {
            graph?.player.stop(); graph?.engine.stop()
            fail("Audio engine could not start: \(error.localizedDescription)")
        }
    }

    public func pause() {
        guard state == .playing else { return }
        updatePosition()
        graph?.player.stop(); graph?.engine.stop()
        timer?.invalidate(); timer = nil
        transport.pause(); state = transport.state; engineRunning = false
    }

    public func stop() {
        transport.stop(hasFile: file != nil)
        graph?.player.stop(); graph?.engine.stop()
        timer?.invalidate(); timer = nil
        state = transport.state; position = 0; resumeFrame = 0; engineRunning = false
        pendingConfiguration = nil
    }

    public func shutdown() {
        stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil; file = nil; graph = nil
        releaseFileAccess()
    }

    private func releaseFileAccess() {
        scopedURL?.stopAccessingSecurityScopedResource(); scopedURL = nil
    }

    private func observeGraph() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                         object: graph?.engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.state == .playing || self.state == .paused {
                    self.updatePosition()
                    self.graph?.player.stop(); self.graph?.engine.stop()
                    self.timer?.invalidate(); self.timer = nil
                    self.transport.pause(); self.state = .paused; self.engineRunning = false
                    self.errorMessage = "Audio output or format changed. Press Play to reconnect."
                }
                self.needsReconnect = true; self.refreshOutput()
            }
        }
    }

    private func updatePosition() {
        guard let graph, let time = graph.player.lastRenderTime,
              let playerTime = graph.player.playerTime(forNodeTime: time), let file else { return }
        resumeFrame = min(file.length, max(0, startFrame + playerTime.sampleTime))
        position = Double(resumeFrame) / sampleRate
    }

    private func tick() {
        guard let graph else { return }
        let completed = completion.consume()
        if completed != 0 && transport.complete(generation: completed) {
            graph.player.stop(); graph.engine.stop()
            timer?.invalidate(); timer = nil
            state = .completed; position = duration; resumeFrame = file?.length ?? 0; engineRunning = false
            return
        }
        guard graph.engine.isRunning else {
            graph.player.stop(); fail("Audio engine stopped unexpectedly. Press Play to retry."); needsReconnect = true
            return
        }
        updatePosition()
        if let pendingConfiguration, graph.processor.submit(pendingConfiguration) { self.pendingConfiguration = nil }
        if graph.unit.metrics.overRange.exchange(false, ordering: .relaxed) { overRange = true }
        engineRunning = graph.engine.isRunning
    }

    private func fail(_ message: String) {
        timer?.invalidate(); timer = nil
        errorMessage = message; transport.fail(); state = .failed; engineRunning = false
    }
}
