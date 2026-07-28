# IceMelt Project Status

Snapshot for resuming work. Everything below is committed and pushed; nothing is
pending in any working tree.

## Where things stand

- **Shipped releases** (GitHub Releases, notarized + stapled DMGs):
  - `v0.12.0-melt.1` — first stable Tahoe release (identification rework, image-cache
    resilience, Ice Bar fixes)
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

## Outstanding — Claude (next session)

1. **Peter's minor bugs** — waiting on issues to be filed (see below); triage and fix.
2. **Replace the app icon** — `AppIcon.appiconset` still contains upstream Ice's artwork.
   The design package (`IceMelt app icon design.zip`, repo root, untracked) includes
   ready `IceMelt-light.iconset`/`IceMelt-dark.iconset`; convert and install.
3. **Phase 2 (PLAN.md)** — add a test target; extract and unit-test pure logic
   (matching/scoring in SourcePIDCache, rehide strategies, hotkey encoding, config
   migration); characterization tests for MenuBarItemManager decision logic; add test
   job to CI.
4. **Phase 3** — canonical menu bar order + reconciliation, status-item autosave guard,
   crash-safe moves, occlusion detection, first-class Screen-Recording-optional mode.
5. **Phase 4** — profiles (port stale `upstream/profiles`), conditional visibility
   triggers, per-display behavior, settings export, notch-hiding appearance preset,
   URL-scheme/Raycast surface.
6. **Deferred cleanups**: dead `#available(macOS <26)` branches; two-state droplet icon
   (needs filled/hollow pair from designer); decide whether icon design sources get
   committed to the repo; macOS 27 beta watch (upstream #965/#954).

## Outstanding — Peter

1. **File the minor bugs** you mentioned as GitHub issues
   (https://github.com/pnikolaidis/icemelt/issues) so they can be worked.
2. **Back up the login keychain** (contains the Sparkle EdDSA private key — losing it
   orphans the update channel).
3. Optional decisions when convenient:
   - Want the app icon swapped to the droplet artwork? (Task 2 above — say go.)
   - Ask the designer for a filled/hollow droplet pair for hidden/visible states?
   - Should the icon design sources live in the repo?

## How to resume

Open Claude Code in this repo and say "resume from docs/STATUS.md". Key context files:
`PLAN.md`, `docs/VERIFY.md`, `claude.md` (workflow rules), plus session memory
(release recipe, dev gotchas).
