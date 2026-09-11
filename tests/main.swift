import Cocoa

// A small test tool. It links the real source files, so it tests the code the
// app runs, not a copy. `./test.sh` builds and runs it; CI runs the same
// script on every push.

var failures = 0
var checks = 0

func check(_ name: String, _ passed: Bool, _ detail: String = "") {
    checks += 1
    if passed {
        print("  ok    \(name)")
    } else {
        failures += 1
        print("  FAIL  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
    }
}

func section(_ name: String) { print("\n\(name)") }

// MARK: - Version comparison

section("Update.isNewer")
let versions: [(String, String, Bool)] = [
    ("1.2", "1.1", true),
    ("1.1", "1.1", false),
    ("1.0", "1.1", false),
    ("1.10", "1.9", true),      // not a string comparison
    ("2.0", "1.99", true),
    ("1.1.1", "1.1", true),     // a longer version wins
    ("1.1", "1.1.1", false),
    ("10.0", "9.9", true),
]
for (a, b, want) in versions {
    check("isNewer(\(a), \(b)) == \(want)", Update.isNewer(a, than: b) == want)
}

// MARK: - Saying a length of time

section("spellDuration")
let durations: [(TimeInterval, String)] = [
    (60, "1 minute"),
    (120, "2 minutes"),
    (3600, "1 hour"),
    (7200, "2 hours"),
    (4800, "1 hour 20 minutes"),
    (28800, "8 hours"),
    (30, "1 minute"),          // rounds up, never "0 minutes"
    (90, "2 minutes"),         // a mutation test found the cases above could
    (3630, "1 hour 1 minute"), // not tell rounding up from rounding down
    (0, "1 minute"),
    (-60, "1 minute"),         // a deadline already past
    (3660, "1 hour 1 minute"), // singular on both halves
]
for (seconds, want) in durations {
    check("\(Int(seconds))s reads as \"\(want)\"", spellDuration(seconds) == want,
          spellDuration(seconds))
}

// MARK: - Shell quoting

section("shellQuote")
check("a plain word", shellQuote("hello") == "'hello'")
check("a space stays inside the quotes", shellQuote("a b") == "'a b'")
check("a single quote is closed and reopened",
      shellQuote("it's") == "'it'\\''s'", shellQuote("it's"))

// MARK: - The pmset commands

section("Privileged.pmsetCommand")
check("off", Privileged.pmsetCommand(false) == "/usr/bin/pmset -a disablesleep 0")
check("on", Privileged.pmsetCommand(true) == "/usr/bin/pmset -a disablesleep 1")

// MARK: - The sudoers rule

section("SudoRule")
if let staged = SudoRule.stage() {
    let body = (try? String(contentsOfFile: staged, encoding: .utf8)) ?? ""
    check("the rule names this user", body.contains(NSUserName()))
    check("it permits exactly the two pmset commands",
          body.contains("/usr/bin/pmset -a disablesleep 0")
          && body.contains("/usr/bin/pmset -a disablesleep 1"))
    // A mutation test found this one too narrow: it looked for one exact
    // spelling, so "ALL=(root) NOPASSWD: ALL" slipped past. Any bare ALL in
    // the command list is the thing to refuse.
    check("it permits nothing wider", !body.contains("NOPASSWD: ALL"))

    // The real check. visudo says whether sudo would accept this file.
    let visudo = run("/usr/sbin/visudo", ["-cqf", staged])
    check("visudo accepts the rule", visudo.status == 0, visudo.out)

    let command = SudoRule.installCommand(stagedAt: staged)
    check("the install command checks before it installs",
          command.hasPrefix("/usr/sbin/visudo -cqf"))
    check("it installs read-only and owned by root",
          command.contains("-m 0440 -o root -g wheel"))
    check("it writes to the expected path", command.contains(SudoRule.path))

    SudoRule.discard(staged)
    check("the temporary file is removed",
          !FileManager.default.fileExists(atPath: staged))
} else {
    check("the rule can be staged", false, "stage() gave nothing")
}

// MARK: - The decisions the app exists to make

section("decide")

let now = Date()
let soon = now.addingTimeInterval(600)
let past = now.addingTimeInterval(-1)

func situation(stayAwake: Bool, deadline: Date? = nil, percent: Int? = nil,
               onBattery: Bool = true, guardIsOn: Bool = true,
               rule: Bool = true) -> Situation {
    Situation(stayAwake: stayAwake,
              deadline: deadline,
              battery: percent.map { PowerState(percent: $0, onBattery: onBattery) },
              guardIsOn: guardIsOn,
              ruleIsInstalled: rule)
}

let cases: [(String, Situation, Decision)] = [
    ("Normal and nothing pending",
     situation(stayAwake: false), .doNothing),

    // The fault: refuse the password dialog and a Deadline was left armed for
    // a session that never began.
    ("a Deadline cannot stand outside Stay Awake",
     situation(stayAwake: false, deadline: soon), .dropDeadline),

    ("Stay Awake with time left",
     situation(stayAwake: true, deadline: soon), .doNothing),
    ("a Deadline exactly now",
     situation(stayAwake: true, deadline: now), .returnToNormal(because: .theDeadlinePassed)),
    ("a Deadline in the past",
     situation(stayAwake: true, deadline: past), .returnToNormal(because: .theDeadlinePassed)),

    ("the battery at 19% acts",
     situation(stayAwake: true, percent: 19),
     .returnToNormal(because: .theBatteryIsLow(percent: 19))),
    ("the limit itself, 20%, acts",
     situation(stayAwake: true, percent: 20),
     .returnToNormal(because: .theBatteryIsLow(percent: 20))),
    ("21% does not act",
     situation(stayAwake: true, percent: 21), .doNothing),

    ("the Guard switched off does nothing",
     situation(stayAwake: true, percent: 5, guardIsOn: false), .doNothing),
    ("without the Rule it warns instead of acting",
     situation(stayAwake: true, percent: 5, rule: false), .warnAboutBattery(percent: 5)),
    ("on the charger at 5% does nothing",
     situation(stayAwake: true, percent: 5, onBattery: false), .doNothing),
    ("a Mac with no battery does nothing",
     situation(stayAwake: true, percent: nil), .doNothing),

    ("a flat battery in Normal is not this app's business",
     situation(stayAwake: false, percent: 3), .doNothing),
    ("a passed Deadline wins over a low battery, so the answer is one thing",
     situation(stayAwake: true, deadline: past, percent: 5),
     .returnToNormal(because: .theDeadlinePassed)),
]

for (name, given, want) in cases {
    let got = decide(given, now: now)
    check(name, got == want, "got \(got), want \(want)")
}

// MARK: - The battery

section("Power")
if let power = Power.read() {
    check("the percentage is between 0 and 100", (0...100).contains(power.percent),
          "\(power.percent)")
    print("        this machine: \(power.percent)%, on battery: \(power.onBattery)")
} else {
    print("        no battery here, so the guard would never act — nothing to check")
}

// MARK: - The icon

section("Icon")
let wide = statusImage(stayAwake: true, size: 18)
let closed = statusImage(stayAwake: false, size: 18)
check("the Stay Awake icon draws", (wide.tiffRepresentation?.count ?? 0) > 0)
check("the Normal icon draws", (closed.tiffRepresentation?.count ?? 0) > 0)
check("the two states are not the same picture",
      wide.tiffRepresentation != closed.tiffRepresentation)
check("it is a template, so the menu bar colours it", wide.isTemplate)

// MARK: - GitHub, over the network

section("Update.check (network)")
var answered = false
Update.check { result in
    switch result {
    case .success(let release):
        let version = release?.version ?? "nothing newer than this build"
        let digits = CharacterSet(charactersIn: "0123456789.")
        check("GitHub answered and the version could be read",
              release == nil || version.rangeOfCharacter(from: digits.inverted) == nil,
              version)
        print("        newest release: \(version)")
    case .failure(let error):
        // A runner without a network, or a rate limit, must not fail the build.
        print("        SKIPPED: \(error.message)")
    }
    answered = true
}
let deadline = Date().addingTimeInterval(20)
while !answered && Date() < deadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
}
if !answered { print("        SKIPPED: no answer within 20 seconds") }

// MARK: - Result

print("\n\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
