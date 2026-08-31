# Versioning

## Versioning — CalVer (fleet standard)

Scratch Itch Software versions every project with **calendar versioning**:
`YYYY.MINOR.PATCH`, e.g. `2026.1.0`.

- `YYYY` — the calendar year of the release line.
- `MINOR` — resets to 1 each January, increments on each feature release.
- `PATCH` — bug-fix-only release inside an existing minor.
- **No MAJOR component.** The version carries no breaking-change signal and
  no "still pre-1.0" signal. Say either one in the CHANGELOG instead.
- Betas take `-beta.N` (`2026.1.0-beta.1`), which sorts below the bare
  version, so an updater offers the release over its own prereleases.
- A product shipping on more than one platform uses **one shared version
  line** across them.
- Year boundary: the year is the year of the *line*, not of the patch. A
  January 2027 fix on the `2026.4` line ships as `2026.4.1`; the next feature
  release after that is `2027.1.0`.

The canonical write-up, with the reasoning, is `acrosskm/RELEASES.md` §1.

**This project:** the next release is `2026.1.0`, superseding `0.12.0-melt.4`. The `-melt.N` suffix carried which upstream Ice release this fork sits on; CalVer has nowhere to put that, so **record the upstream Ice version in the CHANGELOG entry and README for every release from now on** — losing that lineage silently is the one real cost of the switch here.

**Never renumber a release that has already shipped.** Installed copies
compare against the version they hold, and rewriting a published tag breaks
that. Adoption happens at the next release, not retroactively. Every fleet
updater — the Swift `UpdateChecker` copies, MoonPhase's C#
`UpdateCheck.IsNewer`, SPX Tracker's `updater.py` — compares dot components
numerically with zero-fill, so a `2026.x` version correctly supersedes the
`0.x`/`1.x` line it replaces (verified 2026-08-31, before the switch).
