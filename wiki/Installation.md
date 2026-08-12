# Installation

Requires **macOS 14 (Sonoma) or later**.

## Homebrew (recommended)

```bash
brew tap roypadina/tap
brew install --cask meetalert
```

## Build from source

```bash
git clone https://github.com/roypadina/MeetAlert.git
cd MeetAlert
./build.sh
open build/MeetAlert.app
```

`build.sh` runs `swift build -c release`, assembles `build/MeetAlert.app` (copies in
`Info.plist` and the built binary), and ad-hoc-signs it with `codesign --sign -`. There's no
Xcode project to open — it's a plain SwiftPM executable target.

If you want it in `/Applications` instead of running from the build folder:

```bash
cp -R build/MeetAlert.app /Applications/
open /Applications/MeetAlert.app
```

## Gatekeeper / "app is damaged" or "can't verify the developer"

MeetAlert is **ad-hoc signed, not notarized** — there's no paid Apple Developer ID behind it.
macOS will complain the first time you open it. Either:

- **Right-click the app → Open** (then **Open** again on the follow-up dialog), or
- Clear the quarantine flag once from Terminal:
  ```bash
  xattr -dr com.apple.quarantine /Applications/MeetAlert.app
  ```

This only affects the *first* launch of a given build. Because the ad-hoc signature is
recomputed on every `./build.sh` run, rebuilding from source can trigger this (and the calendar
permission prompt below) again — that's expected, not a bug.

## Calendar permission

On first launch, macOS prompts for **Calendar** access (`NSCalendarsFullAccessUsageDescription`
in `Info.plist`). MeetAlert can't see any events without it. If you accidentally deny it, the
menu bar will show `⚠︎ no calendar access` — re-grant it under **System Settings → Privacy &
Security → Calendars → MeetAlert**, then relaunch.

## Login item

MeetAlert registers itself to **start at login** automatically via `SMAppService` — but only
**once, ever**. The very first launch sets a flag (`didRegisterLoginItem`, stored in
`~/Library/Preferences/com.roy.meetalert.plist`) and calls `register()`; every launch after that
skips the check entirely, regardless of what the login item's actual status is.

**Removing it:** turn it off via **System Settings → General → Login Items & Extensions** — it
stays off. MeetAlert never re-checks the login item's status after that first-ever registration,
so a later launch can't silently re-add it.

**Re-enabling it:** delete the flag and relaunch:

```bash
defaults delete com.roy.meetalert didRegisterLoginItem
```

The next launch registers it again, exactly like a fresh install.
