// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Darwin

public enum WriteOperation: String, Codable, Sendable { case formatWindows, raw }
public struct SourceIdentity: Codable, Sendable, Equatable {
    public let inode: UInt64
    public let device: Int32
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanos: Int64
    public init(fileDescriptor: Int32) throws {
        var data = stat()
        guard fstat(fileDescriptor, &data) == 0, data.st_mode & S_IFMT == S_IFREG else {
            throw MediaError.missingImage
        }
        inode = data.st_ino; device = data.st_dev; size = data.st_size
        modifiedSeconds = Int64(data.st_mtimespec.tv_sec); modifiedNanos = Int64(data.st_mtimespec.tv_nsec)
    }
    public init(url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw MediaError.missingImage }
        defer { Darwin.close(fd) }
        try self.init(fileDescriptor: fd)
    }
}
public struct WriteJob: Codable, Sendable {
    public let operation: WriteOperation
    public let device: USBDevice
    public let imagePath: String
    public let imageIdentity: SourceIdentity
    public let sourceSHA256: String
    public let protectedPaths: [String]
    public let ownerUID: UInt32
    public let eraseAcknowledgement: String
    public init(operation: WriteOperation, device: USBDevice, image: MediaImage,
                sourceSHA256: String, protectedPaths: [String]) throws {
        self.operation = operation; self.device = device; imagePath = image.url.path
        imageIdentity = try SourceIdentity(url: image.url); self.sourceSHA256 = sourceSHA256
        self.protectedPaths = protectedPaths; ownerUID = getuid()
        eraseAcknowledgement = "ERASE /dev/" + device.identifier
    }
    public func validate() throws {
        guard device.isEligible, device.registryID != 0,
              eraseAcknowledgement == "ERASE /dev/" + device.identifier,
              sourceSHA256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              imageIdentity.size > 0, UInt64(imageIdentity.size) <= device.size,
              ["iso", "img"].contains(URL(fileURLWithPath: imagePath).pathExtension.lowercased()) else {
            throw MediaError.unsafeDevice
        }
    }
}

public enum ShellQuote {
    public static func argument(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
