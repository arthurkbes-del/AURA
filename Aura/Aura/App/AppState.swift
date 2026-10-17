// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

@MainActor @Observable public final class AppState {
    public static let shared = AppState()
    public let audio = AudioEngineManager()
    public let systemAudio: SystemAudioSession
    public private(set) var sourceErrorMessage: String?
    public private(set) var saved = SavedState()
    public var selectedModule = 0
    public var selectedBandID: UUID?
    public private(set) var isLoaded = false
    public private(set) var persistenceMessage: String?

    @ObservationIgnored private let writer: PersistenceWriter
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var parameterTask: Task<Void, Never>?
    @ObservationIgnored private var canSave = true
    @ObservationIgnored private var restoreStarted = false

    public init(store: PresetStore = PresetStore(), systemAudio: SystemAudioSession? = nil) {
        writer = PersistenceWriter(store: store)
        self.systemAudio = systemAudio ?? SystemAudioSession(makeBackend: { ProcessTapBackend() })
    }
    public var sourceMode: AudioSourceMode { saved.systemAudioPreferences.sourceMode }
    public var activeSampleRate: Double { sourceMode == .systemAudio ? systemAudio.sampleRate : audio.sampleRate }
    public var engineRunning: Bool { sourceMode == .systemAudio ? systemAudio.state == .running : audio.engineRunning }
    public var activeOutputName: String { sourceMode == .systemAudio ? systemAudio.outputName : audio.outputName }
    public var activeError: String? { sourceErrorMessage ?? (sourceMode == .systemAudio ? systemAudio.errorMessage : audio.errorMessage) }
    public var activeOverRange: Bool { sourceMode == .systemAudio ? systemAudio.metrics.overRange : audio.overRange }
    public var transportDescription: String {
        sourceMode == .systemAudio ? "System audio · \(systemAudio.state.rawValue)" : "\(audio.state.label) · Engine \(audio.engineRunning ? "running" : "stopped")"
    }

    public func setSourceMode(_ mode: AudioSourceMode) {
        guard mode != sourceMode else { return }
        stopAllAudio()
        saved.systemAudioPreferences.sourceMode = mode; changed()
    }
    public func startSystemAudio(selection: SystemAudioSelection) async {
        audio.stop()
        saved.systemAudioPreferences.sourceMode = .systemAudio
        saved.systemAudioPreferences.outputUID = selection.deviceUID
        saved.systemAudioPreferences.applicationBundleID = selection.applicationBundleID
        sourceErrorMessage = nil
        do {
            try await systemAudio.start(selection: selection, configuration: saved.configuration)
            saved.configuration.normalize(sampleRate: systemAudio.sampleRate)
            systemAudio.apply(saved.configuration)
        } catch { sourceErrorMessage = error.localizedDescription }
        changed()
    }
    public func startPreferredSystemAudio() async {
        let preferences = saved.systemAudioPreferences
        let application = preferences.applicationBundleID.flatMap { bundle in
            (try? SystemAudioInventory.applications())?.first { $0.bundleID == bundle }
        }
        await startSystemAudio(selection: SystemAudioSelection(deviceUID: preferences.outputUID,
            applicationPID: application?.pid, applicationBundleID: preferences.applicationBundleID))
    }
    public func playLocalAudio() {
        systemAudio.stopImmediately()
        guard systemAudio.state == .idle else { sourceErrorMessage = systemAudio.errorMessage; return }
        saved.systemAudioPreferences.sourceMode = .localFile
        sourceErrorMessage = nil; audio.play(); changed()
    }
    public func stopAllAudio() { audio.stop(); systemAudio.stopImmediately(); sourceErrorMessage = nil }
    public var module: EqualizerModule { saved.configuration.modules[min(3, max(0, selectedModule))] }
    public var presets: [EqualizerPreset] { EqualizerPreset.factory + saved.presets }
    public var selectedBand: EqualizerBand? {
        module.bands.first { $0.id == selectedBandID } ?? module.bands.first
    }

    public func restore() async {
        guard !restoreStarted else { return }
        restoreStarted = true
        do {
            let result = try await writer.load()
            saved = result.state; persistenceMessage = result.warning
        } catch {
            persistenceMessage = error.localizedDescription
            canSave = false
        }
        isLoaded = true
        selectedBandID = module.bands.first?.id
        audio.apply(saved.configuration)
    }

    public func editModule(_ edit: (inout EqualizerModule) -> Void) {
        selectedModule = min(3, max(0, selectedModule))
        edit(&saved.configuration.modules[selectedModule])
        saved.configuration.modules[selectedModule].normalize(sampleRate: activeSampleRate)
        changed()
    }

    public func editBand(_ id: UUID, _ edit: (inout EqualizerBand) -> Void) {
        editModule { module in
            guard let index = module.bands.firstIndex(where: { $0.id == id }) else { return }
            edit(&module.bands[index]); module.presetName = "Custom"; module.presetID = nil
        }
    }

    public func editConfiguration(_ edit: (inout AudioConfiguration) -> Void) {
        edit(&saved.configuration); saved.configuration.normalize(sampleRate: activeSampleRate); changed()
    }

    public func selectModule(_ index: Int) {
        selectedModule = min(3, max(0, index)); selectedBandID = module.bands.first?.id
    }

    public func loadAudio(_ url: URL) throws {
        systemAudio.stopImmediately()
        guard systemAudio.state == .idle else { throw SystemAudioError(systemAudio.errorMessage ?? "Stop system processing before opening a file.") }
        saved.systemAudioPreferences.sourceMode = .localFile; sourceErrorMessage = nil
        try audio.load(url)
        saved.configuration.normalize(sampleRate: audio.sampleRate)
        audio.apply(saved.configuration)
        changed()
    }

    public func addBand() {
        editModule { $0.addBand() }; selectedBandID = module.bands.last?.id
    }

    public func removeSelectedBand() {
        guard let id = selectedBand?.id else { return }
        editModule { $0.removeBand(id: id) }; selectedBandID = module.bands.first?.id
    }

    public func applyPreset(id: UUID) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        editModule { $0.apply(preset) }; selectedBandID = module.bands.first?.id
    }

    public func savePreset(name: String) {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        guard !clean.isEmpty else { return }
        let preset = EqualizerPreset(name: clean, bands: module.bands, outputGain: module.outputGain)
        saved.presets.append(preset)
        editModule { $0.presetName = clean; $0.presetID = preset.id }
    }

    public func renamePreset(id: UUID, name: String) {
        let clean = String(name.prefix(64))
        guard !clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = saved.presets.firstIndex(where: { $0.id == id }) else { return }
        saved.presets[index].name = clean
        for moduleIndex in 0..<4 where saved.configuration.modules[moduleIndex].presetID == id {
            saved.configuration.modules[moduleIndex].presetName = clean
        }
        changed()
    }

    public func deletePreset(id: UUID) {
        saved.presets.removeAll { $0.id == id }
        for index in 0..<4 where saved.configuration.modules[index].presetID == id {
            saved.configuration.modules[index].presetID = nil
            saved.configuration.modules[index].presetName = "Custom"
        }
        changed()
    }

    public func resetAll() {
        saved.configuration = AudioConfiguration(); selectedBandID = module.bands.first?.id; changed()
    }

    private func changed() {
        // At most 30 control snapshots/second during graph dragging.
        if parameterTask == nil {
            parameterTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(33))
                guard let self, !Task.isCancelled else { return }
                self.audio.apply(self.saved.configuration)
                self.systemAudio.apply(self.saved.configuration)
                self.parameterTask = nil
            }
        }
        saveTask?.cancel()
        guard isLoaded && canSave else { return }
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            await self.persist()
        }
    }

    private func persist() async {
        do { try await writer.save(saved); persistenceMessage = nil }
        catch { persistenceMessage = error.localizedDescription }
    }

    public func flush() async {
        saveTask?.cancel(); parameterTask?.cancel(); parameterTask = nil
        audio.apply(saved.configuration)
        systemAudio.apply(saved.configuration)
        if isLoaded && canSave { await persist() }
    }
}
