// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import MediaCore

final class WriterTests: XCTestCase {
    func workspace() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }
    func testRealMacOSWholeDiskMetadata() throws {
        let values: [String: Any] = ["DeviceIdentifier": "disk9", "TotalSize": 16_000_000_000,
                                    "WholeDisk": true, "Internal": false, "WritableMedia": true,
                                    "BusProtocol": "USB", "MediaName": "Fixture"]
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        XCTAssertTrue(try DiskService.decodeDevice(data).isEligible)
    }
    func testRawCopyVerifiesExactlyTheSourceLength() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.img")
        let targetURL = root.appendingPathComponent("target.img")
        let sourceBytes = Data(repeating: 0xa5, count: 2 * 1024 * 1024 + 512)
        try sourceBytes.write(to: sourceURL)
        try Data(repeating: 0x12, count: sourceBytes.count + 4096).write(to: targetURL)
        let source = try FileHandle(forReadingFrom: sourceURL)
        let target = try FileHandle(forUpdating: targetURL)
        defer { try? source.close(); try? target.close() }
        try RawStreamCopier.copyAndVerify(source: source, destination: target, size: UInt64(sourceBytes.count),
                                         expectedSHA256: ImageChecksum().sha256(of: sourceURL), control: WriteControl(directory: root))
        let result = try Data(contentsOf: targetURL)
        XCTAssertEqual(result.prefix(sourceBytes.count), sourceBytes)
        XCTAssertEqual(result.suffix(4096), Data(repeating: 0x12, count: 4096))
    }
    func testCancellationBeforeRawWritePreservesDestination() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.img"), targetURL = root.appendingPathComponent("target.img")
        try Data(repeating: 7, count: 512).write(to: sourceURL)
        let original = Data(repeating: 9, count: 512); try original.write(to: targetURL)
        let source = try FileHandle(forReadingFrom: sourceURL), target = try FileHandle(forUpdating: targetURL)
        defer { try? source.close(); try? target.close() }
        let control = WriteControl(directory: root); try control.cancel()
        XCTAssertThrowsError(try RawStreamCopier.copyAndVerify(source: source, destination: target, size: 512,
                                                              expectedSHA256: String(repeating: "0", count: 64), control: control))
        XCTAssertEqual(try Data(contentsOf: targetURL), original)
    }
    func testHybridPartitionBounds() {
        var header = Data(repeating: 0, count: 512)
        header[510] = 0x55; header[511] = 0xaa
        header[446] = 0x80; header[450] = 0x83
        header[454] = 1; header[458] = 7
        XCTAssertTrue(RawImageProbe.validateHeader(header, imageSize: 4096))
        header[458] = 8
        XCTAssertFalse(RawImageProbe.validateHeader(header, imageSize: 4096))
        header[450] = 0
        XCTAssertFalse(RawImageProbe.validateHeader(header, imageSize: 4096))
    }
    func testRawProbeUsesOpenedSourceWhenFilenameIsReplaced() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("source.img")
        var bytes = Data(repeating: 0, count: 4096)
        bytes[510] = 0x55; bytes[511] = 0xaa
        bytes[450] = 0x83; bytes[454] = 1; bytes[458] = 7
        try bytes.write(to: image)
        let opened = try FileHandle(forReadingFrom: image)
        defer { try? opened.close() }
        try Data(repeating: 0, count: 4096).write(to: image, options: .atomic)
        XCTAssertTrue(try RawImageProbe.supports(opened, imageSize: 4096))
        XCTAssertFalse(try RawImageProbe.supports(image))
    }
    func testGPTChecksumsAndPartitionBounds() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("gpt.img")
        var bytes = Data(repeating: 0, count: 64 * 512)
        func put(_ value: UInt64, at offset: Int, count: Int) {
            for index in 0..<count { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * index)) }
        }
        bytes[510] = 0x55; bytes[511] = 0xaa; bytes[450] = 0xee
        put(1, at: 454, count: 4); put(63, at: 458, count: 4)
        bytes.replaceSubrange(512..<520, with: Data("EFI PART".utf8))
        put(0x10000, at: 520, count: 4); put(92, at: 524, count: 4)
        put(1, at: 536, count: 8); put(63, at: 544, count: 8)
        put(4, at: 552, count: 8); put(62, at: 560, count: 8)
        put(2, at: 584, count: 8); put(1, at: 592, count: 4); put(128, at: 596, count: 4)
        bytes[1024] = 1; bytes[1040] = 2
        put(4, at: 1056, count: 8); put(62, at: 1064, count: 8)
        put(UInt64(RawImageProbe.crc32(Data(bytes[1024..<1152]))), at: 600, count: 4)
        put(UInt64(RawImageProbe.crc32(Data(bytes[512..<604]))), at: 528, count: 4)
        try bytes.write(to: image)
        XCTAssertTrue(try RawImageProbe.supports(image))
        bytes[556] ^= 1
        try bytes.write(to: image)
        XCTAssertFalse(try RawImageProbe.supports(image))
    }
    func testShellArgumentsRemainLiteral() throws {
        let value = "a'b $(printf injected) `printf injected`\nnext line"
        let output = try CommandRunner().run("/bin/sh", ["-c", "/usr/bin/printf '%s' " + ShellQuote.argument(value)])
        XCTAssertEqual(String(decoding: output, as: UTF8.self), value)
    }
    func testWindowsCopyAndVerificationAndRefusalToOverwrite() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for path in ["setup.exe", "sources/boot.wim", "sources/install.wim", "efi/boot/bootx64.efi"] {
            let file = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(("fixture:" + path).utf8).write(to: file)
        }
        let control = WriteControl(directory: root), pipeline = WindowsFiles()
        let prepared = try pipeline.prepare(root: source, workspace: root, wimTool: root.appendingPathComponent("unused"), control: control)
        try pipeline.copyAndVerify(prepared, to: target, control: control)
        for file in prepared.files {
            XCTAssertEqual(try Data(contentsOf: file.source), try Data(contentsOf: target.appendingPathComponent(file.relativePath)))
        }
        XCTAssertThrowsError(try pipeline.copyAndVerify(prepared, to: target, control: control))
    }
    func testBufferedCopyStillDetectsDestinationCorruption() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        let paths = ["setup.exe", "sources/boot.wim", "sources/install.wim", "efi/boot/bootx64.efi"]
        for path in paths {
            let file = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(("original:" + path).utf8).write(to: file)
        }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let control = WriteControl(directory: root), pipeline = WindowsFiles()
        let prepared = try pipeline.prepare(root: source, workspace: root, wimTool: root.appendingPathComponent("unused"), control: control)
        var corrupted = false
        XCTAssertThrowsError(try pipeline.copyAndVerify(prepared, to: target, control: control) {
            if !corrupted && paths.allSatisfy({ FileManager.default.fileExists(atPath: target.appendingPathComponent($0).path) }) {
                try Data("corrupted EFI".utf8).write(to: target.appendingPathComponent("efi/boot/bootx64.efi"))
                corrupted = true
            }
        }) { error in
            XCTAssertTrue(error.localizedDescription.contains("USB verification failed"))
        }
        XCTAssertTrue(corrupted)
        XCTAssertNotEqual(control.readProgress()?.phase, "Files verified")
    }
    func testSourceSymlinkIsRejected() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let actual = root.appendingPathComponent("actual.iso"), link = root.appendingPathComponent("link.iso")
        try Data([1]).write(to: actual)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actual)
        XCTAssertThrowsError(try SourceIdentity(url: link))
    }
    func testCopyRefusesSymlinkedDestinationFolder() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target"), outside = root.appendingPathComponent("outside")
        for path in ["setup.exe", "sources/boot.wim", "sources/install.wim", "efi/boot/bootx64.efi"] {
            let file = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: file)
        }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: target.appendingPathComponent("efi"), withDestinationURL: outside)
        let control = WriteControl(directory: root)
        let pipeline = WindowsFiles()
        let prepared = try pipeline.prepare(root: source, workspace: root, wimTool: root.appendingPathComponent("unused"), control: control)
        XCTAssertThrowsError(try pipeline.copyAndVerify(prepared, to: target, control: control))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }
    func testSourceVolumeResolvesAndIsProtected() throws {
        guard ProcessInfo.processInfo.environment["MEDIA_CREATOR_VIRTUAL_DISK_TESTS"] == "1" else { throw XCTSkip("Enable disk integration tests for real source-volume introspection.") }
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let disks = try DiskService().physicalDisks(containing: root)
        XCTAssertFalse(disks.isEmpty)
        let identifier = try XCTUnwrap(disks.first)
        let destination = USBDevice(identifier: identifier, name: "Fixture", size: 16_000_000_000,
                                    isInternal: false, isWhole: true, isWritable: true, bus: "USB")
        XCTAssertThrowsError(try DiskService().protect([root], from: destination))
    }
    func testWIMSplittingAndVerificationRoundTrip() throws {
        guard let toolPath = ProcessInfo.processInfo.environment["MEDIA_CREATOR_WIM_TOOL"] else {
            throw XCTSkip("Set MEDIA_CREATOR_WIM_TOOL to the locally built wimlib-imagex.")
        }
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        for index in 1...16 { try Data(repeating: UInt8(index), count: 256 * 1024).write(to: input.appendingPathComponent("file\(index).bin")) }
        let wim = root.appendingPathComponent("install.wim")
        _ = try CommandRunner().run(toolPath, ["capture", input.path, wim.path, "--compress=none", "--check"])
        let parts = try WindowsFiles().split(payload: wim, workspace: root, wimTool: URL(fileURLWithPath: toolPath), control: WriteControl(directory: root), limitMiB: 1)
        XCTAssertGreaterThan(parts.count, 1)
        let restored = root.appendingPathComponent("restored")
        _ = try CommandRunner().run(toolPath, ["apply", parts.first(where: { $0.lastPathComponent == "install.swm" })!.path, "1", restored.path, "--ref=" + parts[0].deletingLastPathComponent().appendingPathComponent("install*.swm").path])
        for index in 1...16 {
            XCTAssertEqual(try Data(contentsOf: input.appendingPathComponent("file\(index).bin")), try Data(contentsOf: restored.appendingPathComponent("file\(index).bin")))
        }
    }
}
