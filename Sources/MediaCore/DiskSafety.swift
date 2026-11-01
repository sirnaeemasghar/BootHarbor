// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import DiskArbitration
import IOKit

public func registryIdentity(_ identifier: String) -> UInt64 {
    guard let session = DASessionCreate(kCFAllocatorDefault),
          let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, identifier) else { return 0 }
    return registryIdentity(disk)
}

private func registryIdentity(_ disk: DADisk) -> UInt64 {
    let media = DADiskCopyIOMedia(disk)
    guard media != 0 else { return 0 }
    defer { IOObjectRelease(media) }
    var identity: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(media, &identity) == KERN_SUCCESS else { return 0 }
    return identity
}

/// Retains the connection, but looks up the current disk/media on every check.
/// Open filesystem descriptors bind writes to the original mounted volume as well.
public final class USBIdentityMonitor {
    private let session: DASession
    private let expected: USBDevice
    public init(device: USBDevice) throws {
        guard device.registryID != 0, let session = DASessionCreate(kCFAllocatorDefault) else { throw MediaError.unsafeDevice }
        self.session = session; expected = device
        try validate()
    }
    public func validate() throws {
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, expected.identifier),
              registryIdentity(disk) == expected.registryID else {
            throw MediaError.commandFailed("The selected USB was disconnected or changed.")
        }
    }
}

public extension DiskService {
    func info(_ reference: String) throws -> [String: Any] {
        let data = try CommandRunner().run("/usr/sbin/diskutil", ["info", "-plist", reference])
        guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw MediaError.invalidResponse
        }
        return result
    }
    func revalidate(_ expected: USBDevice) throws {
        let data = try CommandRunner().run("/usr/sbin/diskutil", ["info", "-plist", expected.identifier])
        let current = try Self.decodeDevice(data)
        guard expected.isEligible, current.isEligible, expected.registryID != 0,
              current.registryID == expected.registryID, current.size == expected.size,
              current.name == expected.name else {
            throw MediaError.commandFailed("USB identity changed or cannot be confirmed. Refresh and select the drive again.")
        }
    }
    /// Resolve filesystem/virtual/APFS ancestry, rejecting unknown backing relationships.
    func physicalDisks(containing url: URL) throws -> Set<String> {
        try resolvePhysicalDisks(containing: url, depth: 0)
    }
    private func resolvePhysicalDisks(containing url: URL, depth: Int) throws -> Set<String> {
        guard depth < 16 else { throw MediaError.commandFailed("Source disk-image ancestry is too deeply nested or cyclic.") }
        let canonical = url.resolvingSymlinksInPath()
        guard let volume = try canonical.resourceValues(forKeys: [.volumeURLKey]).volume else {
            throw MediaError.commandFailed("Cannot determine the source volume.")
        }
        let first = try info(volume.path)
        var visited = Set<String>()
        func descend(_ data: [String: Any]) throws -> Set<String> {
            guard let identifier = data["DeviceIdentifier"] as? String else { throw MediaError.invalidResponse }
            guard visited.insert(identifier).inserted else {
                throw MediaError.commandFailed("Cannot resolve cyclic disk ancestry safely.")
            }
            defer { visited.remove(identifier) }
            if let stores = data["APFSPhysicalStores"] as? [[String: Any]], !stores.isEmpty {
                return try stores.reduce(into: Set<String>()) { result, store in
                    guard let id = store["APFSPhysicalStore"] as? String else { throw MediaError.invalidResponse }
                    result.formUnion(try descend(info(id)))
                }
            }
            if let parent = data["ParentWholeDisk"] as? String, parent != identifier {
                return try descend(info(parent))
            }
            if data["VirtualOrPhysical"] as? String == "Virtual" || data["BusProtocol"] as? String == "Disk Image" {
                let attached = try CommandRunner().run("/usr/bin/hdiutil", ["info", "-plist"])
                guard let plist = try PropertyListSerialization.propertyList(from: attached, format: nil) as? [String: Any],
                      let images = plist["images"] as? [[String: Any]] else { throw MediaError.invalidResponse }
                for image in images {
                    let entities = image["system-entities"] as? [[String: Any]] ?? []
                    if entities.contains(where: { ($0["dev-entry"] as? String) == "/dev/" + identifier }),
                       let path = image["image-path"] as? String {
                        return try resolvePhysicalDisks(containing: URL(fileURLWithPath: path), depth: depth + 1)
                    }
                }
                throw MediaError.commandFailed("Cannot resolve the backing device of a mounted image.")
            }
            guard data["WholeDisk"] as? Bool == true || data["Whole"] as? Bool == true else {
                throw MediaError.invalidResponse
            }
            return [identifier]
        }
        return try descend(first)
    }
    func protect(_ urls: [URL], from device: USBDevice) throws {
        for url in urls {
            if try physicalDisks(containing: url).contains(device.identifier) { throw MediaError.sourceOnDestination }
        }
        if try physicalDisks(containing: URL(fileURLWithPath: "/")).contains(device.identifier) {
            throw MediaError.unsafeDevice
        }
    }
    func mountedFAT32Partition(on device: USBDevice) throws -> URL {
        try revalidate(device)
        let data = try CommandRunner().run("/usr/sbin/diskutil", ["list", "-plist", device.identifier])
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let disks = plist["AllDisksAndPartitions"] as? [[String: Any]],
              let whole = disks.first(where: { $0["DeviceIdentifier"] as? String == device.identifier }),
              let partitions = whole["Partitions"] as? [[String: Any]] else { throw MediaError.invalidResponse }
        for partition in partitions {
            guard let id = partition["DeviceIdentifier"] as? String else { continue }
            let details = try info(id)
            guard details["ParentWholeDisk"] as? String == device.identifier,
                  details["FilesystemType"] as? String == "msdos",
                  let mount = details["MountPoint"] as? String else { continue }
            return URL(fileURLWithPath: mount, isDirectory: true)
        }
        throw MediaError.commandFailed("The newly formatted FAT32 partition is not mounted.")
    }
}
