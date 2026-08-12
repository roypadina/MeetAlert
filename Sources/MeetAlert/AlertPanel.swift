import AppKit
import SwiftUI

/// Floating, non-activating panel that stays up until the user acts on it.
/// Multiple panels stack vertically; dismissing one closes the gap for the ones below it.
@MainActor
enum AlertPanel {
    private static var active: [NSPanel] = []
    private static let width: CGFloat = 560
    private static let height: CGFloat = 140
    private static let gap: CGFloat = 8
    private static let margin: CGFloat = 12

    static func show(_ m: Store.Meeting,
                      onAck: @escaping () -> Void,
                      onSnooze: @escaping (Int) -> Void,
                      onSnoozeStart: @escaping () -> Void,
                      onIgnore: @escaping () -> Void) {
        guard let screen = NSScreen.main else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        func closeThen(_ action: @escaping () -> Void) {
            dismiss(panel)
            action()
        }

        panel.contentView = NSHostingView(rootView: AlertContent(
            meeting: m,
            onSnooze1: { closeThen { onSnooze(1) } },
            onSnooze5: { closeThen { onSnooze(5) } },
            onSnoozeStart: { closeThen(onSnoozeStart) },
            onIgnore: { closeThen(onIgnore) },
            onDismiss: { closeThen(onAck) }
        ))

        panel.setFrame(frame(forIndex: active.count, screen: screen), display: false)
        panel.orderFrontRegardless()
        active.append(panel)

        NSSound(named: "Funk")?.play()
    }

    private static func dismiss(_ panel: NSPanel) {
        guard let idx = active.firstIndex(of: panel) else { return }
        active.remove(at: idx)
        panel.orderOut(nil)
        reflow()
    }

    private static func reflow() {
        guard let screen = NSScreen.main else { return }
        for (i, panel) in active.enumerated() {
            panel.setFrame(frame(forIndex: i, screen: screen), display: true)
        }
    }

    private static func frame(forIndex index: Int, screen: NSScreen) -> NSRect {
        let x = screen.visibleFrame.midX - width / 2
        let y = screen.visibleFrame.maxY - margin - CGFloat(index + 1) * (height + gap) + gap
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private struct AlertContent: View {
    let meeting: Store.Meeting
    let onSnooze1: () -> Void
    let onSnooze5: () -> Void
    let onSnoozeStart: () -> Void
    let onIgnore: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(meeting.title).font(.title3.bold())
            HStack(spacing: 6) {
                Text(meeting.start, style: .time)
                Text("·")
                Text(meeting.start, style: .relative)  // live "in 3 min" / "3 min ago"
            }
            .font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button("Snooze 1m", action: onSnooze1)
                Button("Snooze 5m", action: onSnooze5)
                if meeting.start > Date() {
                    Button("Till start", action: onSnoozeStart)
                }
                Spacer()
                Button("Ignore forever", action: onIgnore)
                Button("Dismiss", action: onDismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 560, height: 140, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}
