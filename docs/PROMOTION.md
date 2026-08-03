# Promotion plan

Goal: reach former/frustrated Ice users — without stepping on Jordan Baird's toes.
Written 2026-08-02; state of play as of 2026-08-03.

## Ground rules

1. **Never say or imply "Ice is dead."** Upstream is dormant (last release 2024-10,
   last commit 2025-09) but not archived, and Jordan has made no statement. He may
   return; the fork's public posture is "maintained for macOS 26+ while upstream is
   quiet," nothing more.
2. **Do not promote in Ice's issue tracker.** Its ~400 open issues are the highest-value
   audience and posting "try my fork" under them is bug-report farming. Sole exception:
   a factual one-time answer if someone explicitly asks for a Tahoe-compatible fork.
3. **Jordan was told first** — heads-up email sent 2026-08-02, including a standing
   offer to upstream the Tahoe work. This is the relationship anchor; keep every public
   statement consistent with it.
4. Disclose being the developer wherever that's the norm (r/macapps enforces it).

## Pre-flight checklist

- [x] Purge licensed design package from git history (#19; BFG, 2026-08-02)
- [x] Attribution pass (#4): About pane, acknowledgements entry for Ice, README, repo description
- [x] Repo topics + homepage set; CI pinned and green (#16); dark app icon wired (#17)
- [x] Heads-up email to Jordan sent (2026-08-02)
- [ ] **Site page**: `scratchitchsoftware.com/icemelt` is linked from the shipped About
      pane, README, and repo homepage but currently **404s** (site products live under
      `/apps/<name>/`). Add the page or a redirect. Highest-priority remaining item —
      it is also the landing page for "Ice broken on Tahoe" search traffic.
- [ ] **Cut a release before promoting** — melt is ahead of the shipped melt.3 with the
      Ice acknowledgement (#22) and the dark icon (#24); first-wave downloaders should
      get both. Human-eyeball the dark icon in that build (liquid-glass rim, cropped
      corners) before shipping it.
- [ ] Homebrew tap: content staged in `packaging/homebrew-tap/` — create the
      `pnikolaidis/homebrew-tap` repo and push it (see README there)
- [ ] Optional: GitHub Support request to drop cached pre-purge commits (text is in a
      comment on issue #19)
- [ ] Human verification checklist (`docs/verify-runs/`) — run before inviting users
      who will exercise exactly those paths

## Channels, ranked

1. **r/macapps** — natural home for a macOS utility; disclose developer status.
2. **Show HN** — lead with the technical story (macOS 26 reassigns menu bar item window
   ownership wholesale to Control Center, breaking ownership-based identification; the
   fix is an AXExtrasMenuBar walk correlated with window IDs). "I forked an app" is not
   a story; the Tahoe breakage is.
3. **alternativeto.net** + awesome-macos / awesome-menubar lists — passive, permanent.
4. **MacRumors forums; Mastodon/Bluesky macOS-dev circles** — small but well targeted.
5. **Homebrew cask** (own tap) — a discovery channel in itself. Do not contest the
   upstream `jordanbaird-ice` cask name.
6. **Search** — the site page + repo README should answer "Ice menu bar Tahoe not
   working." Repo topics/homepage are already set for this.

## Notes

- The repo is a standalone repo, not a GitHub-network fork: it does not appear in Ice's
  fork list (less passive discovery, but also not "yet another fork" in a long list).
- If Jordan replies to the email, his preference shapes everything above.
