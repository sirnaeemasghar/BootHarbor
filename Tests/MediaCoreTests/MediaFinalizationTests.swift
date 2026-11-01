// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import MediaCore

final class MediaFinalizationTests: XCTestCase {
    func testSpotlightEjectionDissentKeepsVerifiedMediaResult() {
        let result = MediaFinalization.finish(detachSource: {}, eject: {
            throw MediaError.commandFailed("Unmount dissented by mds_stores")
        }, retryDelay: {})
        XCTAssertFalse(result.ejected)
        XCTAssertNotNil(result.ejectionWarning)
        let message = result.message(windows: true)
        XCTAssertTrue(message.contains("files verified"))
        XCTAssertTrue(message.contains("Finder"))
        XCTAssertFalse(message.contains("Creation failed"))
        XCTAssertFalse(message.contains("USB safely ejected"))
    }
    func testSourceCleanupFailureStillAttemptsEjection() {
        var ejectAttempted = false
        let result = MediaFinalization.finish(detachSource: {
            throw MediaError.commandFailed("Source mount busy")
        }, eject: { ejectAttempted = true })
        XCTAssertTrue(ejectAttempted)
        XCTAssertTrue(result.ejected)
        XCTAssertNotNil(result.sourceDetachWarning)
        XCTAssertTrue(result.message(windows: true).contains("Source image cleanup warning"))
    }
    func testTransientSpotlightDissentRetriesWithoutRecreatingMedia() {
        var attempts = 0
        let result = MediaFinalization.finish(detachSource: {}, eject: {
            attempts += 1
            if attempts < 3 { throw MediaError.commandFailed("Unmount dissented by mds_stores") }
        }, retryDelay: {})
        XCTAssertEqual(attempts, 3)
        XCTAssertTrue(result.ejected)
    }
    func testIdentityChangeDoesNotRetryEjection() {
        var attempts = 0
        let result = MediaFinalization.finish(detachSource: {}, eject: {
            attempts += 1
            throw MediaError.unsafeDevice
        }, retryDelay: {})
        XCTAssertEqual(attempts, 1)
        XCTAssertFalse(result.ejected)
    }
    func testSuccessfulFinalizationReportsVerifiedAndEjected() {
        let result = MediaFinalization.finish(detachSource: {}, eject: {})
        XCTAssertTrue(result.ejected)
        XCTAssertNil(result.sourceDetachWarning)
        XCTAssertNil(result.ejectionWarning)
        XCTAssertTrue(result.message(windows: false).contains("read-back SHA-256 verified"))
        XCTAssertTrue(result.message(windows: false).contains("USB safely ejected"))
    }
}
