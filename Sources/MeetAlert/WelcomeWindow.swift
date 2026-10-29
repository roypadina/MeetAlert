import ServiceManagement
import SwiftUI

/// First-launch welcome (MBX-18): where the icon is, what an alert looks like, how to get back in
/// without the icon (MBX-8, MBX-9), and the login item (MBX-17). Shown once from AppDelegate, and again from "Welcome Guide…".
@MainActor
enum WelcomeWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: WelcomeView(
                onOpenSettings: { window?.close(); SettingsWindow.shared.show() },
                onDone: { window?.close() })))
            w.title = "Welcome"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
            // Release on close: a kept-alive window keeps the login toggle's activation subscription running.
            Task { @MainActor in
                for await _ in NotificationCenter.default.notifications(named: NSWindow.willCloseNotification, object: w) { break }
                window = nil
            }
        }
        if let window { AccessoryWindows.shared.show(window) }
    }
}

struct WelcomeView: View {
    let onOpenSettings: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to MeetAlert").font(.title2.bold())
                    Text("A calendar reminder is easy to miss when you are deep in work. MeetAlert puts a panel on screen before each meeting that stays until you act, and can ring your phone too.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            row("calendar", "MeetAlert lives in the menu bar.",
                "Its icon shows your next meeting. Click it for today's list and Settings.")
            row("bell.badge", "Alerts stay until you act.",
                "A panel appears at the top of the screen before each meeting: Join, Snooze 5 Min or Dismiss.")
            row("questionmark.circle", "Icon missing?",
                "Open MeetAlert again from Applications to get Settings, or check System Settings > Menu Bar.")
            LaunchAtLoginToggle()
            SupportBox()
            HStack {
                Button("Open Settings", action: onOpenSettings)
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tint).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Free-and-open-source note with the Ko-fi link; the welcome window's own next step stays the primary action.
struct SupportBox: View {
    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Free and open source").font(.headline)
                    Text("If MeetAlert saves you time, a coffee on Ko-fi keeps the next one coming.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Link("Support on Ko-fi ☕", destination: AboutInfo.kofi).buttonStyle(.bordered)
            }
            .padding(4)
        }
    }
}

/// Settings > Alerts and the welcome window (MBX-17): user action only, status re-read on activation.
struct LaunchAtLoginToggle: View {
    @State private var status = SMAppService.mainApp.status

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Open at Login", isOn: Binding(
                get: { status == .enabled },
                set: { on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    status = SMAppService.mainApp.status
                }))
            if status == .requiresApproval {
                Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
            } else if status == .notFound {
                Text("Move MeetAlert to Applications to open it at login.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status  // the user may change it in System Settings
        }
    }
}
