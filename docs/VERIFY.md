# IceMelt Manual Verification Checklist

Run on a macOS 26+ machine before tagging a release. Automated tests don't cover the
menu bar mechanics (they depend on live OS behavior), so this checklist is the
regression gate. Check items off in the PR or release notes.

## Setup
- [ ] Build Release (`xcodebuild -scheme IceMelt -configuration Release`), launch `IceMelt.app`.
- [ ] Both `IceMelt` and `MenuBarItemService` processes running (`pgrep -lx IceMelt MenuBarItemService`).
- [ ] No errors in logs: `/usr/bin/log show --last 5m --predicate 'subsystem == "com.pnikolaidis.icemelt"' | grep -iE "error|fail"`.

## Identification
- [ ] Settings → Menu Bar Layout shows every third-party item with its real icon.
- [ ] Hover tooltips show real app names — **no "(UUID)" suffixes**.
- [ ] Quit and relaunch a third-party menu bar app: its item keeps its section.

## Hide/show mechanics
- [ ] Click the IceMelt icon: hidden section collapses/expands.
- [ ] Option-click: always-hidden section reveals (if enabled).
- [ ] Show on hover, show on scroll work when enabled.
- [ ] Auto-rehide (timed and smart) re-hides.

## Layout pane
- [ ] Items render with pixel-accurate captures (Screen Recording granted).
- [ ] Drag an item between sections; order persists after the move.
- [ ] Degraded mode: revoke Screen Recording (`tccutil reset ScreenCapture
      com.pnikolaidis.icemelt`), relaunch — layout pane shows **app icons**, not
      "Unable to display menu bar items". Re-grant afterward.

## IceMelt Bar
- [ ] Enable the IceMelt Bar; click the IceMelt icon: pill appears below the menu bar with items.
- [ ] Items are clickable (left and right click forward correctly).
- [ ] All three locations work: Dynamic, Mouse pointer, IceMelt icon — no crash.
- [ ] On an external display: pill background matches that display's menu bar color.

## Search
- [ ] Search hotkey opens the panel; fuzzy search finds items; Enter clicks the item.

## Appearance
- [ ] Tint (solid + gradient), shadow, border render; split shape works.
- [ ] Settings → General renders correctly; no blank panes.

## Multi-display / spaces (if hardware available)
- [ ] Hide/show works on a second display's menu bar.
- [ ] Fullscreen app: IceMelt idles gracefully, resumes on exit.
- [ ] Display hot-plug: no crash, layout recovers.

## Known-broken (do not block release)
- Moving Control Center's own items (Sound, Focus) can fail with "Move events
  failed" — macOS 26 restricts synthetic drags on CC-internal items.
- Items owned by apps with no AX presence (some agents publish only as titleless
  Control Center children) may be unidentifiable — they render but can't be named.
