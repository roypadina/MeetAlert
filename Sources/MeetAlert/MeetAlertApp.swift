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
            Image(systemName: store.menuBarSymbol)
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
        Section("Next up") {
            if store.upcomingList.isEmpty {
                Text("No upcoming meetings")
            }
            ForEach(store.upcomingList) { m in
                let row = "\(m.start.formatted(date: .omitted, time: .shortened))  \(m.title)"
                // Meetings with an online link are clickable straight from the menu; joining here is
                // just "open the link" — it does NOT ack the meeting, so the alert still fires later.
                if let url = m.joinURL {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Label("\(row)  — Join \(Ntfy.provider(for: url))", systemImage: "video.fill")
                    }
                } else {
                    Label(row, systemImage: m.hasPhysicalLocation ? "figure.walk" : "calendar")
                }
            }
        }
        if let snoozed = store.upcomingList.first(where: { store.snoozedUntilDate(for: $0.key) != nil }),
           let until = store.snoozedUntilDate(for: snoozed.key) {
            Label("Snoozed: \(snoozed.title) until \(until.formatted(date: .omitted, time: .shortened))",
                  systemImage: "zzz")
        }
        // Demoted into a submenu so a long "ignore forever" sentence never dominates the top level.
        if let next = store.upcomingList.first {
            Menu("Ignore") {
                Button(next.seriesId != nil ? "Ignore \(next.title) forever (whole series)"
                                            : "Ignore \(next.title) forever") { store.ignoreForever(next) }
            }
        }
        if store.calendarSelectionBroken {
            Label("Calendar selection invalid — open Settings", systemImage: "exclamationmark.triangle")
        }
        Divider()
        SettingsLink { Text("Settings…") }
        Button("Edit config file…") { NSWorkspace.shared.open(Store.configURL) }
        Divider()
        Button("About MeetAlert") { showAbout() }
        Button("Support on Ko-fi ☕") { NSWorkspace.shared.open(AboutInfo.kofi) }
        Button("Quit") { NSApp.terminate(nil) }
    }

    private func showAbout() {
        let credits = NSMutableAttributedString(
            string: "\(AboutInfo.text)\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        credits.append(NSAttributedString(string: "Support on Ko-fi ☕", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .link: AboutInfo.kofi]))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

enum AboutInfo {
    static let kofi = URL(string: "https://ko-fi.com/roypadina")!
    static let github = URL(string: "https://github.com/roypadina/MeetAlert")!
    static let text = """
        Made by Roy Padina

        I'm a software engineer from Israel who builds small, focused Mac tools to fix the little annoyances in my own day — then shares them free and open source.

        If this app saves you time, a coffee on Ko-fi keeps the next one coming. ☕
        """
}
