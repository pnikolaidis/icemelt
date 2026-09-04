# IceMelt Project Status

Snapshot for resuming work. Last updated 2026-08-02.

## Where things stand

- **Shipped releases** (GitHub Releases, notarized + stapled DMGs):
  - `v0.12.0-melt.1` — first stable Tahoe release (identification rework, image-cache
    resilience, IceMelt Bar fixes)
  - `v0.12.0-melt.2` — automatic updates (Sparkle feed), IceMelt droplet menu bar icon
    (default), About-pane branding
  - `v0.12.0-melt.3` — Ice → IceMelt rename, droplet app icon, IceMelt Bar dismissal
    fix (#14), acknowledgements rebrand (#15)
- **Automatic updates are live**: feed at `https://pnikolaidis.github.io/icemelt/appcast.xml`
  (served from the `gh-pages` branch). Every future release must append a signed entry
  (see `~/.claude` memory: "IceMelt release recipe"). The EdDSA private key lives in
  Peter's login keychain — **critical secret; include it in keychain backups.**
- **Branches**: `melt` is the **default branch** and where all work lands. `main` is now
  fast-forwarded to match `melt` — it is **no longer an upstream mirror**. Upstream is
  still available as the `upstream` remote for cherry-picking.
- **Local install**: the latest signed build goes to `/Applications/IceMelt.app`
  (Peter, 2026-09-04 — reverses the earlier `~/Applications` rule; see
  `docs/INSTALL-LOCATION.md`). `~/Applications` remains a silent fallback, and
  a copy already installed there is left alone rather than moved.
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
- **Untracked in the working tree** (deliberately not committed, and now in `.gitignore`):
  `IceMelt app icon design.zip` (designer package), `dist/` (build output), `claude.md`
  (workflow rules — same file as `CLAUDE.md` on this case-insensitive filesystem).
  These were committed by mistake, untracked again, and on 2026-08-02 **purged from git
  history with BFG** (issue #19, closed) — note the repo is **public**, so this mattered.
  Residual: the old commits remain fetchable by SHA via GitHub's `refs/pull/*` and cache
  until a GitHub Support request removes them.
- **App icon**: replaced with the designer's droplet artwork (PR #11). Dark variant wired
  via an Icon Composer `AppIcon.icon` package (issue #17) — the mac appiconset format has
  no dark slots, so the asset-catalog route suggested in the issue does not work on macOS.
- **Unreleased**: `melt` is ahead of the shipped melt.3 DMG with the upstream-Ice
  acknowledgements entry (#22), the SwiftLint pin (#23), and the dark app icon (#24).
  The next release ships all three; `MARKETING_VERSION` is still `0.12.0-melt.3`.
- **Attribution (issue #4, done)**: About pane/Info.plist copyright, acknowledgements
  entry for Ice, README closing paragraph, and repo description all present IceMelt as
  Scratch Itch Software's work built on Ice by Jordan Baird. **Known gap**: the
  `scratchitchsoftware.com/icemelt` URL shipped in the About pane and README is a 404
  until Peter adds the page or a redirect (site products live under `/apps/<name>/`).
- **Promotion prep**: plan, ground rules, and pre-flight checklist live in
  [`docs/PROMOTION.md`](PROMOTION.md). Heads-up email to Jordan Baird sent 2026-08-02.
  Homebrew cask staged in `packaging/homebrew-tap/` (see `PUBLISHING.md` there); the
  GitHub Support request text is a comment on issue #19; the human verification
  checklist is `docs/verify-runs/pending-human-checklist.md`.

## Outstanding

Everything discrete is now a GitHub issue — see
https://github.com/pnikolaidis/icemelt/issues. This list is the map, not the detail.

### Open issues

None as of 2026-08-02 — #3, #4, and #14–#19 are all closed. New work goes through the
tracker.

### Verification debt

`docs/verify-runs/2026-07-29.md` records the last pass. Several items still need a real
human click and **cannot be done with synthetic input** — show on click, show on scroll,
layout drag, degraded mode (no Screen Recording), appearance rendering, multi-display.
An ordered 10-minute checklist was handed to Peter on 2026-08-02. The dark app icon
(#24) also needs a human eyeball once installed — Tahoe's liquid-glass pipeline adds a
glass rim and crops the artwork's baked corners; revert is a clean single commit if the
look is wrong.

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
  #965/#954).

## Outstanding — Peter

1. **File the minor bugs** you mentioned as GitHub issues so they can be worked.
2. **Back up the login keychain** — it holds the Sparkle EdDSA private key; losing it
   orphans the update channel.
3. **Pre-promotion items** (2026-08-02):
   - Add the IceMelt page (or a redirect) at `scratchitchsoftware.com/icemelt` — the
     shipped About pane and README link there; it currently 404s.
   - ~~Review and send the heads-up email to Jordan Baird~~ — sent 2026-08-02.
   - Create the `pnikolaidis/homebrew-tap` repo and push the staged cask.
   - Optionally file the GitHub Support request (draft provided) to drop cached
     pre-purge commits.
   - Run the 10-minute human verification checklist; report results so the verify run
     can be updated.
4. Decisions when convenient:
   - Ask the designer for a filled/hollow droplet pair for hidden/visible menu bar states?
   - Should the icon design sources live in the repo?

## How to resume

Open Claude Code in this repo and say "resume from docs/STATUS.md". Key context files:
`PLAN.md`, `docs/VERIFY.md`, `claude.md` (workflow rules), plus session memory
(release recipe, dev gotchas).
