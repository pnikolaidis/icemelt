# IceMelt Bar: showing only the clicked item on macOS 27 — status for review

Written 2026-09-30 for a second opinion. Branch `icebar-single-item` (draft PR),
on top of `melt` at v2026.3.0. Nothing here has shipped.

## The question

On macOS 26 and earlier, clicking a hidden item in the IceMelt Bar moved **only that
item** next to the visible items, clicked it, and moved it back after the rehide delay.
On macOS 27 (shipped in 2026.2.0–2026.3.0), clicking a hidden item instead opens the
system's `«` overflow, which lays **every** hidden item out at the leading end of the bar
(left of the notch on a MacBook), clicks the item there, and closes the overflow when the
item's menu closes.

Peter prefers the old behaviour. The branch brings it back for macOS 27. It works, but
the result is still noisy, and the last step (returning the item cleanly) is unreliable.
**Should we keep pursuing this, settle for a middle version, or drop it?**

## macOS 27 facts this depends on

Measured on a MacBook Pro built-in display (1800 pt wide, notch from x≈790 to x≈1010),
macOS 27.0. More detail is in `docs/STATUS.md` → "macOS 27 (MenuBarAgent)".

- Status items aren't windows any more. One `MenuBarAgent` window per display holds them
  as slots in its accessibility tree. IceMelt drives them only by posting real HID events
  (clicks, ⌘-drags) at slot frames, so the user's pointer moves. IceMelt hides it during
  these and warps it back.
- The only way to hide an item is the system overflow. IceMelt sizes its hidden divider
  (plus blank spacers on wide displays) to fill the bar, so the hidden section overflows.
- Overflow is strictly leading-first: the first item that doesn't fit, and everything to
  its left, overflow (probe, 2026-09-28).
- Items in the **collapsed** overflow have no slot. They are stacked at the chevron and
  often not listed at all. To touch one, IceMelt must **expand** the overflow (click `«`),
  which lays the items out from just after the app menu, left-aligned. It has room for
  about the area left of the notch, so with ~25 hidden items not all of them get a slot.
- ⌘-drag rules: within the expanded overflow works; overflow → bar proper works; bar
  proper → overflow does nothing. To put a visible item into the hidden section, drop it
  just left of the hidden divider on the bar proper. A drop at `target.minX + 3` lands
  left of the target, and at `target.maxX − 3` lands right of it.
- macOS never places an item left of the notch except in the expanded overflow.
- A hosted item's window ID is synthetic and **changes on every read**. Match by tag.

## What the branch does

`temporarilyShow(item:clickingWith:)` no longer diverts hosted items to the overflow
route. They take the pre-27 path: compute a return destination, `move(item:to:)` next to
the first visible item, click it, then rehide after `tempShowInterval` (30 s for Peter),
or sooner once the item's menu window closes. If any step fails, it falls back to the
overflow route (`temporarilyShowHosted`).

| Commit | Change | Why (what testing showed) |
|---|---|---|
| 77e7783 | Route hosted items through move → click → move back; fall back to the overflow route | First try: "No return destination", so it always fell back |
| 006a3ce | Return destination by tag, then the cache's section order, then "left of the hidden divider" | Window IDs change per read, and overflowed items are often unlisted |
| 01940b1 | After collapsing the dividers for room, reopen the overflow only once the chevron has settled, and only if it is closed | The move expanded the overflow, but the item got no slot. Collapsing the dividers closed the overflow, and the re-click hit a moving chevron |
| c78d818 | Collapse the overflow whenever any item is laid out in it; key the "drop left of divider first" step on where the item actually sits | The overflow stayed open after the move (the collapse only checked the moved item). The return went straight into the overflow, which the agent ignores, because the item was still *cached* as hidden |
| 5a60191 | Always show the pointer again after a failed drop; collapse the overflow at a settled chevron | The pointer vanished, and a collapse click hit a stale chevron |
| f4f9d49 | Serialize: rehide waits while an item is being shown, and showing waits for a rehide in progress | Clicking Shottr while MoonPhase was still out ran both moves at once, and they undid each other |
| 9e9e8f5 | Keep the left-of-divider drop out of the notch | That drop target (x≈985) was under the notch: it never took first time, and twice the pointer stayed hidden until Peter Cmd-Tabbed away. Suspected cause: an agent drag session left hanging |
| 95d71e5 | Return beside the divider with one drag and no overflow (order drifts) | Exact return flashes all hidden items once per item. Peter chose to try order drift instead |

## Where it stands (Peter's tests, built-in display only)

- **Showing one item: works.** All hidden items flash briefly while the overflow is open
  for the grab. The clicked item then sits alone beside the visible items with its menu
  open, and nothing lingers on the left. That flash can't be avoided: a hidden item
  can't be grabbed until the overflow lays it out.
- **Exact return (as of 9e9e8f5): works.** One flash of all hidden items per returned item.
  With two items out, there were two flashes ~45 s later. Pointer stayed visible. Peter:
  "much better, still a little annoying".
- **Return beside the divider (95d71e5): unreliable.** The divider's slot starts under the
  notch (x≈988), so "just left of it" can't be targeted. Dropping just right of the notch
  (x≈1013, inside the divider's leading part) took once in about thirteen tries. Each miss
  shows as the item sliding toward the notch and snapping back. One drop at x≈1023 worked.
  The pointer stayed visible.
- **Timing:** about 1–2 s from click to menu (vs well under 1 s on the overflow route).
  The return happens at the rehide delay.

## Options

1. **Drop the branch.** Keep 2026.3.0 (overflow route). Simplest and fastest. Shows all
   hidden items while the menu is open, but closes the overflow as soon as the menu closes.
2. **Ship the branch up to 9e9e8f5 (exact return).** Only the clicked item shows while its
   menu is open. Costs a flash on the way out and another per item on the way back, plus
   about a second of latency and a lot more moving parts (drags, divider collapse,
   serialization). Probably behind a setting.
3. **Keep working on the clean return.** Find a drop target that reliably lands left of a
   divider whose slot starts under the notch. Ideas: drop on the leftmost *visible* item's
   leading edge while the hidden section is temporarily shown; or shrink the divider so
   its slot starts right of the notch for the duration of the drop. Both are more
   synthetic input and more reflows, and need careful measurement first.

## Questions for the reviewer

- Is the single-item behaviour worth the added complexity and flashing on macOS 27, or is
  the overflow route the honest UX for this OS?
- If it's worth it, should it be opt-in (a setting), given the latency and the synthetic
  input it adds?
- Is there a cleaner way to land an item left of a divider that starts under the notch?

## Where to look

- `MenuBarItemManager.temporarilyShow(item:clickingWith:)`: the single-item path and its
  fallbacks.
- `MenuBarItemManager.moveHosted(item:to:)`: overflow expansion, divider collapse, ⌘-drag,
  success judged by order.
- `returnHostedItemToHiddenSection`, `dropXLeftOfHiddenDivider`,
  `getHostedReturnDestination`: added on this branch.
- `temporarilyShowHosted`: the shipped overflow route, and the fallback.
- `rehideTemporarilyShownItems`, `isTemporarilyShowing`,
  `isRehidingTemporarilyShownItems`: serialization.
- Debug logs: run `log stream --level debug --predicate 'process == "IceMelt"'` while
  testing. Debug lines aren't persisted otherwise.
