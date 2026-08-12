<div align="center">

# MeetAlert

### Unmissable meeting alerts for your Mac.

Desktop popup + phone push + urgent escalation — so "I didn't see the calendar reminder"
stops being an excuse.

[![macOS](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?logo=opensourceinitiative&logoColor=white)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?logo=github)](CONTRIBUTING.md)

<br>

![MeetAlert popup: a meeting alert panel showing the event title, start time, and Snooze / Ignore / Dismiss buttons](docs/screenshots/popup.png)

</div>

---

## Table of Contents

- [Features](#features)
- [Install](#install)
- [ntfy setup](#ntfy-setup)
- [How it works](#how-it-works)
- [Configuration](#configuration)
- [Filtering / ignoring events](#filtering--ignoring-events)
- [Testing](#testing)
- [Google Calendar (and any other calendar)](#google-calendar-and-any-other-calendar)
- [Support](#support)
- [License](#license)

## Features

- **Desktop popup** that stays on screen until you act on it — no auto-dismiss, no silently missed alert.
- **Phone push via [ntfy](https://ntfy.sh)** at the same moment, with a tappable **ACK** action.
- **Urgent escalation** — if nobody acks within a configurable window, MeetAlert resends the push at urgent priority so it can punch through a phone on silent/DND.
- **Snooze** for 1 minute, 5 minutes, or **till start**.
- Reads **every calendar macOS syncs** — Google, iCloud, Exchange, CalDAV — with zero API setup. See [below](#google-calendar-and-any-other-calendar).
- Per-calendar checklist, all-day filtering, and keyword-based ignore list.
- Menu-bar countdown to your next meeting; starts at login automatically.
- Ad-hoc signed, un-notarized, no analytics, no network calls besides the ntfy push you configure.

## Install

> **Requires macOS 14+ (Sonoma).**

### Homebrew

```bash
brew tap roypadina/tap
brew install --cask meetalert
```

> MeetAlert is ad-hoc signed (not notarized). On first launch, if Gatekeeper complains,
> **right-click it in `/Applications` → Open** (then Open again), or clear quarantine once:
> ```bash
> xattr -dr com.apple.quarantine /Applications/MeetAlert.app
> ```

On first launch macOS will prompt for **Calendar** access — MeetAlert can't see your meetings
without it. It also registers itself to **start at login** automatically (no toggle for this
yet; see [Configuration](#configuration) if you want to turn it off).

### Build from source

```bash
git clone https://github.com/roypadina/MeetAlert.git
cd MeetAlert
./build.sh
open build/MeetAlert.app
```

`build.sh` runs `swift build -c release` and assembles/ad-hoc-signs `build/MeetAlert.app`.
No Xcode project — it's a plain Swift Package executable.

## ntfy setup

**This is the part that makes escalation actually reach your phone — don't skip it.**

1. Install the **ntfy** app: [App Store](https://apps.apple.com/app/ntfy/id1625396347) (iOS) or
   [Play Store](https://play.google.com/store/apps/details?id=io.heckel.ntfy) (Android).
2. Pick a **private, random topic name** — a long random string, e.g. `meetalert-9f3a1c7b2e`.
   A topic name is effectively a password: on the public `ntfy.sh` server, anyone who knows the
   name can publish to it or read it. Don't use anything guessable.
3. In the ntfy app, **subscribe** to that topic (and leave the server as `ntfy.sh`, unless
   you're [self-hosting](https://docs.ntfy.sh/install/)).
4. Put the same **topic** (and server, if not `ntfy.sh`) into MeetAlert: menu bar icon →
   **Settings…** → **ntfy** section, or edit `~/.config/meetalert/config.json` directly.
   > The app ships with a placeholder topic used during development — you must set your own
   > before relying on this for anything real.
5. In the ntfy app, make sure **urgent (priority 5)** notifications are set up to bypass
   silence/Do Not Disturb — that's the whole point of the escalation. The exact steps differ
   between Android and iOS and are more fiddly than you'd hope; see the
   [ntfy Setup wiki page](https://github.com/roypadina/MeetAlert/wiki/ntfy-Setup) for the
   per-platform walkthrough (short version: Android needs a per-channel "override Do Not
   Disturb" toggle; iOS's Focus-mode bypass is a known ntfy limitation, so also allow the ntfy
   app explicitly under Focus mode settings as a backstop).

Self-hosted ntfy servers work the same way — just set `ntfyServer` to your own instance.

## How it works

| When | What happens |
|---|---|
| `leadMinutes` before start | Desktop popup appears **and** an ntfy push is sent (priority: high) with an **ACK** button. |
| Anything up to escalation | Clicking **Dismiss**, **Snooze**, **Till start**, **Ignore forever**, or tapping **ACK** on the push all count as acknowledged — escalation is cancelled. |
| `escalationSeconds` after the first alert, if still unacked | The push is resent at **urgent** priority (`rotating_light` tag) — meant to break through a silenced phone. |
| Up to `lateAlertMinutes` after the actual start time | MeetAlert still fires the first alert even if it only *saw* the event this late — covers sync lag between Google/Exchange and macOS's local calendar cache. |

Each meeting occurrence alerts once (tracked in `state.json`); a snooze that comes back due
re-shows the popup without re-sending a push or re-arming escalation.

## Configuration

Everything lives in `~/.config/meetalert/config.json`, written with defaults on first launch,
and re-read every 30 seconds — so a hand edit (or a Settings-window change) applies without
restarting the app. Menu bar icon → **Settings…** gives you a native GUI for all of this except
raw file editing.

| Field | Default | Meaning |
|---|---|---|
| `leadMinutes` | `3` | Minutes before start to fire the first alert. |
| `lateAlertMinutes` | `10` | Still alert up to this many minutes *after* start (sync-lag cushion). |
| `escalationSeconds` | `120` | Seconds to wait for an ack before escalating to urgent priority. |
| `ignoreAllDay` | `true` | Skip all-day events entirely. |
| `ignoreKeywords` | `[]` | Case-insensitive substrings — any event title containing one is skipped. |
| `ntfyServer` | `"https://ntfy.sh"` | Base URL of your ntfy server. |
| `ntfyTopic` | *(placeholder)* | Your private ntfy topic — see [ntfy setup](#ntfy-setup). |
| `calendarIds` | `null` | `null` = every calendar. Otherwise a list of calendar identifiers — set this via the Settings checklist, not by hand. |

`state.json` in the same folder tracks which occurrences already alerted (`alertedKeys`, pruned
after 24h) and which are permanently ignored (`ignoredKeys`) — see the
[Configuration wiki page](https://github.com/roypadina/MeetAlert/wiki/Configuration) for the
exact key format if you ever need to hand-edit it (e.g. to un-ignore something).

## Filtering / ignoring events

- **All-day events** — skipped by default (`ignoreAllDay`).
- **Keywords** — add comma-separated substrings (Settings → Filters, or `ignoreKeywords`) to
  skip any event whose title matches, e.g. `focus time, lunch`.
- **Whole calendars** — untick a calendar in Settings → Calendars to stop watching it entirely.
- **One occurrence** — the menu's "Ignore *\<title\>* forever" button (or the popup's **Ignore
  forever**) ignores that specific meeting occurrence. For a *recurring* series, this only
  ignores the occurrence you clicked on — use a keyword filter to ignore the whole series.

## Testing

Set `MEETALERT_TEST=1` to run a fully headless self-test: no calendar access is requested (no
TCC prompt, no EventKit touched at all), and 10 seconds after launch it fires a synthetic
`[TEST] MeetAlert pipeline` meeting 3 minutes out, with the escalation window forced to 20
seconds. State transitions print to stdout so you can watch the whole pipeline:

```bash
MEETALERT_TEST=1 build/MeetAlert.app/Contents/MacOS/MeetAlert
# fired 1712345678
# acked 1712345678      (if you click a button in the popup, or ACK the push)
# escalated 1712345678  (if nothing acks it within 20s)
```

Run the executable inside the built `.app` directly (not `.build/release/MeetAlert`, and not
via `open`) so the bundle's `Info.plist`/`LSUIElement` context is intact and stdout stays
attached to your terminal.

## Google Calendar (and any other calendar)

MeetAlert doesn't talk to any calendar API — it reads whatever macOS's own EventKit already
has, which is every calendar synced through **System Settings → Internet Accounts**: Google,
iCloud, Exchange, CalDAV, whatever. Zero setup on MeetAlert's side.

The tradeoff is that you're at the mercy of macOS's own sync interval for that account. If
last-minute meetings are showing up late, open Calendar.app → Settings → General and set
**"Refresh calendars"** to **Every minute**. `lateAlertMinutes` exists specifically to cushion
whatever lag remains.

## Support

If MeetAlert saves you from walking into a meeting 10 minutes late, you can
[**buy me a coffee on Ko-fi ☕**](https://ko-fi.com/roypadina) — totally optional, always
appreciated. A **⭐ star** helps just as much.

## License

[MIT](LICENSE) © 2026 Roy Padina
