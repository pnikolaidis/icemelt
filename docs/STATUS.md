# IceMelt Project Status

Snapshot for resuming work. Last updated 2026-07-29.

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
- **Branches**: `melt` is the working branch (all work lands here). `main` still mirrors
  upstream's main + PLAN.md. Upstream remains available as the `upstream` remote for
  cherry-picking.
- **Local install**: the latest signed build always goes to `~/Applications/IceMelt.app`.
- **CI**: `.github/workflows/ci.yml` — SwiftLint + Release build on the `macos-26`
  runner; green as of the last push.
- **Plan of record**: `PLAN.md` (phases), `docs/VERIFY.md` (manual regression checklist).
- Phase 0 (fork hygiene) and Phase 1 (Tahoe correctness) are **complete and verified
  on-device**; the milestone releases shipped.
- **Naming (issue #3, done)**: project is `IceMelt.xcodeproj`, scheme/target `IceMelt`,
  source folder `IceMelt/`; all type names and file headers say IceMelt. Build with
  `xcodebuild -project IceMelt.xcodeproj -scheme IceMelt`.
  **Deliberately frozen at their "Ice" spellings** because they are persisted on disk and
  renaming them would silently reset users' settings: `UserDefaults` keys
  (`ShowIceIcon`, `IceIcon`, `CustomIceIconIsTemplate`, `UseIceBar`, `IceBarLocation`),
  the `Ice.ControlItem.*` status-item autosave names, `HotkeyAction`'s `"EnableIceBar"`
  raw value, and the "Ice Cube" icon name plus its `IceCube*` assets (upstream's
  artwork, kept as an icon option). Each site carries a comment saying so.
- **Untracked in the working tree** (deliberately not committed): `IceMelt app icon
  design.zip` (designer package), `dist/` (build output), `claude.md` (workflow rules —
  same file as `CLAUDE.md` on this case-insensitive filesystem).

## Outstanding — Claude (next session)

1. **Update the copyright** (issue #4) — verify `INFOPLIST_KEY_NSHumanReadableCopyright`
   and license headers read "Scratch Itch Software" with upstream attribution.
2. **Peter's minor bugs** — waiting on issues to be filed (see below); triage and fix.
3. **Replace the app icon** — `AppIcon.appiconset` still contains upstream Ice's cube
   artwork. The design package (`IceMelt app icon design.zip`, repo root, untracked)
   includes ready `IceMelt-light.iconset`/`IceMelt-dark.iconset`; convert and install.
4. **Phase 2 (PLAN.md)** — add a test target; extract and unit-test pure logic
   (matching/scoring in SourcePIDCache, rehide strategies, hotkey encoding, config
   migration); characterization tests for MenuBarItemManager decision logic; add test
   job to CI.
5. **Phase 3** — canonical menu bar order + reconciliation, status-item autosave guard,
   crash-safe moves, occlusion detection, first-class Screen-Recording-optional mode.
6. **Phase 4** — profiles (port stale `upstream/profiles`), conditional visibility
   triggers, per-display behavior, settings export, notch-hiding appearance preset,
   URL-scheme/Raycast surface.
7. **Deferred cleanups**: dead `#available(macOS <26)` branches; two-state droplet icon
   (needs filled/hollow pair from designer); decide whether icon design sources get
   committed to the repo; macOS 27 beta watch (upstream #965/#954); Homebrew cask.

## Outstanding — Peter

1. **File the minor bugs** you mentioned as GitHub issues
   (https://github.com/pnikolaidis/icemelt/issues) so they can be worked.
2. **Back up the login keychain** (contains the Sparkle EdDSA private key — losing it
   orphans the update channel).
3. Optional decisions when convenient:
   - Want the app icon swapped to the droplet artwork? (Task 3 above — say go.)
   - Ask the designer for a filled/hollow droplet pair for hidden/visible states?
   - Should the icon design sources live in the repo?

## How to resume

Open Claude Code in this repo and say "resume from docs/STATUS.md". Key context files:
`PLAN.md`, `docs/VERIFY.md`, `claude.md` (workflow rules), plus session memory
(release recipe, dev gotchas).
