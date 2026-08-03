# Publishing this tap

This directory is the staged content for the (not yet created) `pnikolaidis/homebrew-tap`
repository. It lives here because the tap repo could not be created without a human
(2026-08-02); once published, that repo is the source of truth and this copy can be
deleted.

To publish:

```sh
cd "$(mktemp -d)"
cp -R /Users/peter/projects/icemelt/packaging/homebrew-tap/. .
rm PUBLISHING.md
git init -b main && git add -A && git commit -m "Add icemelt cask"
gh repo create pnikolaidis/homebrew-tap --public \
  --description "Homebrew tap for Scratch Itch Software apps" \
  --source . --push
```

Then verify: `brew install --cask pnikolaidis/tap/icemelt` (installs to /Applications).

Notes:
- The cask was `brew style`-validated 2026-08-02. One deliberate deviation: it keeps
  `depends_on macos: ">= :tahoe"` (the style cop's autocorrect to `:tahoe` would block
  macOS 27 users later).
- sha256 verified against the actual v0.12.0-melt.3 release DMG.
- On each release, bump `version` and `sha256` in the cask (the DMG sha256 is printed
  by the release recipe).
