import AppKit
import EventKit
import SwiftUI

// MARK: - Alerts

struct AlertsTab: View {
    @Bindable var store: Store
    @State private var alertMinutesText = ""
    @State private var alertMinutesError: String?
    @FocusState private var alertMinutesFocused: Bool

    var body: some View {
        Form {
            Section {
                LaunchAtLoginToggle()
            } footer: {
                Text("MeetAlert can only alert you while it is running.").formFooter()
            }
            Section {
                TextField("Alert times", text: $alertMinutesText, prompt: Text("3, 0"))
                    .focused($alertMinutesFocused)
                    .onSubmit { commitAlertMinutes() }
            } header: {
                Text("When to Alert")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let alertMinutesError {
                        Label(alertMinutesError, systemImage: "exclamationmark.triangle").formFooter()
                    }
                    Text("Comma-separated minutes before the meeting starts. 0 = at start, negative = after start (a late nag). Example: 10, 3, 0, -5.").formFooter()
                }
            }
            Section {
                stepperRow("Catch up late alerts", "Still fire a missed alert this long after its time (calendar sync lag).",
                           value: $store.config.lateAlertMinutes, in: 2...30, unit: " min")
                stepperRow("Escalate after", "No acknowledgement in time → urgent re-push to the phone.",
                           value: $store.config.escalationSeconds, in: 30...600, step: 30, unit: " s")
                stepperRow("Re-push up to", "Repeats here instead of the phone's insistent ring — an ACK stops these, the ring can't be stopped.",
                           value: $store.config.escalationRepeats, in: 1...20, unit: "×")
                stepperRow("Away after idle", "Idle or locked this long → the first push already goes out urgent.",
                           value: $store.config.awayIdleSeconds, in: 60...600, step: 30, unit: " s")
                stepperRow("Travel lead", "Extra early alert for meetings with a physical address.",
                           value: $store.config.travelLeadMinutes, in: 10...120, step: 5, unit: " min")
            } header: {
                Text("Timing")
            } footer: {
                // The panel's shortcuts, listed once (KBD-1); each button's tooltip repeats its own.
                Text("In an alert: Return joins, 5 or Esc snoozes 5 minutes, ⌘D dismisses, ⌘⇧I ignores. More holds J (join), 1 (snooze 1 minute) and T (until start).").formFooter()
            }
        }
        .formStyle(.grouped)
        .onAppear { alertMinutesText = formattedAlertMinutes }
        .onChange(of: alertMinutesFocused) { _, focused in
            if !focused { commitAlertMinutes() }
        }
    }

    private var formattedAlertMinutes: String {
        store.config.alertMinutesBefore.map(String.init).joined(separator: ", ")
    }

    /// Commits on Enter or on losing focus — not per keystroke, so typing "-" or "," along the way
    /// (e.g. building up "-5") never gets silently eaten mid-edit. Unparseable/empty input reverts
    /// the field to whatever's currently in config rather than clobbering it.
    private func commitAlertMinutes() {
        let parts = alertMinutesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let mins = parts.compactMap { Int($0) }
        if !mins.isEmpty {
            store.config.alertMinutesBefore = Store.Config.normalized(mins)
        }
        let typed = alertMinutesText
        alertMinutesText = formattedAlertMinutes
        // Say what was dropped instead of silently rewriting the field (FLW-23).
        alertMinutesError = mins.count == parts.count ? nil
            : "“\(typed)” isn't a list of whole minutes, so \(alertMinutesText) was kept."
    }
}

/// Title + subtitle on the leading side (a Form styles the second Text as a subtitle), the current
/// value right next to its stepper on the trailing side so values line up down the column.
private func stepperRow(_ title: String, _ subtitle: String, value: Binding<Int>, in range: ClosedRange<Int>,
                        step: Int = 1, unit: String) -> some View {
    LabeledContent {
        HStack(spacing: 6) {
            Text("\(value.wrappedValue)\(unit)").monospacedDigit()
            Stepper(title, value: value, in: range, step: step).labelsHidden()
        }
    } label: {
        Text(title)
        Text(subtitle)
    }
}

extension View {
    /// Grouped-form footers default to trailing-aligned body text; Apple's are leading, small, secondary.
    func formFooter() -> some View {
        font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)  // line up with the section header and row text, not the card edge
    }
}

// MARK: - Ignore

struct IgnoreTab: View {
    @Bindable var store: Store
    @State private var upcoming: [Store.Meeting] = []

    var body: some View {
        Form {
            Section {
                Toggle("Ignore all-day events", isOn: $store.config.ignoreAllDay)
                TextField("Ignore keywords", text: keywordsBinding, prompt: Text("focus time, lunch"))
            } header: {
                Text("Filters")
            } footer: {
                Text("Comma-separated. Any meeting whose title contains one of these is never alerted — this is also how you pre-ignore a whole class of meetings.").formFooter()
            }

            Section {
                if upcoming.isEmpty {
                    Text("Nothing in the next 7 days").foregroundStyle(.secondary)
                }
                ForEach(upcoming) { m in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title)
                            Text(m.start.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if m.seriesId != nil {
                            Menu("Ignore") {
                                Button("This Time Only") { store.ignoreOccurrence(m); reload() }
                                Button("Whole Series") { store.ignoreSeries(m); reload() }
                            }
                            .fixedSize()
                        } else {
                            Button("Ignore") { store.ignoreOccurrence(m); reload() }
                        }
                    }
                }
            } header: {
                Text("Upcoming — Next 7 Days")
            } footer: {
                Text("Pre-ignore a specific meeting before it ever alerts. Recurring meetings can be ignored once or as a whole series.").formFooter()
            }

            Section {
                let entries = store.ignoredEntries()
                if entries.isEmpty {
                    Text("Nothing ignored").foregroundStyle(.secondary)
                }
                ForEach(entries, id: \.id) { entry in
                    HStack {
                        Text(entry.label)
                        Spacer()
                        Button("Stop Ignoring", systemImage: "xmark.circle.fill") {
                            store.unignore(entry.id); reload()
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .frame(minWidth: 20, minHeight: 20)
                        .contentShape(Rectangle())
                        .help("Stop ignoring \(entry.label)")
                    }
                }
            } header: {
                Text("Currently Ignored")
            } footer: {
                Text("One-off entries clean themselves up a day after the meeting passes; series entries stay until removed here.").formFooter()
            }
        }
        .formStyle(.grouped)
        .onAppear { reload() }
    }

    private func reload() {
        upcoming = store.upcomingWeek()
    }

    private var keywordsBinding: Binding<String> {
        Binding(
            get: { store.config.ignoreKeywords.joined(separator: ", ") },
            set: { text in
                store.config.ignoreKeywords = text.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

// MARK: - Calendars

struct CalendarsTab: View {
    @Bindable var store: Store

    var body: some View {
        Form {
            let groups = store.calendarsBySource()
            if groups.isEmpty {
                Section("Calendars") {
                    if store.calendarAccessDenied {
                        LabeledContent {
                            Button("Open System Settings") { Self.openCalendarPrivacy() }
                        } label: {
                            Label("Calendar access is off", systemImage: "exclamationmark.triangle")
                            Text("MeetAlert can't see any meetings, so it can't alert you. Allow MeetAlert under Privacy & Security > Calendars.")
                        }
                    } else {
                        Text("No calendars yet. Add an account in System Settings > Internet Accounts.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.calendars, id: \.calendarIdentifier) { cal in
                            HStack {
                                Toggle(cal.title, isOn: Binding(
                                    get: { isEnabled(cal) },
                                    set: { _ in toggle(cal) }
                                ))
                                Spacer()
                                // Alert-panel dot colour for this calendar; starts at the colour
                                // macOS already uses for it in Calendar.app.
                                ColorPicker("", selection: colorBinding(cal)).labelsHidden()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    static func openCalendarPrivacy() {
        let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        if !NSWorkspace.shared.open(pane) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    private func colorBinding(_ cal: EKCalendar) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: store.colorFor(cal) ?? .systemGray) },
            set: { store.config.calendarColors[cal.calendarIdentifier] = NSColor($0).hexString }
        )
    }

    private func isEnabled(_ cal: EKCalendar) -> Bool {
        guard let ids = store.config.calendarIds else { return true }
        return ids.contains(cal.calendarIdentifier)
    }

    private func toggle(_ cal: EKCalendar) {
        let allIds = store.allCalendarIds()
        var ids = Set(store.config.calendarIds ?? allIds)
        if ids.contains(cal.calendarIdentifier) {
            ids.remove(cal.calendarIdentifier)
        } else {
            ids.insert(cal.calendarIdentifier)
        }
        store.config.calendarIds = (ids == Set(allIds)) ? nil : Array(ids)
    }
}

// MARK: - Phone

struct PhoneTab: View {
    @Bindable var store: Store
    @State private var testPushResult: Bool?

    var body: some View {
        Form {
            Section {
                TextField("Server", text: $store.config.ntfyServer)
                TextField("Topic", text: $store.config.ntfyTopic, prompt: Text("empty = phone push off"))
                SecureField("Access token (optional)", text: $store.config.ntfyToken)
                SecureField("Fallback topic URL (optional)", text: $store.config.ntfyFallbackURL, prompt: Text("https://ntfy.sh/…"))
                HStack {
                    Button("Send Test Push") {
                        Task { testPushResult = await store.sendTestPush() }
                    }
                    if let ok = testPushResult {
                        Label {
                            Text(ok ? "Sent. Check your phone." : "Couldn't send. Check the server, topic and token, then try again.")
                        } icon: {
                            Image(systemName: ok ? "checkmark.circle" : "exclamationmark.triangle.fill")
                                .foregroundStyle(ok ? Color.secondary : Color.red)
                        }
                        .font(.callout)
                    }
                }
            } header: {
                Text("ntfy")
            } footer: {
                Text("Pushes go to this topic with tappable ACK / Join / Snooze actions. Keep the topic private — anyone who knows it can read it. The access token (for a password-protected server) and the fallback topic URL (used, without actions, when the main server can't be reached) are kept in the macOS Keychain, not in config.json.").formFooter()
            }

            Section {
                Toggle("Send morning agenda", isOn: agendaEnabledBinding)
                if store.config.agendaTime != nil {
                    DatePicker("Send at", selection: agendaDateBinding, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Morning Agenda")
            } footer: {
                Text("One push per day at this time: today's meeting count, the first one, up to 6 upcoming, and your largest free gap.").formFooter()
            }
        }
        .formStyle(.grouped)
    }

    private var agendaEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.config.agendaTime != nil },
            set: { on in store.config.agendaTime = on ? (store.config.agendaTime ?? 7 * 60) : nil }
        )
    }

    /// DatePicker wants a Date; config stores minutes-since-midnight. Only the time-of-day
    /// components round-trip, the calendar day is irrelevant.
    private var agendaDateBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = store.config.agendaTime ?? 7 * 60
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.config.agendaTime = (c.hour ?? 7) * 60 + (c.minute ?? 0)
            }
        )
    }
}
