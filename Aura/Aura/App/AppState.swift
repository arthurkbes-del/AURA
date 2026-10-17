import Foundation
import Observation

@MainActor @Observable public final class AppState {
    public static let shared = AppState()
    public let audio = AudioEngineManager()
    public private(set) var saved = SavedState()
    public var selectedModule = 0
    public var selectedBandID: UUID?
    public private(set) var isLoaded = false
    public private(set) var persistenceMessage: String?

    @ObservationIgnored private let writer: PersistenceWriter
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var parameterTask: Task<Void, Never>?
    @ObservationIgnored private var canSave = true

    public init(store: PresetStore = PresetStore()) { writer = PersistenceWriter(store: store) }
    public var module: EqualizerModule { saved.configuration.modules[min(3, max(0, selectedModule))] }
    public var presets: [EqualizerPreset] { EqualizerPreset.factory + saved.presets }
    public var selectedBand: EqualizerBand? {
        module.bands.first { $0.id == selectedBandID } ?? module.bands.first
    }

    public func restore() async {
        guard !isLoaded else { return }
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
        saved.configuration.modules[selectedModule].normalize(sampleRate: audio.sampleRate)
        changed()
    }

    public func editBand(_ id: UUID, _ edit: (inout EqualizerBand) -> Void) {
        editModule { module in
            guard let index = module.bands.firstIndex(where: { $0.id == id }) else { return }
            edit(&module.bands[index]); module.presetName = "Custom"; module.presetID = nil
        }
    }

    public func editConfiguration(_ edit: (inout AudioConfiguration) -> Void) {
        edit(&saved.configuration); saved.configuration.normalize(sampleRate: audio.sampleRate); changed()
    }

    public func selectModule(_ index: Int) {
        selectedModule = min(3, max(0, index)); selectedBandID = module.bands.first?.id
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
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        guard !clean.isEmpty, let index = saved.presets.firstIndex(where: { $0.id == id }) else { return }
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
        if isLoaded && canSave { await persist() }
    }
}
