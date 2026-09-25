# IceMelt Project Status

Snapshot for resuming work. Last updated 2026-09-25 (macOS 27 section); the rest 2026-08-02.

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

## macOS 27 (MenuBarAgent) — resume point, 2026-09-25

**Read this first if you are resuming the macOS 27 work.** Everything below is on
branch `macos-27-recreate-spacers`, open as **PR #49**, stacked on `macos-27-hosted-menu-bar`
(PR #46, base `melt`). Neither is merged. The build at the tip of #49 is installed in
`/Applications` on Peter's laptop. Tracking issues: #40 (user bug, fixed by #46+#49),
#47 (hiding / drag-and-drop), #48 (IceMelt Bar clicks). Each issue carries dated
comments with the measurements; the commit messages carry the reasoning per change.

### What macOS 27 changed, in one paragraph

Status items are no longer windows. Each display's bar is one window owned by
`MenuBarAgent`; items are slots in its accessibility tree (`MenuBarItemService/
HostedItemReader.swift` reads it, `MenuBarItem.getHostedMenuBarItemsByDisplay`
interprets it). The only way to hide an item is the system overflow (the `«` chevron):
whatever doesn't fit between the app menu and the trailing items overflows, leading
items first. IceMelt hides a section by sizing its divider (plus blank "spacer" status
items, since one item may be at most half a display wide) to exactly the room. Moving
or clicking an item means posting real events to the HID system at the slot's frame.

### What works on the built-in display (verified by hand and by log)

- Hiding: divider sized to the measured room within ~1 s of launch, stable across
  relaunches, app menus intact. Room is measured to the first item of the *visible*
  section as the previous cache recorded it (not to the divider), on every display,
  widest wins; each item capped at half the *narrowest* display.
- Show-on-hover / show-on-click no longer fire over items, the gaps between them, or
  the chevron.
- Layout pane rows hold still across section toggles and during a move; hidden items
  stay listed while their app runs (the agent lists only some overflowed items).
- **Layout drag-and-drop between hidden items works** (Claude→SentinelAgent, Granola,
  2026-09-25), via the expanded overflow. Rules measured: click the chevron → overflowed
  items are laid out at the leading end with real frames, *only while the pointer stays
  over the overflow*; ⌘-drag among those slots reorders, drop at target.minX+3 lands
  left of it, target.maxX-3 right of it; overflow → bar proper works; bar proper →
  overflow does nothing (a visible item is moved into the hidden section by dropping it
  just left of the divider first); the expanded overflow has room for about the area
  left of the notch and IceMelt's own divider is laid out in it too, so the dividers are
  collapsed for the duration when an item gets no slot.
- Success of a move is judged by *order* (nothing else's slot between item and target),
  not by touching frames — slots beside system items have gaps.

### Known limits and open items

- **Not tested on two displays.** The 4K was disconnected the whole time. Spacer
  placement (verdict-driven bisection of `NSStatusItem Preferred Position`,
  `ControlItem.reconcileSpacers`) has never run for real. Preferred positions map into
  an ordering of the agent's own, not geometry; the band beside an *expanded* divider is
  tens of units wide.
- **Flicker during a move**: the overflow visibly opens, and when the dividers must be
  collapsed the bar reflows twice. Inherent to the approach; reduced, not gone.
- Dragging next to a *system* item (Focus, battery) is unverified.
- IceMelt Bar / search clicks on hidden items take the same overflow route; the click
  inside the overflow and the collapse afterwards are implemented but **unverified by
  hand**. Thumbnails are app icons / SF Symbols, not live images.
- On a narrow display where the divider itself overflows, `ControlItemPair` fails
  ("Missing control item for hidden section") and the cache keeps its previous value;
  the Layout pane can sit on its spinner if that display is active at launch.
- The agent has been seen holding **two windows for one display** (same frame, layouts
  a few points apart). The reader keys items by window index and the app picks the one
  where its own divider matches AppKit's window frame. Cause unknown (appeared after a
  display disconnect?).
- Cold start: the divider must start collapsed (`hostedHidingLengths` returns `[0]`
  until measured) or the first cache reads the sections from whatever the agent packed
  off the bar.
- `Bridging.isWindowOnScreen(item.windowID)` in the IceMelt Bar / search click handlers
  is always false for hosted items (synthetic window ID), which is fine — the hosted
  path decides for itself — but reads oddly.

### Tooling that made this tractable (rebuild in a scratch dir, ~40 lines each)

`axdump` (walk `MenuBarAgent`'s AX windows → slots → child pid, print x/width/name),
`click x y` / `drag x1 y1 x2 y2` (⌘ held) / `move x y` posting `CGEvent`s to
`.cghidEventTap`, and `/usr/bin/log stream --process IceMelt --level debug` filtered to
the `MenuBarItemManager` category — `waitForHostedItemsOnBar` logs each read. Peter's
screen recordings, split with `ffmpeg -vf fps=1`, were the fastest way to see what a
drag did. Synthetic clicks on the bar trigger IceMelt's own show-on-click unless the
chevron band excludes them, and every experiment reflows the real bar: reverse each one.

### Next steps, in order

1. Retest on the 4K + laptop pair: does the multi-item fill converge, do the spacers
   land (watch `Spacer … landed … trying …` in the log), does hiding hold on both?
2. Hand-test an IceMelt Bar click on a hidden item, and a drag next to a system item.
3. Review and merge #46 then #49 into `melt`; bump to `2026.2.0`, CHANGELOG, release
   per the recipe (notarize + appcast). #40 closes with the release.
4. Then the cleanups above (spinner on the narrow display, thumbnails).

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
