# MeetAlert demo — storyboard (11.9 s, loops)

Real code: `AlertContent` + `Theme` from `Sources/MeetAlert/AlertPanel.swift` / `Theme.swift`, compiled unchanged (`stubs.swift` stands in
for `Store.Meeting` and `Ntfy.provider`). Status-item text/symbol follow `Store.menuBarTextFor/symbolFor`; menu rows copy `MenuContent`
in `MeetAlertApp.swift`. Fake data: "Design review" 9:46–10:15 AM (Zoom), Customer sync, Team lunch, Roadmap planning; calendar "Work".

| # | Scene | Start | Dur | What happens | Caption |
|---|-------|-------|-----|--------------|---------|
| 1 | menu bar | 0.0 | 2.4 | Menu bar only, clock 9:41. Status item: clock glyph + "in 5m · Design review". | Your next meeting sits in the menu bar |
| 2 | menu | 2.4 | 4.2 | Cursor glides to the status item, click: item highlights, menu opens at once (Next Up: 4 meetings, Ignore, Settings…, About, Quit). Hover highlights the enabled rows under the cursor (the in-person "Team lunch" row is disabled gray, as in a real menu). Click on the desktop: menu closes at once, cursor fades. | Open the menu for today's meetings |
| 3 | alert | 6.6 | 3.0 | Clock 9:43, status item "in 3m", glyph turns to the alert badge. Panel slides in from the top (real 0.28 s ease-out, 14 pt) and stays: "Starting in 3 min", Join Zoom / Snooze 5 Min / Dismiss / Ignore Series / More. | A panel stays on screen until you act |
| 4 | join | 9.6 | 2.3 | Cursor glides to Join Zoom, click pulse, panel fades out (real 0.15 s), cursor fades. | Join opens the call and ends the alert |

Transitions: 0.2 s crossfade between scenes; captions fade old 0–0.12 s / new 0.12–0.35 s (never two pills at once); the last 0.2 s
dissolves into scene 1's first frame (clean loop).
Cursor: system arrow (`NSCursor.arrow`), eased 0.5–0.75 s glides on a slight arc, click = dip + white ripple; visible only while it points at something.
Render: `./render.sh` (swiftc + 30 fps frames + encode). Panel countdown reads "3 min" because `DemoClock.now` is pinned to 9:43:02.
