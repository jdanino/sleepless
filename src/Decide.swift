import Foundation

// The decisions this app exists to make, as one pure function.
//
// It was not always like this. The rules lived inside the AppDelegate, where
// no test can reach them, and three faults hid there at once: a note that
// outlived the state it explained, a Deadline that could be cancelled without
// ever taking effect, and a Deadline armed for a session that never began.
// Every one of those is a line in the test table now.

/// How low the battery may fall before a Guard acts.
let lowBatteryPercent = 20

/// Everything the app knows about this moment, in one value.
struct Situation: Equatable {
    var stayAwake: Bool
    var deadline: Date?
    var battery: PowerState?
    var guardIsOn: Bool
    var ruleIsInstalled: Bool
}

/// Why the app returned the Mac to Normal without being asked.
enum Reason: Equatable {
    case theDeadlinePassed
    case theBatteryIsLow(percent: Int)
}

enum Decision: Equatable {
    case doNothing
    /// A Deadline is standing outside Stay Awake and means nothing there.
    case dropDeadline
    case returnToNormal(because: Reason)
    /// The battery is low, but without the Rule the app cannot act silently.
    case warnAboutBattery(percent: Int)
}

func decide(_ situation: Situation, now: Date) -> Decision {
    // A Deadline only means something inside Stay Awake. If the state changed
    // some other way — a refused password, or pmset in a terminal — the
    // Deadline goes with it.
    if !situation.stayAwake {
        return situation.deadline != nil ? .dropDeadline : .doNothing
    }

    if let deadline = situation.deadline, now >= deadline {
        return .returnToNormal(because: .theDeadlinePassed)
    }

    // A Mac that cannot sleep, in a closed bag, on a falling battery, gets hot
    // and empty.
    if situation.guardIsOn,
       let battery = situation.battery,
       battery.onBattery,
       battery.percent <= lowBatteryPercent {
        // Act without a word only when the Rule permits it. A password dialog
        // appearing by itself, with the lid closed, would be worse than the
        // problem it solves.
        return situation.ruleIsInstalled
            ? .returnToNormal(because: .theBatteryIsLow(percent: battery.percent))
            : .warnAboutBattery(percent: battery.percent)
    }

    return .doNothing
}
