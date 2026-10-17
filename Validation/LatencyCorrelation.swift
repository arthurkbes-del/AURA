// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Offline analysis of controlled markers only; never used on an audio thread.
enum LatencyCorrelation {
    struct Result { let lagFrames: Int; let correlation: Double }
    static func estimate(reference: [Float], returned: [Float], start: Int, window: Int, maximumLag: Int) throws -> Result {
        guard window > 0, maximumLag >= 0, start >= maximumLag,
              start + window + maximumLag <= min(reference.count, returned.count) else {
            throw NSError(domain: "AURALatency", code: 1)
        }
        var best = -Double.infinity, bestLag = 0
        var scores: [(Int, Double)] = []
        for lag in -maximumLag...maximumLag {
            var dot = 0.0, a = 0.0, b = 0.0
            for index in 0..<window {
                let x = Double(reference[start + index]), y = Double(returned[start + index + lag])
                dot += x * y; a += x * x; b += y * y
            }
            if a > 1e-20 && b > 1e-20 {
                let score = dot / sqrt(a * b)
                scores.append((lag, score))
                if score > best { best = score; bestLag = lag }
            }
        }
        let secondary = scores.filter { abs($0.0 - bestLag) > 8 }.map { $0.1 }.max() ?? -Double.infinity
        guard best > 0.8 && best - secondary > 0.1 else { throw NSError(domain: "AURALatencyUncorrelated", code: 2) }
        return Result(lagFrames: bestLag, correlation: best)
    }
}
