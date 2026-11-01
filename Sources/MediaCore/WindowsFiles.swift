// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Darwin
import CryptoKit

public struct WindowsFile: Sendable {
    public let source: URL
    public let relativePath: String
    public let size: UInt64
    public let sha256: String
}
public struct PreparedWindows: Sendable {
    public let files: [WindowsFile]
    public var totalBytes: UInt64 { files.reduce(0) { $0 + $1.size } }
    public var requiredCapacity: UInt64 {
        // Conservative FAT cluster allocation plus partition/filesystem overhead.
        files.reduce(UInt64(64 * 1024 * 1024)) { $0 + (($1.size + 32767) / 32768) * 32768 }
    }
}

public struct WindowsFiles: Sendable {
    public init() {}
    public func prepare(root: URL, workspace: URL, wimTool: URL, control: WriteControl,
                        splitLimitMiB: Int = 3800) throws -> PreparedWindows {
        guard (1...3800).contains(splitLimitMiB) else { throw MediaError.invalidResponse }
        let inspection = try ImageInspector.inspectDirectory(root)
        guard inspection.strategy == .windowsUEFI else { throw MediaError.unsupportedImage }
        let originals = try enumerate(root)
        var replacements: [(URL, String)] = []
        var omitted = Set<String>()
        if inspection.requiresWIMSplit {
            guard FileManager.default.isExecutableFile(atPath: wimTool.path),
                  let payload = originals.first(where: {
                      ["sources/install.wim", "sources/install.esd"].contains($0.1.lowercased()) && $0.2 > 4_294_967_295
                  }) else { throw MediaError.commandFailed("The bundled WIM tool is missing or the installation payload could not be found.") }
            omitted.insert(payload.1.lowercased())
            let parts = try split(payload: payload.0, workspace: workspace, wimTool: wimTool,
                                  control: control, limitMiB: splitLimitMiB)
            let sourcesDirectory = (payload.1 as NSString).deletingLastPathComponent
            replacements = parts.map { ($0, sourcesDirectory + "/" + $0.lastPathComponent) }
        }
        let all: [(URL, String)] = originals.filter { !omitted.contains($0.1.lowercased()) }.map { ($0.0, $0.1) } + replacements
        var names = Set<String>()
        var files: [WindowsFile] = []
        for (index, entry) in all.enumerated() {
            try control.check()
            guard names.insert(entry.1.lowercased()).inserted else { throw MediaError.commandFailed("Conflicting FAT32 filenames: " + entry.1) }
            let bytes = try entry.0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard UInt64(bytes) <= 4_294_967_295 else { throw MediaError.commandFailed("A file still exceeds FAT32 limits: " + entry.1) }
            control.report(WriteProgress("Checking " + entry.1, completed: UInt64(index), total: UInt64(all.count)))
            let hash = try checksum(entry.0, control: control)
            files.append(WindowsFile(source: entry.0, relativePath: entry.1, size: UInt64(bytes), sha256: hash))
        }
        return PreparedWindows(files: files)
    }

    /// Public for repeatable splitter tests with a small valid WIM; no disks are accessed.
    public func split(payload: URL, workspace: URL, wimTool: URL, control: WriteControl, limitMiB: Int = 3800) throws -> [URL] {
        guard (1...3800).contains(limitMiB) else { throw MediaError.invalidResponse }
        let output = workspace.appendingPathComponent("swm-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let runner = CommandRunner()
        control.report(WriteProgress("Splitting Windows image before erasing USB"))
        do {
            _ = try runner.run(wimTool.path, ["split", payload.path, output.appendingPathComponent("install.swm").path, String(limitMiB), "--check"], control: control)
        } catch is CancellationError { throw CancellationError() }
        catch {
            // Solid/ESD-compressed images must first be exported to a non-solid WIM.
            for file in try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil) {
                try FileManager.default.removeItem(at: file)
            }
            let converted = workspace.appendingPathComponent(UUID().uuidString + ".wim")
            defer { try? FileManager.default.removeItem(at: converted) }
            control.report(WriteProgress("Converting compressed Windows image before splitting"))
            _ = try runner.run(wimTool.path, ["export", payload.path, "all", converted.path, "--compress=LZX", "--recompress", "--check"], control: control)
            _ = try runner.run(wimTool.path, ["split", converted.path, output.appendingPathComponent("install.swm").path, String(limitMiB), "--check"], control: control)
        }
        let files = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension.lowercased() == "swm" }
        guard files.contains(where: { $0.lastPathComponent == "install.swm" }), !files.isEmpty else {
            throw MediaError.commandFailed("WIM splitting did not produce installation parts.")
        }
        for file in files {
            guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 4_294_967_295 else {
                throw MediaError.commandFailed("A split Windows image part exceeds FAT32 limits.")
            }
        }
        _ = try runner.run(wimTool.path, ["verify", output.appendingPathComponent("install.swm").path,
                                        "--ref=" + output.appendingPathComponent("install*.swm").path], control: control)
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func copyAndVerify(_ prepared: PreparedWindows, to destination: URL, control: WriteControl,
                              validateDestination: () throws -> Void = {}) throws {
        let rootFD = open(destination.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard rootFD >= 0 else { throw MediaError.invalidResponse }
        defer { Darwin.close(rootFD) }
        var disk = stat()
        guard fstat(rootFD, &disk) == 0, disk.st_mode & S_IFMT == S_IFDIR else { throw MediaError.invalidResponse }
        let volumeDevice = disk.st_dev
        func validate() throws {
            try control.check(); try validateDestination()
            var current = stat()
            guard lstat(destination.path, &current) == 0, current.st_dev == volumeDevice,
                  current.st_mode & S_IFMT == S_IFDIR, current.st_ino == disk.st_ino else { throw MediaError.commandFailed("The destination USB was disconnected or changed.") }
        }
        var copied: UInt64 = 0
        for (index, file) in prepared.files.enumerated() {
            try validate()
            let parentFD = try openParent(file.relativePath, rootFD: rootFD, device: volumeDevice, create: true)
            // Open each parent relative to an already-open directory, refusing symlinks.
            let fd = openat(parentFD, (file.relativePath as NSString).lastPathComponent, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
            Darwin.close(parentFD)
            guard fd >= 0 else { throw MediaError.commandFailed("Cannot create USB file: " + file.relativePath) }
            let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            let input = try FileHandle(forReadingFrom: file.source)
            do {
                var hash = SHA256(), bytesCopied: UInt64 = 0
                var lastReport = ContinuousClock.now
                while let bytes = try input.read(upToCount: 4 * 1024 * 1024), !bytes.isEmpty {
                    try validate()
                    try output.write(contentsOf: bytes); hash.update(data: bytes)
                    bytesCopied += UInt64(bytes.count); copied += UInt64(bytes.count)
                    let now = ContinuousClock.now
                    if now - lastReport >= .milliseconds(200) || bytesCopied == file.size {
                        control.report(WriteProgress("Copying file \(index + 1)/\(prepared.files.count): " + file.relativePath, completed: copied, total: prepared.totalBytes))
                        lastReport = now
                    }
                }
                guard bytesCopied == file.size,
                      hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else {
                    throw MediaError.commandFailed("Source changed during copy: " + file.relativePath)
                }
                try output.close(); try input.close()
            } catch { try? output.close(); try? input.close(); throw error }
        }
        var verified: UInt64 = 0
        // Let macOS coalesce filesystem/FAT updates across the entire copy. Every
        // file is still explicitly synchronized before its read-back verification.
        // This avoids hundreds of forced write/flush cycles during directory growth.
        for (index, file) in prepared.files.enumerated() {
            try validate()
            control.report(WriteProgress("Flushing & verifying file \(index + 1)/\(prepared.files.count): " + file.relativePath, completed: verified, total: prepared.totalBytes))
            let parentFD = try openParent(file.relativePath, rootFD: rootFD, device: volumeDevice, create: false)
            let fd = openat(parentFD, (file.relativePath as NSString).lastPathComponent, O_RDONLY | O_NOFOLLOW)
            Darwin.close(parentFD)
            guard fd >= 0 else { throw MediaError.commandFailed("Cannot read back USB file: " + file.relativePath) }
            let input = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? input.close() }
            guard fsync(fd) == 0 else { throw MediaError.commandFailed("Could not flush USB file: " + file.relativePath) }
            try validate()
            guard try checksum(input, control: control) == file.sha256 else {
                throw MediaError.commandFailed("USB verification failed: " + file.relativePath)
            }
            verified += file.size
        }
        control.report(WriteProgress("Files verified", completed: prepared.totalBytes, total: prepared.totalBytes))
    }
    private func openParent(_ path: String, rootFD: Int32, device: dev_t, create: Bool) throws -> Int32 {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty, components.allSatisfy({ $0 != "." && $0 != ".." }), !path.hasPrefix("/") else { throw MediaError.invalidResponse }
        var current = dup(rootFD)
        guard current >= 0 else { throw MediaError.invalidResponse }
        do {
            for component in components.dropLast() {
                if create && mkdirat(current, component, 0o755) != 0 && errno != EEXIST { throw MediaError.commandFailed("Cannot create USB folder: " + component) }
                let next = openat(current, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard next >= 0 else { throw MediaError.commandFailed("Unsafe or unavailable USB folder: " + component) }
                var info = stat()
                guard fstat(next, &info) == 0, info.st_dev == device else { Darwin.close(next); throw MediaError.unsafeDevice }
                Darwin.close(current); current = next
            }
            return current
        } catch { Darwin.close(current); throw error }
    }
    private func enumerate(_ root: URL) throws -> [(URL, String, UInt64)] {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        var failure = false
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], errorHandler: { _, _ in failure = true; return false }) else {
            throw MediaError.invalidResponse
        }
        var files: [(URL, String, UInt64)] = []
        var names = Set<String>()
        for case let file as URL in iterator {
            let value = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            let components = file.standardizedFileURL.pathComponents.dropFirst(root.pathComponents.count)
            let path = components.joined(separator: "/")
            guard value.isSymbolicLink != true, value.isDirectory == true || value.isRegularFile == true,
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasSuffix(".") && !$0.hasSuffix(" ") && $0.rangeOfCharacter(from: CharacterSet(charactersIn: "<>:\"\\|?*\0")) == nil }),
                  names.insert(path.lowercased()).inserted else { throw MediaError.commandFailed("Unsupported FAT32 path or conflicting filename: " + path) }
            if value.isRegularFile == true { files.append((file, path, UInt64(value.fileSize ?? 0))) }
        }
        guard !failure else { throw MediaError.commandFailed("Not all ISO files could be enumerated.") }
        return files.sorted { $0.1 < $1.1 }
    }
    private func checksum(_ url: URL, control: WriteControl) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try checksum(handle, control: control)
    }
    private func checksum(_ handle: FileHandle, control: WriteControl) throws -> String {
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try control.check(); hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
