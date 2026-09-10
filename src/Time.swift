import Foundation

/// Says a length of time in whole words: "1 hour 20 minutes".
/// It rounds up, so a session with 30 seconds left says "1 minute" and never
/// "0 minutes".
func spellDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded(.up)))
    let hours = minutes / 60
    let rest = minutes % 60

    func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    if hours == 0 { return plural(max(rest, 1), "minute") }
    if rest == 0 { return plural(hours, "hour") }
    return plural(hours, "hour") + " " + plural(rest, "minute")
}

/// The time of day, in the way this Mac writes it.
func clockTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter.string(from: date)
}
