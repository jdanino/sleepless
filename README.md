# Sleepless

A macOS menu-bar app. It toggles `sudo pmset -a disablesleep 0/1`.
The Mac then stays awake, also when the lid is closed.

## Install

Download **`Sleepless-1.0.dmg`** from the
[releases](https://github.com/jdanino/sleepless/releases/latest), open it, and
drag **Sleepless** into **Applications**.

The app is signed with a Developer ID and notarised by Apple, so a plain
double-click opens it. There is no right-click trick and no `xattr` command.
The ticket is stapled to the app itself, so the first start also works with no
network.

The app has no Dock icon. Look for the face in the menu bar at the top right.

**Or build it yourself:**

```bash
git clone https://github.com/jdanino/sleepless.git && cd sleepless && ./build.sh && open ~/Applications/Sleepless.app
```

That needs the Xcode command-line tools (`xcode-select --install`).

## Use

- **Left click** on the menu-bar icon: toggle the setting.
- **Right click** (or control-click): open the menu.
- Face with **wide eyes**: sleep is off, the Mac stays awake. It stares,
  because it cannot sleep.
- Face with **closed eyes**: sleep is on, the Mac may sleep.

The app reads the true state from `pmset -g` every 5 seconds and after wake.
Thus the icon is correct, also when you change the setting from the terminal.

## Password

`pmset -a disablesleep` needs root permission. The app asks for your password
one time only:

1. The **first toggle** shows the standard macOS authorisation dialog. The
   dialog shows the name **Sleepless**, because the app runs the AppleScript
   inside itself (`NSAppleScript`). It does not start the `osascript` process.
2. That one privileged step does two things together: it installs
   `/etc/sudoers.d/sleepless`, and it applies the toggle.
3. Each toggle after that runs with `sudo -n` and shows no dialog.

The sudoers rule permits only these two exact commands, and only for your user:

```
<user> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

The menu item *Toggle without a password* shows the state of the rule with a
checkmark. Remove the checkmark to delete the rule. The app then asks for the
password at each toggle, and it does not install the rule again. Put the
checkmark back to install the rule again.

If the rule is deleted from outside the app, the next toggle finds this and
asks for the password again.

## Warning

`disablesleep 1` stays active after a restart. The app does not reset it when
you quit. Set the toggle back to sleep before you put the Mac in a bag.

## Build

```bash
./build.sh              # installs in ~/Applications
./build.sh /Applications # or a different folder
```

Requirements: the Xcode command-line tools (`swiftc`), macOS 13 or later.
The app is ad-hoc signed. It is not notarised, because it is a local build.

## Files

- `src/main.swift` — the app (menu bar, state, privileges).
- `src/Icon.swift` — the face drawing, in two states. It makes the menu-bar
  template image and the Finder icon from the same code. No image files are
  necessary.
- `tools/main.swift` — a small tool. `sheet` makes a preview PNG of both
  states, `iconset` makes the PNG set for `iconutil`. In the preview sheet the
  left image of each pair is the true 18 pt icon, made big with hard pixels.
- `build.sh` — makes `build/Sleepless.app` and copies it to the target folder.

To look at the icon after a change:

```bash
./build.sh && ./build/icontool sheet build/icons.png && open build/icons.png
```

## Distribution

`release.sh` makes a signed and notarised DMG for other Macs. It needs two
things one time only:

1. **A Developer ID Application certificate.** Xcode → Settings → Accounts →
   your account → Manage Certificates → **+** → *Developer ID Application*.
   An *Apple Development* certificate is not sufficient: it works on your own
   Mac only, and notarisation refuses it.
2. **A notarytool credential:**

   ```bash
   xcrun notarytool store-credentials sleepless --apple-id <your Apple ID> --team-id 25GE53E3A4
   ```

   It asks for an app-specific password. Make one at appleid.apple.com.

Then:

```bash
./release.sh
```

The script stops one time and asks you to test the toggle. Do that test. The
hardened runtime, which notarisation demands, can stop
`do shell script … with administrator privileges`. If the toggle fails, the
app needs a privileged helper (`SMAppService` daemon plus XPC) instead of the
sudoers rule.

### Continuous integration

`.github/workflows/build.yml` builds on each push and each pull request. It:

- builds with `./build.sh -` on `macos-latest`;
- checks that the binary holds `arm64` **and** `x86_64`;
- lints `Info.plist`, confirms the icon, and verifies the signature;
- uploads `Sleepless.zip` as a build artifact.

A tag that starts with `v` also makes a GitHub release:

```bash
git tag v1.0 && git push origin v1.0
```

The app from CI has an ad-hoc signature only. Gatekeeper blocks it on another
Mac. For a real distribution use `release.sh` on a Mac that holds your
Developer ID certificate.

### Other ways

- **Build from source.** The user clones the repository and runs `./build.sh`.
  There is no Gatekeeper warning, because the Mac signs it locally. They need
  the Xcode command-line tools.
- **Homebrew cask** in your own tap. Use the notarised DMG.
- **The Mac App Store is not possible.** The sandbox forbids a write to
  `/etc/sudoers.d` and a root `pmset`.
