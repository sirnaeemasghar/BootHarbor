// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import MediaCore

final class VirtualDiskTests: XCTestCase {
    func testFormatCopyVerifyAndRawWriteOnDisposableDiskImage() throws {
        guard ProcessInfo.processInfo.environment["MEDIA_CREATOR_VIRTUAL_DISK_TESTS"] == "1" else {
            throw XCTSkip("Enable MEDIA_CREATOR_VIRTUAL_DISK_TESTS for disposable disk-image integration tests.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("media-virtual-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = CommandRunner(), image = root.appendingPathComponent("disposable.dmg")
        _ = try runner.run("/usr/bin/hdiutil", ["create", "-size", "128m", "-layout", "NONE", "-type", "UDIF", image.path])
        let attached = try runner.run("/usr/bin/hdiutil", ["attach", "-nomount", "-plist", image.path])
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: attached, format: nil) as? [String: Any])
        let entries = try XCTUnwrap(plist["system-entities"] as? [[String: Any]])
        let node = try XCTUnwrap(entries.compactMap { $0["dev-entry"] as? String }.first)
        defer { _ = try? runner.run("/usr/bin/hdiutil", ["detach", node]) }
        let details = try DiskService().info(node)
        // This test has no production USB eligibility bypass: only this just-created,
        // small, virtual, disk-image-backed device is used by the test harness.
        XCTAssertEqual(details["BusProtocol"] as? String, "Disk Image")
        guard details["BusProtocol"] as? String == "Disk Image",
              (details["TotalSize"] as? NSNumber)?.uint64Value == 128 * 1024 * 1024 else { throw MediaError.unsafeDevice }
        let identifier = try XCTUnwrap(details["DeviceIdentifier"] as? String)
        let registryID = registryIdentity(identifier)
        XCTAssertNotEqual(registryID, 0)
        let diskData = try PropertyListSerialization.data(fromPropertyList: details, format: .xml, options: 0)
        let monitor = try USBIdentityMonitor(device: DiskService.decodeDevice(diskData))
        try monitor.validate()
        _ = try runner.run("/usr/sbin/diskutil", ["eraseDisk", "MS-DOS FAT32", "MCTEST", "MBRFormat", node])
        XCTAssertEqual(registryIdentity(identifier), registryID)
        try monitor.validate()
        let partition = try DiskService().info(node + "s1")
        XCTAssertEqual(partition["FilesystemType"] as? String, "msdos")
        let destination = URL(fileURLWithPath: try XCTUnwrap(partition["MountPoint"] as? String))
        let source = root.appendingPathComponent("windows")
        for path in ["setup.exe", "sources/boot.wim", "sources/install.wim", "efi/boot/bootx64.efi"] {
            let file = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(("layout fixture:" + path).utf8).write(to: file)
        }
        for index in 0..<128 {
            try Data(repeating: UInt8(index), count: 4096).write(to: source.appendingPathComponent("small-\(index).bin"))
        }
        let control = WriteControl(directory: root)
        let plan = try WindowsFiles().prepare(root: source, workspace: root, wimTool: root.appendingPathComponent("unused"), control: control)
        let started = ContinuousClock.now
        try WindowsFiles().copyAndVerify(plan, to: destination, control: control) { try monitor.validate() }
        print("Buffered FAT32 copy/read-back: \(plan.files.count) files in \(ContinuousClock.now - started)")
        for file in plan.files { XCTAssertEqual(try Data(contentsOf: file.source), try Data(contentsOf: destination.appendingPathComponent(file.relativePath))) }
        let backing = try DiskService().physicalDisks(containing: destination)
        XCTAssertFalse(backing.isEmpty)
        XCTAssertFalse(backing.contains(identifier))
        let claim = try ExclusiveDisk(identifier: identifier)
        defer { withExtendedLifetime(claim) {} }
        let sourceImage = root.appendingPathComponent("raw.img")
        var bytes = Data(repeating: 0, count: 4 * 1024 * 1024)
        bytes[510] = 0x55; bytes[511] = 0xaa; bytes[450] = 0x83; bytes[454] = 1
        let sectors: UInt32 = UInt32(bytes.count / 512 - 1)
        for index in 0..<4 { bytes[458 + index] = UInt8(truncatingIfNeeded: sectors >> (8 * index)) }
        bytes[512] = 0x42
        try bytes.write(to: sourceImage)
        XCTAssertTrue(try RawImageProbe.supports(sourceImage))
        let input = try FileHandle(forReadingFrom: sourceImage)
        let output = try FileHandle(forUpdating: URL(fileURLWithPath: "/dev/r" + identifier))
        defer { try? input.close(); try? output.close() }
        try RawStreamCopier.copyAndVerify(source: input, destination: output, size: UInt64(bytes.count),
                                         expectedSHA256: ImageChecksum().sha256(of: sourceImage), control: control)
    }
}
