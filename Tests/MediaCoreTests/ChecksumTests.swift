// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import MediaCore

final class ChecksumTests: XCTestCase {
    func testSHA256KnownVector() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try ImageChecksum().sha256(of: url),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
