import AppKit
import SwiftUI

enum AboutInfo {
    static let kofi = URL(string: "https://ko-fi.com/roypadina")!
    static let github = URL(string: "https://github.com/roypadina/MeetAlert")!
}

// Custom About window (the standard panel's fixed-height credits box clipped the text).
@MainActor
enum AboutWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            w.title = "About MeetAlert"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        if let window { AccessoryWindows.shared.show(window) }
    }
}

struct AboutView: View {
    private let info = Bundle.main.infoDictionary ?? [:]

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)  // decorative; the title below names the app

            VStack(spacing: 2) {
                Text("MeetAlert").font(.title.bold())
                Text("Version \(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Text("Made by Roy Padina").font(.headline)
                Text("I'm a software engineer from Israel who builds small, focused Mac tools to fix the little annoyances in my own day — then shares them free and open source.")
                Text("If this app saves you time, a coffee on Ko-fi keeps the next one coming. ☕")
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Link(destination: AboutInfo.kofi) {
                    Text("Support on Ko-fi ☕").frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Link(destination: AboutInfo.github) {
                    Text("GitHub").frame(minWidth: 70)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Link("Report an issue", destination: AboutInfo.github.appendingPathComponent("issues"))
                .font(.callout)

            Divider()

            VStack(spacing: 8) {
                Text("Have an idea, or want to help build it?").font(.headline)
                Text("Feature requests and pull requests are welcome. Ko-fi supporters go to the front of the queue.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Link(destination: URL(string: "https://github.com/roypadina/MeetAlert/issues/new?template=feature_request.yml")!) {
                        Text("Request a feature").frame(minWidth: 120)
                    }
                    .buttonStyle(.bordered)

                    Link(destination: URL(string: "https://github.com/roypadina/MeetAlert/blob/main/CONTRIBUTING.md")!) {
                        Text("Contribute").frame(minWidth: 90)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("© Roy Padina · MIT")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 380)
    }
}
