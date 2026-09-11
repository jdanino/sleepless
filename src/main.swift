import Cocoa
import ServiceManagement

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let askEveryTimeKey = "AskForPasswordEveryTime"
    private let explainedKey = "HasExplainedTheFirstPassword"
    private let batteryGuardKey = "LetItSleepOnLowBattery"
    private let lowBattery = 20

    /// The choices in the "Keep it awake for" submenu, in minutes.
    static let durations: [(String, Int)] = [
        ("15 minutes", 15), ("30 minutes", 30), ("1 hour", 60),
        ("2 hours", 120), ("4 hours", 240), ("8 hours", 480),
    ]

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var timer: Timer?
    private var stayAwake = false
    private var busy = false

    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Toggle", action: #selector(toggle), keyEquivalent: "t")
    private let sudoItem = NSMenuItem(title: "Toggle without a password", action: #selector(toggleSudoRule), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(updateItemClicked), keyEquivalent: "")
    private let batteryItem = NSMenuItem(title: "", action: #selector(toggleBatteryGuard), keyEquivalent: "")
    private let timedItem = NSMenuItem(title: "Keep it awake for", action: nil, keyEquivalent: "")
    private let noteItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var pendingUpdate: Release?

    /// Set when the user says at quit that the Mac must stay awake.
    private var stayAwakeOnPurpose = false
    /// When a timed session must end. Nil means "until you say otherwise".
    private var deadline: Date?
    private var deadlineTimer: Timer?
    private var activeDuration = 0
    /// What the battery guard last did, shown in the menu.
    private var note: String?
    /// Stops a warning that repeats every poll.
    private var warnedAboutBattery = false

    private var askEveryTime: Bool {
        get { UserDefaults.standard.bool(forKey: askEveryTimeKey) }
        set { UserDefaults.standard.set(newValue, forKey: askEveryTimeKey) }
    }

    private var hasExplained: Bool {
        get { UserDefaults.standard.bool(forKey: explainedKey) }
        set { UserDefaults.standard.set(newValue, forKey: explainedKey) }
    }

    private var batteryGuard: Bool {
        get { UserDefaults.standard.bool(forKey: batteryGuardKey) }
        set { UserDefaults.standard.set(newValue, forKey: batteryGuardKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The guard is on unless the user turns it off.
        UserDefaults.standard.register(defaults: [batteryGuardKey: true])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        buildMenu()
        readState()
        updateUI()

        // Every 5 minutes. This timer is only a backstop, for the one case
        // nothing else covers: somebody changing the setting with `pmset` in a
        // terminal. Your own toggle, opening the menu and waking the Mac all
        // read the state by themselves. 288 runs a day instead of 17 000.
        //
        // The battery guard rides on the same timer. That is late by up to 5
        // minutes, and that is fine: a battery needs many minutes to fall one
        // percent, and half an hour to go from 20 to empty.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self, !self.busy else { return }
            self.readState()
            self.checkTheDeadline()
            self.guardTheBattery()
            self.updateUI()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)

        // A quiet look for a newer version: shortly after start, then once a
        // day. It says nothing unless it finds one, and then only in the menu.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.lookForUpdate(quiet: true) }
        Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            self?.lookForUpdate(quiet: true)
        }
    }

    private func buildMenu() {
        stateItem.isEnabled = false
        noteItem.isEnabled = false
        let durations = NSMenu()
        for (title, minutes) in Self.durations {
            let item = NSMenuItem(title: title, action: #selector(setDeadline(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            durations.addItem(item)
        }
        timedItem.submenu = durations

        for item in [stateItem, noteItem, NSMenuItem.separator(), toggleItem, timedItem,
                     NSMenuItem.separator(),
                     batteryItem, sudoItem, loginItem, updateItem, NSMenuItem.separator()] {
            menu.addItem(item)
        }
        let quitItem = NSMenuItem(title: "Quit Sleepless", action: #selector(quitRequested), keyEquivalent: "q")
        menu.addItem(quitItem)
        for item in [toggleItem, batteryItem, sudoItem, loginItem, updateItem, quitItem] {
            item.target = self
        }
    }

    // MARK: State

    private func readState() {
        let r = run("/usr/bin/pmset", ["-g"])
        for line in r.out.split(separator: "\n") where line.contains("SleepDisabled") {
            stayAwake = line.trimmingCharacters(in: .whitespaces).hasSuffix("1")
            return
        }
        stayAwake = false
    }

    private func updateUI() {
        // A Deadline only means something inside Stay Awake. If the state
        // changed some other way - a refused password, or pmset in a terminal
        // - the Deadline goes with it. Not while a change is in flight,
        // because then the state has not settled yet.
        if !busy, !stayAwake, deadline != nil { cancelDeadline() }

        let description = stayAwake
            ? "Your Mac will stay awake when closed"
            : "Your Mac will go to sleep when closed"
        if let button = statusItem.button {
            // The face has open eyes while the Mac stays awake.
            let icon = statusImage(stayAwake: stayAwake, size: 18)
            icon.accessibilityDescription = description
            button.image = icon
            button.appearsDisabled = busy
            button.toolTip = description
        }
        // The state line carries the character. The action line must be plain,
        // because the user acts on it.
        if let until = deadline, stayAwake {
            stateItem.title = "Stays awake for another \(spellDuration(until.timeIntervalSinceNow))"
        } else {
            stateItem.title = stayAwake ? "Stays awake when closed" : "Sleeps when closed"
        }
        timedItem.isEnabled = true
        for item in timedItem.submenu?.items ?? [] {
            item.state = (deadline != nil && item.tag == activeDuration) ? .on : .off
        }
        toggleItem.title = stayAwake ? "Let it sleep when closed" : "Keep it awake when closed"
        sudoItem.state = SudoRule.isInstalled ? .on : .off
        loginItem.state = isLoginEnabled ? .on : .off
        updateItem.title = pendingUpdate.map { "Version \($0.version) is available…" }
            ?? "Check for Updates…"
        batteryItem.title = "Let it sleep under \(lowBattery)% battery"
        batteryItem.state = batteryGuard ? .on : .off
        noteItem.title = note ?? ""
        noteItem.isHidden = note == nil
    }

    // MARK: Actions

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRightClick { showMenu() } else { toggle() }
    }

    private func showMenu() {
        readState()
        updateUI()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggle() {
        // A toggle by hand always ends a timed session. You asked for this
        // state, so nothing may take it away behind your back.
        cancelDeadline()
        // The note explains why the app last changed the state by itself.
        // Once you change it, that explanation is no longer true.
        note = nil
        apply(!stayAwake)
    }

    /// Puts the setting to `target`. Silent when the rule is in place,
    /// otherwise it asks for the password.
    private func apply(_ target: Bool) {
        guard !busy else { return }
        busy = true
        updateUI()

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
        // The very first time, say why macOS is about to ask for a password.
        // Without this a stranger clicks a face and gets a password dialog
        // with no reason given, which is where most people stop.
        if !askEveryTime, !SudoRule.isInstalled, !hasExplained {
            guard explainTheFirstPassword() else { finish(); return }
            hasExplained = true
        }

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

    /// Returns false when the user wants to stop.
    private func explainTheFirstPassword() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Sleepless needs your password one time"
        alert.informativeText = """
            Only the root user may change the sleep setting of a Mac, so macOS \
            asks for your password now.

            With that one password Sleepless installs a small rule that permits \
            exactly two commands and nothing else:

                pmset -a disablesleep 0
                pmset -a disablesleep 1

            Every toggle after this one is immediate and silent. You can remove \
            the rule again from the menu at any moment.
            """
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Do not install the rule. Ask for my password at each toggle."
        NSApp.activate(ignoringOtherApps: true)

        let answer = alert.runModal()
        if alert.suppressionButton?.state == .on { askEveryTime = true }
        return answer == .alertFirstButtonReturn
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

    // MARK: Updates

    @objc private func updateItemClicked() {
        // The menu already says a version is waiting, so go straight there.
        if let release = pendingUpdate {
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        lookForUpdate(quiet: false)
    }

    /// `quiet` means: change the menu, but do not open a window.
    private func lookForUpdate(quiet: Bool) {
        Update.check { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let release):
                self.pendingUpdate = release
                self.updateUI()
                guard !quiet else { return }
                if let release {
                    self.offer(release)
                } else {
                    self.alert("Sleepless is up to date",
                               "You have version \(Update.currentVersion).")
                }
            case .failure(let error):
                guard !quiet else { return }
                self.alert("Cannot look for a newer version", error.message)
            }
        }
    }

    private func offer(_ release: Release) {
        let a = NSAlert()
        a.messageText = "Sleepless \(release.version) is available"
        a.informativeText = "You have \(Update.currentVersion). "
            + "The release page has the DMG."
        a.addButton(withTitle: "Open the release page")
        a.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.pageURL)
        }
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

    @objc private func wake() {
        readState()
        guardTheBattery()
        finish()
    }

    // MARK: A session with an end

    @objc private func setDeadline(_ sender: NSMenuItem) {
        let minutes = sender.tag
        activeDuration = minutes
        deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        note = nil

        deadlineTimer?.invalidate()
        deadlineTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60),
                                             repeats: false) { [weak self] _ in
            self?.deadlineReached()
        }

        if stayAwake {
            updateUI()          // Already awake: only the end time is new.
        } else {
            apply(true)
        }
    }

    private func cancelDeadline() {
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        deadline = nil
        activeDuration = 0
    }

    private func deadlineReached() {
        // apply() does nothing while another change is in flight. Leave the
        // Deadline armed and let the 5-minute backstop try again, or it would
        // be cancelled without ever taking effect.
        guard !busy else { return }
        cancelDeadline()
        guard stayAwake else { updateUI(); return }
        note = "The time was up at " + clockTime(Date())
        apply(false)
    }

    // MARK: The battery guard

    @objc private func toggleBatteryGuard() {
        batteryGuard.toggle()
        if batteryGuard { warnedAboutBattery = false }
        updateUI()
    }

    /// A backstop. A Timer can be late or be lost, and the end of a session
    /// must not depend on that.
    private func checkTheDeadline() {
        guard let until = deadline, Date() >= until else { return }
        deadlineReached()
    }

    /// A Mac that stays awake in a closed bag on a flat battery gets hot and
    /// empty. When the charge falls under the limit, give sleep back.
    private func guardTheBattery() {
        guard batteryGuard, stayAwake, !busy else { return }
        guard let power = Power.read(), power.onBattery else {
            warnedAboutBattery = false   // On the charger again.
            return
        }
        guard power.percent <= lowBattery else {
            warnedAboutBattery = false
            return
        }

        // Act without a word only when the rule permits it. A password dialog
        // that appears by itself, with a closed lid, would be worse than the
        // problem.
        guard SudoRule.isInstalled else {
            if !warnedAboutBattery {
                warnedAboutBattery = true
                alert("The battery is at \(power.percent)%",
                      "Your Mac is set to stay awake, and Sleepless cannot change that "
                      + "without your password. Toggle it by hand, or switch on "
                      + "\"Toggle without a password\" in the menu.")
            }
            return
        }

        busy = true
        updateUI()
        let percent = power.percent
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Privileged.pmsetQuietly(false)
            DispatchQueue.main.async {
                self.busy = false
                if ok {
                    self.cancelDeadline()
                    self.note = "Sleep was given back at \(percent)% battery"
                }
                self.readState()
                self.updateUI()
            }
        }
    }

    // MARK: Quitting

    @objc private func quitRequested() {
        guard stayAwake else { NSApp.terminate(nil); return }

        let alert = NSAlert()
        alert.messageText = "Your Mac will stay awake. Let it sleep again?"
        alert.informativeText = "It will not sleep, also with the lid closed, and after "
            + "Sleepless quits nothing shows it any more."
        alert.addButton(withTitle: "Let it sleep and quit")
        alert.addButton(withTitle: "Keep it awake and quit")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if SudoRule.isInstalled {
                _ = Privileged.pmsetQuietly(false)
            } else {
                _ = Privileged.runAsRoot(Privileged.pmsetCommand(false))
            }
            readState()
            NSApp.terminate(nil)
        case .alertSecondButtonReturn:
            stayAwakeOnPurpose = true
            NSApp.terminate(nil)
        default:
            break   // Cancel: stay running.
        }
    }

    /// Also covers a log out and a shut down, where no window can appear. It
    /// works silently, so it needs the rule. A force quit or `kill -9` sends
    /// no such message, and then the setting stays as it is.
    func applicationWillTerminate(_ notification: Notification) {
        guard stayAwake, !stayAwakeOnPurpose, SudoRule.isInstalled else { return }
        _ = Privileged.pmsetQuietly(false)
    }

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
