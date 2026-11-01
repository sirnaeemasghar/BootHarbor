// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
import IOKit.pwr_mgt
@testable import MediaCore

final class SystemActivityTests: XCTestCase {
    func testIdleSleepAssertionExistsOnlyDuringActivity() throws {
        let activity = try SystemActivity()
        let identifier = try XCTUnwrap(activity.assertionID)
        let properties = try XCTUnwrap(IOPMAssertionCopyProperties(identifier)?.takeRetainedValue() as? [String: Any])
        XCTAssertEqual(properties[kIOPMAssertionTypeKey as String] as? String, "PreventUserIdleSystemSleep")
        XCTAssertEqual((properties[kIOPMAssertionLevelKey as String] as? NSNumber)?.intValue, Int(kIOPMAssertionLevelOn))
        activity.end()
        XCTAssertNil(activity.assertionID)
        XCTAssertNil(IOPMAssertionCopyProperties(identifier))
        activity.end() // Cleanup is idempotent on success, cancellation and failure paths.
    }
    func testScopeExitReleasesIdleSleepAssertion() throws {
        var identifier: IOPMAssertionID = 0
        do {
            let activity = try SystemActivity()
            identifier = try XCTUnwrap(activity.assertionID)
            withExtendedLifetime(activity) {}
        }
        XCTAssertNil(IOPMAssertionCopyProperties(identifier))
    }
}
