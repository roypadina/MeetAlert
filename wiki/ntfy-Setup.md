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
needed. `ntfyTopic` is **empty by default**, which means phone push (and escalation with it) is
completely off — desktop popups still work, but nothing reaches your phone until you set a topic
here. Use the **"Send test push"** button in Settings → ntfy to confirm it's actually working.

## 5. Make urgent priority actually bypass silence

This is the fiddly part, and it's a real limitation of ntfy's mobile clients, not something
MeetAlert can fix on its own.

**What MeetAlert sends:** the first alert normally goes out at priority 4 (high) — but if
MeetAlert thinks you're away from the Mac (idle past `awayIdleSeconds`, or the screen is locked),
that first push skips straight to priority 5 (urgent) instead, since there's no point waiting on
a grace window nobody at the desk would see. Either way, if nobody acks within `escalationSeconds`,
it re-sends at priority 5 (tag `rotating_light`) — up to **3 times total**, and never past
**15 minutes** after the meeting's start (if the alert itself first fires later than that, there's
no escalation window left — just the one push). The intent is that the urgent pushes are loud
enough, and persistent enough, to wake you up even on a silenced phone — but whether they actually
do depends on OS-level notification settings the ntfy app can't fully control for you. Every push
is sent through ntfy's JSON publish API (not the older header-based endpoint), so titles with
emoji or non-Latin text come through intact.

**Action buttons on the alert push:** an **ACK** button (acknowledges and stops escalation), a
**Join** button when MeetAlert found a video-call link in the event, and a **Snooze 5m** button
(snoozes the alert — clamped to the meeting's start if it hasn't started yet — and stops
escalation). **Join only opens the link — it does not ack.** That's a hard ntfy limitation: a
"view" action just opens a URL on your phone and never talks back to MeetAlert, so there's no way
for it to also register an ack. Tap **ACK** separately if you want to stop escalation. ntfy caps
notifications at 3 actions, so without a Join link it's just ACK + Snooze 5m — and escalation
re-pushes carry ACK (+ Join) too, not just the first one. The separate daily morning-agenda push
(if `agendaTime` is set) is plain default-priority, informational only — no actions, no escalation.

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

**Keep message caching enabled** (`cache-duration` in `server.yml` — the default is on). MeetAlert
detects an ACK or snooze by *polling the topic's message history*
(`GET /<topic>/json?poll=1&since=...`); with `cache-duration: 0` there's no history to poll at
all, so a real ACK is invisible to MeetAlert and it escalates the full 3 times regardless of
whether you actually tapped ACK. This is the single most common self-hosting misconfiguration for
MeetAlert specifically — public `ntfy.sh` caches by default, so this only bites self-hosters who
turned caching off.
