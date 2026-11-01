// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import IOKit.pwr_mgt

/// Scoped idle-sleep protection; display sleep and explicit lid/manual sleep are unchanged.
public final class SystemActivity {
    private(set) var assertionID: IOPMAssertionID?

    public init() throws {
        var identifier: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "Creating and verifying installation USB media" as CFString, &identifier)
        guard status == kIOReturnSuccess else {
            throw MediaError.commandFailed("macOS could not prevent idle sleep during USB creation (\(status)).")
        }
        assertionID = identifier
    }
    public func end() {
        guard let identifier = assertionID else { return }
        IOPMAssertionRelease(identifier)
        assertionID = nil
    }
    deinit { end() }
}
