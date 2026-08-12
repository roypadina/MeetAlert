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
4. Follow the existing code style (match surrounding code; no force-unwraps in non-test code).
5. Commit with a clear message and open a **Pull Request** against `main`.
6. CI must be green and the maintainer must approve before merge.

## Commit messages

Short imperative summary line, then a blank line and details if needed. Example:

```
Add per-calendar mute in the Settings checklist

Lets a calendar be excluded without touching keyword filters.
```

## Reporting bugs / requesting features

Use the [issue templates](https://github.com/roypadina/MeetAlert/issues/new/choose).
Include your macOS version and, for calendar issues, which calendar provider (Google/iCloud/
Exchange/CalDAV).
