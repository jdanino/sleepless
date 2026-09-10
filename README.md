# Sleepless

A macOS menu-bar app. It toggles `sudo pmset -a disablesleep 0/1`.
The Mac then stays awake, also when the lid is closed.

![The two states: a face with wide eyes when sleep is off, and a face with closed eyes when sleep is on](docs/states.png)

## Install

Download the **`.dmg`** from the
[latest release](https://github.com/jdanino/sleepless/releases/latest), open
it, and drag **Sleepless** into **Applications**.

The app is signed with a Developer ID and notarised by Apple, so a plain
double-click opens it. There is no right-click trick and no `xattr` command.
The ticket is stapled to the app itself, so the first start also works with no
network.

The app has no Dock icon. Look for the face in the menu bar at the top right.

**Drag it to Applications first. Do not start it from the disk image.** macOS
runs an app that is still in a download or on a disk image from a random
read-only shadow copy (App Translocation). The toggle still works there, but
*Open at Login* records a path that is gone at the next start. A drag in the
Finder ends the translocation.

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

## Updates

The app looks for a newer version 5 seconds after it starts, and then one time
each day. It asks only `api.github.com` for the newest release of this
repository, and it sends nothing about you.

- Nothing found: the app stays silent.
- Something found: the menu says **"Version 1.3 is available…"**. Click it to
  open the release page.
- The menu item **Check for Updates…** does the same look immediately, and
  says the result in a window.

## The first password

The first click on the icon shows a window that says why macOS is about to ask
for a password: only root may change the sleep setting, and that one password
installs a rule that permits exactly two `pmset` commands and nothing else. A
checkbox there lets you refuse the rule and give your password at each toggle
instead.

The app does **not** replace itself. You download the new DMG and drag it over
the old app. That is a deliberate choice: an app that can replace its own
files is also a way to install anything, and the check that stops that misuse
is easy to get wrong.

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
  states, `docs` makes the picture at the top of this file, and `iconset`
  makes the PNG set for `iconutil`. In the preview sheet the left image of
  each pair is the true 18 pt icon, made big with hard pixels.
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

Two workflows.

**`build.yml`** runs on each push to `main` and each pull request. It builds,
checks that the binary holds `arm64` **and** `x86_64`, lints `Info.plist`,
confirms the icon, verifies the signature, and uploads a zip artifact. It does
not sign with the Developer ID and it does not touch a release.

**`release.yml`** runs on a tag that starts with `v`. It:

1. imports the Developer ID certificate into a keychain that lives only as
   long as the job;
2. writes the App Store Connect key to a temporary file;
3. runs the **same `release.sh`** as your Mac — there is no second copy of the
   signing logic that can drift;
4. proves the result the way Gatekeeper does: it puts a browser quarantine
   flag on the DMG, mounts it, copies the app out, and checks that the copy
   still carries its own stapled ticket;
5. deletes the key material from the runner;
6. attaches the DMG to the GitHub release.

So a release is two steps:

1. Change `CFBundleShortVersionString` in `build.sh`, and commit it. That
   number names the DMG and it is what the update check compares against.
2. Tag and push:

```bash
git tag v1.3 && git push origin v1.3
```

About 1 minute 40, most of it waiting for Apple.

**The tag and that number must agree.** `release.sh` compares them straight
after the build, before anything is signed or sent to Apple, and stops with
`The tag says 1.3, but the app says 1.2.` Without that check a tag `v1.3` with
an unchanged `build.sh` would put an old build on a new release, and every
installed copy would keep believing it is up to date.

**The five secrets** in the repository settings:

| Secret | What it is |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | the Developer ID identity, base64 of a `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | the password of that `.p12` |
| `APPLE_API_KEY_P8` | the App Store Connect key, base64 of the `.p8` |
| `APPLE_API_KEY_ID` | the Key ID |
| `APPLE_API_ISSUER` | the Issuer ID |

**The certificate expires on 1 February 2027.** After that date the pipeline
fails at the signing step. Make a new Developer ID certificate, export it, and
replace `MACOS_CERTIFICATE_P12` and `MACOS_CERTIFICATE_PASSWORD`.

### Other ways

- **Build from source.** The user clones the repository and runs `./build.sh`.
  There is no Gatekeeper warning, because the Mac signs it locally. They need
  the Xcode command-line tools.
- **Homebrew cask** in your own tap. Use the notarised DMG.
- **The Mac App Store is not possible.** The sandbox forbids a write to
  `/etc/sudoers.d` and a root `pmset`.
