// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import AuraSystemValidation

final class LatencyCorrelationTests: XCTestCase {
    func marker() -> [Float] {
        var seed: UInt32 = 901
        return (0..<4096).map { _ in
            seed = seed &* 1664525 &+ 1013904223
            return Float(Int32(bitPattern: seed)) / Float(Int32.max)
        }
    }
    func testRecoversKnownDelayedAndAdvancedReturnDespiteAmplitudeChange() throws {
        let reference = marker()
        for shift in [37, -23] {
            var returned = [Float](repeating: 0, count: reference.count)
            for index in reference.indices where returned.indices.contains(index + shift) { returned[index + shift] = reference[index] * 0.25 }
            let result = try LatencyCorrelation.estimate(reference: reference, returned: returned, start: 1000, window: 512, maximumLag: 100)
            XCTAssertEqual(result.lagFrames, shift)
            XCTAssertGreaterThan(result.correlation, 0.9999)
        }
    }
    func testPeriodicToneCannotMasqueradeAsUniqueTimingMarker() {
        let tone = (0..<4096).map { Float(sin(2 * Double.pi * Double($0) / 48)) }
        XCTAssertThrowsError(try LatencyCorrelation.estimate(reference: tone, returned: tone, start: 1000, window: 512, maximumLag: 100))
    }
    func testSilenceOrMismatchedSignalCannotProduceLatencyPass() {
        let reference = marker(), silence = [Float](repeating: 0, count: 4096)
        XCTAssertThrowsError(try LatencyCorrelation.estimate(reference: reference, returned: silence, start: 1000, window: 512, maximumLag: 100))
        let different = reference.reversed().map { $0 }
        XCTAssertThrowsError(try LatencyCorrelation.estimate(reference: reference, returned: different, start: 1000, window: 512, maximumLag: 100))
    }
}
