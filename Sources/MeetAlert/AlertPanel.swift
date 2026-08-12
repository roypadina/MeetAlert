import AppKit
import SwiftUI

/// A borderless nonactivating NSPanel can never become key by default, which silently kills the
/// Return-key shortcut on its Dismiss button. Overriding canBecomeKey fixes that WITHOUT calling
/// makeKey/makeKeyAndOrderFront ourselves — no focus stealing, no activating the app. Return only
/// starts working once the user has already clicked into the panel.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Floating, non-activating panel that stays up until the user acts on it.
/// Multiple panels stack vertically; dismissing one closes the gap for the ones below it.
@MainActor
enum AlertPanel {
    private static var active: [(key: String, panel: NSPanel)] = []
    private static let width: CGFloat = 560
    private static let height: CGFloat = 140
    private static let gap: CGFloat = 8
    private static let margin: CGFloat = 12

    static func show(_ m: Store.Meeting, alertKey: String,
                      onAck: @escaping () -> Void,
                      onSnooze: @escaping (Int) -> Void,
                      onSnoozeStart: @escaping () -> Void,
                      onIgnore: @escaping () -> Void) {
        if let existing = active.first(where: { $0.key == alertKey }) {
            existing.panel.orderFrontRegardless()  // already showing (e.g. re-tick) — don't stack a duplicate
            return
        }
        // No screen at all (e.g. woke from sleep with displays not yet re-attached) — the alertKey
        // is already marked fired, so dropping the panel here would lose the alert for good. Retry
        // instead of un-marking anything; it self-heals once a display shows up.
        guard let screen = screenUnderMouse() else {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(30))
                show(m, alertKey: alertKey, onAck: onAck, onSnooze: onSnooze, onSnoozeStart: onSnoozeStart, onIgnore: onIgnore)
            }
            return
        }
        let panel = makePanel()

        func closeThen(_ action: @escaping () -> Void) {
            dismiss(panel)
            action()
        }

        let onJoin: (() -> Void)? = m.joinURL.map { url in { closeThen { NSWorkspace.shared.open(url); onAck() } } }

        panel.contentView = NSHostingView(rootView: AlertContent(
            meeting: m,
            onJoin: onJoin,
            onSnooze1: { closeThen { onSnooze(1) } },
            onSnooze5: { closeThen { onSnooze(5) } },
            onSnoozeStart: { closeThen(onSnoozeStart) },
            onIgnore: { closeThen(onIgnore) },
            onDismiss: { closeThen(onAck) }
        ))

        panel.setFrame(frame(forIndex: active.count, screen: screen), display: false)
        panel.orderFrontRegardless()
        active.append((alertKey, panel))

        NSSound(named: "Funk")?.play()
    }

    /// Reduced-buttons variant for the meeting-overrun heads-up: Dismiss only, no ack/snooze/ignore.
    static func showOverrun(key: String, title: String, subtitle: String, onDismiss: @escaping () -> Void) {
        if let existing = active.first(where: { $0.key == key }) {
            existing.panel.orderFrontRegardless()
            return
        }
        guard let screen = screenUnderMouse() else {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(30))
                showOverrun(key: key, title: title, subtitle: subtitle, onDismiss: onDismiss)
            }
            return
        }
        let panel = makePanel()

        func closeThen(_ action: @escaping () -> Void) {
            dismiss(panel)
            action()
        }

        panel.contentView = NSHostingView(rootView: OverrunContent(
            title: title, subtitle: subtitle,
            onDismiss: { closeThen(onDismiss) }
        ))

        panel.setFrame(frame(forIndex: active.count, screen: screen), display: false)
        panel.orderFrontRegardless()
        active.append((key, panel))

        NSSound(named: "Funk")?.play()
    }

    /// Closes the panel for `key` if one is open — e.g. an ACK or snooze that arrived via the phone
    /// push, which previously stopped escalation but left the desktop panel sitting there forever.
    static func dismiss(key: String) {
        guard let idx = active.firstIndex(where: { $0.key == key }) else { return }
        remove(at: idx)
    }

    private static func makePanel() -> NSPanel {
        let panel = KeyablePanel(
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
        return panel
    }

    private static func dismiss(_ panel: NSPanel) {
        guard let idx = active.firstIndex(where: { $0.panel == panel }) else { return }
        remove(at: idx)
    }

    private static func remove(at idx: Int) {
        let panel = active[idx].panel
        active.remove(at: idx)
        panel.orderOut(nil)
        reflow()
    }

    // ponytail: reflow repositions ALL currently-open panels onto whichever screen has the mouse
    // right now — correct for the common case (one alert at a time), but if several panels are
    // stacked across different screens and the mouse has since moved, a dismiss can jump the
    // survivors to the new screen. Upgrade to a per-panel screen if that turns out to matter.
    private static func reflow() {
        guard let screen = screenUnderMouse() else { return }
        for (i, entry) in active.enumerated() {
            entry.panel.setFrame(frame(forIndex: i, screen: screen), display: true)
        }
    }

    private static func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Clamps to the last fully-visible slot on this screen — beyond that, extra panels overlap the
    /// last slot instead of computing a Y coordinate below the screen's bottom edge.
    private static func frame(forIndex index: Int, screen: NSScreen) -> NSRect {
        let maxSlots = max(1, Int((screen.visibleFrame.height - margin) / (height + gap)))
        let clampedIndex = min(index, maxSlots - 1)
        let x = screen.visibleFrame.midX - width / 2
        let y = screen.visibleFrame.maxY - margin - CGFloat(clampedIndex + 1) * (height + gap) + gap
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private struct AlertContent: View {
    let meeting: Store.Meeting
    let onJoin: (() -> Void)?
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
                if let onJoin {
                    Button("Join", action: onJoin).buttonStyle(.borderedProminent)
                }
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

private struct OverrunContent: View {
    let title: String
    let subtitle: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Dismiss", action: onDismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 560, height: 140, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}
