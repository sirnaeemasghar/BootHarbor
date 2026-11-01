// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Darwin

public final class MountedImage {
    public let root: URL
    private var attached = false
    public init(url: URL) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("media-source-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        do {
            _ = try CommandRunner().run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", root.path, url.path])
            attached = true
        } catch {
            _ = root.path.withCString { rmdir($0) }
            throw error
        }
    }
    public func close() throws {
        if attached {
            _ = try CommandRunner().run("/usr/bin/hdiutil", ["detach", root.path])
            attached = false
        }
        _ = root.path.withCString { rmdir($0) }
    }
    deinit { try? close() }
}
