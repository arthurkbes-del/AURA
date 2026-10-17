// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum CaptureHealthAction { case none, activate, deactivate, stalled }

/// Silence is not classified as permission denial. Until useful PCM is seen,
/// ordinary audio remains unmuted and AURA's return is gated. A stalled callback
/// is a separate error. Control-side monotonic time; no work on the audio thread.
struct CaptureHealthPolicy {
    private(set) var outputActive = false
    private var lastSignal: Double
    private var lastProgress: Double
    private var lastBlocks = 0
    init(now: Double) { lastSignal = now; lastProgress = now }
    mutating func evaluate(_ metrics: SystemAudioMetrics, now: Double) -> CaptureHealthAction {
        if metrics.blocks > lastBlocks { lastProgress = now; lastBlocks = metrics.blocks }
        if now - lastProgress > 2 { outputActive = false; return .stalled }
        if metrics.frames > 0 && metrics.inputPeak > 1e-10 && metrics.invalidBuffers == 0 {
            lastSignal = now
            if !outputActive { outputActive = true; return .activate }
        } else if outputActive && now - lastSignal > 0.5 {
            outputActive = false; return .deactivate
        }
        return .none
    }
}

enum HALResourceRelease {
    /// Nil means inventory verified the original device no longer exists.
    /// A different UID means its numeric object ID has been reused. This applies
    /// only to the identity registration that was never started, not active I/O.
    static func releaseNeverStartedRegistration(expectedUID: String, observedUID: String?, destroy: () throws -> Void) throws {
        guard observedUID == expectedUID else { return }
        try destroy()
    }
}
