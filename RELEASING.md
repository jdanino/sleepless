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

## Signing and notarising

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

## Continuous integration

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

## Other ways to hand out the app

- **Build from source.** The user clones the repository and runs `./build.sh`.
  There is no Gatekeeper warning, because the Mac signs it locally. They need
  the Xcode command-line tools.
- **Homebrew cask** in your own tap. Use the notarised DMG.
- **The Mac App Store is not possible.** The sandbox forbids a write to
  `/etc/sudoers.d` and a root `pmset`.
