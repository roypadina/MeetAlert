import AppKit
import EventKit
import SwiftUI

struct SettingsView: View {
    @Bindable var store: Store

    var body: some View {
        TabView {
            AlertsTab(store: store)
                .tabItem { Label("Alerts", systemImage: "bell.badge") }
            IgnoreTab(store: store)
                .tabItem { Label("Ignore", systemImage: "bell.slash") }
            CalendarsTab(store: store)
                .tabItem { Label("Calendars", systemImage: "calendar") }
            PhoneTab(store: store)
                .tabItem { Label("Phone", systemImage: "iphone") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 480)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("MeetAlert").font(.title2.bold())
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .foregroundStyle(.secondary)
            HStack {
                Button("About MeetAlert…") { AboutWindow.show() }
                Button("Support on Ko-fi ☕") { NSWorkspace.shared.open(AboutInfo.kofi) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Alerts

private struct AlertsTab: View {
    @Bindable var store: Store
    @State private var alertMinutesText = ""
    @FocusState private var alertMinutesFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Alert times", text: $alertMinutesText, prompt: Text("3, 0"))
                    .focused($alertMinutesFocused)
                    .onSubmit { commitAlertMinutes() }
            } header: {
                Text("When to alert")
            } footer: {
                Text("Comma-separated minutes before the meeting starts. 0 = at start, negative = after start (a late nag). Example: 10, 3, 0, -5.")
            }
            Section("Timing") {
                Stepper(value: $store.config.lateAlertMinutes, in: 2...30) {
                    labeled("Catch up late alerts", "Still fire an alert up to \(store.config.lateAlertMinutes) min after its time (calendar sync lag).")
                }
                Stepper(value: $store.config.escalationSeconds, in: 30...600, step: 30) {
                    labeled("Escalate after \(store.config.escalationSeconds)s", "No ack in time → urgent re-push to the phone.")
                }
                Stepper(value: $store.config.escalationRepeats, in: 1...20) {
                    labeled("Re-push up to \(store.config.escalationRepeats)×", "Own the repetition here instead of the phone's insistent ring — an ACK stops it, insistent can't be stopped.")
                }
                Stepper(value: $store.config.awayIdleSeconds, in: 60...600, step: 30) {
                    labeled("Away after \(store.config.awayIdleSeconds)s idle", "Idle or locked this long → first push already goes out urgent.")
                }
                Stepper(value: $store.config.travelLeadMinutes, in: 10...120, step: 5) {
                    labeled("Travel lead \(store.config.travelLeadMinutes) min", "Extra early alert for meetings with a physical address.")
                }
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
        let mins = alertMinutesText.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if !mins.isEmpty {
            store.config.alertMinutesBefore = Store.Config.normalized(mins)
        }
        alertMinutesText = formattedAlertMinutes
    }
}

/// Title + secondary explanation line, the visual pattern every stepper row shares.
private func labeled(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: - Ignore

private struct IgnoreTab: View {
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
                Text("Comma-separated. Any meeting whose title contains one of these is never alerted — this is also how you pre-ignore a whole class of meetings.")
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
                                Button("This time only") { store.ignoreOccurrence(m); reload() }
                                Button("Whole series") { store.ignoreSeries(m); reload() }
                            }
                            .fixedSize()
                        } else {
                            Button("Ignore") { store.ignoreOccurrence(m); reload() }
                        }
                    }
                }
            } header: {
                Text("Upcoming — next 7 days")
            } footer: {
                Text("Pre-ignore a specific meeting before it ever alerts. Recurring meetings can be ignored once or as a whole series.")
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
                        Button {
                            store.unignore(entry.id); reload()
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Stop ignoring")
                    }
                }
            } header: {
                Text("Currently ignored")
            } footer: {
                Text("One-off entries clean themselves up a day after the meeting passes; series entries stay until removed here.")
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

private struct CalendarsTab: View {
    @Bindable var store: Store

    var body: some View {
        Form {
            let groups = store.calendarsBySource()
            if groups.isEmpty {
                Section("Calendars") {
                    Text("No calendar access")
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

private struct PhoneTab: View {
    @Bindable var store: Store
    @State private var testPushResult: String?

    var body: some View {
        Form {
            Section {
                TextField("Server", text: $store.config.ntfyServer)
                TextField("Topic", text: $store.config.ntfyTopic, prompt: Text("empty = phone push off"))
                HStack {
                    Button("Send test push") {
                        Task {
                            let ok = await store.sendTestPush()
                            testPushResult = ok ? "sent ✓" : "failed ✗"
                        }
                    }
                    if let testPushResult {
                        Text(testPushResult).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("ntfy")
            } footer: {
                Text("Pushes go to this topic with tappable ACK / Join / Snooze actions. Keep the topic private — anyone who knows it can read it.")
            }

            Section {
                Toggle("Send morning agenda", isOn: agendaEnabledBinding)
                if store.config.agendaTime != nil {
                    DatePicker("Send at", selection: agendaDateBinding, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Morning agenda")
            } footer: {
                Text("One push per day at this time: today's meeting count, the first one, up to 6 upcoming, and your largest free gap.")
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
