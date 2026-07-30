# IceMelt Project Status

Snapshot for resuming work. Last updated 2026-07-30.

## Where things stand

- **Shipped releases** (GitHub Releases, notarized + stapled DMGs):
  - `v0.12.0-melt.1` — first stable Tahoe release (identification rework, image-cache
    resilience, IceMelt Bar fixes)
  - `v0.12.0-melt.2` — automatic updates (Sparkle feed), IceMelt droplet menu bar icon
    (default), About-pane branding
- **Automatic updates are live**: feed at `https://pnikolaidis.github.io/icemelt/appcast.xml`
  (served from the `gh-pages` branch). Every future release must append a signed entry
  (see `~/.claude` memory: "IceMelt release recipe"). The EdDSA private key lives in
  Peter's login keychain — **critical secret; include it in keychain backups.**
- **Branches**: `melt` is the **default branch** and where all work lands. `main` is now
  fast-forwarded to match `melt` — it is **no longer an upstream mirror**. Upstream is
  still available as the `upstream` remote for cherry-picking.
- **Local install**: the latest signed build always goes to `~/Applications/IceMelt.app`.
- **CI**: `.github/workflows/ci.yml` — SwiftLint + Release build on the `macos-26`
  runner; green as of the last push.
- **Plan of record**: `PLAN.md` (phases), `docs/VERIFY.md` (manual regression checklist).
- Phase 0 (fork hygiene) and Phase 1 (Tahoe correctness) are **complete and verified
  on-device**; the milestone releases shipped.
- **Naming (issue #3, done)**: project is `IceMelt.xcodeproj`, scheme/target `IceMelt`,
  source folder `IceMelt/`; all type names and file headers say IceMelt. Build with
  `xcodebuild -project IceMelt.xcodeproj -scheme IceMelt`.
  **Caveat**: the rename processed `*.swift` only, so `Acknowledgements.rtf`/`.pdf` still
  say "Ice" in the shipped bundle (issue #15).
  **Deliberately frozen at their "Ice" spellings** because they are persisted on disk and
  renaming them would silently reset users' settings: `UserDefaults` keys
  (`ShowIceIcon`, `IceIcon`, `CustomIceIconIsTemplate`, `UseIceBar`, `IceBarLocation`),
  the `Ice.ControlItem.*` status-item autosave names, `HotkeyAction`'s `"EnableIceBar"`
  raw value, and the "Ice Cube" icon name plus its `IceCube*` assets (upstream's
  artwork, kept as an icon option). Each site carries a comment saying so.
- **Untracked in the working tree** (deliberately not committed, and now in `.gitignore`):
  `IceMelt app icon design.zip` (designer package), `dist/` (build output), `claude.md`
  (workflow rules — same file as `CLAUDE.md` on this case-insensitive filesystem).
  These were committed by mistake in `d86be07` and untracked again in `c23d852`; the blobs
  are still in history (issue #19).
- **App icon**: replaced with the designer's droplet artwork (PR #11). Light variant only;
  the dark iconset is unused (issue #17).
- **Unreleased**: `melt` is several merged PRs ahead of the last shipped DMG and
  `MARKETING_VERSION` is still `0.12.0-melt.2` (issue #18).

## Outstanding

Everything discrete is now a GitHub issue — see
https://github.com/pnikolaidis/icemelt/issues. This list is the map, not the detail.

### Open issues

| # | Item |
| --- | --- |
| [#4](https://github.com/pnikolaidis/icemelt/issues/4) | Update copyright — Info.plist is already correct; the acknowledgements text is the remaining piece |
| [#15](https://github.com/pnikolaidis/icemelt/issues/15) | `Acknowledgements.rtf`/`.pdf` still say "Ice" in the shipped bundle |
| [#16](https://github.com/pnikolaidis/icemelt/issues/16) | Pin the SwiftLint CI container instead of `:latest` — already reddened CI once on a docs-only merge |
| [#17](https://github.com/pnikolaidis/icemelt/issues/17) | Wire up the dark app-icon variant |
| [#18](https://github.com/pnikolaidis/icemelt/issues/18) | Ship a release — rename, icon, and the bar-dismissal fix are all unreleased |
| [#19](https://github.com/pnikolaidis/icemelt/issues/19) | Purge the design package and DMG from git history (only needed if the repo goes public) |

### Verification debt

`docs/verify-runs/2026-07-29.md` records the last pass. Several items still need a real
human click and **cannot be done with synthetic input** — show on click, show on scroll,
layout drag, degraded mode (no Screen Recording), appearance rendering, multi-display.
Issue #18 is blocked on these.

### Roadmap (PLAN.md)

- **Phase 2** — test target; unit-test pure logic (SourcePIDCache matching, rehide
  strategies, hotkey encoding, config migration); characterization tests for
  MenuBarItemManager; add a test job to CI.
- **Phase 3** — canonical menu bar order + reconciliation, status-item autosave guard,
  crash-safe moves, occlusion detection, first-class Screen-Recording-optional mode.
- **Phase 4** — profiles (port stale `upstream/profiles`), conditional visibility
  triggers, per-display behavior, settings export, notch-hiding appearance preset,
  URL-scheme/Raycast surface.
- **Deferred cleanups**: dead `#available(macOS <26)` branches; two-state droplet menu bar
  icon (needs a filled/hollow pair from the designer); macOS 27 beta watch (upstream
  #965/#954); Homebrew cask; one hotlinked upstream image left in `FREQUENT_ISSUES.md`.

## Outstanding — Peter

1. **File the minor bugs** you mentioned as GitHub issues so they can be worked.
2. **Back up the login keychain** — it holds the Sparkle EdDSA private key; losing it
   orphans the update channel.
3. Decisions when convenient:
   - Ask the designer for a filled/hollow droplet pair for hidden/visible menu bar states?
   - Should the icon design sources live in the repo?
   - Purge git history (#19), or leave it since the repo is private?

## How to resume

Open Claude Code in this repo and say "resume from docs/STATUS.md". Key context files:
`PLAN.md`, `docs/VERIFY.md`, `claude.md` (workflow rules), plus session memory
(release recipe, dev gotchas).
