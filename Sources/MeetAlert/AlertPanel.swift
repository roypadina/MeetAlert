import AppKit
import SwiftUI

/// A borderless nonactivating NSPanel can never become key by default, which silently kills the
/// Return-key shortcut on its Dismiss button. Overriding canBecomeKey fixes that WITHOUT calling
/// makeKey/makeKeyAndOrderFront ourselves — no focus stealing, no activating the app. Return only
/// starts working once the user has already clicked into the panel.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Per-panel presentational state the view observes. `escalated` is flipped by Store's escalation
/// loop (see `AlertPanel.escalated(key:)`); `isKey` drives the keyboard-hint row.
@MainActor @Observable final class PanelState {
    var escalated = false
}

/// Floating, non-activating panel that stays up until the user acts on it.
/// Multiple panels stack vertically; dismissing one closes the gap for the ones below it.
@MainActor
enum AlertPanel {
    private static var active: [(key: String, panel: NSPanel, state: PanelState)] = []
    private static let width: CGFloat = 640
    private static let height: CGFloat = 168
    private static let gap: CGFloat = 10
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
        let state = PanelState()
        func closeThen(_ action: @escaping () -> Void) {
            dismiss(panel)
            action()
        }

        let onJoin: (() -> Void)? = m.joinURL.map { url in { closeThen { NSWorkspace.shared.open(url); onAck() } } }

        panel.contentView = NSHostingView(rootView: AlertContent(
            meeting: m,
            state: state,
            onJoin: onJoin,
            onSnooze1: { closeThen { onSnooze(1) } },
            onSnooze5: { closeThen { onSnooze(5) } },
            onSnoozeStart: { closeThen(onSnoozeStart) },
            onIgnore: { closeThen(onIgnore) },
            onDismiss: { closeThen(onAck) }
        ))
        let final = frame(forIndex: active.count, screen: screen)
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        panel.setFrame(reduce ? final : final.offsetBy(dx: 0, dy: 14), display: false)
        panel.orderFrontRegardless()
        active.append((alertKey, panel, state))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduce ? 0.12 : 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(final, display: true)
        }

        // Rising fanfare for an alert that is already late, the familiar Funk for one still ahead.
        NSSound(named: m.start <= Date() ? "Hero" : "Funk")?.play()
    }

    /// Closes the panel for `key` if one is open — e.g. an ACK or snooze that arrived via the phone
    /// push, which previously stopped escalation but left the desktop panel sitting there forever.
    static func dismiss(key: String) {
        guard let idx = active.firstIndex(where: { $0.key == key }) else { return }
        remove(at: idx)
    }

    /// Escalation reached the phone and the alert is still unacknowledged — say so on the desktop
    /// panel too (pulsing rim, state word, one more sound) instead of leaving it looking untouched.
    static func escalated(key: String) {
        guard let entry = active.first(where: { $0.key == key }), !entry.state.escalated else { return }
        entry.state.escalated = true
        NSSound(named: "Sosumi")?.play()
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
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
            Task { @MainActor in reflow() }
        })
    }

    // ponytail: reflow repositions ALL currently-open panels onto whichever screen has the mouse
    // right now — correct for the common case (one alert at a time), but if several panels are
    // stacked across different screens and the mouse has since moved, a dismiss can jump the
    // survivors to the new screen. Upgrade to a per-panel screen if that turns out to matter.
    private static func reflow() {
        guard let screen = screenUnderMouse() else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduce ? 0 : 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for (i, entry) in active.enumerated() {
                entry.panel.animator().setFrame(frame(forIndex: i, screen: screen), display: true)
            }
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

/// How close the meeting is — drives hue, icon, state word and the numeral's unit together, so
/// urgency is never carried by colour alone.
private enum Urgency {
    case upcoming, imminent, started

    var signal: Color {
        switch self {
        case .upcoming: Theme.calm
        case .imminent: Theme.imminent
        case .started: Theme.started
        }
    }

    var symbol: String {
        switch self {
        case .upcoming: "clock"
        case .imminent: "clock.badge.exclamationmark"
        case .started: "exclamationmark.circle.fill"
        }
    }

    var word: String { self == .started ? "Started" : "Starting in" }
}

private struct AlertContent: View {
    let meeting: Store.Meeting
    let state: PanelState
    let onJoin: (() -> Void)?
    let onSnooze1: () -> Void
    let onSnooze5: () -> Void
    let onSnoozeStart: () -> Void
    let onIgnore: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    @State private var pulsing = false

    var body: some View {
        // ponytail: one tick a second regardless of distance — a single panel, negligible cost.
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let remaining = meeting.start.timeIntervalSince(ctx.date)
            card(urgency: remaining > 60 ? .upcoming : remaining > 0 ? .imminent : .started, remaining: remaining)
        }
        .frame(width: 640, height: 168)
    }

    private func card(urgency: Urgency, remaining: TimeInterval) -> some View {
        let numbers = countdown(remaining)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    stateRow(urgency)
                    Text(meeting.title).font(Theme.title).lineLimit(2)
                    metaRow
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(numbers.big)
                        .font(Theme.countdown)
                        .foregroundStyle(urgency.signal)
                        .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                        .animation(.snappy, value: numbers.big)
                    Text(numbers.unit).font(Theme.unit).foregroundStyle(.secondary)
                }
                .frame(minWidth: 96, alignment: .trailing)
            }
            Spacer(minLength: 6)
            actions(urgency)
        }
        .padding(18)
        .padding(.leading, 6)  // clear the signal rim
        .frame(width: 640, height: 168, alignment: .topLeading)
        .background(background(urgency))
    }

    private func stateRow(_ urgency: Urgency) -> some View {
        HStack(spacing: 5) {
            Image(systemName: state.escalated ? "bell.and.waves.left.and.right.fill" : urgency.symbol)
                .font(.system(size: 12, weight: .semibold))
            Text(state.escalated ? "Not acknowledged — phone alerted" : urgency.word)
                .font(Theme.state)
        }
        .foregroundStyle(urgency.signal)
    }

    private var metaRow: some View {
        HStack(spacing: 14) {
            Text("\(meeting.start.formatted(date: .omitted, time: .shortened))–\(meeting.end.formatted(date: .omitted, time: .shortened))")
            if let color = meeting.calendarColor, !meeting.calendarTitle.isEmpty {
                HStack(spacing: 5) {
                    Circle().fill(Color(nsColor: color)).frame(width: 8, height: 8)
                    Text(meeting.calendarTitle).font(Theme.calendarTag)
                }
            }
            if let url = meeting.joinURL {
                Label(Ntfy.provider(for: url), systemImage: "video.fill")
            } else if meeting.hasPhysicalLocation {
                Label("In person", systemImage: "figure.walk")
            }
        }
        .font(Theme.meta)
        .foregroundStyle(.secondary)
    }

    private func actions(_ urgency: Urgency) -> some View {
        HStack(spacing: 8) {
            if let onJoin, let url = meeting.joinURL {
                Button {
                    onJoin()
                } label: {
                    Label("Join \(Ntfy.provider(for: url))", systemImage: "video.fill")
                }
                .buttonStyle(SignalButtonStyle(signal: urgency.signal, prominent: true))
                .keyboardShortcut(.defaultAction)
            }
            Button("Snooze 5m", action: onSnooze5)
                .buttonStyle(SignalButtonStyle(signal: urgency.signal))
                .keyboardShortcut("5", modifiers: [])
            Button("Dismiss", action: onDismiss)
                // Exactly one filled button: Dismiss takes it when there is nothing to join.
                .buttonStyle(SignalButtonStyle(signal: urgency.signal, prominent: onJoin == nil))
                // ⌘D, never a bare "d" or Return: dismiss is FINAL (it acks the occurrence), and a
                // clicked card is key, so a bare letter would let ordinary typing kill the alert.
                .keyboardShortcut("d", modifiers: .command)
            Button(meeting.seriesId != nil ? "Ignore series" : "Ignore", action: onIgnore)
                .buttonStyle(SignalButtonStyle(signal: urgency.signal))
                // ⌘⇧I, same reasoning as Dismiss and then some: ignoring is final AND wide-reaching.
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Spacer(minLength: 0)
            Menu("More") {
                if let onJoin {
                    Button("Join meeting", action: onJoin).keyboardShortcut("j", modifiers: [])
                }
                Button("Snooze 1 min", action: onSnooze1).keyboardShortcut("1", modifiers: [])  // snooze is reversible
                if meeting.start > Date() {
                    Button("Snooze until start (\(meeting.start.formatted(date: .omitted, time: .shortened)))",
                           action: onSnoozeStart).keyboardShortcut("t", modifiers: [])
                }
            }
            .menuStyle(.button)
            .buttonStyle(SignalButtonStyle(signal: urgency.signal))
            .fixedSize()
            // esc means "go away, come back" — never a silent final dismissal.
            Button("", action: onSnooze5).keyboardShortcut(.cancelAction).opacity(0).frame(width: 0)
        }
    }

    private func background(_ urgency: Urgency) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        let signal = urgency.signal
        let wide = state.escalated || urgency == .started
        return ZStack(alignment: .leading) {
            if contrast == .increased {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else {
                shape.fill(.regularMaterial)
                shape.fill(Theme.ink)
                if scheme == .dark {
                    shape.fill(RadialGradient(colors: [signal.opacity(0.18), .clear],
                                              center: .topLeading, startRadius: 0, endRadius: 340))
                }
            }
            Rectangle()
                .fill(signal)
                .frame(width: wide ? 6 : Theme.rimWidth)
                .opacity(pulsing ? 0.5 : 1)
                .animation(state.escalated && !reduceMotion
                           ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : .default,
                           value: pulsing)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(contrast == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(signal.opacity(0.55)),
                                    lineWidth: contrast == .increased ? 2 : Theme.strokeWidth))
        .onChange(of: state.escalated) { _, escalated in
            pulsing = escalated && !reduceMotion
        }
    }

    private func countdown(_ remaining: TimeInterval) -> (big: String, unit: String) {
        if remaining > 60 { return ("\(Int(ceil(remaining / 60)))", "min") }
        if remaining > 0 { return ("\(Int(ceil(remaining)))", "sec") }
        let late = -remaining
        return late < 60 ? ("now", "") : ("+\(Int(late / 60))", "min late")
    }
}

/// One button look for the whole panel: capsule, hover brighten, press shrink. `prominent` fills
/// with the urgency hue (exactly one per panel); the rest are quiet outlines in the same hue.
private struct SignalButtonStyle: ButtonStyle {
    var signal: Color
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        SignalButtonBody(cfg: configuration, signal: signal, prominent: prominent)
    }

    private struct SignalButtonBody: View {
        let cfg: Configuration
        let signal: Color
        let prominent: Bool
        @State private var hover = false

        var body: some View {
            cfg.label
                .font(Theme.button)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .foregroundStyle(prominent ? AnyShapeStyle(Theme.onSignal) : AnyShapeStyle(.primary))
                .background(
                    Capsule()
                        .fill(prominent ? AnyShapeStyle(signal) : AnyShapeStyle(Color.primary.opacity(hover ? 0.14 : 0.08)))
                        .overlay(Capsule().strokeBorder(prominent ? .clear : signal.opacity(hover ? 0.7 : 0.35)))
                )
                .brightness(prominent && hover ? 0.06 : 0)
                .scaleEffect(cfg.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: hover)
                .onHover { hover = $0 }
        }
    }
}
