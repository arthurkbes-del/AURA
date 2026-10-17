// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import AuraCore

final class SystemAudioCapturePolicyTests: XCTestCase {
    func testUnresolvedSelectedAppCannotFallBackToAllApplications() {
        XCTAssertThrowsError(try SystemAudioCapturePolicy.make(selection: .init(deviceUID: "output", applicationBundleID: "example.player"), ownPID: 100, applications: catalog))
    }
    private let catalog = [
        SystemAudioApplication(objectID: 11, pid: 100, bundleID: "com.evoluere.aura", name: "AURA"),
        SystemAudioApplication(objectID: 12, pid: 101, bundleID: "com.evoluere.aura.helper", name: "AURA helper"),
        SystemAudioApplication(objectID: 21, pid: 200, bundleID: "example.player", name: "Player")
    ]
    func testAllApplicationsExcludesAuraAndItsHelpersBeforeOutputStarts() throws {
        let policy = try SystemAudioCapturePolicy.make(selection: .init(deviceUID: "output"), ownPID: 100, applications: catalog)
        XCTAssertTrue(policy.exclusive)
        XCTAssertEqual(Set(policy.processes), [11, 12])
    }
    func testMissingOwnAudioRegistrationCannotEnableGlobalCapture() {
        XCTAssertThrowsError(try SystemAudioCapturePolicy.make(selection: .init(deviceUID: "output"), ownPID: 999, applications: catalog))
    }
    func testSelectedProcessMustStillMatchIdentityAndCannotBeAura() throws {
        let policy = try SystemAudioCapturePolicy.make(selection: .init(deviceUID: "output", applicationPID: 200, applicationBundleID: "example.player"), ownPID: 100, applications: catalog)
        XCTAssertFalse(policy.exclusive); XCTAssertEqual(policy.processes, [21])
        XCTAssertThrowsError(try SystemAudioCapturePolicy.make(selection: .init(deviceUID: "output", applicationPID: 100), ownPID: 100, applications: catalog))
        XCTAssertThrowsError(try SystemAudioCapturePolicy.make(selection: .init(deviceUID: "output", applicationPID: 200, applicationBundleID: "another.app"), ownPID: 100, applications: catalog))
        XCTAssertThrowsError(try SystemAudioCapturePolicy.make(selection: .init(deviceUID: "output", applicationPID: 300), ownPID: 100, applications: catalog))
    }
}
