# Changelog

All notable changes to MeetAlert are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.5.4] - 2026-10-05

### Fixed
- MeetAlert doing nothing at all in 1.5.2-1.5.3 (no alerts, menu showing "No upcoming meetings") when built with the macOS 27 SDK: the app started one internal store but bound the menu and Settings to another, unstarted one.
- Touching Settings on 1.5.2/1.5.3 could reset `config.json` to defaults; re-check your ntfy topic and calendar selection after upgrading.

## [1.5.3] - 2026-10-03

### Changed
- Custom About window (nothing clipped); compact Settings About tab.

## [1.5.2] - 2026-10-03

### Added
- About tab in Settings; About and Support on Ko-fi menu items; Ko-fi links in README/wiki.

## [1.5.1] - 2026-09-22

### Added
- App icon: teal calendar with a high-contrast bell badge (the app previously shipped with no icon).

## [1.5.0] - 2026-09-17

### Added
- `escalationRepeats` config field (default 3, previously hardcoded) with a stepper in Settings → Alerts. Pair a short `escalationSeconds` with a higher repeat count (e.g. 45 and 8) for a ring that keeps going and that a single ACK ends.

### Changed
- MeetAlert now owns the alert repetition itself instead of relying on the ntfy Android app's "Keep alerting for highest priority" setting, which cannot be silenced from a notification action. Leave that setting off. Escalation still hard-stops 15 minutes after the meeting's start; test mode caps at one resend.
- README explains why ntfy's insistent ring is not used; the incorrect claim that ACK/Snooze stops insistent ringing is removed.

## [1.4.0] - 2026-09-08

### Added
- Redesigned alert popup: live countdown in large monospaced digits (minutes → seconds → `now` → minutes late).
- Urgency drives the whole card: cyan more than a minute out, amber inside the last minute, coral once started; state word, icon, rim width and countdown unit change together.
- Escalation visible on the desktop: once an unacked push has gone to the phone, the card says "Not acknowledged - phone alerted", pulses its rim and replays a sound.
- A color per calendar: name and color dot on every alert, defaulting to the Calendar.app color and overridable in Settings → Calendars (`calendarColors`).
- Ranked actions: `Join <provider>` is the one filled button, then `Snooze 5m`, `Dismiss`, `Ignore`, and a `More` menu with the remaining snoozes; with no meeting link, `Dismiss` takes the filled slot.
- Keyboard shortcuts after clicking the card: ↩/J join, 5 snooze 5m, 1 snooze 1m, T until start, esc snooze; ⌘D dismiss and ⌘⇧I ignore need a modifier on purpose.
- Menu bar icon carries state (calendar, clock, badged clock, filled clock, warning triangle); text reads `in 12m · Title`; dropdown groups meetings under "Next up" with an Ignore submenu.
- Slide-in/out animation; Reduce Motion falls back to fades, Increase Contrast to an opaque background.

### Changed
- Phone push titles and bodies state the meeting's state with a matching emoji tag; escalation pushes are titled "Not acknowledged" and numbered "Alert n of 3"; tapping the body opens the meeting link; the Join action names the provider.
- `MEETALERT_TEST=1` now uses a separate test config directory, so a test run never touches your real ntfy topic or alert state.

## [1.3.1] - 2026-08-26

### Added
- Every upcoming meeting with a video-call link is a clickable Join row in the menu bar. It only opens the link and does not acknowledge the meeting.
- Link detection also recognises GoToMeeting, Jitsi, Chime, BlueJeans and RingCentral (on top of Zoom, Google Meet, Teams, Webex, Whereby).

## [1.3.0] - 2026-08-19

### Added
- Pre-ignore picker: Settings → Ignore lists the next 7 days of meetings; ignore any before it alerts ("This time only" / "Whole series"), and un-ignore from the "Currently ignored" list.
- Tabbed Settings (Alerts / Ignore / Calendars / Phone) with grouped forms and plain-language captions.
- Minute-precision morning agenda time via a native time picker (`agendaTime`; legacy `agendaHour` migrates automatically).

### Fixed
- Ignoring a recurring meeting from the popup/menu now ignores the whole series (previously next week's alert fired again).
- Morning agenda now honors ignores.

## [1.2.0] - 2026-08-19

### Changed
- Dismiss is final: Dismiss/ACK/Join on any of a meeting's alerts marks the whole occurrence done, suppressing remaining offsets and dropping pending snoozes. Snooze still brings the alert back.
- Phone ACK and Snooze 5m buttons now remove the notification from the phone.

### Removed
- The "Meeting ends" 2-minute overrun warning and its `endWarning` config field (an old key in `config.json` is ignored).

## [1.1.1] - 2026-08-12

### Fixed
- Safer screen-lock detection, login-item removal now sticks, panel/timer robustness, calendar-selection edge cases, silent phone-ack echoes.

## [1.1.0] - 2026-08-12

### Added
- Multi-offset alerts (any times before/after start), away-aware repeating escalation, one-tap Join, push actions (ACK/Join/Snooze), overrun guard, morning agenda.
- Full UTF-8 push titles via the ntfy JSON API.

### Fixed
- Calendar-picker and upgrade-safety issues found in a full review.

## [1.0.0] - 2026-08-12

First release.

### Added
- Menu-bar meeting alerts: unmissable popup, ntfy phone push with ACK, urgent escalation, snooze 1m/5m/till-start, calendar picker, keyword filters, late-alert window, login item.

[Unreleased]: https://github.com/roypadina/MeetAlert/compare/v1.5.4...HEAD
[1.5.4]: https://github.com/roypadina/MeetAlert/compare/v1.5.3...v1.5.4
[1.5.3]: https://github.com/roypadina/MeetAlert/compare/v1.5.2...v1.5.3
[1.5.2]: https://github.com/roypadina/MeetAlert/compare/v1.5.1...v1.5.2
[1.5.1]: https://github.com/roypadina/MeetAlert/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/roypadina/MeetAlert/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/roypadina/MeetAlert/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/roypadina/MeetAlert/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/roypadina/MeetAlert/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/roypadina/MeetAlert/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/roypadina/MeetAlert/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/roypadina/MeetAlert/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/roypadina/MeetAlert/releases/tag/v1.0.0
