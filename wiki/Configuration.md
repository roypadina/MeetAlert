# Configuration

MeetAlert stores everything under `~/.config/meetalert/`:

- **`config.json`** — yours to edit. Written with defaults on first launch, and **re-read every
  30 seconds**, so a hand edit or a change in the Settings window applies live, no restart.
- **`state.json`** — app-owned bookkeeping (what's already alerted, what's permanently
  ignored). **Only read once, at launch** — see [below](#stat-json) if you need to hand-edit it.

## config.json fields

| Field | Type | Default | Meaning |
|---|---|---|---|
| `leadMinutes` | Int | `3` | Minutes before a meeting's start to fire the first alert. |
| `lateAlertMinutes` | Int | `10` | Still fire the first alert up to this many minutes *after* start — covers the lag between an event landing in Google/Exchange and macOS's local calendar cache picking it up. |
| `escalationSeconds` | Int | `120` | Seconds to wait for an acknowledgement before re-sending the push at urgent priority. |
| `ignoreAllDay` | Bool | `true` | Skip all-day events. |
| `ignoreKeywords` | [String] | `[]` | Case-insensitive substring match against the event title; any match skips the event. |
| `ntfyServer` | String | `"https://ntfy.sh"` | Base URL of your ntfy server. |
| `ntfyTopic` | String | *(dev placeholder)* | Your private ntfy topic. See [ntfy Setup](ntfy-Setup). |
| `calendarIds` | [String]? | `null` | `null` watches every calendar. A list of EventKit calendar identifiers restricts MeetAlert to just those — set this from the Settings **Calendars** checklist rather than typing identifiers by hand. |

The Settings window (menu bar icon → **Settings…**) covers every field above except raw file
editing convenience — it's a thin `Form` bound directly to the same config object, so GUI edits
and file edits are equivalent and interchangeable.

### Example: quieter defaults, self-hosted ntfy

```json
{
  "leadMinutes": 5,
  "lateAlertMinutes": 15,
  "escalationSeconds": 180,
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
  "alertedKeys": []
}
```

Both are sets of strings shaped `"<identifier>|<epoch>"`, where `<identifier>` is the
calendar event's EventKit identifier (falling back to its title if that's ever missing) and
`<epoch>` is the meeting's start time as Unix seconds. This is exactly why "Ignore forever"
only ignores *one occurrence* of a recurring meeting — the key is tied to that occurrence's
specific start time, not the series.

- **`alertedKeys`** — every meeting that's already fired an alert, so it's never re-fired.
  Pruned automatically: any key whose embedded epoch is more than 24 hours old is dropped the
  next time state is saved. You generally never need to touch this.
- **`ignoredKeys`** — occurrences you've told MeetAlert to skip via "Ignore forever" (menu or
  popup button). **Not** pruned by age — permanent until removed.

### Un-ignoring something

Because `state.json` is only loaded at app launch, editing it by hand requires a restart to
take effect (unlike `config.json`, which live-reloads):

1. Quit MeetAlert.
2. Open `~/.config/meetalert/state.json` and remove the key from `ignoredKeys` (you'll need the
   event's identifier and start epoch — if you don't have them handy, it's usually faster to
   just clear the whole array and accept you'll get re-alerted for everything still ahead of
   you).
3. Relaunch MeetAlert.
