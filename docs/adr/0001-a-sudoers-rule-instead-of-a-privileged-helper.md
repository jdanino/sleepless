# A sudoers Rule instead of a privileged helper

Changing whether the Mac may sleep needs root. Apple's sanctioned way is a
privileged helper: an `SMAppService` daemon, registered by the app and spoken
to over XPC. Sleepless instead installs a `sudoers` drop-in that permits
exactly two commands, for one user, and shells out to `pmset`.

## Considered Options

**A privileged helper.** The path Apple documents, and what a macOS developer
reading this code will expect. It means a second executable, an XPC protocol,
and install and uninstall paths — for an app that is 250 KB and does one
thing. The daemon is invisible to the user: they cannot read what it is
allowed to do, and deleting the app leaves a `launchd` job behind.

**The Rule.** About 40 lines. The user can read the file, and the first-run
window shows them the two commands it permits. They can delete it with `rm`,
or from the menu.

At the time of the first version there was no choice at all: a privileged
helper must be signed with a Developer ID, and the project had none.

## Decision

Keep the Rule, now as a deliberate choice rather than a forced one. A
permission the user can read and delete is more honest for an app this small
than a root daemon they cannot see. The narrowness is the point: the Rule can
do two things and nothing else, and that is provable by reading one file.

## Consequences

- A Guard can return the Mac to Normal without a password, including at
  logout. That is the whole reason Guards work.
- Deleting the app leaves `/etc/sudoers.d/sleepless` behind. Nothing removes
  it yet. A Homebrew cask would, and an uninstall item in the menu should.
- The reason that first forced this choice is gone: the project has held a
  Developer ID certificate since 10 September 2026. If the app ever needs to
  do more than these two commands, this decision should be reopened rather
  than the Rule widened.
- **The narrowness is what lets the app take an updater that replaces its own
  bundle.** A hostile update would gain exactly two `pmset` commands, which is
  no escalation. That stops being true the day the Rule is widened, so any
  widening must be weighed against self-replacement, not judged on its own.
