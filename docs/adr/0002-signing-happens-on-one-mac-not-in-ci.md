# Signing happens on one Mac, not in CI

A release is signed with a Developer ID certificate and notarised with an App
Store Connect key. Both are on the maintainer's Mac and nowhere else. CI runs
the tests and proves the build; it holds no secrets and cannot sign.

## Considered Options

**Signing in CI.** This was built, worked, and shipped v1.1 to v1.6. The
certificate went in as a base64 `.p12` and the notarisation key as a base64
`.p8`, and a release was `git tag && git push`. It is the normal shape for a
macOS project, and the convenience is real.

**Signing on one Mac.** A release is `./release.sh` at the keyboard, about
three minutes, most of it waiting for Apple.

## Decision

Signing moved back to the Mac, and the five secrets were deleted from GitHub.

The reason is asymmetry, not fear. After the first burst, an app this small
gets released a few times a year, so CI signing saves perhaps three minutes,
a few times a year. The keys, however, sit in GitHub every day, released or
not. That is a permanent exposure bought with an occasional convenience.

The blast radius was never wide — one collaborator, only official GitHub
actions, and no secrets for pull requests from forks — so it reduced to a
single point: the GitHub account. But a key that can sign *and* notarise is
enough to ship trusted malware under the maintainer's name, and that outcome
is bad enough that a small standing probability is not worth three minutes.

It also cost nothing to reverse. `release.sh` already did the whole job;
CI only called it. The script now uploads the DMG itself.

## Consequences

- A release cannot be made from another machine, or without the certificate.
  That is the price.
- CI keeps what CI is good at: the tests and the build, on every push, with no
  secrets at all. It also still refuses a tag whose version disagrees with the
  bundle.
- The keys lived in GitHub for a few hours across five runs, encrypted at rest
  and decrypted only inside the project's own jobs, with no third-party action
  present. Deleting the secrets was judged enough; the certificate and the API
  key were not reissued.
- **Reopen this if either changes:** a second person gets push access, or any
  third-party action enters a workflow. Both break the reasoning above.
- Sparkle will bring an EdDSA signing key. It is the same question again, and
  the same answer should apply unless something here has changed.
