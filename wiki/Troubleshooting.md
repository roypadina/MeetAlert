# Troubleshooting

## No alerts firing for a meeting I know exists

Work through these in order:

1. **Is the calendar it's on actually enabled?** Menu bar icon → **Settings…** → **Calendars**
   — an unticked calendar is completely invisible to MeetAlert (`calendarIds` excludes it from
   the EventKit query, not just from the UI). If you've unticked **every** calendar, that's
   respected as deliberate — the menu bar says "no calendars selected" and nothing fires, on
   purpose. That's different from a *stale* selection (e.g. after re-adding an account, whose
   calendar identifiers changed): MeetAlert detects when a saved selection matches zero real
   calendars and falls back to watching everything with a ⚠︎ warning, rather than going quietly
   dead — if you're seeing that warning, re-open Settings → Calendars and re-tick what you want.
2. **Is it within an alert window?** Each entry in `alertMinutesBefore` (plus a `travelLeadMinutes`
   window if the meeting has a physical location) opens its own window, from that offset until
   `lateAlertMinutes` after it. A meeting 2 hours out won't alert yet; with the default
   `alertMinutesBefore: [3, 0]` and `lateAlertMinutes: 10`, one that started more than 10 minutes
   ago never will.
3. **Sync lag.** If the event is genuinely new (just accepted an invite, calendar just synced),
   macOS's own calendar cache might not have it yet — MeetAlert only sees what EventKit already
   has. Open **Calendar.app → Settings → General** and set **"Refresh calendars"** to **Every
   minute**. `lateAlertMinutes` exists specifically to cushion whatever lag remains after that.
4. **Keyword filter.** Check `ignoreKeywords` (Settings → Filters) — a title containing any of
   those substrings is silently skipped.
5. **Already ignored.** Check Settings → **Ignore** — the "Currently ignored" list shows every
   ignored occurrence and series with a one-click remove. (Under the hood: `state.json`'s
   `ignoredKeys`/`ignoredSeriesIds`.)
6. **All-day.** `ignoreAllDay` defaults to `true`.
7. **Declined.** If you (the current user) declined the invite, it's always skipped — there's
   no setting to change this.

## The first push came in at urgent priority instead of high

Expected, not a bug: MeetAlert treats you as "away" — idle past `awayIdleSeconds` (default 120s),
or your screen is locked — and skips the normal high-priority grace window for the *first* push
when that's the case. If this fires too eagerly, raise `awayIdleSeconds` in Settings.

## Escalation stopped after `escalationRepeats` pushes / stopped once the meeting was 15 minutes old / never escalated at all

Also expected. Escalation repeats at most `escalationRepeats` times (3 by default), and never continues past 15 minutes after the
meeting's start time, regardless of `escalationSeconds`. Both bounds are fixed, not configurable.
If an alert itself first fired *later* than that 15-minute mark (e.g. a very late offset, or a
missed alert caught up via `lateAlertMinutes`), there's no escalation window left at all by the
time it fires — you'll get exactly one push and no re-pushes, which is correct, not a bug.

## I acked/snoozed from my phone but it escalated the full count anyway (self-hosted ntfy)

Check your server's `cache-duration` setting. MeetAlert detects an ACK/snooze by polling the
topic's message history — if your self-hosted server has caching disabled
(`cache-duration: 0`), there's no history for it to poll, so your reply is invisible to MeetAlert
even though ntfy delivered it to your phone fine. Turn message caching back on (it's the default);
see [ntfy Setup](ntfy-Setup#self-hosting). Public `ntfy.sh` isn't affected — it caches by default.

## The morning agenda push never shows up

- Check `agendaTime` (Settings → Phone → "Send morning agenda") — it defaults **off** (`null`).
- It's skipped entirely under `MEETALERT_TEST=1`.
- The agenda push only fires once its hour has passed for the day (`Calendar.current`'s local
  hour) and only once per calendar day — check `state.json`'s `lastAgendaDay`; if it already
  matches today, it already fired (or there were no meetings left to summarize) and won't again
  until tomorrow.

## A later alert never fired for a meeting I dismissed earlier

Expected. Dismissing/ACKing (or Joining from) any of a meeting's alerts marks that whole
occurrence done — every remaining offset is suppressed and pending snoozes are dropped
(`alertedKeys` gets a `...@dismissed` key). Use **Snooze** instead of Dismiss if you want the
alert back later.

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

## I tapped ACK on my phone and it keeps ringing anyway (Android)

You have the ntfy app's **Settings → Notifications → "Keep alerting for highest priority"** turned
on. Turn it off — it has to be the *global* toggle, because a per-topic "Alert only once" does not
override the global setting.

ACK is working: it reached MeetAlert, escalation stopped, and the notification was cleared and
marked read. What didn't stop is ntfy's insistent alarm, which is a single looping `MediaPlayer`
that only the notification's delete intent (a swipe) or opening the topic screen ever stops. An
action button with `clear: true` cancels the notification programmatically, which never fires that
delete intent — so the ring outlives the notification. Filed upstream as
[ntfy-android#189](https://github.com/binwiederhier/ntfy-android/issues/189); see
[ntfy Setup](ntfy-Setup#leave-keep-alerting-for-highest-priority-off) for the full explanation.

Until you turn it off, the only way out is **tap ACK, then swipe the notification away** (or open
the topic). Swiping alone doesn't ack — ntfy has no dismiss callback, so MeetAlert never hears it
and the next re-push restarts the ring.

Once it's off, get the persistence back from MeetAlert instead: set `escalationSeconds` to `45`
and `escalationRepeats` to `8` (about six minutes of pings, each one silenceable, all of them
ended by a single ACK).

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
