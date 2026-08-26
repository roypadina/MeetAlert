import AppKit
import SwiftUI

@main
struct MeetAlertApp: App {
    @State private var store = Store()

    init() {
        let store = store
        Task { @MainActor in store.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Image(systemName: "calendar")
            Text(store.menuBarText)
        }
        Settings {
            SettingsView(store: store)
        }
    }
}

private struct MenuContent: View {
    let store: Store

    var body: some View {
        if store.upcomingList.isEmpty {
            Text("No upcoming meetings")
        }
        ForEach(store.upcomingList) { m in
            let row = "\(m.start.formatted(date: .omitted, time: .shortened))  \(m.title)"
            // Meetings with an online link are clickable straight from the menu; joining here is
            // just "open the link" — it does NOT ack the meeting, so the alert still fires later.
            if let url = m.joinURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    Label("\(row)  — Join", systemImage: "video.fill")
                }
            } else {
                Text(row)
            }
        }
        if let snoozed = store.upcomingList.first(where: { store.snoozedUntilDate(for: $0.key) != nil }),
           let until = store.snoozedUntilDate(for: snoozed.key) {
            Text("Snoozed: \(snoozed.title) until \(until.formatted(date: .omitted, time: .shortened))")
        }
        if let next = store.upcomingList.first {
            Button(next.seriesId != nil ? "Ignore \(next.title) forever (whole series)"
                                        : "Ignore \(next.title) forever") { store.ignoreForever(next) }
        }
        if store.calendarSelectionBroken {
            Text("Calendar selection invalid — open Settings")
        }
        Divider()
        SettingsLink { Text("Settings…") }
        Button("Edit config file…") { NSWorkspace.shared.open(Store.configURL) }
        Button("Quit") { NSApp.terminate(nil) }
    }
}
