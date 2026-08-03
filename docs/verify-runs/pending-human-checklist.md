# IceMelt — 10-minute human verification checklist

The items synthetic input can't test (from `docs/verify-runs/2026-07-29.md`).
Do them in this order — earlier items don't disturb your setup; later ones do
(and each says how to undo). Tell Claude the results and it will update the
verify run record.

## No setup changes needed

1. **Show on click** — click an *empty* spot in the menu bar (not on any icon).
   → The hidden section should toggle. Click again to restore.
2. **Show on scroll** — hover the menu bar and scroll/swipe on it.
   → Hidden items should reveal, then rehide.
3. **Item clicking in the IceMelt Bar** — open the IceMelt Bar, click an item inside it.
   → The item's menu should open and the bar should close.
4. **Search Enter-to-click** — open search, type to match an item, press Enter.
   → The matched item's menu should open.

## Changes a setting (restore after)

5. **Appearance rendering** — Settings → Menu Bar Appearance: turn on a tint, then
   shadow, then border; try the split shape. → Each renders immediately, no artifacts.
   Turn them all back off afterwards.
6. **Layout drag** — Settings → Menu Bar Layout: drag one item from visible to hidden
   (pick one you don't care about). → It moves; relaunch IceMelt; it stays. Drag it back.

## Heavier (do only if convenient)

7. **Quit/relaunch a third-party menu bar app** (e.g. Shottr): quit it, reopen it.
   → Its item returns to the same section it was in.
8. **Degraded mode** — `tccutil reset ScreenCapture com.pnikolaidis.icemelt`, relaunch
   IceMelt. → Layout pane shows app icons (not an empty pane). Then re-grant Screen
   Recording in System Settings and relaunch.
9. **Multi-display** — plug in an external display if you have one. → IceMelt Bar pill
   appears on the correct display with a matching background.
