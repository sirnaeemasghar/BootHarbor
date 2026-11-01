// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import MediaCore

final class MountIntegrationTests: XCTestCase {
    func testReadOnlyMountAndInspection() throws {
        guard let path = ProcessInfo.processInfo.environment["MEDIA_CREATOR_TEST_ISO"] else {
            throw XCTSkip("Set MEDIA_CREATOR_TEST_ISO to a synthetic Windows-layout ISO to test hdiutil mounting.")
        }
        let image = try MediaImage(url: URL(fileURLWithPath: path))
        let result = try ImageInspector().inspect(image)
        XCTAssertEqual(result.strategy, .windowsUEFI)
        XCTAssertEqual(result.efiLoaders, ["efi/boot/bootx64.efi"])
        XCTAssertFalse(result.requiresWIMSplit)
    }
}
