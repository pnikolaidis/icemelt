# Install location — `/Applications`

macOS apps install to **`/Applications`** (Peter, 2026-09-04). This reverses an
earlier `~/Applications` rule; amend that wording wherever it survives rather
than stacking a second rule on top of it.

`~/Applications` survives **only** as an automatic fallback for when
`/Applications` is not writable — a standard (non-admin) account, or a
managed/MDM Mac. Fall back silently: never prompt for an admin password, never
escalate.

## Why the reversal costs nothing

The old rule was chosen because `~/Applications` needs no admin rights, cannot
collide with another account's copy, and lets a standard user install without a
password prompt. Every one of those reasons is preserved by keeping it as the
fallback — they only ever applied to non-admin accounts in the first place.

`/Applications` is `drwxrwxr-x root:admin`. An admin-group user — the owner of
any personal Mac — writes to it with **no authentication prompt at all**. The
password prompt the old rule avoided only ever appears for genuinely standard
accounts, which is exactly the case the fallback covers.

## This repo already shipped it

`brew install --cask pnikolaidis/tap/icemelt` installs to `/Applications`, as
every cask does (`packaging/homebrew-tap/PUBLISHING.md`). The Homebrew tap is
IceMelt's distribution channel, so the shipped install location has been
`/Applications` all along — only the local dev-build convention said otherwise.
This file closes that gap rather than opening a new one.

## Never relocate an app that is already installed

A bundle already running from `~/Applications` stays there. Moving it risks
dropping its Accessibility grant and breaking Login Item registration, and that
TCC behaviour has not been tested — which is the reason not to move anything,
not a detail to work around. **New installs only.**

A self-updater swaps the bundle in place with an unprivileged move. That
succeeds in `/Applications` for an admin user and fails with `EPERM` for a
standard one: surface the failure and roll back rather than leaving a
half-swapped bundle.

## Reference implementation

cmdtab's `Sources/cmdtab/Translocation.swift` holds the fleet-standard
candidate-list ordering.

Tracking issue: [icemelt#30](https://github.com/pnikolaidis/icemelt/issues/30).

> **`gh` in this working copy targets upstream.** This repo has an `upstream`
> remote pointing at `jordanbaird/Ice`, and a bare `gh issue`/`gh pr` command
> resolves there, not to `pnikolaidis/icemelt`. Always pass
> `-R pnikolaidis/icemelt` — filing a fleet issue on the public upstream
> project is a one-keystroke mistake.
