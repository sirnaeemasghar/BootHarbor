// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import MediaCore

final class InspectionTests: XCTestCase {
    private func withTree(_ paths: [String], _ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for path in paths {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: file)
        }
        try body(root)
    }
    func testWindowsRequiresSetupPayloadAndUEFILoader() throws {
        try withTree(["SETUP.EXE", "Sources/Boot.wim", "Sources/Install.esd", "EFI/BOOT/BOOTX64.EFI"]) { root in
            XCTAssertEqual(try ImageInspector.inspectDirectory(root).strategy, .windowsUEFI)
        }
        try withTree(["setup.exe", "sources/boot.wim", "sources/install.wim"]) { root in
            XCTAssertEqual(try ImageInspector.inspectDirectory(root).strategy, .unsupported)
        }
    }
    func testUnknownISOIsNotAssumedBootable() throws {
        try withTree(["readme.txt"]) { root in
            XCTAssertEqual(try ImageInspector.inspectDirectory(root).strategy, .unsupported)
        }
    }
    func testOversizedWIMNeedsSplit() throws {
        try withTree(["setup.exe", "sources/boot.wim", "sources/install.wim", "efi/boot/bootx64.efi"]) { root in
            let handle = try FileHandle(forWritingTo: root.appendingPathComponent("sources/install.wim"))
            defer { try? handle.close() }
            try handle.truncate(atOffset: 4_294_967_296)
            let result = try ImageInspector.inspectDirectory(root)
            XCTAssertTrue(result.requiresWIMSplit)
            XCTAssertEqual(result.strategy, .windowsUEFI)
        }
    }
    func testOversizedESDRequiresConversionAndSplit() throws {
        try withTree(["setup.exe", "sources/boot.wim", "sources/install.esd", "efi/boot/bootx64.efi"]) { root in
            let handle = try FileHandle(forWritingTo: root.appendingPathComponent("sources/install.esd"))
            defer { try? handle.close() }
            try handle.truncate(atOffset: 4_294_967_296)
            XCTAssertEqual(try ImageInspector.inspectDirectory(root).strategy, .windowsUEFI)
            XCTAssertTrue(try ImageInspector.inspectDirectory(root).requiresWIMSplit)
        }
    }
}
