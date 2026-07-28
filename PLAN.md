# IceMelt Development Plan

Fork of [jordanbaird/Ice](https://github.com/jordanbaird/Ice) (GPL-3.0), modernized for
macOS 26 (Tahoe) and beyond, incorporating techniques pioneered in
[scottaw66/mikanbar](https://github.com/scottaw66/mikanbar). Open source, GPL-3.0,
distributed outside the Mac App Store (the app cannot be sandboxed).

## Guiding decisions

1. **Base branch: `upstream/macos-26`, not `main`.** It contains 77 commits (~10.6k
   insertions) of Tahoe adaptation: the `MenuBarItemService` XPC target, the
   `EventManager` → `HIDEventManager` event-tap rework, Tahoe menu bar geometry, and a
   screen-capture fix. `main` is a year staler and broken on Tahoe. `0.12.0` is already
   merged into main; ignore it.
2. **Minimum macOS: 26 (Tahoe).** Recommendation, not yet locked. Rationale: the
   community's top pain is Tahoe support; macOS 27 is already in beta; MikanBar's
   empirical knowledge is Tahoe-specific; and dropping the 14/15 code paths removes a
   large untested compatibility matrix. Users on older macOS can keep using upstream
   Ice 0.11.12, which works fine there. (Fallback option: keep 14.0 as upstream does,
   at the cost of maintaining `#available` forks everywhere.)
3. **MikanBar is a reference, not a source of code.** It has **no license** — do not
   copy code from it. Reimplement the techniques (many of its primitives are themselves
   ports of Ice's own GPL code, e.g. the event "scromble" relay, so Ice already contains
   that machinery). Optionally: ask scottaw66 for an MIT/GPL grant, which would let us
   port modules directly.
4. **Fork identity.** Rename app to IceMelt, new bundle ID (`com.pnikolaidis.icemelt`),
   and **remove or repoint the Sparkle update feed** (`SUFeedURL` currently points at
   jordanbaird's appcast — shipping with it would auto-"update" our users back to
   upstream Ice). GPL-3.0 retained; keep upstream attribution and license headers.
5. **Updates: keep Sparkle (fleet decision, 2026-07).** Scratch Itch's closed-source
   apps standardize on a custom appcast self-updater (cmdtab's `UpdateChecker.swift`
   is the reference implementation); IceMelt, as the open-source (GPL-3.0) project,
   stays on upstream's Sparkle — now repointed to our own feed
   (`SUFeedURL` = `https://pnikolaidis.github.io/icemelt/appcast.xml`) with our own
   EdDSA key. Do not port the custom updater here.

## Phase 0 — Repo & fork hygiene

- [x] Push all branches/tags to `pnikolaidis/icemelt`.
- [x] Create `melt` working branch from `upstream/macos-26`; merge `main`'s trailing
      doc/template commits.
- [x] Rename product to IceMelt; new bundle IDs for app (`com.pnikolaidis.icemelt`) +
      `MenuBarItemService` XPC (service name constant updated in `Shared/Services/`).
      Target/scheme/folder names still say "Ice" — cosmetic, rename later if desired.
- [x] Neutralize Sparkle: `SUFeedURL`/`SUPublicEDKey` removed, automatic checks
      disabled until we host our own appcast (GitHub Releases + generated appcast later).
- [x] CI: GitHub Actions `ci.yml` — SwiftLint (container) + Release build on `macos-26`
      runner; replaces upstream's stale `lint.yml`.
- [x] Deployment target raised to 26.0. Required bridging
      `CGWindowListCreateImageFromArray` via `@_silgen_name` (obsoleted in the 26 SDK
      but still the only way to capture offscreen items). `#available` cleanup deferred.
- verify: app builds, launches, onboards permissions, basic hide/show works on Tahoe.
- **Status: COMPLETE** (merged via PR #1; Developer ID signing added after).

## Phase 1 — Make it work on Tahoe (the stable release upstream never shipped)

Community demand is unambiguous: the two top-voted issues (74 and 56 👍) are "stable
version for Tahoe?"; most top bugs are Tahoe symptoms.

- [ ] **Host-app resolution under Control Center ownership** — the branch's central
      unsolved problem (commit `ad86802`: "hopefully a temporary measure"). Rework
      `MenuBarItemService/SourcePIDCache` using the MikanBar-proven approach: walk each
      running app's `AXExtrasMenuBar` via Accessibility, resolve AX element → window ID
      via `_AXUIElementGetWindow`, and correlate with the CGS window list, instead of
      trusting window ownership (Control Center owns everything on 26).
      → fixes: items misidentified, "unable to display menu bar items" (#679, #711).
- [ ] **Fix empty Menu Bar Layout / image cache** (#744, #951, #891, #846 — ~150 👍
      combined). Two-pronged:
      1. Repair `MenuBarItemImageCache` capture on Tahoe (branch already reverted the
         deprecated-API shim that broke capture for some users).
      2. Add a **no-Screen-Recording fallback**: derive item identity/labels/icons from
         `NSRunningApplication` (MikanBar technique). Layout and search UIs degrade to
         app icons + names instead of a blank pane when capture is unavailable.
- [ ] **Fix Ice Bar on Tahoe** (#665 invisible, #786 crash).
- [ ] **Crash on menu bar click** (#947) and the unresponsive Sparkle dialog (#681,
      #937) — the latter likely disappears with the Sparkle feed rework.
- [ ] Triage upstream's macOS 27 beta reports (#965, #954) — build against Xcode 26.x
      SDK, keep 27 breakage on a watchlist; do not block the Tahoe release on it.
- verify: manual smoke suite on a Tahoe machine (hide/show, layout pane populated,
  Ice Bar, search, appearance styling) + regression checklist written down in
  `docs/VERIFY.md`.
- **Milestone: tag v0.12.0-melt.1, publish a notarized release.** This alone leapfrogs
  upstream for most users.
- **Status: COMPLETE** — v0.12.0-melt.1 shipped 2026-07-17; v0.12.0-melt.2 (automatic
  updates via Sparkle feed + droplet icon) shipped 2026-07-18. See docs/STATUS.md for
  current state and outstanding work.

## Phase 2 — De-risk the codebase (tests + decoupling)

All three studied codebases share the same flaw: zero automated coverage over fragile,
OS-dependent mechanisms.

- [ ] Extract pure logic from managers and unit-test it: section state machine, rehide
      strategies, hotkey key-combination encoding, appearance config
      migration (the branch has a `FIXME: Migration has gotten extremely messy`),
      layout-ordering math, occlusion/geometry decisions.
- [ ] Characterization tests for `MenuBarItemManager`'s decision logic (not the CGEvent
      I/O itself — that stays manually verified, as every project in this space does).
- [ ] Loosen the `AppState` god-object incrementally: pass narrow dependencies into new
      code; don't big-bang refactor working managers.
- [ ] Keep the private-API surface consolidated in `Shared/Bridging` with runtime
      guards and logging; document each symbol's known-good macOS range.
- verify: `xcodebuild test` green in CI; test target covers all new pure-logic modules.

## Phase 3 — MikanBar's best features (reimplemented)

- [ ] **Canonical menu bar order** — persist a user-blessed ordering; "Adopt current
      order" action; background reconciliation folds drift back to canonical (60s loop,
      after reveals, on display changes). Directly answers upstream's #2 feature request
      (choose where new items appear, 70 👍) and the "items randomly move sections" bug
      (#344, 40 👍): new items get auto-filed to a configured section.
- [ ] **Status-item autosave guard** — snapshot/restore other apps' `NSStatusItem
      Preferred Position` defaults around programmatic drags; heal corrupted keys at
      launch. Fixes a whole class of "my icons got scrambled" reports.
- [ ] **Crash-safe item moves** — persist pending moves to disk; recover/rollback at
      next launch.
- [ ] **Screen-recording-optional mode** (completes the Phase 1 fallback): a first-class
      setting where all UI uses app-derived icons/labels; Screen Recording becomes an
      optional enhancement for pixel-true previews rather than a hard requirement.
- [ ] Evaluate MikanBar's occlusion detection (notch + app-menu overlap via AX frames
      vs. `kCGWindowIsOnscreen`) to improve Ice's fullscreen/notch handling and the
      "hide application menus" feature.
- verify: unit tests for canonical-order math and autosave-guard classification (pure
  logic); manual smoke for moves/reconciliation.

## Phase 4 — Most-wanted community features

Ordered by upstream 👍, effort-weighted:

- [ ] **Profiles** (#26, 23 👍) — port the stale `upstream/profiles` scaffolding
      (Oct 2024, +1k lines: `MenuBarProfile`, `MenuBarProfileManager`,
      `MenuBarItemConfiguration`) onto the new architecture. Builds naturally on
      Phase 3's canonical-order engine.
- [ ] **Conditional visibility triggers** (#62, 68 👍) — show hidden section when
      conditions are met (e.g., app active, battery state). Start minimal: per-app
      triggers.
- [ ] **Per-display behavior** (#223, 68 👍 / #188 / #303) — Ice Bar or hiding only on
      the built-in/notched display.
- [ ] **Settings export/import** (#326, 27 👍) — settings are already Codable-heavy;
      add JSON export. Cheap win, do early if convenient.
- [ ] **Full-black menu bar to hide the notch** (#82, 37 👍) — appearance manager
      already draws overlay tints; add a "notch-hiding" preset.
- [ ] Investigate **Raycast/URL-scheme/CLI surface** (#501, 25 👍) — a small
      `icemelt://` handler for toggle/search actions.

## Ongoing

- macOS 27 compatibility watch (upstream #965/#954; Hidden Bar's #360 shows the
  length-inflation trick itself may need rework on 27 — if so, MikanBar-style
  reveal-on-demand becomes the hedge).
- Own release pipeline: notarized DMG via GitHub Releases and a self-hosted Sparkle
  appcast with our own EdDSA key (both live — see guiding decision 5); Homebrew cask
  still pending.
- Track upstream: cherry-pick from jordanbaird/Ice if it revives.

## Sequencing summary

Phase 1 is the product (a working Tahoe release); Phase 2 is insurance; Phases 3–4 are
differentiation. Each phase ends in a taggable, shippable state.
