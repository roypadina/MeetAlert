# Security Policy

## Reporting a Vulnerability

MeetAlert reads your calendar and pushes meeting content to a third-party ntfy server you
configure, so security reports are taken seriously. Please **do not** open a public issue for
security problems.

Instead, use GitHub's private vulnerability reporting (**Security → Report a vulnerability**)
or email **roypadina@gmail.com**.

You'll get an acknowledgement within a few days. Once a fix is available it will be released
and the report disclosed, with credit unless you prefer otherwise.

## Scope

- **Calendar data** never leaves your Mac except in the ntfy push you configure (meeting title
  and start time only, sent to whatever `ntfyServer`/`ntfyTopic` you set).
- **ntfy topics are not secret by design** — anyone who knows your topic name can publish to or
  read it on a shared server like `ntfy.sh`. That's a property of ntfy itself, not a MeetAlert
  bug; see [ntfy setup](README.md#ntfy-setup) for picking a topic that isn't guessable, or
  self-host for real access control.
- MeetAlert requests no elevated privileges. Relevant local APIs: EventKit (calendar read),
  `SMAppService` (login item registration), and outbound HTTPS to the ntfy server you configure.
