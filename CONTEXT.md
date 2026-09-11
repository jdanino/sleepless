# Sleepless

A macOS menu-bar app that controls whether this Mac is permitted to sleep.

## Language

### The two states

**Stay Awake**:
The state in which the Mac may not sleep, also with the lid closed.
Two words in prose, `stayAwake` in code.
_Avoid_: Awake, sleep disabled, sleep is off, zombie roams, disablesleep

**Normal**:
The state in which the Mac sleeps as macOS decides.
_Avoid_: asleep, sleeping, sleep is on, sleep enabled

"Awake" alone is not enough: a Mac in Normal is also awake right now, while
you use it. The state is not "currently not sleeping" — it is "held open so it
cannot sleep".

And the opposite of Stay Awake is never "Asleep". The Mac is not asleep while
you read the menu — it is *permitted* to sleep. Naming that state "Asleep" is
what produced five different phrases for one thing.

### Granting the app permission

**Rule**:
A standing permission on this Mac that lets Sleepless switch between Stay Awake
and Normal without asking for a password. It is granted once and can be withdrawn.
_Avoid_: sudoers rule, password-free rule, the permission, NOPASSWD

### Ending Stay Awake

**Deadline**:
A moment set in advance at which Stay Awake ends. The user asked for it, so it
owes no explanation when it happens.
_Avoid_: timer, session, countdown, expiry

**Guard**:
A condition that returns the Mac to Normal because Stay Awake has become a bad
idea. Nobody asked for it, so a Guard always says afterwards what it did and
why. Two exist: the **Battery Guard** and the **Quit Guard**.
_Avoid_: safety, failsafe, watchdog, auto-disable

A timed Stay Awake is not a third state. It is Stay Awake with a Deadline.
