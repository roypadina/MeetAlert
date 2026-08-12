# Configuration

MeetAlert stores everything under `~/.config/meetalert/`:

- **`config.json`** — yours to edit. Written with defaults on first launch, and **re-read every
  30 seconds**, so a hand edit or a change in the Settings window applies live, no restart.
- **`state.json`** — app-owned bookkeeping (what's already alerted, what's permanently
  ignored). **Only read once, at launch** — see [below](#stat-json) if you need to hand-edit it.

## config.json fields

| Field | Type | Default | Meaning |
|---|---|---|---|
| `alertMinutesBefore` | [Int] | `[3, 0]` | One alert per entry. Positive = minutes before start, `0` = at start, negative = that many minutes *after* start (a late alert). Deduplicated and sorted descending on load — e.g. `[10, 3, -5]`. If several offsets of the same meeting are due in one scan (event synced in late), they collapse into a single alert (the latest due one) instead of stacking popups. |
| `lateAlertMinutes` | Int | `10` | Still fire a missed alert up to this many minutes *after* its scheduled time — covers the lag between an event landing in Google/Exchange and macOS's local calendar cache picking it up. |
| `escalationSeconds` | Int | `120` | Seconds between each escalation re-push. Escalation repeats up to 3 times, and never continues past 15 minutes after the meeting's start regardless of `escalationSeconds`. If an alert itself first fires later than that 15-minute mark, there's no escalation window left at all — just the one initial push, no re-pushes. |
| `awayIdleSeconds` | Int | `120` | Seconds of idle time (mouse/keyboard) — or an immediately-detected screen lock — before MeetAlert treats you as away from the Mac. Away changes only the *first* push: it goes out at urgent priority right away instead of high priority with a grace window. |
| `travelLeadMinutes` | Int | `30` | An extra alert offset added automatically for meetings whose `location` field is a physical address rather than a video-call link (i.e. non-empty and containing no `://`). |
| `endWarning` | Bool | `true` | Mac-only popup (no ntfy, no escalation) 2 minutes before a meeting ends, naming the next meeting if one starts within an hour. |
| `agendaHour` | Int? | `null` | Hour of day (0–23, local time, `Calendar.current`) to push a one-time daily agenda summary via ntfy. `null` disables it. |
| `ignoreAllDay` | Bool | `true` | Skip all-day events. |
| `ignoreKeywords` | [String] | `[]` | Case-insensitive substring match against the event title; any match skips the event. |
| `ntfyServer` | String | `"https://ntfy.sh"` | Base URL of your ntfy server. |
| `ntfyTopic` | String | `""` (empty) | Your private ntfy topic. **Empty means phone push is off entirely** — desktop popups still fire, nothing goes to your phone or gets escalated. See [ntfy Setup](ntfy-Setup). |
| `calendarIds` | [String]? | `null` | `null` watches every calendar. A list of EventKit calendar identifiers restricts MeetAlert to just those — set this from the Settings **Calendars** checklist rather than typing identifiers by hand. |

Declined invites (events where you're a participant marked `.declined`) are always filtered out
— there's no config field for it.

The Settings window (menu bar icon → **Settings…**) covers every field above except raw file
editing convenience — it's a thin `Form` bound directly to the same config object, so GUI edits
and file edits are equivalent and interchangeable.

### Example: quieter defaults, self-hosted ntfy

```json
{
  "alertMinutesBefore": [5],
  "lateAlertMinutes": 15,
  "escalationSeconds": 180,
  "awayIdleSeconds": 180,
  "travelLeadMinutes": 30,
  "endWarning": true,
  "agendaHour": 7,
  "ignoreAllDay": true,
  "ignoreKeywords": ["focus time", "lunch", "OOO"],
  "ntfyServer": "https://ntfy.example.com",
  "ntfyTopic": "meetalert-9f3a1c7b2e",
  "calendarIds": null
}
```

## state.json

```json
{
  "ignoredKeys": [],
  "alertedKeys": [],
  "snoozedUntil": {},
  "lastAgendaDay": ""
}
```

`ignoredKeys` entries are shaped `"<identifier>|<epoch>"`, where `<identifier>` is the calendar
event's EventKit identifier (falling back to its title if that's ever missing) and `<epoch>` is
the meeting's start time as Unix seconds. This is exactly why "Ignore forever" only ignores *one
occurrence* of a recurring meeting — the key is tied to that occurrence's specific start time,
not the series.

`alertedKeys` entries are shaped `"<identifier>|<epoch>@<offset>"` — one key per
(meeting occurrence, `alertMinutesBefore`/`travelLeadMinutes` entry) pair, since each offset
alerts independently. The overrun warning reuses the same set with a literal `@end` suffix
(`"<identifier>|<epoch>@end"`) instead of a numeric offset.

- **`alertedKeys`** — every (meeting, offset) pair — plus every meeting whose overrun warning
  already fired — that's already alerted, so none of it re-fires. Pruned automatically: any key
  whose embedded epoch is more than 24 hours old is dropped the next time state is saved. You
  generally never need to touch this.
- **`ignoredKeys`** — occurrences you've told MeetAlert to skip via "Ignore forever" (menu or
  popup button) — this ignores *all* of that occurrence's offsets. **Not** pruned by age —
  permanent until removed.
- **`snoozedUntil`** — alertKey → the date/time to re-show that alert's popup. Persisted so a
  snooze survives a restart or a crash instead of silently turning into a missed meeting. Pruned
  the same way as `alertedKeys` (entries more than 24 hours old are dropped).
- **`lastAgendaDay`** — `"yyyy-MM-dd"` of the last date the morning-agenda push was sent, so it
  fires at most once per day. Empty string means it's never sent one. Only relevant when
  `agendaHour` is set.

### Un-ignoring something

Because `state.json` is only loaded at app launch, editing it by hand requires a restart to
take effect (unlike `config.json`, which live-reloads):

1. Quit MeetAlert.
2. Open `~/.config/meetalert/state.json` and remove the key from `ignoredKeys` (you'll need the
   event's identifier and start epoch — if you don't have them handy, it's usually faster to
   just clear the whole array and accept you'll get re-alerted for everything still ahead of
   you).
3. Relaunch MeetAlert.
