import AppKit
import SwiftUI

@main
struct MeetAlertApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    // Plain let, not @State: reading a @State in init() isn't the installed value — SwiftUI builds a
    // fresh Store on each such read, so start() ran on a throwaway Store (deallocated after its first
    // tick) while the menu and Settings bound an unstarted one with default config.
    private let store: Store

    init() {
        let store = Store()
        self.store = store
        SettingsWindow.shared.store = store
        Task { @MainActor in store.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Image(systemName: store.menuBarSymbol)
                .accessibilityLabel("MeetAlert")  // VoiceOver: the app's name, not the symbol's
            Text(store.menuBarText)
        }
        .commands {  // App menu while a window is open (policy .regular)
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { SettingsWindow.shared.show() }.keyboardShortcut(",")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        // First launch only (MBX-18); never in the headless test pipeline.
        guard ProcessInfo.processInfo.environment["MEETALERT_TEST"] != "1",
              !UserDefaults.standard.bool(forKey: "didShowWelcome") else { return }
        UserDefaults.standard.set(true, forKey: "didShowWelcome")
        WelcomeWindow.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Opening MeetAlert again (Finder, Raycast) shows Settings: the way in when the icon is hidden (MBX-8).
    @MainActor func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { SettingsWindow.shared.show() }
        return true
    }
}

private struct MenuContent: View {
    let store: Store

    var body: some View {
        // Every panel action is also here: the panel never takes keyboard focus on its own (A11Y-8, MNU-2).
        if let alert = store.showingAlerts.first {
            Section("Current Alert") {
                if let url = alert.meeting.joinURL {
                    Button("Join \(Ntfy.provider(for: url))") { NSWorkspace.shared.open(url); store.ack(alert.key) }
                }
                Button("Snooze 5 Minutes") { store.snooze(alert.meeting, alertKey: alert.key, minutes: 5) }
                Button("Dismiss \(alert.meeting.title)") { store.ack(alert.key) }
            }
            Divider()
        }
        Section("Next Up") {
            if store.upcomingList.isEmpty {
                Text("No upcoming meetings")
            }
            ForEach(store.upcomingList) { m in
                let row = "\(m.start.formatted(date: .omitted, time: .shortened))  \(m.title)"
                // Meetings with an online link are clickable straight from the menu; joining here is
                // just "open the link" — it does NOT ack the meeting, so the alert still fires later.
                if let url = m.joinURL {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Label("\(row)  — Join \(Ntfy.provider(for: url))", systemImage: "video")
                    }
                } else {
                    Label(row, systemImage: m.hasPhysicalLocation ? "figure.walk" : "calendar")
                }
            }
        }
        .labelStyle(.titleAndIcon)  // macOS 27 hides menu item images unless opted in; in-person vs. plain lives in the icon
        if let snoozed = store.upcomingList.first(where: { store.snoozedUntilDate(for: $0.key) != nil }),
           let until = store.snoozedUntilDate(for: snoozed.key) {
            Label("Snoozed: \(snoozed.title) until \(until.formatted(date: .omitted, time: .shortened))",
                  systemImage: "zzz")
                .labelStyle(.titleAndIcon)
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
                .labelStyle(.titleAndIcon)
        }
        // The menu-bar warning triangle always says why here (FLW-11, FLW-17).
        if store.calendarAccessDenied {
            Button("Calendar Access Is Off — Open System Settings…") { CalendarsTab.openCalendarPrivacy() }
        }
        if store.lastPushFailed {
            Button("Phone Push Failed — Check Settings…") { SettingsWindow.shared.show() }
        }
        Divider()
        Button("Settings…") { SettingsWindow.shared.show() }.keyboardShortcut(",")
        Button("Edit Config File…") { NSWorkspace.shared.open(Store.configURL) }
        Divider()
        Button("About MeetAlert") { AboutWindow.show() }
        Button("Support on Ko-fi ☕") { NSWorkspace.shared.open(AboutInfo.kofi) }
        Button("Quit MeetAlert") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
