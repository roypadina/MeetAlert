# Contributing to MeetAlert

Thanks for your interest in improving MeetAlert! Contributions of all kinds are welcome — bug
reports, feature ideas, docs, and code.

## Ground rules

- **`main` is protected.** No direct pushes. All changes land via Pull Request and are
  reviewed/merged by the maintainer ([@roypadina](https://github.com/roypadina)).
- Be respectful — see the [Code of Conduct](CODE_OF_CONDUCT.md).
- Keep changes focused. One logical change per PR.

## Getting started

```bash
git clone https://github.com/roypadina/MeetAlert.git
cd MeetAlert
./build.sh
open build/MeetAlert.app
```

Requirements: macOS 14+, a Swift 5.9+ toolchain (Swift 5 language mode).

## Architecture

Plain Swift Package executable, four files under `Sources/MeetAlert/`: `MeetAlertApp` (the
`MenuBarExtra` + `Settings` scenes), `Store` (calendar polling, alert state machine, config/state
persistence), `AlertPanel` (the floating popup), and `Ntfy` (push + ack polling). No AppDelegate,
no unit test target — see [Testing](README.md#testing) for how the `MEETALERT_TEST=1` path
substitutes for one.

## Workflow

1. **Fork** the repo and create a branch: `git checkout -b feature/my-thing`.
2. Make your change. Run `./build.sh` — it must exit 0.
3. Exercise the change with `MEETALERT_TEST=1` (see [Testing](README.md#testing)) where it
   applies.
   UI changes: run Xcode's Accessibility Inspector > Audit on the alert panel and each Settings
   tab, and one VoiceOver pass (SwiftPM has no UI-test runner for `performAccessibilityAudit()`).
4. Follow the existing code style (match surrounding code; no force-unwraps in non-test code).
5. Commit with a clear message and open a **Pull Request** against `main`.
6. CI must be green and the maintainer must approve before merge.

## Commit messages

Short imperative summary line, then a blank line and details if needed. Example:

```
Add per-calendar mute in the Settings checklist

Lets a calendar be excluded without touching keyword filters.
```

## Feature requests and bugs

- **Feature requests:** [open one](https://github.com/roypadina/MeetAlert/issues/new?template=feature_request.yml) and say what you're trying to do; that matters more than the exact feature. Search the [open requests](https://github.com/roypadina/MeetAlert/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement) first and 👍 an existing one if it's there.
- **Bugs:** use the [bug report](https://github.com/roypadina/MeetAlert/issues/new?template=bug_report.yml). Include your macOS version and, for calendar issues, which calendar provider (Google/iCloud/Exchange/CalDAV).
- **Ko-fi supporters:** add your Ko-fi name to the request and it goes to the front of my queue. It's a thank-you, not a purchase: no promise on what ships or when.
- **Bigger changes:** open an issue before the PR so we agree on the shape first. Small, focused PRs can come straight in.
- Replies are best effort, evenings and weekends. I read everything.
