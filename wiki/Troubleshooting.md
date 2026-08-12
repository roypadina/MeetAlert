# Troubleshooting

## No alerts firing for a meeting I know exists

Work through these in order:

1. **Is the calendar it's on actually enabled?** Menu bar icon → **Settings…** → **Calendars**
   — an unticked calendar is completely invisible to MeetAlert (`calendarIds` excludes it from
   the EventKit query, not just from the UI).
2. **Is it within the alert window?** MeetAlert only fires for meetings starting within
   `leadMinutes` from now, up to `lateAlertMinutes` after they've already started. A meeting
   2 hours out won't alert yet; one that started 20 minutes ago with the default
   `lateAlertMinutes: 10` never will.
3. **Sync lag.** If the event is genuinely new (just accepted an invite, calendar just synced),
   macOS's own calendar cache might not have it yet — MeetAlert only sees what EventKit already
   has. Open **Calendar.app → Settings → General** and set **"Refresh calendars"** to **Every
   minute**. `lateAlertMinutes` exists specifically to cushion whatever lag remains after that.
4. **Keyword filter.** Check `ignoreKeywords` (Settings → Filters) — a title containing any of
   those substrings is silently skipped.
5. **Already ignored.** If you previously clicked "Ignore forever" on this exact occurrence,
   it's in `state.json`'s `ignoredKeys` — see [Configuration](Configuration#un-ignoring-something)
   to undo it.
6. **All-day.** `ignoreAllDay` defaults to `true`.

## Menu bar icon is missing

If the calendar icon isn't showing up at all, a menu-bar-management app (Bartender, Ice, the
built-in "menu bar spacer" in newer macOS, etc.) may be hiding it rather than MeetAlert failing
to launch. Check that tool's hidden-items list, or hold ⌘ and drag in the menu bar area to
reveal hidden icons. If it's not there even after that, check Activity Monitor for a running
`MeetAlert` process — if there isn't one, relaunch from `/Applications` or your build folder.

## Calendar permission prompt keeps coming back after I rebuild

Expected. `build.sh` re-signs the app ad-hoc on every run, and macOS ties the TCC (privacy)
grant to that signature — a new signature looks like a new app to Gatekeeper/TCC. This only
matters for building from source; a Homebrew install doesn't rebuild locally so it won't churn
the signature.

## Urgent escalation isn't bypassing Do Not Disturb / Focus mode

This is almost always an OS-level notification setting, not a MeetAlert problem — MeetAlert
only controls the priority header it sends; whether that priority actually breaks through
silence is entirely up to the ntfy app and the phone's own settings. See the
[ntfy Setup](ntfy-Setup#5-make-urgent-priority-actually-bypass-silence) page for the exact
Android channel setting and the (currently limited) iOS story. Short version: Android needs a
per-channel "Override Do Not Disturb" toggle set manually; iOS Focus-mode bypass isn't fully
supported by ntfy's iOS app yet, so treat the desktop popup as your real backstop there.

## "MeetAlert is damaged and can't be opened" / "can't verify the developer"

MeetAlert is ad-hoc signed, not notarized — macOS's Gatekeeper doesn't recognize the signer.
Either right-click the app → **Open** (then **Open** again on the follow-up), or clear the
quarantine flag once:

```bash
xattr -dr com.apple.quarantine /Applications/MeetAlert.app
```

If you built from source yourself, this can recur on every rebuild since the ad-hoc signature
changes each time `./build.sh` runs.
