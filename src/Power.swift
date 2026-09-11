import Foundation
import IOKit.ps

struct PowerState: Equatable {
    let percent: Int
    let onBattery: Bool
}

enum Power {
    /// The battery of this Mac. It is nil on a Mac that has none, and then the
    /// battery guard simply never acts.
    static func read() -> PowerState? {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard
                let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
                    as? [String: Any],
                let now = info[kIOPSCurrentCapacityKey] as? Int,
                let full = info[kIOPSMaxCapacityKey] as? Int, full > 0
            else { continue }
            let state = info[kIOPSPowerSourceStateKey] as? String
            return PowerState(percent: now * 100 / full,
                              onBattery: state == kIOPSBatteryPowerValue)
        }
        return nil
    }
}
