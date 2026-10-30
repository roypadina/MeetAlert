// MeetAlert demo: the real AlertContent view (AlertPanel.swift + Theme.swift, compiled unchanged) over fake data.
// Menu rows are copied verbatim from MenuContent in MeetAlertApp.swift; status text/symbol follow Store.swift at the fake clock.
import AppKit
import SwiftUI

private let cal = Calendar(identifier: .gregorian)
private func at(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: h, minute: m, second: s))!
}

private let design = Store.Meeting(
    key: "design", title: "Design review", start: at(9, 46), end: at(10, 15), hasPhysicalLocation: false,
    joinURL: URL(string: "https://zoom.us/j/1234567890"), seriesId: "weekly", calendarTitle: "Work",
    calendarColor: NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1))

// MeetAlertApp.swift MenuContent. A row with a video link is a Button (:93); one without is a bare Label, so a real NSMenu shows it disabled (:96).
private let menuRows: [MenuMock.Row] = [
    .header("Next Up"),                                                                  // :83
    .item("9:46 AM  Design review  — Join Zoom", symbol: "video"),                       // :93  "<time>  <title>  — Join <provider>"
    .item("10:30 AM  Customer sync  — Join Google Meet", symbol: "video"),               // :93
    .item("12:30 PM  Team lunch", symbol: "figure.walk", enabled: false),                // :96  in person, no link
    .item("2:00 PM  Roadmap planning  — Join Teams", symbol: "video"),                   // :93
    .item("Ignore", submenu: true),                                                      // :109
    .separator,
    .item("Settings…", key: "⌘,"),                                                       // :126
    .item("Edit Config File…"),                                                          // :127
    .separator,
    .item("About MeetAlert"),                                                            // :129
    .item("Welcome Guide…"),                                                             // :130
    .item("Support on Ko-fi ☕"),                                                         // :131
    .item("Quit MeetAlert", key: "⌘Q"),                                                  // :132
]

// Store.swift: menuBarTextFor :499 "in <ceil(min)>m · <title>"; symbolFor :479 "clock" until 180 s before start, then the badge.
private let in5 = StatusItem(symbol: "clock", text: "in 5m · Design review")                              // fake clock 9:41:00, start 9:46
private let in3 = StatusItem(symbol: "clock.badge.exclamationmark", text: "in 3m · Design review")      // fake clock 9:43:02
private let clock941 = Demo.clock
private let clock943 = "Thu Oct 30 9:43 AM"

private let W = Demo.size.width, H = Demo.size.height
private let panelOrigin = CGPoint(x: W / 2 - 320, y: Demo.barHeight + 12)  // AlertPanel.frame(forIndex:): centred, 12 pt below the bar
private let joinButton = CGPoint(x: panelOrigin.x + 84, y: panelOrigin.y + 134)  // centre of "Join Zoom" in the 640x168 card

@MainActor private func alertImage() -> CGImage {
    DemoClock.now = at(9, 43, 2)  // 178 s to go: "3 min", calm hue, as the default 3-minutes-before alert (Store.swift:38) shows
    return renderView(AlertContent(meeting: design, state: PanelState(), onJoin: {}, onSnooze1: {}, onSnooze5: {},
                                   onSnoozeStart: {}, onIgnore: {}, onDismiss: {}))!
}

@MainActor private func menuBarFrame(_ s: StatusItem) -> CGRect { Canvas(background: nil).menuBar(app: s) }

@MainActor func meetAlertScenes() -> [Scene] {
    let alert = alertImage()
    let item = menuBarFrame(in5)
    let menu = Canvas.menuFrame(menuRows, under: item)
    let rowFrames = MenuMock.frames(menuRows).map { $0.offsetBy(dx: menu.minX, dy: menu.minY) }
    func rowCenter(_ i: Int) -> CGPoint { CGPoint(x: menu.minX + 120, y: rowFrames[i].midY) }

    // 1. the status item
    let s1 = Scene(name: "menu bar", duration: 2.4, caption: "Your next meeting sits in the menu bar") { _ in
        let c = Canvas()
        c.menuBar(app: in5, clock: clock941)
        return c.image
    }

    // 2. the menu: click opens it at once, hover follows the cursor, a click on the desktop closes it at once
    let path2 = CursorPath(start: CGPoint(x: W * 0.78, y: H * 0.42),
                           moves: [.init(t0: 0.10, t1: 0.70, to: CGPoint(x: item.midX, y: Demo.barHeight / 2)),
                                   .init(t0: 1.15, t1: 1.65, to: rowCenter(1)),
                                   .init(t0: 2.15, t1: 2.55, to: rowCenter(2)),
                                   .init(t0: 3.00, t1: 3.55, to: CGPoint(x: W * 0.42, y: H * 0.52))],
                           clicks: [0.80, 3.70])
    let s2 = Scene(name: "menu", duration: 4.2, caption: "Open the menu for today's meetings") { t in
        let c = Canvas()
        let fadeIn = ramp(t, 0.80, 0.92), fadeOut = 1 - ramp(t, 3.70, 3.82)
        c.menuBar(app: in5, appActive: t >= 0.80 && fadeOut > 0, clock: clock941)
        if t >= 0.80 && fadeOut > 0 { c.menu(menuRows, under: item, hover: path2.position(t), alpha: CGFloat(min(fadeIn, fadeOut))) }
        let click = path2.click(t)
        c.cursor(at: path2.position(t), alpha: CGFloat(ramp(t, 0.0, 0.25) * (1 - ramp(t, 3.85, 4.05))), press: click.press, pulse: click.pulse)
        return c.image
    }

    // 3. the alert panel: AlertPanel.show animates alpha + a 14 pt slide over 0.28 s
    let s3 = Scene(name: "alert", duration: 3.0, caption: "A panel stays on screen until you act") { t in
        let c = Canvas()
        c.menuBar(app: in3, clock: clock943)
        let slide = easeOut(ramp(t, 0.35, 0.63))
        c.panel(alert, at: CGPoint(x: panelOrigin.x, y: panelOrigin.y - 14 * (1 - slide)), radius: Theme.panelRadius, alpha: CGFloat(slide))
        return c.image
    }

    // 4. Join: AlertPanel.remove fades the panel out over 0.15 s
    let path4 = CursorPath(start: CGPoint(x: W * 0.72, y: H * 0.50),
                           moves: [.init(t0: 0.20, t1: 0.95, to: joinButton)],
                           clicks: [1.25])
    let s4 = Scene(name: "join", duration: 2.3, caption: "Join opens the call and ends the alert") { t in
        let c = Canvas()
        c.menuBar(app: in3, clock: clock943)
        let gone = ramp(t, 1.25, 1.40)
        if gone < 1 { c.panel(alert, at: panelOrigin, radius: Theme.panelRadius, alpha: CGFloat(1 - gone)) }
        let click = path4.click(t)
        c.cursor(at: path4.position(t), alpha: CGFloat(ramp(t, 0.1, 0.3) * (1 - ramp(t, 1.45, 1.70))), press: click.press, pulse: click.pulse)
        return c.image
    }
    return [s1, s2, s3, s4]
}

@main struct MeetAlertDemo {
    @MainActor static func main() { Demo.run(scenes: meetAlertScenes()) }
}
