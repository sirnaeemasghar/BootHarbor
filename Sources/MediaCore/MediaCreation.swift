// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CryptoKit

public struct MediaCreation: Sendable {
    public let helper: URL
    public let wimTool: URL
    public let application: URL
    public init(helper: URL, wimTool: URL, application: URL) {
        self.helper = helper; self.wimTool = wimTool; self.application = application
    }
    public func create(image: MediaImage, device: USBDevice, control: WriteControl) throws -> String {
        let activity = try SystemActivity()
        defer { activity.end() }
        let disks = DiskService()
        try control.check()
        try disks.revalidate(device)
        var protected = [image.url, control.directory, application, helper]
        if FileManager.default.fileExists(atPath: wimTool.path) { protected.append(wimTool) }
        try disks.protect(protected, from: device)
        control.report(WriteProgress("Inspecting installation image"))
        let inspection = try ImageInspector().inspect(image)
        guard inspection.strategy != .unsupported else { throw MediaError.commandFailed(inspection.notes) }
        var mounted: MountedImage?
        defer { try? mounted?.close() }
        var prepared: PreparedWindows?
        if inspection.strategy == .windowsUEFI {
            let mount = try MountedImage(url: image.url)
            mounted = mount
            prepared = try WindowsFiles().prepare(root: mount.root, workspace: control.directory,
                                                 wimTool: wimTool, control: control)
            guard let prepared, prepared.requiredCapacity <= device.size else { throw MediaError.insufficientCapacity }
        } else {
            guard device.size >= image.size else { throw MediaError.insufficientCapacity }
        }
        try control.check()
        control.report(WriteProgress("Checking source image checksum"))
        let identity = try SourceIdentity(url: image.url)
        let checksum = try ImageChecksum().sha256(of: image.url, control: control)
        guard try SourceIdentity(url: image.url) == identity else { throw MediaError.commandFailed("The source image changed during preflight.") }
        try disks.revalidate(device)
        let job = try WriteJob(operation: inspection.strategy == .windowsUEFI ? .formatWindows : .raw,
                               device: device, image: image, sourceSHA256: checksum,
                               protectedPaths: protected.map(\.path))
        try job.validate()
        let data = try JSONEncoder().encode(job)
        let jobURL = control.directory.appendingPathComponent("job.json")
        guard FileManager.default.createFile(atPath: jobURL.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw MediaError.commandFailed("Cannot save the confirmed write job.")
        }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try control.check()
        control.report(WriteProgress("Waiting for macOS authorization; then preparing USB"))
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw MediaError.commandFailed("The bundled disk writer is missing. Build the full app bundle before writing.") }
        let command = [helper.path, jobURL.path, hash].map(ShellQuote.argument).joined(separator: " ")
        let script = "on run argv\nreturn do shell script (item 1 of argv) with administrator privileges\nend run"
        // Arguments are shell-quoted independently and passed as data, never AppleScript source.
        _ = try CommandRunner().run("/usr/bin/osascript", ["-e", script, command])
        try control.check()
        if let prepared {
            let mount = try disks.mountedFAT32Partition(on: device)
            let attributes = try mount.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            guard UInt64(max(0, attributes.volumeAvailableCapacity ?? 0)) >= prepared.requiredCapacity - 64 * 1024 * 1024 else {
                throw MediaError.insufficientCapacity
            }
            let identity = try USBIdentityMonitor(device: device)
            try WindowsFiles().copyAndVerify(prepared, to: mount, control: control) {
                try identity.validate()
            }
        }
        // Verification has succeeded. Cleanup/ejection failures are warnings about
        // finalized media, not reasons to erase and recreate a verified installer.
        let finalization = MediaFinalization.finish(detachSource: {
            try mounted?.close(); mounted = nil
        }, eject: {
            try disks.revalidate(device)
            control.report(WriteProgress("Ejecting verified USB"))
            _ = try CommandRunner().run("/usr/sbin/diskutil", ["eject", device.identifier])
        })
        control.report(WriteProgress(finalization.ejected
            ? "Complete — verified USB safely ejected"
            : "Files verified — safe ejection needs attention", completed: 1, total: 1))
        return finalization.message(windows: inspection.strategy == .windowsUEFI)
    }
}
