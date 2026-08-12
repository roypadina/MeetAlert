import AppKit
import EventKit
import SwiftUI

struct SettingsView: View {
    @Bindable var store: Store
    @State private var alertMinutesText = ""
    @FocusState private var alertMinutesFocused: Bool
    @State private var testPushResult: String?

    var body: some View {
        Form {
            Section("Timing") {
                TextField("Alert times (min before start; 0 = at start; negative = after)", text: $alertMinutesText)
                    .focused($alertMinutesFocused)
                    .onSubmit { commitAlertMinutes() }
                Stepper("Fire missed alerts up to \(store.config.lateAlertMinutes) min late",
                        value: $store.config.lateAlertMinutes, in: 2...30)
                Stepper("Escalate after \(store.config.escalationSeconds)s",
                        value: $store.config.escalationSeconds, in: 30...600, step: 30)
                Stepper("Away after \(store.config.awayIdleSeconds)s idle",
                        value: $store.config.awayIdleSeconds, in: 60...600, step: 30)
                Stepper("Travel lead \(store.config.travelLeadMinutes) min",
                        value: $store.config.travelLeadMinutes, in: 10...120, step: 5)
                Toggle("Warn 2 min before a meeting ends", isOn: $store.config.endWarning)
            }
            Section("Morning agenda") {
                Toggle("Send morning agenda", isOn: agendaEnabledBinding)
                if let hour = store.config.agendaHour {
                    Stepper("Send at \(hour):00", value: agendaHourBinding(hour), in: 0...23)
                }
            }
            Section("Filters") {
                Toggle("Ignore all-day events", isOn: $store.config.ignoreAllDay)
                TextField("Ignore keywords (comma-separated)", text: keywordsBinding)
            }
            calendarsContent
            Section("ntfy") {
                TextField("Server", text: $store.config.ntfyServer)
                TextField("Topic", text: $store.config.ntfyTopic)
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
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            alertMinutesText = formattedAlertMinutes
            NSApp.activate(ignoringOtherApps: true)
        }
        .onChange(of: alertMinutesFocused) { _, focused in
            if !focused { commitAlertMinutes() }
        }
    }

    @ViewBuilder
    private var calendarsContent: some View {
        let groups = store.calendarsBySource()
        if groups.isEmpty {
            Section("Calendars") {
                Text("No calendar access")
            }
        } else {
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.calendars, id: \.calendarIdentifier) { cal in
                        Toggle(cal.title, isOn: Binding(
                            get: { isEnabled(cal) },
                            set: { _ in toggle(cal) }
                        ))
                    }
                }
            }
        }
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

    private var agendaEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.config.agendaHour != nil },
            set: { on in store.config.agendaHour = on ? (store.config.agendaHour ?? 7) : nil }
        )
    }

    private func agendaHourBinding(_ hour: Int) -> Binding<Int> {
        Binding(get: { hour }, set: { store.config.agendaHour = $0 })
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
