// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import DiskArbitration

private final class DAWait: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var error: Int32 = 0
    func finish(_ dissenter: DADissenter?) {
        lock.lock(); error = dissenter.map { DADissenterGetStatus($0) } ?? 0; lock.unlock()
        semaphore.signal()
    }
    func wait() throws {
        guard semaphore.wait(timeout: .now() + 90) == .success else { throw MediaError.commandFailed("Timed out waiting for exclusive USB access.") }
        lock.lock(); let result = error; lock.unlock()
        guard result == 0 else { throw MediaError.commandFailed("macOS refused exclusive USB access (\(result)). Close apps using this drive and retry.") }
    }
}

public final class ExclusiveDisk {
    private let session: DASession
    private let disk: DADisk
    private let queue = DispatchQueue(label: "org.mediacreationtool.disk-claim")
    private var claimed = false
    public init(identifier: String) throws {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, identifier) else { throw MediaError.unsafeDevice }
        self.session = session; self.disk = disk
        DASessionSetDispatchQueue(session, queue)
        let claim = DAWait()
        DADiskClaim(disk, DADiskClaimOptions(kDADiskClaimOptionDefault), { _, _ in
            Unmanaged.passRetained(DADissenterCreate(kCFAllocatorDefault, DAReturn(kDAReturnNotPermitted), "Installation media is being written" as CFString))
        }, nil, { _, error, context in
            guard let context else { return }
            Unmanaged<DAWait>.fromOpaque(context).takeRetainedValue().finish(error)
        }, Unmanaged.passRetained(claim).toOpaque())
        try claim.wait()
        claimed = true
        let unmount = DAWait()
        DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionWhole), { _, error, context in
            guard let context else { return }
            Unmanaged<DAWait>.fromOpaque(context).takeRetainedValue().finish(error)
        }, Unmanaged.passRetained(unmount).toOpaque())
        do { try unmount.wait() } catch { DADiskUnclaim(disk); claimed = false; throw error }
    }
    deinit {
        if claimed { DADiskUnclaim(disk) }
        DASessionSetDispatchQueue(session, nil)
    }
}
