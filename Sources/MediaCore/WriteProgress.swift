// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct WriteProgress: Codable, Sendable {
    public let phase: String
    public let completed: UInt64
    public let total: UInt64
    public var fraction: Double { total == 0 ? 0 : min(1, Double(completed) / Double(total)) }
    public init(_ phase: String, completed: UInt64 = 0, total: UInt64 = 0) {
        self.phase = phase; self.completed = completed; self.total = total
    }
}

public struct WriteControl: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public var isCancelled: Bool { FileManager.default.fileExists(atPath: directory.appendingPathComponent("cancel").path) }
    public func check() throws {
        if isCancelled || Task.isCancelled { throw CancellationError() }
    }
    public func cancel() throws { try Data().write(to: directory.appendingPathComponent("cancel"), options: .atomic) }
    public func report(_ progress: WriteProgress) {
        try? JSONEncoder().encode(progress).write(to: directory.appendingPathComponent("progress.json"), options: .atomic)
    }
    public func readProgress() -> WriteProgress? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("progress.json")) else { return nil }
        return try? JSONDecoder().decode(WriteProgress.self, from: data)
    }
}
