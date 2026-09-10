import Cocoa
import ServiceManagement

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

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let askEveryTimeKey = "AskForPasswordEveryTime"

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var timer: Timer?
    private var sleepDisabled = false
    private var busy = false

    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Toggle", action: #selector(toggle), keyEquivalent: "t")
    private let sudoItem = NSMenuItem(title: "Toggle without a password", action: #selector(toggleSudoRule), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")

    private var askEveryTime: Bool {
        get { UserDefaults.standard.bool(forKey: askEveryTimeKey) }
        set { UserDefaults.standard.set(newValue, forKey: askEveryTimeKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        buildMenu()
        readState()
        updateUI()

        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, !self.busy else { return }
            self.readState()
            self.updateUI()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func buildMenu() {
        stateItem.isEnabled = false
        for item in [stateItem, NSMenuItem.separator(), toggleItem, NSMenuItem.separator(),
                     sudoItem, loginItem, NSMenuItem.separator()] {
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem(title: "Quit Sleepless",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in [toggleItem, sudoItem, loginItem] { item.target = self }
    }

    // MARK: State

    private func readState() {
        let r = run("/usr/bin/pmset", ["-g"])
        for line in r.out.split(separator: "\n") where line.contains("SleepDisabled") {
            sleepDisabled = line.trimmingCharacters(in: .whitespaces).hasSuffix("1")
            return
        }
        sleepDisabled = false
    }

    private func updateUI() {
        let description = sleepDisabled
            ? "Your Mac will stay awake when closed"
            : "Your Mac will go to sleep when closed"
        if let button = statusItem.button {
            // The face has open eyes while the Mac stays awake.
            let icon = statusImage(awake: sleepDisabled, size: 18)
            icon.accessibilityDescription = description
            button.image = icon
            button.appearsDisabled = busy
            button.toolTip = description
        }
        // The state line carries the character. The action line must be plain,
        // because the user acts on it.
        stateItem.title = sleepDisabled ? "Zombie roams when closed" : "Sleeps when closed"
        toggleItem.title = sleepDisabled ? "Let it sleep when closed" : "Keep it awake when closed"
        sudoItem.state = SudoRule.isInstalled ? .on : .off
        loginItem.state = isLoginEnabled ? .on : .off
    }

    // MARK: Actions

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRightClick { showMenu() } else { toggle() }
    }

    private func showMenu() {
        updateUI()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggle() {
        guard !busy else { return }
        let target = !sleepDisabled
        busy = true
        updateUI()

        // The rule is in place: apply the setting in the background, with no dialog.
        if SudoRule.isInstalled {
            DispatchQueue.global(qos: .userInitiated).async {
                let ok = Privileged.pmsetQuietly(target)
                DispatchQueue.main.async {
                    if ok {
                        self.finish()
                    } else {
                        // The rule is broken or gone. Ask for the password again.
                        self.askForPassword(target)
                    }
                }
            }
            return
        }
        askForPassword(target)
    }

    /// Shows one dialog. It installs the password-free rule (if permitted) and
    /// applies the setting in the same privileged step.
    private func askForPassword(_ target: Bool) {
        var staged: String?
        var command = Privileged.pmsetCommand(target)
        if !askEveryTime, let tmp = SudoRule.stage() {
            staged = tmp
            command = SudoRule.installCommand(stagedAt: tmp) + " && " + command
        }

        var result = Privileged.runAsRoot(command)
        // If the rule cannot be installed, do at least the toggle.
        if case .failure(let error) = result, !error.isCancel, staged != nil {
            result = Privileged.runAsRoot(Privileged.pmsetCommand(target))
        }
        SudoRule.discard(staged)

        if case .failure(let error) = result, !error.isCancel {
            alert("Cannot change the sleep setting", error.message)
        }
        finish()
    }

    @objc private func toggleSudoRule() {
        if SudoRule.isInstalled {
            let result = SudoRule.remove()
            if case .failure(let error) = result {
                if !error.isCancel { alert("Cannot remove the rule", error.message) }
            } else {
                askEveryTime = true   // Do not install it again without permission.
            }
        } else {
            askEveryTime = false
            var staged: String?
            if let tmp = SudoRule.stage() {
                staged = tmp
                let result = Privileged.runAsRoot(SudoRule.installCommand(stagedAt: tmp))
                if case .failure(let error) = result, !error.isCancel {
                    alert("Cannot install the rule", error.message)
                }
            } else {
                alert("Cannot install the rule", "The temporary file cannot be written.")
            }
            SudoRule.discard(staged)
        }
        updateUI()
    }

    private var isLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @objc private func toggleLogin() {
        do {
            if isLoginEnabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            alert("Cannot change the login setting", error.localizedDescription)
        }
        updateUI()
    }

    @objc private func wake() { finish() }

    private func finish() {
        busy = false
        readState()
        updateUI()
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
