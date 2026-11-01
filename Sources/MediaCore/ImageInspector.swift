// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Darwin

public enum BootStrategy: String, Sendable {
    case windowsUEFI = "Windows UEFI file-copy"
    case rawCandidate = "Raw image — boot compatibility unverified"
    case unsupported = "Unsupported or unidentified ISO"
}

public struct ImageInspection: Sendable {
    public let strategy: BootStrategy
    public let efiLoaders: [String]
    public let oversizedFiles: [String]
    public let requiresWIMSplit: Bool
    public let notes: String
}

public struct ImageInspector: Sendable {
    public init() {}
    public func inspect(_ image: MediaImage) throws -> ImageInspection {
        if try RawImageProbe.supports(image.url) {
            return ImageInspection(strategy: .rawCandidate, efiLoaders: [], oversizedFiles: [],
                                   requiresWIMSplit: false,
                                   notes: "Partitioned disk/hybrid image detected. It will be written sector-for-sector and verified. Boot support follows the original image and target firmware.")
        }
        guard image.kind == .iso else {
            throw MediaError.commandFailed("This raw image has no valid supported partition table.")
        }
        let mounted = try MountedImage(url: image.url)
        defer { try? mounted.close() }
        let result = try Self.inspectDirectory(mounted.root)
        try mounted.close()
        return result
    }

    public static func inspectDirectory(_ directory: URL) throws -> ImageInspection {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let manager = FileManager.default
        var failures: [String] = []
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                                                  options: [], errorHandler: { url, _ in
            failures.append(url.lastPathComponent); return false
        }) else { throw MediaError.invalidResponse }
        var oversized: [String] = []
        var regular = Set<String>()
        for case let file as URL in enumerator {
            let props = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard props.isSymbolicLink != true else { continue }
            let relative = file.standardizedFileURL.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/").lowercased()
            if props.isRegularFile == true {
                regular.insert(relative)
                if UInt64(props.fileSize ?? 0) > 4_294_967_295 { oversized.append(relative) }
            }
        }
        guard failures.isEmpty else { throw MediaError.commandFailed("Cannot inspect image contents: " + failures.joined(separator: ", ")) }
        let loaders = regular.filter { ["efi/boot/bootx64.efi", "efi/boot/bootaa64.efi", "efi/boot/bootia32.efi"].contains($0) }.sorted()
        let hasInstall = regular.contains("sources/install.wim") || regular.contains("sources/install.esd") || regular.contains("sources/install.swm")
        let isWindows = regular.contains("sources/boot.wim") && regular.contains("setup.exe") && hasInstall
        let split = oversized.contains("sources/install.wim") || oversized.contains("sources/install.esd")
        let blockers = oversized.filter { $0 != "sources/install.wim" && $0 != "sources/install.esd" }
        if isWindows && !loaders.isEmpty {
            return ImageInspection(strategy: blockers.isEmpty ? .windowsUEFI : .unsupported,
                                   efiLoaders: loaders, oversizedFiles: oversized.sorted(), requiresWIMSplit: split,
                                   notes: blockers.isEmpty
                                    ? (split ? "Windows UEFI layout found. The installation payload will be converted if needed and split into SWM files before FAT32 copying. Booting is not yet verified."
                                             : "Windows UEFI layout found. FAT32 file-copy candidate; booting is not yet verified.")
                                    : "Files exceed FAT32 limits and are not a splittable install.wim: " + blockers.joined(separator: ", "))
        }
        return ImageInspection(strategy: .unsupported, efiLoaders: loaders,
                               oversizedFiles: oversized.sorted(), requiresWIMSplit: false,
                               notes: "No supported Windows UEFI layout found. No supported partitioned hybrid layout was detected; this image cannot be written automatically.")
    }
}
