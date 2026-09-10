import Cocoa

// The parts that talk to the system: running a command, asking for root, and
// the password-free sudo rule. They live apart from main.swift because that
// file holds the top-level code of the app, and top-level code cannot be
// linked into the test binary.

// MARK: - Helpers

struct Failure: Error {
    let message: String
    init(_ message: String) { self.message = message }
    var isCancel: Bool { message == "cancelled" }
}

@discardableResult
func run(_ launchPath: String, _ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// MARK: - Root permission

enum Privileged {
    /// Runs a shell command as root. The AppleScript runs inside this process.
    /// Thus the macOS dialog shows the name Sleepless, not osascript.
    /// Call this on the main thread only.
    static func runAsRoot(_ shellCommand: String) -> Result<Void, Failure> {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            return .failure(Failure("Cannot make the script."))
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        guard let info = errorInfo else { return .success(()) }
        let number = info[NSAppleScript.errorNumber] as? Int ?? 0
        if number == -128 { return .failure(Failure("cancelled")) }
        let text = info[NSAppleScript.errorMessage] as? String ?? "Error \(number)"
        return .failure(Failure(text))
    }

    /// Applies the setting with the password-free rule. No dialog.
    static func pmsetQuietly(_ on: Bool) -> Bool {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"]).status == 0
    }

    static func pmsetCommand(_ on: Bool) -> String {
        "/usr/bin/pmset -a disablesleep \(on ? "1" : "0")"
    }
}

// MARK: - The password-free sudo rule

enum SudoRule {
    static let path = "/etc/sudoers.d/sleepless"

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: path) }

    /// Writes the rule to a temporary file and gives back the path.
    static func stage() -> String? {
        let user = NSUserName()
        let body = """
        # Installed by Sleepless. It permits only these two exact commands.
        \(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1

        """
        let tmp = NSTemporaryDirectory() + "sleepless.sudoers"
        do { try body.write(toFile: tmp, atomically: true, encoding: .utf8) } catch { return nil }
        return tmp
    }

    /// The shell part that checks the rule and puts it in place.
    static func installCommand(stagedAt tmp: String) -> String {
        "/usr/sbin/visudo -cqf \(shellQuote(tmp))"
        + " && /usr/bin/install -m 0440 -o root -g wheel \(shellQuote(tmp)) \(shellQuote(path))"
    }

    static func discard(_ tmp: String?) {
        guard let tmp else { return }
        try? FileManager.default.removeItem(atPath: tmp)
    }

    static func remove() -> Result<Void, Failure> {
        Privileged.runAsRoot("/bin/rm -f \(shellQuote(path))")
    }
}
