// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

public enum AudioSourceMode: String, Codable, Sendable { case systemAudio, localFile }

public struct SystemAudioPreferences: Codable, Equatable, Sendable {
    public var sourceMode = AudioSourceMode.systemAudio
    public var outputUID = "aura.system-default"
    public var applicationBundleID: String?
    public init() {}
}

public struct SystemAudioSelection: Equatable, Sendable {
    public var deviceUID: String
    public var applicationPID: Int32?
    public var applicationBundleID: String?
    public init(deviceUID: String, applicationPID: Int32? = nil, applicationBundleID: String? = nil) {
        self.deviceUID = deviceUID; self.applicationPID = applicationPID; self.applicationBundleID = applicationBundleID
    }
}

public struct SystemAudioMetrics: Equatable, Sendable {
    public var frames = 0
    public var blocks = 0
    public var invalidBuffers = 0
    public var inputPeak = 0.0
    public var outputPeak = 0.0
    public var overRange = false
    public init() {}
}

public enum SystemAudioState: String, Sendable { case idle, preparing, running, stopping, failed }

public struct SystemAudioError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// HAL operations are injected below the real lifecycle controller. Destruction
/// is idempotent and restricted to resources owned by this backend instance.
@MainActor public protocol SystemAudioBackend: AnyObject {
    var sampleRate: Double { get }
    var outputName: String { get }
    var metrics: SystemAudioMetrics { get }
    func resolve(_ selection: SystemAudioSelection) throws
    func createTap() throws
    func createAggregate() throws
    func prepareIO(_ configuration: AudioConfiguration) throws
    func addListeners(_ changed: @escaping @MainActor (String) -> Void) throws
    func start() throws
    func apply(_ configuration: AudioConfiguration) -> Bool
    func stop() throws
    func removeListeners()
    func destroyIO() throws
    func destroyAggregate() throws
    func destroyTap() throws
    func releaseRegistration() throws
}

@MainActor @Observable public final class SystemAudioSession {
    public private(set) var state = SystemAudioState.idle
    public private(set) var errorMessage: String?
    public private(set) var selection: SystemAudioSelection?
    public private(set) var sampleRate = 48_000.0
    public private(set) var outputName = "No selected output"
    public private(set) var metrics = SystemAudioMetrics()
    @ObservationIgnored private let makeBackend: @MainActor () -> any SystemAudioBackend
    @ObservationIgnored private var backend: (any SystemAudioBackend)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingConfiguration: AudioConfiguration?
    @ObservationIgnored private var timer: Timer?

    public init(makeBackend: @escaping @MainActor () -> any SystemAudioBackend) { self.makeBackend = makeBackend }

    public func start(selection: SystemAudioSelection, configuration: AudioConfiguration) async throws {
        if state == .running && self.selection == selection { apply(configuration); return }
        halt(reason: nil)
        guard backend == nil else { throw SystemAudioError(errorMessage ?? "Previous audio resources could not be released. Retry Stop.") }
        generation += 1; let token = generation
        let candidate = makeBackend(); backend = candidate
        self.selection = selection; state = .preparing; errorMessage = nil; metrics = SystemAudioMetrics()
        do {
            try candidate.resolve(selection)
            try candidate.createTap()
            try candidate.createAggregate()
            try candidate.prepareIO(configuration)
            try candidate.addListeners { [weak self] reason in
                guard let self, self.generation == token else { return }
                self.halt(reason: reason)
            }
            guard generation == token else { throw SystemAudioError("Audio configuration changed during startup. Retry.") }
            try candidate.start()
            guard generation == token else { throw SystemAudioError("Audio session stopped during startup.") }
            sampleRate = candidate.sampleRate; outputName = candidate.outputName
            state = .running
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                MainActor.assumeIsolated { self.refreshMetrics() }
            }
        } catch {
            halt(reason: error.localizedDescription)
            throw error
        }
    }

    public func apply(_ configuration: AudioConfiguration) {
        guard state == .running, let backend else { return }
        pendingConfiguration = backend.apply(configuration) ? nil : configuration
    }

    public func refreshMetrics() {
        guard state == .running, let backend else { return }
        if let pendingConfiguration, backend.apply(pendingConfiguration) { self.pendingConfiguration = nil }
        metrics = backend.metrics
        if metrics.invalidBuffers > 0 { halt(reason: "Audio callback format or capacity changed. Processing stopped safely; start again to reconnect.") }
    }

    public func stop() async { halt(reason: nil) }
    public func stopImmediately() { halt(reason: nil) }

    private func halt(reason: String?) {
        timer?.invalidate(); timer = nil
        generation += 1; pendingConfiguration = nil
        guard let backend else {
            errorMessage = reason; state = reason == nil ? .idle : .failed
            return
        }
        state = .stopping
        var errors: [String] = []
        func attempt(_ action: () throws -> Void) { do { try action() } catch { errors.append(error.localizedDescription) } }
        attempt { try backend.stop() }
        backend.removeListeners()
        attempt { try backend.destroyIO() }
        attempt { try backend.destroyAggregate() }
        attempt { try backend.destroyTap() }
        attempt { try backend.releaseRegistration() }
        // Keep the owner alive for retry when a HAL release failed; never lose
        // the callback's resources merely because cleanup returned an error.
        if errors.isEmpty { self.backend = nil }
        errorMessage = ([reason].compactMap { $0 } + errors).joined(separator: "\n")
        if errorMessage?.isEmpty == true { errorMessage = nil }
        state = errorMessage == nil ? .idle : .failed
    }
}
