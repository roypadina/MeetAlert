# ntfy Setup

MeetAlert's phone push and escalation both go through [ntfy](https://ntfy.sh) — a free
pub/sub push service, self-hostable if you want your own. This page walks through setup and,
importantly, why the **urgent-priority escalation push doesn't always bypass silence** without
extra configuration.

## 1. Install the app

- iOS: [ntfy on the App Store](https://apps.apple.com/app/ntfy/id1625396347)
- Android: [ntfy on Google Play](https://play.google.com/store/apps/details?id=io.heckel.ntfy)
  (or via F-Droid)

## 2. Pick a topic

A topic is just a string — there's no account, no registration. On the public `ntfy.sh`
server, **the topic name is the only access control**: anyone who knows it can publish to it
or subscribe to it. Treat it like a password:

- Long and random: `meetalert-9f3a1c7b2e`, not `roy-meetings`.
- Don't reuse a topic you've posted anywhere public.
- If you want real access control (private topics, auth), [self-host ntfy](https://docs.ntfy.sh/install/)
  and set `ntfyServer` to your instance.

## 3. Subscribe on your phone

Open the ntfy app → **+** → paste your topic name → **Subscribe**. Leave the server as
`ntfy.sh` unless self-hosting.

## 4. Point MeetAlert at it

Menu bar icon → **Settings…** → **ntfy** section: fill in `Server` and `Topic` to match. Or
edit `~/.config/meetalert/config.json` directly — it's re-read every 30 seconds, no restart
needed. The app ships with a placeholder topic used during development; you need to set your
own before this does anything useful for you.

## 5. Make urgent priority actually bypass silence

This is the fiddly part, and it's a real limitation of ntfy's mobile clients, not something
MeetAlert can fix on its own.

**What MeetAlert sends:** the first alert at `X-Priority: high`; if nobody acks within
`escalationSeconds`, a second push at `X-Priority: urgent` (priority 5, tag `rotating_light`).
The intent is that the urgent one is loud enough, and persistent enough, to wake you up even on
a silenced phone — but whether it actually does depends on OS-level notification settings the
ntfy app can't fully control for you.

### Android

Android notification channels (not the ntfy app itself) decide whether a notification can
break through Do Not Disturb. ntfy creates a separate channel per priority level:

1. Long-press a notification from ntfy (or **Settings → Apps → ntfy → Notifications**).
2. Find the channel corresponding to **max/urgent priority**.
3. Enable **"Override Do Not Disturb"** (wording varies by Android version/OEM — sometimes
   under an "Importance" or "Interruptions" sub-menu).

Without this, a max-priority ntfy push behaves like any other notification under DND — silent.

### iOS

iOS's Focus modes only let notifications through if they're marked **Time-Sensitive** or
**Critical** — and Critical Alerts require a special Apple entitlement that ntfy's iOS app does
not currently have (this is an open, tracked limitation upstream, not a MeetAlert bug). In
practice, don't assume an urgent-priority push will wake an iPhone that's in a Focus mode or has
Do Not Disturb on.

Workarounds:
- **Settings → Focus → [your active mode] → Apps** → add **ntfy** to the always-allowed list.
- Turn off Focus/DND during hours you actually have meetings, if that's simpler.
- Treat the desktop popup — which never auto-dismisses — as your real backstop, and the phone
  push as a bonus, not the primary line of defense, until ntfy's iOS app ships full Critical
  Alert support.

## Self-hosting

Any ntfy-compatible server works — set `ntfyServer` to its base URL (e.g.
`https://ntfy.example.com`). See [docs.ntfy.sh/install](https://docs.ntfy.sh/install/) for
running your own. Self-hosting also gets you actual topic access control instead of
security-by-obscurity.
