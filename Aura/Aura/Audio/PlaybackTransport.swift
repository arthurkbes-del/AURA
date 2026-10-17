public enum PlaybackState: String, Sendable {
    case empty, ready, playing, paused, stopped, completed, failed
    public var label: String { rawValue.capitalized }
}

public struct PlaybackTransport: Sendable {
    public private(set) var state: PlaybackState = .empty
    public private(set) var generation = 0
    public init() {}
    public mutating func loaded() { generation += 1; state = .ready }
    @discardableResult public mutating func beginPlayback() -> Int {
        if state != .playing { generation += 1; state = .playing }
        return generation
    }
    public mutating func pause() { generation += 1; state = .paused }
    public mutating func stop(hasFile: Bool) { generation += 1; state = hasFile ? .stopped : .empty }
    public mutating func fail() { generation += 1; state = .failed }
    public mutating func complete(generation: Int) -> Bool {
        guard generation == self.generation && state == .playing else { return false }
        state = .completed; return true
    }
}
