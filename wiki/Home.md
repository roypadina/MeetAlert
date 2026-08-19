# MeetAlert Wiki

MeetAlert is a macOS menu-bar app that makes meeting reminders hard to miss: a desktop popup
that won't auto-dismiss, a phone push via [ntfy](https://ntfy.sh), and an urgent re-push if
nobody acknowledges in time. Start with the [README](https://github.com/roypadina/MeetAlert#readme)
for the pitch and quick install; this wiki goes deeper on setup and day-to-day config.

## Pages

- **[Installation](Installation)** — Homebrew and build-from-source, Gatekeeper/quarantine,
  calendar permission, the login item.
- **[ntfy Setup](ntfy-Setup)** — picking a topic, subscribing on your phone, and the Android/iOS
  specifics for getting urgent-priority pushes to actually bypass Do Not Disturb / Focus mode.
- **[Configuration](Configuration)** — every `config.json` field with examples, plus
  `state.json`'s `ignoredKeys`/`alertedKeys` semantics and how to un-ignore something by hand.
- **[Troubleshooting](Troubleshooting)** — no alerts firing, sync lag, missing menu-bar icon,
  re-prompted calendar permission after a rebuild, escalation not bypassing DND, "app is
  damaged" on launch.

## Quick facts

- Five Swift files, one Swift Package executable, no Xcode project. `./build.sh` builds and
  ad-hoc-signs `build/MeetAlert.app`.
- All state lives under `~/.config/meetalert/` — `config.json` (yours to edit) and `state.json`
  (app-owned, tracks what's already alerted, ignored, and the last morning-agenda date).
- `MEETALERT_TEST=1` runs a fully headless self-test — no calendar access requested, no TCC
  prompt, always "present" (never away), single-urgent escalation, no agenda push —
  useful for verifying the ntfy/escalation pipeline without waiting for a real meeting.
- Multiple alerts per meeting, away-aware and repeating escalation, one-tap Join, and an
  optional morning agenda push are all covered on the
  [Configuration](Configuration) page.
