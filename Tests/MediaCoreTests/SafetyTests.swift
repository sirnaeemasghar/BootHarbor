// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import MediaCore

final class SafetyTests: XCTestCase {
    func testOnlyExternalWholeWritableUSBDisksAreEligible() {
        func disk(_ id: String = "disk3", internalDrive: Bool = false, whole: Bool = true,
                  writable: Bool = true, bus: String = "USB") -> USBDevice {
            USBDevice(identifier: id, name: "Test", size: 16_000_000_000,
                      isInternal: internalDrive, isWhole: whole, isWritable: writable, bus: bus)
        }
        XCTAssertTrue(disk().isEligible)
        XCTAssertFalse(disk(internalDrive: true).isEligible)
        XCTAssertFalse(disk(whole: false).isEligible)
        XCTAssertFalse(disk(writable: false).isEligible)
        XCTAssertFalse(disk(bus: "Virtual Interface").isEligible)
        XCTAssertFalse(disk("disk3s1").isEligible)
        XCTAssertFalse(disk("disk3; echo unsafe").isEligible)
    }
    func testIncompleteDiskMetadataFailsClosed() throws {
        let plist: [String: Any] = ["DeviceIdentifier": "disk4", "TotalSize": 16_000_000_000]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        XCTAssertFalse(try DiskService.decodeDevice(data).isEligible)
    }
    func testPlanRejectsUndersizedDestination() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iso")
        try Data(repeating: 0, count: 1024).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try MediaImage(url: url)
        let disk = USBDevice(identifier: "disk9", name: "Test", size: 512,
                             isInternal: false, isWhole: true, isWritable: true, bus: "USB")
        XCTAssertThrowsError(try MediaPlan(image: image, device: disk))
    }
}
