import Foundation

public struct SavedState: Codable, Equatable, Sendable {
    public static let currentVersion = 2
    public var version = currentVersion
    public var configuration = AudioConfiguration()
    public var presets: [EqualizerPreset] = []
    public init() {}

    public mutating func normalize() {
        version = Self.currentVersion
        configuration.normalize()
        presets = presets.filter { !$0.isFactory }.map {
            var preset = $0
            preset.name = String(preset.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
            if preset.name.isEmpty { preset.name = "Untitled" }
            var module = EqualizerModule(name: preset.name, bands: preset.bands)
            module.outputGain = preset.outputGain; module.normalize()
            preset.bands = module.bands; preset.outputGain = module.outputGain
            return preset
        }
        var seen = Set<UUID>()
        for index in presets.indices {
            if !seen.insert(presets[index].id).inserted { presets[index].id = UUID() }
        }
    }
}

public struct StoreLoadResult: Sendable {
    public let state: SavedState
    public let warning: String?
}

public enum StoreError: LocalizedError {
    case unsupportedVersion(Int)
    case oversizedFile
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Settings version \(version) is unsupported. The file was preserved."
        case .oversizedFile: "Settings exceed the 8 MB safety limit. The file was preserved."
        }
    }
}

public struct PresetStore: Sendable {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("configuration.json") }
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.evoluere.aura", isDirectory: true)
    }

    private struct Header: Decodable { let version: Int }

    private func checkExistingVersion() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 8_388_608 else { throw StoreError.oversizedFile }
        let data = try Data(contentsOf: fileURL)
        if let header = try? JSONDecoder().decode(Header.self, from: data),
           header.version > SavedState.currentVersion || header.version < 1 {
            throw StoreError.unsupportedVersion(header.version)
        }
    }

    public func load() throws -> StoreLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return StoreLoadResult(state: SavedState(), warning: nil)
        }
        try checkExistingVersion()
        let data = try Data(contentsOf: fileURL)
        do {
            var state = try JSONDecoder().decode(SavedState.self, from: data)
            state.normalize()
            return StoreLoadResult(state: state, warning: nil)
        } catch {
            let quarantine = directory.appendingPathComponent("configuration.corrupt-\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: fileURL, to: quarantine)
            return StoreLoadResult(state: SavedState(), warning: "Damaged settings were preserved as \(quarantine.lastPathComponent). Defaults restored.")
        }
    }

    public func save(_ value: SavedState) throws {
        try checkExistingVersion()
        var state = value; state.normalize()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}

public actor PersistenceWriter {
    private let store: PresetStore
    public init(store: PresetStore = PresetStore()) { self.store = store }
    public func load() throws -> StoreLoadResult { try store.load() }
    public func save(_ state: SavedState) throws { try store.save(state) }
}
