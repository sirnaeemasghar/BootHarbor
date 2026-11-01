// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum RawImageProbe {
    public static func supports(_ url: URL) throws -> Bool {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard size >= 512 else { return false }
        return try supports(handle, imageSize: UInt64(size))
    }

    /// Validate the already-open source that will actually be copied, not a
    /// filename that could have been replaced after checksum validation.
    public static func supports(_ handle: FileHandle, imageSize: UInt64) throws -> Bool {
        try handle.seek(toOffset: 0)
        let header = try handle.read(upToCount: 512) ?? Data()
        guard validateHeader(header, imageSize: imageSize) else { return false }
        let protective = (0..<4).contains { header[450 + $0 * 16] == 0xee }
        if protective { return try validateGPT(handle, imageSize: imageSize) }
        return true
    }
    private static func validateGPT(_ handle: FileHandle, imageSize: UInt64) throws -> Bool {
        try handle.seek(toOffset: 512)
        guard var header = try handle.read(upToCount: 512), header.count == 512,
              header.prefix(8) == Data("EFI PART".utf8) else { return false }
        func integer(_ data: Data, _ offset: Int, _ count: Int) -> UInt64 {
            (0..<count).reduce(UInt64(0)) { $0 | UInt64(data[offset + $1]) << (8 * $1) }
        }
        let headerSize = integer(header, 12, 4), recordedCRC = integer(header, 16, 4)
        guard (92...512).contains(headerSize), integer(header, 24, 8) == 1,
              integer(header, 32, 8) < imageSize / 512,
              integer(header, 40, 8) <= integer(header, 48, 8), integer(header, 48, 8) < imageSize / 512 else { return false }
        header.replaceSubrange(16..<20, with: [0, 0, 0, 0])
        guard UInt64(crc32(Data(header.prefix(Int(headerSize))))) == recordedCRC else { return false }
        let lba = integer(header, 72, 8), count = integer(header, 80, 4), entrySize = integer(header, 84, 4)
        guard lba >= 2, lba < imageSize / 512, count > 0, count <= 4096,
              entrySize >= 128, entrySize <= 4096, entrySize % 8 == 0,
              count * entrySize <= 16 * 1024 * 1024, count * entrySize <= imageSize - lba * 512 else { return false }
        try handle.seek(toOffset: lba * 512)
        guard let entries = try handle.read(upToCount: Int(count * entrySize)), entries.count == Int(count * entrySize),
              UInt64(crc32(entries)) == integer(header, 88, 4) else { return false }
        var found = false
        for index in 0..<Int(count) {
            let offset = index * Int(entrySize)
            if entries[offset..<(offset + 16)].allSatisfy({ $0 == 0 }) { continue }
            let first = integer(entries, offset + 32, 8), last = integer(entries, offset + 40, 8)
            guard first <= last, last < imageSize / 512 else { return false }
            found = true
        }
        return found
    }
    static func crc32(_ bytes: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xedb88320) }
        }
        return ~crc
    }
    public static func validateHeader(_ data: Data, imageSize: UInt64) -> Bool {
        guard data.count == 512, imageSize >= 512, imageSize % 512 == 0,
              data[510] == 0x55, data[511] == 0xaa else { return false }
        func u32(_ offset: Int) -> UInt64 {
            (0..<4).reduce(UInt64(0)) { $0 | UInt64(data[offset + $1]) << (8 * $1) }
        }
        var hasPartition = false
        for index in 0..<4 {
            let start = 446 + index * 16
            let type = data[start + 4]
            let lba = u32(start + 8), sectors = u32(start + 12)
            if type == 0 && sectors == 0 { continue }
            guard type != 0, sectors > 0, data[start] == 0 || data[start] == 0x80,
                  lba < imageSize / 512 else { return false }
            // Protective MBRs can deliberately use the largest representable size.
            guard type == 0xee || lba + sectors <= imageSize / 512 else { return false }
            hasPartition = true
        }
        return hasPartition
    }
}
