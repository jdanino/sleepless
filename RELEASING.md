# Releasing Sleepless

Everything in this file is for the person who maintains the app. To *use*
Sleepless you need none of it — see [README.md](README.md).

## Build

```bash
./build.sh              # installs in ~/Applications
./build.sh /Applications # or a different folder
```

Requirements: the Xcode command-line tools (`swiftc`), macOS 13 or later.
The app is ad-hoc signed. It is not notarised, because it is a local build.

## The updater is temporary

`src/Update.swift` only *tells* the user that a newer version exists. Sparkle
is expected to replace it. When that happens the file goes entirely, together
with the menu item and the version-comparison tests — not kept as a fallback,
because two updaters on two timers telling the same news is a bug waiting for
a bad day.

Two things will land on this pipeline when it happens:

- **An appcast.** Sparkle reads an XML file, not the GitHub releases API.
  Something must publish `appcast.xml` at every release, and it must never be
  newer than the DMG it points at.
- **A third key.** Sparkle signs updates with an EdDSA key, separate from the
  Developer ID. It joins the GitHub secrets.

## Tests

```bash
./test.sh
```

It links the real source files, minus `main.swift`, which holds the top-level
code of the app. So it tests the code the app runs, not a copy. 53 checks:
**every rule in `decide`** — when a Deadline ends Stay Awake, when the Battery
Guard acts, when it warns instead, and the boundaries of each — plus the
version comparison, how a length of time is spelled, shell quoting, the exact
`pmset` commands, the sudoers rule (including a real `visudo -cqf` on it), the
battery reading, the two icon states, and one call to GitHub that is skipped,
not failed, when there is no network.

Both workflows run it. Nothing is signed or notarised before it passes.

**Break the code on purpose now and then.** A test that cannot fail is worth
nothing. Inverting the comparison in `Update.isNewer` must turn 7 checks red,
widening the sudoers rule to `NOPASSWD: ALL` must turn 1 red, changing
`.rounded(.up)` to `.rounded(.down)` in `spellDuration` must turn 2 red, and
in `decide` each of these must turn exactly 1 red: `<=` to `<` on the battery
limit, dropping the `dropDeadline` rule, and putting the battery test before
the Deadline test.

The exercise has already paid twice. It found that the sudoers assertion
looked for one exact spelling, so `ALL=(root) NOPASSWD: ALL` walked past it.
And it found that every duration case passed either way, because `max(rest, 1)`
hid the rounding — 90 seconds and 3630 seconds were added to tell them apart.

## Decisions

Three are written down in [docs/adr/](docs/adr/):

1. **[A sudoers Rule instead of a privileged helper](docs/adr/0001-a-sudoers-rule-instead-of-a-privileged-helper.md)** —
   why the app does not use the way Apple documents, and why the Rule must
   stay narrow.
2. **[Signing happens on one Mac, not in CI](docs/adr/0002-signing-happens-on-one-mac-not-in-ci.md)** —
   why no signing key lives in GitHub, and what would reopen that.
3. **[The icon is drawn in code](docs/adr/0003-the-icon-is-drawn-in-code.md)** —
   why there is no image file, that nobody chose this at the time, and that
   the Finder icon is a known placeholder.

The words this project uses are in [CONTEXT.md](CONTEXT.md).

## Files

- `src/main.swift` — the app (menu bar, state, privileges).
- `src/Icon.swift` — the face drawing, in two states. It makes the menu-bar
  template image and the Finder icon from the same code. No image files are
  necessary.
- `src/Decide.swift` — every rule about when the app changes the state by
  itself, as one pure function. It knows nothing about menus or `pmset`, so
  the tests can cover all of it.
- `tests/main.swift` — the tests. `test.sh` builds and runs them.
- `tools/main.swift` — a small tool. `sheet` makes a preview PNG of both
  states, `docs` makes the picture at the top of this file, and `iconset`
  makes the PNG set for `iconutil`. In the preview sheet the left image of
  each pair is the true 18 pt icon, made big with hard pixels.
- `build.sh` — makes `build/Sleepless.app` and copies it to the target folder.

To look at the icon after a change:

```bash
./build.sh && ./build/icontool sheet build/icons.png && open build/icons.png
```

## Signing and notarising

`release.sh` makes a signed and notarised DMG for other Macs, from your own
Mac. It needs two things one time only:

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

## Continuous integration

One workflow, `build.yml`, and it holds **no secrets**. On every push, every
pull request and every `v*` tag it runs `./test.sh`, builds the app, checks
that the binary holds `arm64` **and** `x86_64`, lints `Info.plist`, confirms
the icon, verifies the signature, and uploads a zip artifact. On a tag it also
refuses to pass when the tag and `CFBundleShortVersionString` disagree.

It cannot sign and it cannot make a release. That is deliberate — see
[ADR 0002](docs/adr/0002-signing-happens-on-one-mac-not-in-ci.md).

## Making a release

Three steps, and the third one is at your own keyboard:

1. Change `CFBundleShortVersionString` in `build.sh`, and commit it.
2. Tag and push:

   ```bash
   git tag v1.7 && git push origin v1.7
   ```

   CI now proves the tag and the version agree.
3. Sign, notarise and publish:

   ```bash
   ./release.sh
   ```

   About three minutes, most of it waiting for Apple. It builds, signs with
   the hardened runtime, notarises the app, staples the ticket to it, wraps it
   in a DMG, notarises and staples that too, and uploads the DMG to the
   release for the tag.

**The tag and the version must agree.** `release.sh` compares them straight
after the build, before anything is signed or sent to Apple, and stops with
`The tag says 1.7, but the app says 1.6.` Without that check a tag `v1.7` with
an unchanged `build.sh` would put an old build on a new release, and every
installed copy would keep believing it is up to date.

**The certificate expires on 1 February 2027.** After that `./release.sh`
fails at the signing step. Make a new Developer ID certificate in Xcode →
Settings → Accounts → Manage Certificates.

## Other ways to hand out the app

- **Build from source.** The user clones the repository and runs `./build.sh`.
  There is no Gatekeeper warning, because the Mac signs it locally. They need
  the Xcode command-line tools.
- **Homebrew cask** in your own tap. Use the notarised DMG.
- **The Mac App Store is not possible.** The sandbox forbids a write to
  `/etc/sudoers.d` and a root `pmset`.
