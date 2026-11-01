// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CryptoKit

public struct ImageChecksum: Sendable {
    public init() {}
    public func sha256(of url: URL, control: WriteControl? = nil) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            try control?.check()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
