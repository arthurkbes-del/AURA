// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import AuraCore

final class SystemAudioHealthTests: XCTestCase {
    func testZeroCaptureKeepsOrdinaryAudioUntilSignalIsVerified() {
        var policy = CaptureHealthPolicy(now: 0)
        var metrics = SystemAudioMetrics()
        for tick in 1...20 {
            metrics.blocks = tick; metrics.frames = tick * 512
            XCTAssertEqual(policy.evaluate(metrics, now: Double(tick) * 0.1), .none)
            XCTAssertFalse(policy.outputActive)
        }
        metrics.inputPeak = 0.001; metrics.blocks += 1
        XCTAssertEqual(policy.evaluate(metrics, now: 2.1), .activate)
        XCTAssertTrue(policy.outputActive)
    }
    func testSignalLossRestoresOrdinaryPathAndCanRecover() {
        var policy = CaptureHealthPolicy(now: 0)
        var metrics = SystemAudioMetrics(); metrics.blocks = 1; metrics.frames = 512; metrics.inputPeak = 0.01
        XCTAssertEqual(policy.evaluate(metrics, now: 0.1), .activate)
        metrics.inputPeak = 0; metrics.blocks = 2
        XCTAssertEqual(policy.evaluate(metrics, now: 0.2), .none)
        metrics.blocks = 3
        XCTAssertEqual(policy.evaluate(metrics, now: 0.8), .deactivate)
        XCTAssertFalse(policy.outputActive)
        metrics.inputPeak = 0.01; metrics.blocks = 4
        XCTAssertEqual(policy.evaluate(metrics, now: 0.9), .activate)
    }
    func testNoCallbackProgressIsBoundedInsteadOfMutingIndefinitely() {
        var policy = CaptureHealthPolicy(now: 0)
        XCTAssertEqual(policy.evaluate(SystemAudioMetrics(), now: 2.1), .stalled)
        XCTAssertFalse(policy.outputActive)
    }
    func testVanishedOrReusedDeviceDoesNotDestroyForeignRegistration() throws {
        var destroyCalls = 0
        try HALResourceRelease.releaseNeverStartedRegistration(expectedUID: "original", observedUID: nil) { destroyCalls += 1 }
        try HALResourceRelease.releaseNeverStartedRegistration(expectedUID: "original", observedUID: "replacement") { destroyCalls += 1 }
        XCTAssertEqual(destroyCalls, 0)
        try HALResourceRelease.releaseNeverStartedRegistration(expectedUID: "original", observedUID: "original") { destroyCalls += 1 }
        XCTAssertEqual(destroyCalls, 1)
    }
    func testTransientReleaseFailureOnExistingOwnedDeviceIsNotDiscarded() {
        struct Transient: Error {}
        XCTAssertThrowsError(try HALResourceRelease.releaseNeverStartedRegistration(expectedUID: "original", observedUID: "original") { throw Transient() })
    }
}
