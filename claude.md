# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## 5. Project Workflow Rules

**After every successful build:**
- Commit and push the changes that produced it.
- Sign with Developer ID "Paradigm Consulting Company (VZGXGAK29Q)" and notarize with
  Apple ID petern@paradigmcc.com (see the release recipe in memory:
  build with `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp"`,
  re-sign Sparkle helpers + XPC + app, notarize a zip of the app, staple).
- Copy the built `IceMelt.app` to `~/Applications/` (replacing the previous copy) so the
  user always knows where to find the latest testable binary, and launch it from there.

**When the user is expected to test:**
- The user should always be testing a build that matches what's committed and pushed.

**When changes could introduce a new bug or a regression:**
- Do not commit directly to the working branch (`melt`) or `main`.
- Create a new branch and open a PR instead, so changes can be reviewed and reverted cleanly.
- When in doubt, branch.

--- 
Software projects should be copyright Scratch Itch Software, with a link to scratchitchsoftware.com/<projectname> 

Software for Apple operating systems should be signed and notarized with the Apple Developer ID petern@paradigmcc.com

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.


