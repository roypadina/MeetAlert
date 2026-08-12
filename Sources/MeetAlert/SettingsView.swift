import AppKit
import EventKit
import SwiftUI

struct SettingsView: View {
    @Bindable var store: Store

    var body: some View {
        Form {
            Section("Timing") {
                Stepper("Alert \(store.config.leadMinutes) min before", value: $store.config.leadMinutes, in: 1...30)
                Stepper("Late alert up to \(store.config.lateAlertMinutes) min after start",
                        value: $store.config.lateAlertMinutes, in: 2...30)
                Stepper("Escalate after \(store.config.escalationSeconds)s",
                        value: $store.config.escalationSeconds, in: 30...600, step: 30)
            }
            Section("Filters") {
                Toggle("Ignore all-day events", isOn: $store.config.ignoreAllDay)
                TextField("Ignore keywords (comma-separated)", text: keywordsBinding)
            }
            calendarsContent
            Section("ntfy") {
                TextField("Server", text: $store.config.ntfyServer)
                TextField("Topic", text: $store.config.ntfyTopic)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
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
                            set: { _ in toggle(cal, in: group.calendars) }
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

    private func toggle(_ cal: EKCalendar, in calendars: [EKCalendar]) {
        let allIds = calendars.map(\.calendarIdentifier)
        var ids = Set(store.config.calendarIds ?? allIds)
        if ids.contains(cal.calendarIdentifier) {
            ids.remove(cal.calendarIdentifier)
        } else {
            ids.insert(cal.calendarIdentifier)
        }
        store.config.calendarIds = (ids == Set(allIds)) ? nil : Array(ids)
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
