// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Darwin

public struct USBDevice: Identifiable, Equatable, Codable, Sendable {
    public var id: String { identifier }
    public let identifier: String
    public let name: String
    public let size: UInt64
    public let isInternal: Bool
    public let isWhole: Bool
    public let isWritable: Bool
    public let bus: String
    public let registryID: UInt64

    public init(identifier: String, name: String, size: UInt64, isInternal: Bool,
                isWhole: Bool, isWritable: Bool, bus: String, registryID: UInt64 = 0) {
        self.identifier = identifier; self.name = name; self.size = size
        self.isInternal = isInternal; self.isWhole = isWhole
        self.isWritable = isWritable; self.bus = bus; self.registryID = registryID
    }

    public var isEligible: Bool {
        identifier.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil &&
        !isInternal && isWhole && isWritable && bus == "USB" && size > 0
    }
}

public enum MediaError: LocalizedError {
    case commandFailed(String), invalidResponse, unsafeDevice, insufficientCapacity
    case unsupportedImage, missingImage, sourceOnDestination
    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message): return message
        case .invalidResponse: return "macOS returned incomplete disk information."
        case .unsafeDevice: return "Select a writable external whole USB disk."
        case .insufficientCapacity: return "The selected USB is too small for this image."
        case .unsupportedImage: return "Choose an ISO or raw IMG file."
        case .missingImage: return "The image is missing, empty, or not a regular file."
        case .sourceOnDestination: return "The source image must not be stored on the destination USB."
        }
    }
}

public struct CommandRunner: Sendable {
    public init() {}
    public func run(_ executable: String, _ arguments: [String], control: WriteControl? = nil) throws -> Data {
        // A file avoids pipe-buffer deadlocks when a command emits large output.
        let output = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("media-command-" + UUID().uuidString)
        let descriptor = open(output.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw MediaError.commandFailed("Cannot create command log.") }
        defer { try? FileManager.default.removeItem(at: output) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = handle; process.standardError = handle
        try control?.check()
        try process.run()
        if let control {
            while process.isRunning {
                if control.isCancelled || Task.isCancelled {
                    process.terminate(); process.waitUntilExit(); throw CancellationError()
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        process.waitUntilExit()
        try handle.seek(toOffset: 0)
        let data = try handle.readToEnd() ?? Data()
        guard process.terminationStatus == 0 else {
            throw MediaError.commandFailed(String(decoding: data, as: UTF8.self))
        }
        return data
    }
}

public struct DiskService: Sendable {
    public init() {}
    public static func decodeDevice(_ data: Data) throws -> USBDevice {
        guard let p = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = p["DeviceIdentifier"] as? String,
              let size = p["TotalSize"] as? NSNumber else { throw MediaError.invalidResponse }
        // Missing security properties default to ineligible, never to writable/external.
        return USBDevice(identifier: id, name: p["MediaName"] as? String ?? id,
                         size: size.uint64Value, isInternal: p["Internal"] as? Bool ?? true,
                         isWhole: p["WholeDisk"] as? Bool ?? p["Whole"] as? Bool ?? false,
                         isWritable: p["WritableMedia"] as? Bool ?? p["Writable"] as? Bool ?? false,
                         bus: p["BusProtocol"] as? String ?? "", registryID: registryIdentity(id))
    }
    public func devices() throws -> [USBDevice] {
        let runner = CommandRunner()
        let data = try runner.run("/usr/sbin/diskutil", ["list", "-plist", "external", "physical"])
        guard let p = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entries = p["AllDisksAndPartitions"] as? [[String: Any]] else { throw MediaError.invalidResponse }
        return try entries.compactMap { entry in
            guard let id = entry["DeviceIdentifier"] as? String else { throw MediaError.invalidResponse }
            let device = try Self.decodeDevice(runner.run("/usr/sbin/diskutil", ["info", "-plist", id]))
            return device.isEligible ? device : nil
        }
    }
}

public enum ImageKind: String, Sendable { case iso = "ISO image", raw = "Raw disk image" }
public struct MediaImage: Sendable {
    public let url: URL
    public let size: UInt64
    public let kind: ImageKind
    public init(url: URL) throws {
        let canonical = url.resolvingSymlinksInPath()
        let properties = try canonical.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard properties.isRegularFile == true, let bytes = properties.fileSize, bytes > 0 else {
            throw MediaError.missingImage
        }
        switch canonical.pathExtension.lowercased() {
        case "iso": kind = .iso
        case "img": kind = .raw
        default: throw MediaError.unsupportedImage
        }
        self.url = canonical; size = UInt64(bytes)
    }
}

public struct MediaPlan: Sendable {
    public let image: MediaImage
    public let device: USBDevice
    public init(image: MediaImage, device: USBDevice) throws {
        guard device.isEligible else { throw MediaError.unsafeDevice }
        guard device.size >= image.size else { throw MediaError.insufficientCapacity }
        self.image = image; self.device = device
    }
    public var summary: String {
        "Inspect \(image.url.lastPathComponent) for \(device.name) (/dev/\(device.identifier)). " +
        "ISO contents must be inspected before choosing Windows file-copy or Linux hybrid-image writing."
    }
}
